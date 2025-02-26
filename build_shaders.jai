#import "Compiler";
#import "Basic";
#import "sl3dge-jai";

#run {
    set_build_options_dc(.{do_output = false});
    compile_shader("noop.frag");
    export_material("static_mesh", "static.vert", "color.frag", .{
        vertex_type = "Standard_Vertex",
        color_target = .{"swapchain", false},
        depth_target = true
    });
    export_pipeline("skybox", "skybox.vert", "skybox.frag", .{
        vertex_type = "Standard_Vertex",
        color_target = .{"swapchain", false},
        depth_target = false
    });
    export_pipeline("irradiance", "cubemap.vert", "irradiance.frag", .{
        vertex_type = "Standard_Vertex",
        color_target = .{"R32G32B32A32_FLOAT", false},
        depth_target = false
    });
    export_pipeline("ui", "ui.vert", "ui.frag", .{
        vertex_type = "UI_Vertex",
        color_target = .{"swapchain", true},
        depth_target = false
    });

    shaders := string.[
        "skinned.vert",
        "static_inst.vert",
        "ducks.comp",
    ];

    for shaders {
        compile_shader(it);
    }
}


