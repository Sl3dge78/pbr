#version 450 core
#extension GL_ARB_shading_language_include : require
#include "common.glsl"

layout(location = 0) in vec3 in_pos;

layout(location = 0) out struct { vec3 pos; } Out;

layout(set = VTX_UNIFORM_SET, binding = 0) uniform CameraData_t { CameraData camera; };

void main() {
    Out.pos = in_pos;
    Out.pos.x *= -1.0;
    gl_Position = camera.proj * camera.view * vec4(in_pos, 1.0);
}
