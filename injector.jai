MIN_FOV :: -.03;
MAX_FOV :: .11;

window: Window_Type;
window_width := 380;
window_height := 240;

injector_thread: Thread;

ui_font: *Simp.Dynamic_Font;
ui_theme: Overall_Theme;

current_time: float64;


ready   := false;
enabled := false;

user_fov: float;

main :: () {

    thread_init(*injector_thread, injector_main);
    thread_start(*injector_thread);
    
    window = create_window1(
        window_width,
        window_height,
        tprint("bbfov %", formatFloat(BBFOV_VERSION, zero_removal = .ONE_ZERO_AFTER_DECIMAL))
    );
    
    Simp.set_render_target(window, .LEFT_HANDED);
    
    font_init();
    ui_init();
    theme_init();
    
    quit := false;
    while !quit {
        
        current_time = seconds_since_init();
        
        Input.update_window_events();
        for Input.events_this_frame {
            
            if it.type == .QUIT then quit = true;
            getrect_handle_event(it);

            if it.type == {
              case .KEYBOARD;
                if it.key_pressed && it.key_code == .ESCAPE quit = true;
                if it.key_pressed && it.key_code == .ARROW_LEFT && enabled {
                    user_fov -= .001;
                    Clamp(*user_fov, MIN_FOV, MAX_FOV);
                    write_message({.FOV_VAL, user_fov});
                }
                if it.key_pressed && it.key_code == .ARROW_RIGHT && enabled {
                    user_fov += .001;
                    Clamp(*user_fov, MIN_FOV, MAX_FOV);
                    write_message({.FOV_VAL, user_fov});
                }            
            }
        }

        draw_one_frame();
    }

    if ready {
        write_message({.EXIT, 0});
        writer_disconnect(*output_channel);
    }
}

injector_main :: (thread: *Thread) -> s64 {
    
    if !file_exists("bbfov.dll") {
        conout(0, .ERROR, "DLL not found! Please make sure bbfov.dll");
        conout(1, .ERROR, "is in the same folder as this exe.");
        return 0;
    };

    pid: u32;
    conout(0, .DOC1, "Searching for shadPS4...");
    PROCESS_NAME :: "shadps4";
    pid = find_process_by_name(PROCESS_NAME);

    if !pid {
        
        conout(0, .WARN, "Bloodborne/shadPS4 process not found!");
        wait_msg := "Waiting for it to start....";
        full_count := wait_msg.count;
        tick: s64;
        while true {
            
            wait_msg.count = full_count - 3 + (tick%4);
            conout(1, .DOC, wait_msg);
            tick += 1;
            sleep_milliseconds(200);
            
            if tick == 8 {
                
                pid = find_process_by_name(PROCESS_NAME);
                if pid break;
                tick = 0;
            }
        }

        conout(0, .OK, "Found shadPS4!");
        wait_msg = "Waiting ten seconds for game start....";
        full_count = wait_msg.count;
        tick = 0;
        while true {
            
            wait_msg.count = full_count - 3 + (tick%4);
            conout(1, .DOC1, wait_msg);
            tick += 1;
            sleep_milliseconds(1000);

            if tick == 10 break;
        }
        
    } else {
        
        conout(0, .OK, "Found shadPS4!");
    }
    
    success:, input_channel = reader_create_channel("bbfov_ir", CHANNEL_DATA_BYTES);
    assert(success);
    
    conout(1, .DOC1, "Injecting DLL...");
    inject_dll(pid, get_absolute_path("bbfov.dll"));
    
    failure: bool;
    while true {
        
        if failure continue;
        
        message_success, fatal_error, message := reader_poll_for_message(*input_channel);
        if message_success {
            
            channel_msg := message.user_read_pointer.(*Channel_Message);

            if channel_msg.type == {
                case .ERROR;
                  conout(0, .ERROR, "Pattern scan failed!");
                  conout(1, .ERROR, "Incompatible version of shadPS4...");
                  failure = true;
                case .FOV_VAL;
                  user_fov = channel_msg.value;
                  reader_done_with_message(*message);
                  break;
            }
        }
    }
    
    reader_release_channel(*input_channel);
    
    success, output_channel = writer_connect("bbfov_dllr");
    assert(success);
    
    conout(0, .NOTE, " READY.");
    conout(1, .DOC1, "-- Grant us eyes, grant us eyes. --");
    ready = true;
    enabled = true;
    
    if file_exists("saved.fov") {
        saved := read_entire_file("saved.fov");
        user_fov = saved.data.(*float).*;
        write_message({.FOV_VAL, user_fov});
    };
    
    return 0;
}


