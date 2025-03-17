// For SPIR-V shaders, use the following resource sets:
// 
// For vertex shaders:
//     0: Sampled textures, followed by storage textures, followed by storage buffers
//     1: Uniform buffers
// 
// For fragment shaders:
//     2: Sampled textures, followed by storage textures, followed by storage buffers
//     3: Uniform buffers
#define VTX_SAMPLER_SET  0
#define VTX_STORAGE_BUFFER_SET  0
#define VTX_UNIFORM_SET  1
#define FRAG_SAMPLER_SET 2
#define FRAG_UNIFORM_SET 3

// For SPIR-V shaders, use the following resource sets:
//    0: Sampled textures, followed by read-only storage textures, followed by read-only storage buffers
//    1: Write-only storage textures, followed by write-only storage buffers
//    2: Uniform buffers
#define COMP_SAMPLER_SET 0
#define COMP_READONLY_TEXTURE_SET 0
#define COMP_READONLY_BUFFER_SET 0
#define COMP_WRITEONLY_TEXTURE_SET 1
#define COMP_WRITEONLY_BUFFER_SET 1
#define COMP_UNIFORM_BUFFER_SET 2

const float PI = 3.14159265359;

struct Light {
    int kind;
    vec3 position_or_direction;
    vec4 color;
};

struct CameraData {
    mat4 proj;
    mat4 view;
    mat4 sun;
    vec3 camera_position;
    uint light_count;
    Light lights[16];
    float time;
};

vec3 gamma(vec3 color) {
    vec3 result = color / (color + vec3(1.0));
    return pow(result, vec3(1.0/2.0));
}

vec3 tonemap(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
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

vec3 ggx_sample(vec2 xi, vec3 normal, float roughness) {
    float a = roughness * roughness;

    float phi = 2.0 * PI * xi.x;
    float cos_theta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
    float sin_theta = sqrt(1.0 - cos_theta * cos_theta);

    vec3 h = vec3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);
    vec3 up = abs(normal.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, normal));
    vec3 bitangent = cross(normal, tangent);

    vec3 sample_vec = tangent * h.x + bitangent * h.y + normal * h.z;
    return normalize(sample_vec);
}
