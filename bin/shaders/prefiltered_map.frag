#version 450 core
#extension GL_ARB_shading_language_include : require
#include "common.glsl"

layout(location = 0) in struct { vec3 local_pos; } In;
layout(location = 0) out vec4 out_color;

layout(set = FRAG_UNIFORM_SET, binding = 0) uniform Material_t {
    float roughness;
} Material;

layout(set = FRAG_SAMPLER_SET, binding = 0) uniform samplerCube environment_map;

void main() {
    vec3 n = normalize(In.local_pos);
    vec3 r = n;
    vec3 v = r;

    const uint SAMPLE_COUNT = 16384;
    float total_weight = 0.0;
    vec3 prefiltered_color = vec3(0.0);
    for(uint i = 0; i < SAMPLE_COUNT; i++) {
        vec2 xi = hammersley(i, SAMPLE_COUNT);
        vec3 h = ggx_sample(xi, n, Material.roughness);
        vec3 l = normalize(2.0 * dot(v, h) * h - v);
        float n_dot_l = dot(n, l);
        if (n_dot_l > 0.0) {
            prefiltered_color += tonemap(texture(environment_map, l).rgb) * n_dot_l;
            total_weight += n_dot_l;
        }
    }
    prefiltered_color = prefiltered_color / total_weight;
    out_color = vec4(prefiltered_color, 1.0);
}