font_otf :: #run add_global_data(get_font_data(), .READ_ONLY);

get_font_data :: () -> [] u8 {
    
    otf := read_entire_file("data/Kozuka Mincho Pro R.otf");
    return xx otf;
}

font_init :: () {

    pixel_height := 16;
    ui_font = Simp.get_font_at_size(font_otf, pixel_height);
    assert(ui_font != null);
}

theme_init :: () {

    // ui_theme = default_theme_procs[Default_Themes.Grayscale]();
    
    surface_color     :: Vector4.{.51, .52, .47, .1};
    border_color      :: Vector4.{.1, .1, .1, 1};
    interact_color    :: Vector4.{.61, .62, .57, .1};
    atop_surface_text :: Vector4.{.6, .6, .6, 1};
    atop_border_text  :: Vector4.{.6, .6, .6, 1};

    set_theme_from_base_colors(*ui_theme, surface_color, border_color, interact_color, atop_surface_text, atop_border_text);
    
    ui_theme.font = ui_font;
    
    {
        using ui_theme.checkbox_theme;
        font = ui_font;
        surface_color = {.5, .48, .44, 1};;
        surface_color_over = surface_color;
        surface_color_flash = surface_color;
        surface_color_down = surface_color;
        button_color_selected = surface_color;
    }
    
    {
        using ui_theme.slider_theme;
        foreground.rectangle_shape.roundedness = .04;
        foreground.text_color          = {.6, .58, .54, 1};
        foreground.surface_color       = {.16, .14, .14, .8};
        foreground.surface_color_over  = {.16, .14, .14, .9};
        foreground.surface_color_flash = {.16, .14, .14, .8};
        foreground.surface_color_down  = {.5, .48, .44, 1};
        foreground.font = ui_font;
        background.rectangle_shape.roundedness = .04;
        decimals = 3;
    }
    
    {
        using ui_theme.button_theme;
        font = ui_font;
        frame_color.w = .1;
        frame_color_over.w = .1;
        frame_color_flash.w = .1;
        frame_color_down.w = .1;
    }
    
    set_default_theme(ui_theme);
}

inject_dll :: (pid: u32, dll_path: string) {

    process := OpenProcess(
        PROCESS_CREATE_THREAD | PROCESS_VM_OPERATION |
        PROCESS_VM_WRITE | PROCESS_VM_READ | PROCESS_QUERY_INFORMATION,
        .FALSE,
        pid
    );

    path_length := dll_path.count + 1;
    remote_mem := VirtualAllocEx(process, null, xx path_length, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);

    path_cstr := to_c_string(dll_path);
    
    written: SIZE_T;
    WriteProcessMemory(process, remote_mem, path_cstr, xx path_length, *written);
    assert(written == xx path_length);

    loadlib_address := GetProcAddress(GetModuleHandleA(to_c_string("kernel32.dll")), to_c_string("LoadLibraryA"));

    thread := CreateRemoteThread(process, null, 0, loadlib_address, remote_mem, 0, null);
    assert(xx thread);

    WaitForSingleObject(thread, 0);

    exit_code: u32;
    GetExitCodeThread(thread, *exit_code);
    assert(xx exit_code);
    
    CloseHandle(thread);
    CloseHandle(process);
}

