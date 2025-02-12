Game_State :: struct {
    player: Player;
}

Player :: struct {
    transform: Transform;
    yaw: float = -PI / 2.0;
    pitch: float = PI / 2.0;
    forward : Vector3;

    EYE_HEIGHT :: 1.6;  
}

game_state_create :: (using state: *Game_State) {
}

game_state_destroy :: (using state: *Game_State) {
}

game_state_update :: (using state: *Game_State, delta_time: float) {
    player_update(*player, state, delta_time);
}

game_state_input_event :: (using state: *Game_State, event: SDL_Event) {

}

game_state_draw :: (using state: *Game_State, frame_data: Frame_Data) {
    lights : [16]Vector4;
    lights[0] = xyzw(unit_vector(.{-1, -1, -1}), 0);

    size:: 40;
    light_proj := orthographic_projection_matrix(-size, size, -size, size, -size, size, true);
    light_view := make_look_at_matrix(.{0, 0, 0}, lights[0].xyz, .{0, 1, 0}, false);
    light_matrix := light_proj * light_view;
    view := player_get_camera_matrix(*state.player);

    matrices := Global_Matrices.{
        projection = transpose(global_renderer.projection),
        view = transpose(view),
        light = transpose(light_matrix),
        light_count = 1,
        light_vec[0] = lights[0],
    };

    shadow_matrices := matrices;
    shadow_matrices.projection = transpose(light_proj);
    shadow_matrices.view = transpose(light_view);

    {   // Shadow pass
        render_pass := SDL_NullCheck(SDL_BeginGPURenderPass(frame_data.cmd, null, 0, *global_renderer.shadowmap_target));
        defer SDL_EndGPURenderPass(render_pass);
        SDL_PushGPUVertexUniformData(frame_data.cmd, 0, *shadow_matrices, size_of(type_of(shadow_matrices)));
        draw_scene(frame_data.cmd, render_pass, .SHADOWMAP, state);
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
        draw_scene(frame_data.cmd, render_pass, .COLOR, state);
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
#import "sl3dge-jai";
