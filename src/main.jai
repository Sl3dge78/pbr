Game_State :: struct {
    player: Player;

    sphere_mesh: Mesh;
    skybox: Cube_Map;
    irradiance_map: Cube_Map;
    unit_cube: Mesh;

    skybox_pipeline: *SDL_GPUGraphicsPipeline;
    irradiance_pipeline: *SDL_GPUGraphicsPipeline;

    show_skybox := true;
}

CUBE_MAP_FORMAT :: SDL_GPUTextureFormat.R32G32B32A32_FLOAT;

Player :: struct {
    transform: Transform;
    yaw: float = -PI / 2.0;
    pitch: float = PI / 2.0;
    forward : Vector3;

    EYE_HEIGHT :: 1.6;  
}

Cube_Map :: *SDL_GPUTexture;

render_irradiance :: (irradiance_pipeline: *SDL_GPUGraphicsPipeline, unit_cube: Mesh, source: Cube_Map, target: Cube_Map) {
    projection := make_projection_matrix(radians(90), 1, 0.0001, 10);
    views := Matrix4.[
        make_look_at_matrix(.{0, 0, 0}, .{-1, 0, 0}, .{0, 1, 0}, false),
        make_look_at_matrix(.{0, 0, 0}, .{1, 0, 0}, .{0, 1, 0}, false),
        make_look_at_matrix(.{0, 0, 0}, .{0, 1, 0}, .{0, 0, -1}, false),
        make_look_at_matrix(.{0, 0, 0}, .{0, -1, 0}, .{0, 0, 1}, false),
        make_look_at_matrix(.{0, 0, 0}, .{0, 0, 1}, .{0, 1, 0}, false),
        make_look_at_matrix(.{0, 0, 0}, .{0, 0, -1}, .{0, 1, 0}, false),
    ];
    cmd := SDL_AcquireGPUCommandBuffer(global_renderer.device);
    defer SDL_Check(SDL_SubmitGPUCommandBuffer(cmd));

    for 0..6-1 {
        color_target := SDL_GPUColorTargetInfo.{
            texture = target,
            mip_level = 0,
            layer_or_depth_plane = xx it,
            clear_color = .{0, 0, 0, 0},
            load_op = .DONT_CARE,
            store_op = .STORE,
            cycle = false,
        };
    
        matrices := Global_Matrices.{
            camera_position = .{0, 0, 0},
            projection = transpose(projection),
            view = transpose(views[it]),
        };

        pass := SDL_NullCheck(SDL_BeginGPURenderPass(cmd, *color_target, 1, null));
        defer SDL_EndGPURenderPass(pass);
        SDL_BindGPUGraphicsPipeline(pass, irradiance_pipeline);

        SDL_PushGPUVertexUniformData(cmd, 0, *matrices, size_of(type_of(matrices)));
        SDL_PushGPUFragmentUniformData(cmd, 0, *matrices, size_of(type_of(matrices)));

        binding := SDL_GPUTextureSamplerBinding.{ source, global_renderer.sampler };
        SDL_BindGPUFragmentSamplers(pass, 0, *binding, 1);
        draw(unit_cube, pass);
    }

}

empty_cube_map :: (width: int, height: int, format : SDL_GPUTextureFormat, usage: SDL_GPUTextureUsageFlags = .SAMPLER, name: string = "") -> Cube_Map {
    texture_ci := SDL_GPUTextureCreateInfo.{
        type = .CUBE,
        format = format,
        width = xx width,
        height = xx height,
        layer_count_or_depth = 6,
        num_levels = 1,
        usage = usage,
    };
    result := SDL_CreateGPUTexture(global_renderer.device, *texture_ci);
    SDL_SetGPUTextureName(global_renderer.device, result, temp_c_string(name));
    return result;
}