draw_one_frame :: () {
    
    ui_per_frame_update(window, xx window_width, xx window_height, current_time);
    
    Simp.clear_render_target(.03, .03, .03, 1);
    
    r: Rect;
    k := window_width * .1;
    
    conout_x := .6*k;
    conout_y := .6*k;
    
    r = get_rect(conout_x, conout_y, 8.4*k, ui_font.character_height*4.);
    rounded_rectangle(r, {roundedness=.04}, {0, 0, 0, 1}, {.02, .02, .02, 1});

    Simp.draw_text(ui_font, xx conout_x + 10, xx conout_y + 24, conout_msg[0], conout_shade[0]);
    Simp.draw_text(ui_font, xx conout_x + 10, xx conout_y + 18 + ui_font.default_line_spacing, conout_msg[1], conout_shade[1]);
    
    if ready {
        
        r = get_rect(1.1*k, 2.4*k, 8*k, ui_font.character_height*2.);
        pressed := base_checkbox(r, " Enable", enabled);
        enabled ^= pressed;
    
        if pressed {
            if enabled {
                write_message({.ENABLE, 0});
            } else {
                write_message({.DISABLE, 0});
            }
        }
        
        r = get_rect(1*k, 3.4*k, 8*k, ui_font.character_height*1.6);
        changed := slider(r, *user_fov, MIN_FOV, MAX_FOV, .001, *ui_theme.slider_theme);

        if changed {

            write_message({.FOV_VAL, user_fov});
        }
    
        if enabled {
            
            r = get_rect(1*k, 4.4*k, 2*k, ui_font.character_height*1.6);
            pressed = button(r, "Reset");

            if pressed {
                user_fov = 0;
                write_message({.FOV_VAL, user_fov});
            }

            r = get_rect(3.4*k, 4.4*k, 3*k, ui_font.character_height*1.6);
            pressed = button(r, "Save & Exit");

            if pressed {
                
                write_entire_file("saved.fov", *user_fov, 4);
                
                write_message({.EXIT, 0});
                writer_disconnect(*output_channel);
                
                exit(0);
            }
        }
    }

    if !enabled {

        r = get_rect(1*k, 3.4*k, 8*k, ui_font.character_height*1.6);
        rounded_rectangle(r, {roundedness=.04}, {.06, .06, .06, 1}, {.02, .02, .02, 1});
    }
    
    Simp.swap_buffers(window);
}

// logging

conout_shade: [2] Vector4;
conout_msg:   [2] string;

conout :: (line: s64, shade: Log_Shade, msg: string, args: .. Any) {
    
    if shade == {
    
        case .ERROR;    conout_shade[line] = {.6, .3, .3, 1};
        case .OK;       conout_shade[line] = {.4, .4, .3, 1};
        case .WARN;     conout_shade[line] = {.62, .54, .46, 1};
        case .NOTE;     conout_shade[line] = {.5, .48, .44, 1};
        case .DOC;      conout_shade[line] = {.6, .6, .6, 1};
        case .DOC1;     conout_shade[line] = {.3, .3, .3, 1};
    
        case; conout_shade[line] = {.1, .1, .1, 1};
    }
    
    conout_msg[line] = "";
    conout_msg[line] = ifx args.count tprint(msg, ..args) else msg;
}

Log_Shade :: enum u8 {
    DEFAULT :: 255;
    ERROR   :: 9;
    OK      :: 143;
    WARN    :: 3;
    NOTE    :: 6;
    NOTE1   :: 145;
    DOC     :: 246;
    DOC1    :: 240;
    BINFO   :: 14;
    BINFO1  :: 12;
}

bbfov :: #library "bbfov";

#load "common.jai";

#import "Basic";
#import "Compiler";
#import "Math";
#import "String";
#import "Windows";
#import "File";
#import "File_Utilities";
#import "Thread";

#import "Window_Creation";
Simp  :: #import "Simp";
Input :: #import "Input";
#import "GetRect_LeftHanded";
