#version 450 core
#extension GL_ARB_shading_language_include : require
#include "common.glsl"

layout(location = 0) in struct { vec3 uv; } In;
layout(location = 0) out vec4 out_color;

layout(set = FRAG_UNIFORM_SET, binding = 0) uniform CameraData_t { CameraData camera; };
layout(set = FRAG_SAMPLER_SET, binding = 0) uniform samplerCube skybox;

void main() {
    vec3 color = textureLod(skybox, In.uv, 1.2).rgb;
    out_color = vec4(color, 1.0);
}