// The folder should have nx, ny, nz, px, py, pz .hdr files
cube_map_from_files :: (folder: string) -> Cube_Map {
    channels: s32;
    width: s32;
    height: s32;
    path := tprint("%/nx.hdr", folder);
    stbi_info(temp_c_string(path), *width, *height, *channels);
    assert(channels == 3);

    result_texture := empty_cube_map(width, height, format = CUBE_MAP_FORMAT, name = "Skybox");

    img_size := width * height * 4 * size_of(float);
    size := img_size * 6;
    cmd := SDL_AcquireGPUCommandBuffer(global_renderer.device);
    defer SDL_SubmitGPUCommandBuffer(cmd);

    copy_pass := SDL_BeginGPUCopyPass(cmd);
    defer SDL_EndGPUCopyPass(copy_pass);

    names := string.[
        "px",
        "nx",
        "py",
        "ny",
        "pz",
        "nz",
    ];
    {
        for 0..6-1 {
            tbuf_ci := SDL_GPUTransferBufferCreateInfo.{
                usage = .UPLOAD,
                size = xx img_size,
                props = 0,
            };
            tbuf := SDL_CreateGPUTransferBuffer(global_renderer.device, *tbuf_ci);
            defer SDL_ReleaseGPUTransferBuffer(global_renderer.device, tbuf);

            channels: s32;
            w: s32;
            h: s32;
            path := tprint("%/%.hdr", folder, names[it]);
            img := stbi_loadf(temp_c_string(path), *w, *h, *channels, 4);
            assert(img != null, "Unable to load %.", path);
            defer stbi_image_free(img);
            assert(w == width && h == height, "% dims do not match!", names[it]);

            data := SDL_MapGPUTransferBuffer(global_renderer.device, tbuf, false);
            SDL_memcpy(data, img, xx img_size);
            SDL_UnmapGPUTransferBuffer(global_renderer.device, tbuf);

            src := SDL_GPUTextureTransferInfo.{ tbuf, 0, xx width, xx height };
            dst := SDL_GPUTextureRegion.{
                result_texture,
                0, xx it,
                0, 0, 0,
                xx width, xx height, 1,
            };
            SDL_UploadToGPUTexture(copy_pass, *src, *dst, false);
        }
    }

    return result_texture;
}

player_update :: (using player: *Player, game_state: *Game_State, delta_time: float) {

    position := transform.position;

    // Look
    LOOK_SPEED :: 0.0025;
    yaw += cast(float)(mouse_delta_x()) * LOOK_SPEED;
    yaw = fmod_cycling(yaw, 2.0 * PI);
    pitch += cast(float)(mouse_delta_y()) * LOOK_SPEED;
    pitch = clamp(pitch, 0.001, PI - 0.001);
    forward = unit_vector(xyz(sin(pitch) * cos(yaw), cos(pitch), sin(pitch) * sin(yaw)));

    look_at(*transform, forward);
    
    right := cross(forward, Vector3.{0, 1, 0});
    speed : float = 1;
    if key_down(.SDL_SCANCODE_LSHIFT) then speed *= 10;

    // Free cam
    velocity: Vector3;
    if key_down(.SDL_SCANCODE_W) then velocity += forward * speed;
    if key_down(.SDL_SCANCODE_S) then velocity -= forward * speed;
    if key_down(.SDL_SCANCODE_D) then velocity += right * speed;
    if key_down(.SDL_SCANCODE_A) then velocity -= right * speed;
    if key_down(.SDL_SCANCODE_E) then velocity += .{0, 1, 0} * speed;
    if key_down(.SDL_SCANCODE_Q) then velocity -= .{0, 1, 0} * speed;

    transform.position += velocity * 5 * delta_time;
    console_message("%", transform.position);

}

player_get_camera_matrix :: (using self: *Player) -> Matrix4 {
    eye_position := transform.position + .{0, EYE_HEIGHT, 0};
    return make_look_at_matrix(eye_position, eye_position + forward, UP, false);
}

