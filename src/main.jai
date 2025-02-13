Game_State :: struct {
    player: Player;

    sphere_mesh: Mesh;
}

Player :: struct {
    transform: Transform;
    yaw: float = -PI / 2.0;
    pitch: float = PI / 2.0;
    forward : Vector3;

    EYE_HEIGHT :: 1.6;  
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
}

game_state_destroy :: (using state: *Game_State) {
    destroy(*sphere_mesh);
}

game_state_update :: (using state: *Game_State, delta_time: float) {
    player_update(*player, state, delta_time);
}

game_state_input_event :: (using state: *Game_State, event: SDL_Event) {

}

game_state_draw :: (using state: *Game_State, frame_data: Frame_Data) {
    sun_dir := unit_vector(.{-1, -1, -1});
    lights : [16]Light;
    lights[0] = .{
        .DIRECTIONAL,
        sun_dir,
        .{1, 1, 1, 1},
    };

    size:: 40;
    light_proj := orthographic_projection_matrix(-size, size, -size, size, -size, size, true);
    light_view := make_look_at_matrix(.{0, 0, 0}, sun_dir, .{0, 1, 0}, false);
    light_matrix := light_proj * light_view;
    view := player_get_camera_matrix(*state.player);

    matrices := Global_Matrices.{
        projection = transpose(global_renderer.projection),
        view = transpose(view),
        sun = transpose(light_matrix),
        lights = lights,
        light_count = 1,
    };

    shadow_matrices := matrices;
    shadow_matrices.projection = transpose(light_proj);
    shadow_matrices.view = transpose(light_view);

    {   // Shadow pass
        render_pass := SDL_NullCheck(SDL_BeginGPURenderPass(frame_data.cmd, null, 0, *global_renderer.shadowmap_target));
        defer SDL_EndGPURenderPass(render_pass);
        SDL_PushGPUVertexUniformData(frame_data.cmd, 0, *shadow_matrices, size_of(type_of(shadow_matrices)));
        draw_scene(state, render_pass, frame_data.cmd, .SHADOWMAP);
    }

    {
        target := create_color_target(frame_data.target, .CLEAR, clear_color = .{0, 0, 0, 1});
        render_pass := SDL_NullCheck(SDL_BeginGPURenderPass(frame_data.cmd, *target, 1, *global_renderer.depth_stencil_target));
        defer SDL_EndGPURenderPass(render_pass);

        SDL_PushGPUVertexUniformData(frame_data.cmd, 0, *matrices, size_of(type_of(matrices)));
        SDL_PushGPUFragmentUniformData(frame_data.cmd, 0, *matrices, size_of(type_of(matrices)));

        // Bind the shadowmap
        binding := SDL_GPUTextureSamplerBinding.{ global_renderer.shadowmap, global_renderer.sampler };
        SDL_BindGPUFragmentSamplers(render_pass, 0, *binding, 1);
        draw_scene(state, render_pass, frame_data.cmd, .COLOR);
    }
}

draw_scene :: (using state: *Game_State, render_pass: *SDL_GPURenderPass, cmd: *SDL_GPUCommandBuffer, kind: Pipeline_Kind) {

    SDL_BindGPUGraphicsPipeline(render_pass, global_renderer.static_mesh_material.pipelines[kind]);
    binding := SDL_GPUTextureSamplerBinding.{ global_renderer.empty_texture, global_renderer.sampler };
    SDL_BindGPUFragmentSamplers(render_pass, 1, *binding, 1);
    for y: 0..10 {
        for x: 0..10 {
            
            mat := PBR_Material.{
                .{1, 1, 1},
                y / 10.0,
                x / 10.0,
                0.5,
            };
            SDL_PushGPUFragmentUniformData(cmd, 1, *mat, size_of(type_of(mat)));
            push_transform(make_translation_matrix4(.{xx (x * 5), xx (y * 5), 0}), cmd);
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
