#import "Compiler";
#import "Basic";
#import "sl3dge-jai";

#run {
    set_build_options_dc(.{do_output = false});
    compile_shader("shaders/noop.frag");
    export_material("static_mesh", .{
        vertex_shader = "shaders/static.vert",
        vertex_info = .{0, 0, 0, 2},
        fragment_shader = "shaders/color.frag", 
        fragment_info = .{samplers = 5, storageTextures = 0, storageBuffers = 0, uniformBuffers = 2},
        vertex_type = "Standard_Vertex",
        color_target = .{"swapchain", false},
        depth_target = true
    });
    export_pipeline("skybox", .{
        vertex_shader = "shaders/skybox.vert",
        vertex_info = .{0, 0, 0, 1},
        fragment_shader = "shaders/skybox.frag", 
        fragment_info = .{1, 0, 0, 1},
        vertex_type = "Standard_Vertex",
        color_target = .{"swapchain", false},
        depth_target = false
    });
    export_pipeline("irradiance", .{
        vertex_shader = "shaders/cubemap.vert",
        vertex_info = .{0, 0, 0, 1},
        fragment_shader = "shaders/irradiance.frag", 
        fragment_info = .{1, 0, 0, 1},
        vertex_type = "Standard_Vertex",
        color_target = .{"R32G32B32A32_FLOAT", false},
        depth_target = false
    });
    export_pipeline("prefiltered", .{
        vertex_shader = "shaders/cubemap.vert",
        vertex_info = .{0, 0, 0, 1},
        fragment_shader = "shaders/prefiltered_map.frag",
        fragment_info = .{1, 0, 0, 1},
        vertex_type = "Standard_Vertex",
        color_target = .{"R32G32B32A32_FLOAT", false},
        depth_target = false
    });
    export_pipeline("ui", .{
        vertex_shader = "shaders/ui.vert",
        vertex_info = .{0, 0, 0, 1},
        fragment_shader = "shaders/ui.frag", 
        fragment_info = .{1, 0, 0, 0},
        vertex_type = "UI_Vertex",
        color_target = .{"swapchain", true},
        depth_target = false
    });
    export_pipeline("sprites", .{
        vertex_shader = "shaders/ui.vert",
        vertex_info = .{0, 0, 0, 1},
        fragment_shader = "shaders/images.frag", 
        fragment_info = .{1, 0, 0, 0},
        vertex_type = "UI_Vertex",
        color_target = .{"swapchain", true},
        depth_target = false
    });
    export_compute_pipeline("brdf_convolution", .{
        shader = "shaders/brdf_convolution.comp",
        metadata = .{ readWriteStorageTextures = 1 },
    });

    shaders := string.[
        "shaders/skinned.vert",
        "shaders/static_inst.vert",
        "shaders/ducks.comp",
    ];

    for shaders {
        compile_shader(it);
    }
}


