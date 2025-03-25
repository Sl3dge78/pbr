#version 450 core
#extension GL_ARB_shading_language_include : require
#include "common.glsl"
 
layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec2 in_uv;
layout(location = 3) in vec3 in_tangent;

layout(set = VTX_UNIFORM_SET, binding = 1) uniform constants {
    mat4 transform;
    mat4 inv_transform;
};

layout(set = VTX_UNIFORM_SET, binding = 0) uniform CameraData_t { CameraData camera; };

layout(location = 0) out struct {
    vec2 uv;
    vec4 pos_light_space;
    vec4 world_position;
    mat3 TBN;
} Out;

void main() {
    vec4 world_position = transform * vec4(in_pos, 1.0);
    gl_Position = camera.proj * camera.view * world_position;

    vec3 bitangent = cross(in_normal, in_tangent);
    mat3 normal_matrix = mat3(transpose(inv_transform));
    vec3 T = normalize(normal_matrix * in_tangent);
    vec3 B = normalize(normal_matrix * bitangent);
    vec3 N = normalize(normal_matrix * in_normal);
    Out.TBN = mat3(T, B, N);

    Out.world_position = world_position;
    Out.uv = in_uv;
    Out.pos_light_space = camera.sun * world_position;
}
