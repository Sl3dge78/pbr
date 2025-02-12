#version 450 core
#extension GL_ARB_shading_language_include : require
#include "common.glsl"
 
layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec2 in_uv;
layout(location = 3) in vec4 in_color;

layout(set = VTX_UNIFORM_SET, binding = 1) uniform constants {
    mat4 transform;
    mat4 inv_transform;
};

struct Light {
    int kind;
    vec3 position;
    vec3 target;
    vec4 color;
};

layout(set = VTX_UNIFORM_SET, binding = 0) uniform CameraBuffer {
    mat4 proj;
    mat4 view;
    mat4 sun;
    uint light_count;
    Light lights[16];
};

layout(location = 0) out struct {
    vec4 color;
    vec3 normal;
    vec2 uv;
    vec4 pos_light_space;
    vec4 world_position;
} Out;

void main() {
    vec4 world_position = transform * vec4(in_pos, 1.0);
    gl_Position = proj * view * world_position;
    Out.world_position = world_position;
    Out.color = in_color;
    Out.normal = mat3(transpose(inv_transform)) * in_normal;
    Out.uv = in_uv;
    Out.pos_light_space = sun * world_position;
}
