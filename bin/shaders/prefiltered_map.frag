#version 450 core
#extension GL_ARB_shading_language_include : require
#include "common.glsl"

layout(location = 0) in struct { vec3 local_pos; } In;
layout(location = 0) out vec4 out_color;

layout(set = FRAG_UNIFORM_SET, binding = 0) uniform Material_t {
    float roughness;
} Material;

layout(set = FRAG_SAMPLER_SET, binding = 0) uniform samplerCube environment_map;

float radical_inverse(uint bits) {
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}

vec2 hammersley(uint i, uint n) {
    return vec2(float(i)/float(n), radical_inverse(i));
}

vec3 ggx_sample(vec2 xi, vec3 normal, float roughness) {
    float a = roughness * roughness;

    float phi = 2.0 * PI * xi.x;
    float cos_theta = sqrt((1.0 - xi.y) / (xi.y) / (1.0 + (a * a - 1.0) * xi.y));
    float sin_theta = sqrt(1.0 - cos_theta * cos_theta);

    vec3 h = vec3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);
    vec3 up = abs(normal.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, normal));
    vec3 bitangent = cross(normal, tangent);

    vec3 sample_vec = tangent * h.x + bitangent * h.y + normal * h.z;
    return normalize(sample_vec);
}

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
