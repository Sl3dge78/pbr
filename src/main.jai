Game_State :: struct {
    player: Player;

    sphere_mesh: Mesh;
    skybox: Cube_Map;
    irradiance_map: Cube_Map;
    prefiltered_map: Cube_Map;
    prefiltered_sampler: *SDL_GPUSampler;

    BRDF_SIZE :: 512;
    precomputed_brdf: *SDL_GPUTexture;

    unit_cube: Mesh;
    unit_plane: Mesh;

    skybox_mode : enum {
        SKYBOX;
        IRRADIANCE;
        PREFILTERED;
    } = .PREFILTERED;
    time : float;
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

game_state_create :: (using state: *Game_State) {
    sphere_mesh = load_mesh_from_file("res/sphere.glb");
    player.transform.position = .{25, 25, 75};
    offset : *Global_Matrices = xx 0;
    skybox = cube_map_from_files("res/env3");

    IRRADIANCE_SIZE :: 32;
    irradiance_map = empty_cube_map(IRRADIANCE_SIZE, IRRADIANCE_SIZE, format = CUBE_MAP_FORMAT, name = "Irradiance", usage = .SAMPLER | .COLOR_TARGET);

    prefiltered_map = empty_cube_map(PREFILTERED_SIZE, PREFILTERED_SIZE, format = CUBE_MAP_FORMAT, name = "Prefiltered Env Map", usage = .SAMPLER | .COLOR_TARGET, mips = PREFILTERED_MIPS);

    sampler_ci := SDL_GPUSamplerCreateInfo.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mipmap_mode = .LINEAR,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
        mip_lod_bias = 0,
        // max_anisotropy = 16,
        compare_op = .ALWAYS,
        min_lod = 0,
        max_lod = PREFILTERED_MIPS,
        enable_anisotropy = false,
        enable_compare = false,
    };
    prefiltered_sampler = SDL_NullCheck(SDL_CreateGPUSampler(global_renderer.device, *sampler_ci));

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
        builder: Mesh_Builder;
        mesh_builder_push_quad(*builder, .{1, -1, -1}, .{1, -1, 1}, .{1, 1, 1 }, .{1, 1, -1 }, .{-1, 0, 0});
        unit_plane = mesh_builder_load_mesh(*builder);
    }

    texture_ci := SDL_GPUTextureCreateInfo.{
        type = ._2D,
        format = .R16G16_FLOAT,
        usage = .SAMPLER | .COMPUTE_STORAGE_WRITE,
        width = BRDF_SIZE,
        height = BRDF_SIZE,
        layer_count_or_depth = 1,
        num_levels = 1,
        sample_count = ._1,
        props = 0,
    };
    precomputed_brdf = SDL_CreateGPUTexture(global_renderer.device, *texture_ci);
    SDL_SetGPUTextureName(global_renderer.device, precomputed_brdf, "precomputed_brdf");

    resources.on_reload = on_resources_reload;
    resources.data = state;
    init_scene_lighting(state);
}

on_resources_reload :: (r: *Resource_Info, data: *void) {
    using game_state := data.(*Game_State);
    game_state.time = 0;
    if r.pointer == *resources.irradiance { 
        render_irradiance(unit_cube, skybox, irradiance_map, time);
    }
    if r.pointer == *resources.prefiltered { 
        render_prefiltered_map(unit_cube, skybox, prefiltered_map);
    }
}

game_state_destroy :: (using state: *Game_State) {
    destroy(precomputed_brdf);
    destroy(*sphere_mesh);
    destroy(skybox);
    destroy(irradiance_map);
    destroy(prefiltered_map);
    destroy(*unit_cube);
    SDL_ReleaseGPUSampler(global_renderer.device, prefiltered_sampler);
}

// --------
// Update

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

game_state_update :: (using state: *Game_State, delta_time: float) {
    player_update(*player, state, delta_time);
    time += delta_time;
}

game_state_input_event :: (using state: *Game_State, event: SDL_Event) {
    if(event.type == .KEY_DOWN) {
        if(event.key.scancode == .B) {
            skybox_mode = .SKYBOX;
        }
        if(event.key.scancode == .I) {
            skybox_mode = .IRRADIANCE;
        }
        if(event.key.scancode == .P) {
            skybox_mode = .PREFILTERED;
        }
        if event.key.scancode == ._1 {
            destroy(skybox);
            skybox = cube_map_from_files("res/env1");
            init_scene_lighting(state);
        }
        if event.key.scancode == ._2 {
            destroy(skybox);
            skybox = cube_map_from_files("res/env2");
            init_scene_lighting(state);
        }
        if event.key.scancode == ._3 {
            destroy(skybox);
            skybox = cube_map_from_files("res/env3");
            init_scene_lighting(state);
        }
    }
}

game_state_draw :: (using state: *Game_State, frame_data: Frame_Data) {
    sun_dir := unit_vector(.{-1, -1, -1});
    lights : [16]Light;
    lights[0] = .{ .POINT, .{-10, 10, 10}, .{300.0, 300.0, 300.0}};
    lights[1] = .{ .POINT, .{10, 10, 10}, .{300.0, 300.0, 300.0}};
    lights[2] = .{ .POINT, .{-10, -10, 10}, .{300.0, 300.0, 300.0}};
    lights[3] = .{ .POINT, .{10, -10, 10}, .{300.0, 300.0, 300.0}};

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
        time = time,
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

        SDL_BindGPUGraphicsPipeline(render_pass, resources.skybox);
        SDL_PushGPUVertexUniformData(frame_data.cmd, 0, *matrices, size_of(type_of(matrices)));
        SDL_PushGPUFragmentUniformData(frame_data.cmd, 0, *matrices, size_of(type_of(matrices)));

        if skybox_mode == {
            case .IRRADIANCE; {
                bind_fragment_texture(render_pass, 0, irradiance_map); 
            }
            case .SKYBOX; { 
                bind_fragment_texture(render_pass, 0, skybox); 
            }
            case .PREFILTERED; { 
                bind_fragment_texture(render_pass, 0, prefiltered_map, prefiltered_sampler); 
            }
        }
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

    SDL_BindGPUGraphicsPipeline(render_pass, resources.static_mesh.pipelines[kind]);
    binding := SDL_GPUTextureSamplerBinding.{ global_renderer.empty_texture, global_renderer.sampler };
    SDL_BindGPUFragmentSamplers(render_pass, 2, *binding, 1);
    nb_x := 7;
    nb_y := 7;
    spacing := 2.5;
    for y: 0..nb_x-1 {
        for x: 0..nb_y-1 {
            mat := PBR_Material.{
                albedo = .{0.5, 0, 0},
                roughness = x.(float) / nb_x,
                metallic = y.(float) / nb_y,
                ambient_occlusion = 1.0,
            };
            SDL_PushGPUFragmentUniformData(cmd, 1, *mat, size_of(type_of(mat)));
            x2 : float = (x - (nb_x / 2)) * spacing;
            y2 : float = (y - (nb_y / 2)) * spacing;
            push_transform(make_translation_matrix4(.{x2, y2, -2}), cmd);
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

#load "pbr.jai";
