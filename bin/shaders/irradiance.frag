#version 450 core
#extension GL_ARB_shading_language_include : require
#include "common.glsl"

layout(location = 0) in struct { vec3 local_pos; } In;
layout(location = 0) out vec4 out_color;

layout(set = FRAG_UNIFORM_SET, binding = 0) uniform CameraData_t { CameraData camera; };
layout(set = FRAG_SAMPLER_SET, binding = 0) uniform samplerCube environment_map;

vec3 tonemap(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
}

vec3 sample_1(vec3 normal) {
    vec3 irradiance = vec3(0.0);
    
    vec3 up    = vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(up, normal));
    up         = normalize(cross(normal, right));

    float sample_delta = 0.025;
    float freq = 10.0;
    int nb_samples = 0;
    for(float phi = 0.0; phi < 2.0 * PI; phi += sample_delta) {
        for(float theta = 0.0; theta < 0.5 * PI; theta += sample_delta) {
            vec3 tangent = vec3(
                    sin(theta) * cos(phi),
                    sin(theta) * sin(phi),
                    cos(theta)
            );
            vec3 dir = tangent.x * right + tangent.y * up + tangent.z * normal;
            irradiance += tonemap(texture(environment_map, dir).rgb) * cos(theta) * sin(theta);
            nb_samples += 1;
        }
    }
    irradiance = PI * irradiance / float(nb_samples);
    return irradiance;
}

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

vec3 ggx_sample(vec2 xi, vec3 normal) {
    float phi = 2.0 * PI * xi.x;
    float cos_theta = sqrt((1.0 - xi.y) / (xi.y));
    float sin_theta = sqrt(1.0 - cos_theta * cos_theta);

    vec3 h = vec3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);
    vec3 up = abs(normal.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, normal));
    vec3 bitangent = cross(normal, tangent);

    vec3 sample_vec = tangent * h.x + bitangent * h.y + normal * h.z;
    return normalize(sample_vec);
}

vec3 sample_2(vec3 normal) {
    const uint SAMPLE_COUNT = 16384;
    float total_weight = 0.0;
    vec3 irradiance = vec3(0.0);
    for(uint i = 0; i < SAMPLE_COUNT; i++) {
        vec2 xi = hammersley(i, SAMPLE_COUNT);
        vec3 h = ggx_sample(xi, normal);
        float n_dot_h = max(dot(normal, h), 0.0);
        irradiance += texture(environment_map, h).rgb * n_dot_h;
        total_weight += n_dot_h;
    }
    irradiance = (PI * irradiance) / total_weight;
    return irradiance;

}

void main() {
    vec3 normal = normalize(In.local_pos);
    vec3 irradiance = sample_1(normal);
    out_color = vec4(irradiance, 1.0);
}

