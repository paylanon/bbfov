BBFOV_VERSION :: 1.0;

CHANNEL_DATA_BYTES :: 65536;

Message_Type :: enum {
    FOV_VAL;
    ENABLE;
    DISABLE;
    EXIT;
}

Channel_Message :: struct {
    
    type: Message_Type;
    fov_value: float;
}

input_channel:  Read_Channel;
output_channel: Write_Channel;

write_message :: (msg: Channel_Message) {

    success, reserved_msg := writer_reserve_message(*output_channel, size_of(Channel_Message));
    assert(success);
    memcpy(reserved_msg.user_write_pointer, *msg, size_of(Channel_Message));
    success = writer_commit_message(*output_channel, reserved_msg);
    assert(success);
}

// tlhelp

TH32CS_SNAPPROCESS :: 0x00000002;

PROCESSENTRY_MAX_PATH :: 260;

PROCESSENTRY32 :: struct {
    
    dwSize: u32;
    cntUsage: u32;
    th32ProcessID: u32;
    th32DefaultHeapID: u64;
    th32ModuleID: u32;
    cntThreads: u32;
    th32ParentProcessID: u32;
    pcPriClassBase: s32;
    dwFlags: u32;
    
    szExeFile: [MAX_PATH] u8;
};

CreateToolhelp32Snapshot :: (dwFlags: u32, th32ProcessId: u32) -> HANDLE #foreign kernel32;

Process32First :: (hSnapshot: HANDLE, lppe: *PROCESSENTRY32) -> BOOL #foreign kernel32;

Process32Next :: (hSnapshot: HANDLE, lppe: *PROCESSENTRY32) -> BOOL #foreign kernel32;

find_process_by_name :: (process_name: string) -> u32 {

    snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if snapshot == INVALID_HANDLE_VALUE return 0;

    entry: PROCESSENTRY32;
    entry.dwSize = size_of(PROCESSENTRY32);

    pid: u32;
    if Process32First(snapshot, *entry) {
        while true {
            
            if contains_nocase(entry.szExeFile.(string), process_name) {
                pid = entry.th32ProcessID;
                break;
            }
            
            memset(entry.szExeFile.data, 0, PROCESSENTRY_MAX_PATH);
            if !Process32Next(snapshot, *entry) break;
        }
    }

    return pid;
}

// dwm

// ** Window_Creation/windows.jai
create_window1 :: (
    width: int,
    height: int,
    window_name: string,
    window_icon: HICON = null,
    window_x := -1,
    window_y := -1,
    parent: Window_Type = null,
    background_color_rgb := float.[.15,.15,.2],
    wanted_msaa := 4
) -> HWND {
    
    if !window_class_initted {
        init_window_class(background_color_rgb);
    }

    style := NORESIZE_STYLE;
    if parent != null
        style = SECONDARY_WINDOW_STYLE;

    SPI_GETWORKAREA :: 0x30;
    user32 :: #system_library "user32";
    SystemParametersInfoW :: (uiAction: u32, uiParam: u32, pvParam: *void, fWinIni: u32) -> BOOL #foreign user32;

    if window_x == -1 {
        work_area: RECT;
        work_area_success := SystemParametersInfoW(SPI_GETWORKAREA, 0, *work_area, 0);
        if work_area_success {
            window_x = work_area.left;
            window_y = work_area.top;
        }
    }

    rect : RECT;
    rect.right  = xx width;
    rect.bottom = xx height;

    AdjustWindowRect(*rect, style, .FALSE); // @Robustness: Could this reasonably fail these days?

    client_width  := rect.right-rect.left;
    client_height := rect.bottom-rect.top;

    // CW_USEDEFAULT :: 0x8000_0000;

    hwnd := CreateWindowExW(0,
                            utf8_to_wide(WINDOW_CLASS_NAME,, temp),
                            utf8_to_wide(window_name,, temp),
                            style,
                            xx window_x, xx window_y,
                            xx client_width,
                            xx client_height,
                            parent,
                            null,
                            cast (HINSTANCE) 0, // @Robustness: If we want to run on win98 we need the app hinstance here...
                            null);

    if hwnd == null {
        log_error("CreateWindowExW returned 0.\n");
        return null;
    }
    
    t := BOOL.TRUE;
    set_dark := DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, *t, size_of(BOOL));
    
    // Display the window
    UpdateWindow(hwnd);
    ShowWindow(hwnd, SW_SHOW);

    return hwnd;
}

// misc.

PROCESS_CREATE_THREAD     :: 0x0002;
PROCESS_VM_OPERATION      :: 0x0008;
PROCESS_VM_READ           :: 0x0010;
PROCESS_VM_WRITE          :: 0x0020;
PROCESS_QUERY_INFORMATION :: 0x0400;

OpenProcess :: (dwDesiredAccess: u32, bInheritHandle: BOOL, dwProcessId: u32) -> HANDLE #foreign kernel32;

