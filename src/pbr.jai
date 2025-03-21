
init_scene_lighting :: (using game_state: *Game_State) {
    render_irradiance(unit_cube, skybox, irradiance_map, 0);
    render_prefiltered_map(unit_cube, skybox, prefiltered_map);
    render_brdf(game_state);
}

render_brdf :: (using game_state: *Game_State) {
    cmd := SDL_AcquireGPUCommandBuffer(global_renderer.device);
    defer SDL_SubmitGPUCommandBuffer(cmd);
    
    binding := SDL_GPUStorageTextureReadWriteBinding.{
        texture = precomputed_brdf,
        mip_level = 0, layer = 0, cycle = false
    };
    pass := SDL_BeginGPUComputePass(cmd, *binding, 1, null, 0);
    defer SDL_EndGPUComputePass(pass);

    SDL_BindGPUComputePipeline(pass, resources.brdf_convolution);
    SDL_DispatchGPUCompute(pass, BRDF_SIZE, BRDF_SIZE, 1);
}

render_irradiance :: (unit_cube: Mesh, source: Cube_Map, target: Cube_Map, time: float) {
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
            time = time,
        };

        pass := SDL_NullCheck(SDL_BeginGPURenderPass(cmd, *color_target, 1, null));
        defer SDL_EndGPURenderPass(pass);
        SDL_BindGPUGraphicsPipeline(pass, resources.irradiance);

        SDL_PushGPUVertexUniformData(cmd, 0, *matrices, size_of(type_of(matrices)));
        SDL_PushGPUFragmentUniformData(cmd, 0, *matrices, size_of(type_of(matrices)));

        bind_fragment_texture(pass, 0, source); 
        draw(unit_cube, pass);
    }
    log("Irradiance rendered");
}

PREFILTERED_SIZE :: 128;
PREFILTERED_MIPS :: 5;

render_prefiltered_map :: (unit_cube: Mesh, source: Cube_Map, target: Cube_Map) {

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
    for mip_level: 0..PREFILTERED_MIPS-1 {
        roughness := cast(float)mip_level / cast(float)(PREFILTERED_MIPS-1);
        for 0..6-1 {
            color_target := SDL_GPUColorTargetInfo.{
                texture = target,
                mip_level = xx mip_level,
                layer_or_depth_plane = xx it,
                clear_color = .{0, 0, 0, 0},
                load_op = .DONT_CARE,
                store_op = .STORE,
                cycle = false,
            };
            pass := SDL_NullCheck(SDL_BeginGPURenderPass(cmd, *color_target, 1, null));
            defer SDL_EndGPURenderPass(pass);
            SDL_BindGPUGraphicsPipeline(pass, resources.prefiltered);

            matrices := Global_Matrices.{
                camera_position = .{0, 0, 0},
                projection = transpose(projection),
                view = transpose(views[it]),
                time = 0,
            };

            push_vertex_uniform(cmd, 0, matrices);
            push_fragment_uniform(cmd, 0, roughness);
            bind_fragment_texture(pass, 0, source); 
            draw(unit_cube, pass);
        }
    }
    log("Prefiltered map renderered");
}

empty_cube_map :: (width: int, height: int, format : SDL_GPUTextureFormat, usage: SDL_GPUTextureUsageFlags = .SAMPLER, mips := 1, name: string = "") -> Cube_Map {
    texture_ci := SDL_GPUTextureCreateInfo.{
        type = .CUBE,
        format = format,
        width = xx width,
        height = xx height,
        layer_count_or_depth = 6,
        num_levels = xx mips,
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
    // assert(channels == 3);

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

load_from_file :: (path: string, mesh: *Mesh, material: *PBR_Material2) -> bool {
    gltf_data := gltf_parse_file(path);
    defer gltf_free(*gltf_data);
    gltf_load_buffers(*gltf_data);

    current_dir := get_working_directory();
    defer set_working_directory(current_dir);

    dir := path_strip_filename(path);
    set_working_directory(dir);

    mesh.* = load_mesh_from_gltf_data(gltf_data);
    success := load_pbr_material_from_gltf_data(gltf_data, material);
    return success;
}

PBR_Material2 :: struct {
    using buffer: PBR_Material_Buffer;
    albedo_texture: *SDL_GPUTexture;
    metallic_roughness_texture: *SDL_GPUTexture;
    normal_texture: *SDL_GPUTexture; // TODO
    ao_texture: *SDL_GPUTexture;
}

bind :: (mat: PBR_Material2, cmd: *SDL_GPUCommandBuffer, render_pass: *SDL_GPURenderPass) {
    SDL_PushGPUFragmentUniformData(cmd, 1, *mat.buffer, size_of(type_of(mat.buffer)));
    if mat.albedo_texture {
        bind_fragment_texture(render_pass, .DIFFUSE, mat.albedo_texture);
    } else {
        bind_fragment_texture(render_pass, .DIFFUSE, global_renderer.empty_texture);
    }
    // if mat.metallic_roughness_texture {
    //     bind_fragment_texture(render_pass, .METALLIC_ROUGHNESS, mat.metallic_roughness_texture);
    // } else {
         // bind_fragment_texture(render_pass, .METALLIC_ROUGHNESS, global_renderer.empty_texture);
    // }
    // if mat.ao_texture {
    //     bind_fragment_texture(render_pass, .AMBIENT_OCCLUSION, mat.ao_texture);
    // } else {
         // bind_fragment_texture(render_pass, 5 /*.AMBIENT_OCCLUSION*/, global_renderer.empty_texture);
    // }
}

load_texture_from_gltf_data :: (gltf_data: GLTF_Data, info: GLTF_Texture_Info, result: **SDL_GPUTexture) -> bool {
    texture_info := gltf_data.textures[info.index];
    image_info := gltf_data.images[texture_info.source];
    assert(image_info.uri != "", "Unable to load image from other sources than external pngs, yet");
    result.* = texture_from_file(image_info.uri);
    return true;
}

load_pbr_material_from_gltf_data :: (gltf_data: GLTF_Data, material: *PBR_Material2) -> bool {
    assert(gltf_data.materials.count == 1);
    mat := gltf_data.materials[0];

    {   // Mettalic Roughness
        mr := mat.metallic_roughness;
        material.albedo = .{ mr.base_color_factor[0], mr.base_color_factor[1], mr.base_color_factor[2] };
        if mr.has_base_color {
            success := load_texture_from_gltf_data(gltf_data, mr.base_color_texture, *material.albedo_texture);
            if !success {
                log_error("Unable to load base color texture");
                return false;
            }
        }
        material.metallic = mr.metallic_factor;
        material.roughness = mr.roughness_factor;
        if mr.has_metallic_roughness {
            success := load_texture_from_gltf_data(gltf_data, mr.metallic_roughness_texture, *material.metallic_roughness_texture);
            if !success {
                log_error("Unable to load metallic_roughness_texture");
                return false;
            }
        }
    }

    {   // Other
        if mat.has_normal {
            success := load_texture_from_gltf_data(gltf_data, mat.normal_texture, *material.normal_texture);
            if !success {
                log_error("Unable to load normal_texture");
                return false;
            }
        }

        if mat.has_occlusion {
            success := load_texture_from_gltf_data(gltf_data, mat.occlusion_texture, *material.ao_texture);
            if !success {
                log_error("Unable to load occlusion_texture");
                return false;
            }
        }
    }

    return true;
}

