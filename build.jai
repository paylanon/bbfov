#run {
    
    make_directory_if_it_does_not_exist("bin");
    
    // dll
    w := compiler_create_workspace();
    options := get_build_options();
    using options;
    output_path = "bin";
    output_executable_name = "bbfov";
    output_type = .DYNAMIC_LIBRARY;
    set_optimization(*options, .VERY_OPTIMIZED);
    set_build_options(options, w);
    
    add_build_file("main.jai", w);

    // injector exe
    w = compiler_create_workspace();
    options = get_build_options();
    output_path = "bin";
    output_executable_name = "bbfov_injector";
    set_optimization(*options, .VERY_OPTIMIZED);
    additional_linker_arguments = .["/SUBSYSTEM:windows", "/ENTRY:mainCRTStartup"];
    
    set_build_options(options, w);

    compiler_begin_intercept(w);
    
    add_build_file("injector.jai", w);

    message_loop(w);
    
    compiler_end_intercept(w);
    
    icon := read_entire_file("data/insight.ico");
    set_icon_by_data("bin/bbfov_injector.exe", icon);
    
    set_build_options_dc(.{do_output = false});
}

message_loop :: (w: Workspace) {
    
    while true {
        
        message := compiler_wait_for_message();
        if message.kind == .COMPLETE break;
    }
}

#import "Compiler";
#import "File";
#import "Windows_Resources";
