SHADPS4_BASE :: 0x800000000;
CODE_SCAN_SIZE :: 256 * 1024 * 1024;

FOV_HOOK_SIGNATURE :: u8.[

    // vmovss [r13+50], xmm1
    // ----------------------------------
    0xC4, 0xC1, 0x7A, 0x11, 0x4D, 0x50, 

    // vmovss xmm2, [r13+184]
    // ----------------------------------
    0xC4, 0xC1, 0x7A, 0x10, 0x95,
    0x84, 0x01, 0x00, 0x00
];

DEFAULT_FOV :: 0.005;

fov_hook_addr: *void;
original_fov_hook: [15] u8;

fov_cave_code: [160] u8;
fov_cave_size: s64;
fov_cave: *void;
fov_offset: s64;

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
        
        fov_hook_addr = scan_pattern(xx SHADPS4_BASE, CODE_SCAN_SIZE, FOV_HOOK_SIGNATURE.data, FOV_HOOK_SIGNATURE.count);
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
    
    dest := (fov_cave + fov_offset).(*float);
    dest.* = desired;
    current_fov = dest.*;
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

    return_addr := fov_hook_addr + FOV_HOOK_SIGNATURE.count;

    if !fov_cave_size {
        memcpy(original_fov_hook.data, fov_hook_addr, FOV_HOOK_SIGNATURE.count);
        build_fov_cave(return_addr);
        current_fov = DEFAULT_FOV;
    }

    fov_cave = VirtualAlloc(null, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    assert(xx fov_cave);

    memcpy(fov_cave, fov_cave_code.data, fov_cave_size);
    FlushInstructionCache(GetCurrentProcess(), fov_cave, fov_cave_size);
    
    // write absolute jump
    buffer: [32] u8;
    buffer[0] = 0xFF;
    buffer[1] = 0x25;
    memcpy(*buffer[6], *fov_cave, 8);
    for 14..FOV_HOOK_SIGNATURE.count buffer[it] = 0x90;
    patch_bytes(fov_hook_addr, buffer.data, FOV_HOOK_SIGNATURE.count);
}

uninstall_fov_hook :: () {

    patch_bytes(fov_hook_addr, original_fov_hook.data, FOV_HOOK_SIGNATURE.count);
    VirtualFree(fov_cave, 0, MEM_RELEASE);
    fov_cave = null;
}

// https://www.nexusmods.com/bloodborne/mods/193

build_fov_cave :: (return_addr: *void) {
    
    p := fov_cave_code.data;

    // addss xmm1, dword ptr [rip + fov]
    // ----------------------------------
    write_and_advance(*p, 0xF3); 
    write_and_advance(*p, 0x0F);
    write_and_advance(*p, 0x58);
    write_and_advance(*p, 0x0D);

    fov_disp := p.(*u8);
    p += 4;

    // vmovss dword ptr [r13+0x50], xmm1
    // ----------------------------------
    write_and_advance(*p, 0xC4);
    write_and_advance(*p, 0xC1);
    write_and_advance(*p, 0x7A);
    write_and_advance(*p, 0x11);
    write_and_advance(*p, 0x4D);
    write_and_advance(*p, 0x50);
    
    // vmovss xmm2, dword ptr [r13+0x184]
    // ----------------------------------
    write_and_advance(*p, 0xC4);
    write_and_advance(*p, 0xC1);
    write_and_advance(*p, 0x7A);
    write_and_advance(*p, 0x10);
    write_and_advance(*p, 0x95);
    write_and_advance(*p, 0x84);
    write_and_advance(*p, 0x01);
    write_and_advance(*p, 0x00);
    write_and_advance(*p, 0x00);
    
    // dq returnAddr
    // ----------------------------------
    write_and_advance(*p, 0xFF);
    write_and_advance(*p, 0x25);
    write_and_advance(*p, 0x00);
    write_and_advance(*p, 0x00);
    write_and_advance(*p, 0x00);
    write_and_advance(*p, 0x00);

    memcpy(p, *return_addr, size_of(*void));
    p += size_of(*void);

    fov_offset = (p - fov_cave_code.data).(s64);

    initial_fov := DEFAULT_FOV;
    memcpy(p, *initial_fov, 4);
    p += 4;

    end_offset := 8;
    disp := (fov_offset - end_offset).(s32);
    memcpy(fov_disp, *disp, 4);
    
    fov_cave_size = p - fov_cave_code.data;
}

write_and_advance :: (dest: **$T, value: T) {

    dest.*.* = value;
    dest.* += 1;
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
