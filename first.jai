#load "src/main.jai";

#run build();
build :: () {
    #import "Compiler";

    if #exists(SECOND) {
        return;
    }
    set_build_options_dc(.{ do_output = false });

    w := compiler_create_workspace();
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_executable_name = "out";
    options.output_path = "bin";
    set_build_options(options, w);

    #if OS == .LINUX {
    } else #if OS == .MACOS {
        options.additional_linker_arguments = .["-framework", "Metal", "-framework", "QuartzCore"];
    } else #if OS == .WINDOWS {
        options.additional_linker_arguments = .["Ws2_32.lib", "Userenv.lib", "Bcrypt.lib", "d3dcompiler.lib", "libcpmt.lib"];
    }

    add_build_string("SECOND :: true;", w);
    add_build_file(#file, w);
}