VirtualAllocEx :: (hProcess: HANDLE, lpAddress: *void, dwSize: u64, flAllocationType: u32, flProtect: u32) -> *void #foreign kernel32;
VirtualFreeEx :: (hProcess: HANDLE, lpAddress: *void, dwSize: u64, dwFreeType: u32) -> *void #foreign kernel32;

WriteProcessMemory :: (
    hProcess: HANDLE,
    lpBaseAddress: *void,
    lpBuffer: *void,
    nSize: SIZE_T,
    lpNumberOfBytesWritten: *SIZE_T
) -> BOOL #foreign kernel32;

THREAD_START_ROUTINE :: #type (lpThreadParameter: *void);

CreateRemoteThread :: (
    hProcess: HANDLE,
    lpThreadAttributes: *SECURITY_ATTRIBUTES,
    dwStackSize: SIZE_T,
    lpStartAddress: THREAD_START_ROUTINE,
    lpParameter: *void,
    dwCreationFlags: u32,
    lpThreadId: *u32
) -> HANDLE #foreign kernel32;

GetExitCodeThread :: (hThread: HANDLE, lpExitCode: *u32) -> BOOL #foreign kernel32;

DisableThreadLibraryCalls :: (hLibModule: HMODULE) -> BOOL #foreign kernel32;

FlushInstructionCache :: (hProcess: HANDLE, lpBaseAddress: *void, dwSize: s64) -> BOOL #foreign kernel32;

// ------------------------------------------------------------
#scope_file

kernel32 :: #system_library "kernel32";
Dwmapi   :: #system_library "Dwmapi";

MAKEINTRESOURCEA :: (i: u32) -> *u8 { return cast(*u8)i; }
MAKEINTRESOURCEW :: (i: u32) -> *u16 { return cast(*u16)i; }

DWMWA_USE_IMMERSIVE_DARK_MODE : u32 : 20;

DwmSetWindowAttribute :: (hwnd: HWND, dwAttribute: DWORD, pvAttribute: *BOOL, cbAttribute: DWORD) -> HRESULT #foreign Dwmapi;

window_class_initted := false;
WINDOW_CLASS_NAME :: "Default Window Class";

NORESIZE_STYLE : u32 : WS_VISIBLE | WS_CAPTION | WS_MINIMIZEBOX | WS_SYSMENU;

init_window_class :: (background_color_rgb: [3] float) {
    if window_class_initted return;

    hInstance := GetModuleHandleW(null);

    // Load the first icon resource (RESOURCE_ID_FIRST_ICON).
    icon := LoadIconW(hInstance, MAKEINTRESOURCEW(2));
    err := GetLastError();

    // If the icon is null, then use the first one found in the exe.
    if icon == null {
        exe_path : [MAX_PATH]u16;
        GetModuleFileNameW(null, exe_path.data, MAX_PATH);

        icon = ExtractIconW(hInstance, exe_path.data, 0); // 0 means first icon.
    }

    to_u8_inside_u32 :: (f: float) -> u32 {
        u := cast(s16)(f * 255);
        if u < 0    u = 0;
        if u > 255  u = 255;

        return cast(u32) u;
    }

    // CreateSolidBrush takes a BGR color, I guess.
    r := to_u8_inside_u32(background_color_rgb[0]);
    g := to_u8_inside_u32(background_color_rgb[1]);
    b := to_u8_inside_u32(background_color_rgb[2]);

    // @LanguageSemantics: Maybe we want to change the relative precedence of << and | so that this does not happen:
    brush := CreateSolidBrush((b << 16) | (g << 8) | r);

    wc: WNDCLASSEXW;
    wc.cbSize = size_of(WNDCLASSEXW);
    wc.style                = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    wc.cbClsExtra           = 0;
    wc.cbWndExtra           = 0;
    wc.hInstance            = hInstance;
    wc.hIcon                = icon;
    wc.hCursor              = LoadCursorW(null, IDC_ARROW);
    wc.hbrBackground        = brush;  // cast(HBRUSH) GetStockObject(WHITE_BRUSH);

    wc.lpszMenuName         = null;
    wc.lpszClassName        = utf8_to_wide(WINDOW_CLASS_NAME,, temp);

    //
    // If you get an error here that _os_input_handlers_are_added is not defined,
    // it means you did not #import "Input" or some equivalent that provides
    // an input handler (which is just about providing a WindowProc on Windows).
    // For this code to run and make sense, you want to provide a handler, probably.
    // In the future we'll hopefully make this a bit cleaner.
    //
    #if #exists(context.input_handler.window_proc, context.input_handler) {
        proc := context.input_handler.window_proc;
    } else {
        proc := DefWindowProcW;
    }

    wc.lpfnWndProc = proc;


    // Register the window class.
    if RegisterClassExW(*wc) == 0 {
        log_error("RegisterClassExW returned 0.\n");
        return;
    }

    window_class_initted = true;
}

#import "Basic";
#import "String";
#import "Input";
#import "Windows";
#import "Window_Creation";
#import "Windows_Utf8";
#import "Shared_Memory_Channel";
