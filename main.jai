SHADPS4_BASE :: 0x800000000;
CODE_SCAN_SIZE :: 256 * 1024 * 1024;
DEFAULT_FOV :: 0.005;

hook_asm :: #library,no_dll "hook";

FOV_HOOK_SIGNATURE:     u8 #elsewhere hook_asm;
FOV_HOOK_SIGNATURE_END: u8 #elsewhere hook_asm;

FOV_CAVE:     u8 #elsewhere hook_asm;
FOV_CAVE_END: u8 #elsewhere hook_asm;
FOV_DEST:     u8 #elsewhere hook_asm;

_patch_returnaddr: u8 #elsewhere hook_asm;

fov_hook_sig: [] u8;
fov_hook_addr: *void;

original_fov_hook: [16] u8;

fov_cave: [] u8;
fov_offset: s64;
fov_dest: *float;

current_fov: float;

instance_handle: HINSTANCE;

entry_thread: HANDLE;

#program_export DllMain :: (dll_instance: HINSTANCE, reason: u32) -> BOOL #c_call {
    push_context {
        
        if reason == DLL_PROCESS_ATTACH {

            success:, output_channel = writer_connect("bbfov_ir");
            assert(success);
            
            success, input_channel = reader_create_channel("bbfov_dllr", CHANNEL_DATA_BYTES);
            assert(success);
            
            instance_handle = dll_instance;
            DisableThreadLibraryCalls(dll_instance);
            entry_thread = CreateThread(null, 0, xx entry_proc, null, 0, null);

            CreateThread(null, 0, xx reader_loop, null, 0, null);
        }
        
        return .TRUE;
    }
}

entry_proc :: (p: *void) #c_call {
    push_context {
        
        fov_hook_sig.data = *FOV_HOOK_SIGNATURE;
        fov_hook_sig.count = *FOV_HOOK_SIGNATURE_END - *FOV_HOOK_SIGNATURE;
        
        fov_hook_addr = scan_pattern(xx SHADPS4_BASE, CODE_SCAN_SIZE, fov_hook_sig.data, fov_hook_sig.count);
        assert(xx fov_hook_addr);
        
        install_fov_hook();
        
        write_message({.FOV_VAL, current_fov});

        writer_disconnect(*output_channel);
    }
}

reader_loop :: (p: *void) #c_call {
    push_context {

        WaitForSingleObject(entry_thread, 0);
    
        quit := false;
        while !quit {

            message_success, fatal_error, message := reader_poll_for_message(*input_channel);
            if message_success {

                channel_msg := message.user_read_pointer.(*Channel_Message);

                if channel_msg.type == {
                
                    case .FOV_VAL;  set_fov(channel_msg.fov_value);
                    case .ENABLE;   install_fov_hook(); set_fov(current_fov);
                    case .DISABLE;  uninstall_fov_hook();
                    case .EXIT;     quit = true;
                }

                reader_done_with_message(*message);
            }
        }

        reader_release_channel(*input_channel);
    }
}

set_fov :: (desired: float) {
    
    fov_dest.* = desired;
    current_fov = fov_dest.*;
}

scan_pattern :: (start: *void, size: s64, pattern: *u8, pattern_length: s64) -> *void {

    end := start + size;
    cursor := start;

    while cursor < end {

        mbi: MEMORY_BASIC_INFORMATION;
        success := VirtualQuery(cursor, *mbi, size_of(MEMORY_BASIC_INFORMATION));
        assert(xx success);

        region_base := mbi.BaseAddress;
        region_end := region_base + mbi.RegionSize;

        scan_start := ifx cursor > region_base then cursor else region_base;
        scan_end := ifx region_end < end then region_end else end;

        if mbi.State == MEM_COMMIT && !(mbi.Protect & PAGE_NOACCESS) && !(mbi.Protect & PAGE_GUARD) {
            
            base := scan_start;
            scan_length := scan_end - scan_start;

            if scan_length >= pattern_length {
                for 0..(scan_length - pattern_length-1) {
                    if !memcmp(base + it, pattern, pattern_length) return scan_start + it;
                }
            }
        }

        cursor = region_end;
    }

    return null;
}

install_fov_hook :: () {

    return_addr := fov_hook_addr + fov_hook_sig.count;

    if !fov_cave.count { // first install
        memcpy(original_fov_hook.data, fov_hook_addr, fov_hook_sig.count);
        patch_fov_cave(return_addr);
        current_fov = DEFAULT_FOV;
    }

    fov_cave.data = VirtualAlloc(null, xx fov_cave.count, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    assert(xx fov_cave.data);

    memcpy(fov_cave.data, *FOV_CAVE, fov_cave.count);
    FlushInstructionCache(GetCurrentProcess(), fov_cave.data, fov_cave.count);
    
    // write absolute jump
    buffer: [32] u8;
    buffer[0] = 0xFF;
    buffer[1] = 0x25;
    memcpy(*buffer[6], *fov_cave.data, 8);
    for 14..fov_hook_sig.count-1 buffer[it] = 0x90;
    
    patch_bytes(fov_hook_addr, buffer.data, fov_hook_sig.count);
    
    fov_dest = (fov_cave.data + fov_offset).(*float);
}

uninstall_fov_hook :: () {

    patch_bytes(fov_hook_addr, original_fov_hook.data, fov_hook_sig.count);
    VirtualFree(fov_cave.data, 0, MEM_RELEASE);
    fov_cave.data = null;
    fov_dest = null;
}

patch_fov_cave :: (return_addr: *void) {
    
    memcpy(*_patch_returnaddr, *return_addr, 8);
    
    initial_fov := DEFAULT_FOV;
    memcpy(*FOV_DEST, *initial_fov, 4);
    
    fov_offset = *FOV_DEST - *FOV_CAVE;
    fov_cave.count = *FOV_CAVE_END - *FOV_CAVE;
}

patch_bytes :: (addr: *void, bytes: *u8, length: s64) {

    old_protect: u32;
    success := VirtualProtect(addr, xx length, PAGE_EXECUTE_READWRITE, *old_protect);
    assert(xx success);

    memcpy(addr, bytes, length);
    VirtualProtect(addr, xx length, old_protect, *old_protect);
    FlushInstructionCache(GetCurrentProcess(), addr, length);
};

#load "common.jai";

#import "Basic";
#import "Windows";
#import "Remap_Context";
#import "Shared_Memory_Channel";