game_state_create :: (using state: *Game_State) {
    sphere_mesh = load_mesh_from_file("res/sphere.glb");
    player.transform.position = .{25, 25, 75};
    offset : *Global_Matrices = xx 0;
    skybox = cube_map_from_files("res/environment");
    IRRADIANCE_SIZE :: 64;
    irradiance_map = empty_cube_map(IRRADIANCE_SIZE, IRRADIANCE_SIZE, format = CUBE_MAP_FORMAT, name = "Irradiance", usage = .SAMPLER | .COLOR_TARGET);
    {
        builder: Mesh_Builder;
        mesh_builder_push_quad(*builder, .{1, -1, -1}, .{1, -1, 1}, .{1, 1, 1 }, .{1, 1, -1 }, .{-1, 0, 0});
        mesh_builder_push_quad(*builder, .{-1, -1, -1}, .{-1, 1, -1}, .{-1, 1, 1}, .{-1, -1, 1}, .{1, 0, 0});
        mesh_builder_push_quad(*builder, .{-1, 1, -1}, .{1, 1, -1}, .{1, 1, 1}, .{-1, 1, 1}, .{0, -1, 0});
        mesh_builder_push_quad(*builder, .{-1, -1, 1}, .{1, -1, 1}, .{1, -1, -1}, .{-1, -1, -1}, .{0, 1, 0});
        mesh_builder_push_quad(*builder, .{-1, 1, 1}, .{1, 1, 1}, .{1, -1, 1}, .{-1, -1, 1}, .{0, 0, -1});
        mesh_builder_push_quad(*builder, .{-1, -1, -1}, .{1, -1, -1}, .{1, 1, -1}, .{-1, 1, -1}, .{0, 0, 1});
        unit_cube = mesh_builder_load_mesh(*builder);
    }

    {
        builder: Pipeline_Builder;
        add_shader(*builder, global_renderer.device, "shaders/skybox.vert.spv");
        add_shader(*builder, global_renderer.device, "shaders/skybox.frag.spv");
        add_vertex_type(*builder, Standard_Vertex);
        add_color_target(*builder, global_renderer.swapchain_format, false);
        skybox_pipeline = build_pipeline(*builder, global_renderer.device);
    }

    {
        builder: Pipeline_Builder;
        add_shader(*builder, global_renderer.device, "shaders/cubemap.vert.spv");
        add_shader(*builder, global_renderer.device, "shaders/irradiance.frag.spv");
        add_vertex_type(*builder, Standard_Vertex);
        add_color_target(*builder, CUBE_MAP_FORMAT, false);
        irradiance_pipeline = build_pipeline(*builder, global_renderer.device);
    }

    render_irradiance(irradiance_pipeline, unit_cube, skybox, irradiance_map);
}

game_state_destroy :: (using state: *Game_State) {
    destroy(*sphere_mesh);
    SDL_ReleaseGPUGraphicsPipeline(global_renderer.device, skybox_pipeline);
    destroy(skybox);
    destroy(irradiance_map);
    SDL_ReleaseGPUGraphicsPipeline(global_renderer.device, irradiance_pipeline);
    destroy(*unit_cube);
}

game_state_update :: (using state: *Game_State, delta_time: float) {
    player_update(*player, state, delta_time);
}

game_state_input_event :: (using state: *Game_State, event: SDL_Event) {
    if(event.type == .KEY_DOWN) {
        if(event.key.scancode == .B) {
            show_skybox = !show_skybox;
        }
    }

}

