#version 450 core
#extension GL_ARB_shading_language_include : require
#include "common.glsl"

layout(location = 0) in struct { vec3 local_pos; } In;
layout(location = 0) out vec4 out_color;

layout(set = FRAG_UNIFORM_SET, binding = 0) uniform CameraData_t { CameraData camera; };
layout(set = FRAG_SAMPLER_SET, binding = 0) uniform samplerCube environment_map;

void main() {
    vec3 normal = normalize(In.local_pos);
    vec3 irradiance = vec3(0.0);
    
    vec3 up    = vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(up, normal));
    up         = normalize(cross(normal, right));

    float sample_delta = 0.025;
    // sample_delta = (0.25 * PI);
    int nb_samples = 0;
    for(float phi = 0.0; phi < 2.0 * PI; phi += sample_delta) {
        for(float theta = 0.0; theta < 0.5 * PI; theta += sample_delta) {
            vec3 tangent = vec3(
                    sin(theta) * cos(phi),
                    sin(theta) * sin(phi),
                    cos(theta)
            );
            vec3 dir = tangent.x * right + tangent.y * up + tangent.z * normal;
            irradiance += texture(environment_map, dir).rgb * cos(theta) * sin(theta);
            nb_samples += 1;
        }
    }
    irradiance = PI * irradiance / float(nb_samples);
    out_color = vec4(irradiance, 1.0);
    // out_color = vec4(texture(environment_map, normal).rgb, 1.0);
}