game_state_draw :: (using state: *Game_State, frame_data: Frame_Data) {
    sun_dir := unit_vector(.{-1, -1, -1});
    lights : [16]Light;
    lights[0] = .{ .POINT, .{-10, 10, 10}, .{300.0, 300.0, 300.0, 1}};
    lights[1] = .{ .POINT, .{10, 10, 10}, .{300.0, 300.0, 300.0, 1}};
    lights[2] = .{ .POINT, .{-10, -10, 10}, .{300.0, 300.0, 300.0, 1}};
    lights[3] = .{ .POINT, .{10, -10, 10}, .{300.0, 300.0, 300.0, 1}};

    size:: 40;
    light_proj := orthographic_projection_matrix(-size, size, -size, size, -size, size, true);
    light_view := make_look_at_matrix(.{0, 0, 0}, sun_dir, .{0, 1, 0}, false);
    light_matrix := light_proj * light_view;
    view := player_get_camera_matrix(*state.player);

    matrices := Global_Matrices.{
        camera_position = player.transform.position + Vector3.{0, Player.EYE_HEIGHT, 0},
        projection = transpose(global_renderer.projection),
        view = transpose(view),
        sun = transpose(light_matrix),
        lights = lights,
        light_count = 4,
    };

    shadow_matrices := matrices;
    shadow_matrices.projection = transpose(light_proj);
    shadow_matrices.camera_position = .{0, 0, 0};
    shadow_matrices.view = transpose(light_view);


    {   // Shadow pass
        render_pass := SDL_NullCheck(SDL_BeginGPURenderPass(frame_data.cmd, null, 0, *global_renderer.shadowmap_target));
        defer SDL_EndGPURenderPass(render_pass);
        SDL_PushGPUVertexUniformData(frame_data.cmd, 0, *shadow_matrices, size_of(type_of(shadow_matrices)));
        draw_scene(state, render_pass, frame_data.cmd, .SHADOWMAP);
    }

    {   // Skybox
        target := create_color_target(frame_data.target, .CLEAR, clear_color = .{0.1, 0.1, 0.1, 1});
        render_pass := SDL_NullCheck(SDL_BeginGPURenderPass(frame_data.cmd, *target, 1, null));
        defer SDL_EndGPURenderPass(render_pass);

        SDL_PushGPUVertexUniformData(frame_data.cmd, 0, *matrices, size_of(type_of(matrices)));
        SDL_PushGPUFragmentUniformData(frame_data.cmd, 0, *matrices, size_of(type_of(matrices)));

        if(!show_skybox) {
            binding := SDL_GPUTextureSamplerBinding.{ irradiance_map, global_renderer.sampler };
            SDL_BindGPUFragmentSamplers(render_pass, 0, *binding, 1);
        } else {
             binding := SDL_GPUTextureSamplerBinding.{ skybox, global_renderer.sampler };
            SDL_BindGPUFragmentSamplers(render_pass, 0, *binding, 1);
        }
        SDL_BindGPUGraphicsPipeline(render_pass, skybox_pipeline);
        draw(unit_cube, render_pass);
    }

    {
        target := create_color_target(frame_data.target);
        render_pass := SDL_NullCheck(SDL_BeginGPURenderPass(frame_data.cmd, *target, 1, *global_renderer.depth_stencil_target));
        defer SDL_EndGPURenderPass(render_pass);

        SDL_PushGPUVertexUniformData(frame_data.cmd, 0, *matrices, size_of(type_of(matrices)));
        SDL_PushGPUFragmentUniformData(frame_data.cmd, 0, *matrices, size_of(type_of(matrices)));

        // Bind the shadowmap
        binding := SDL_GPUTextureSamplerBinding.{ global_renderer.shadowmap, global_renderer.sampler };
        SDL_BindGPUFragmentSamplers(render_pass, 0, *binding, 1);
        // Bind the irradiance map
        binding = SDL_GPUTextureSamplerBinding.{ irradiance_map, global_renderer.sampler };
        SDL_BindGPUFragmentSamplers(render_pass, 1, *binding, 1);
        draw_scene(state, render_pass, frame_data.cmd, .COLOR);
    }
}

draw_scene :: (using state: *Game_State, render_pass: *SDL_GPURenderPass, cmd: *SDL_GPUCommandBuffer, kind: Pipeline_Kind) {

    SDL_BindGPUGraphicsPipeline(render_pass, global_renderer.static_mesh_material.pipelines[kind]);
    binding := SDL_GPUTextureSamplerBinding.{ global_renderer.empty_texture, global_renderer.sampler };
    SDL_BindGPUFragmentSamplers(render_pass, 2, *binding, 1);
    for y: 0..10 {
        for x: 0..10 {
            mat := PBR_Material.{
                albedo = .{1, 0, 0},
                roughness = x.(float) / 10.0,
                metallic = y.(float) / 10.0,
                ambient_occlusion = 1.0,
            };
            SDL_PushGPUFragmentUniformData(cmd, 1, *mat, size_of(type_of(mat)));
            push_transform(make_translation_matrix4(.{xx ((x - (10 / 2)) * 5), xx ((y - (10 / 2)) * 5), 0}), cmd);
            draw(sphere_mesh, render_pass);
        }
    }
}

main :: () {
    defer report_memory_leaks();
    defer log("Exit.");

    engine_run(
        game_state_create,
        game_state_input_event,
        game_state_update,
        game_state_draw,
        game_state_destroy
    );
}

#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Math";
#import "sl3dge-jai";
#import "stb_image";
