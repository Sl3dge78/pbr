#version 450 core
#extension GL_ARB_shading_language_include : require
#include "common.glsl"

layout(location = 0) in struct {
    vec4 vertex_color;
    vec3 normal;
    vec2 uv;
    vec4 pos_light_space;
    vec4 world_position;
} In;

layout(location = 0) out vec4 out_color;

layout(set = FRAG_UNIFORM_SET, binding = 0) uniform CameraData_t {
    CameraData camera;
};

layout(set = FRAG_UNIFORM_SET, binding = 1) uniform Material_t {
    vec3 albedo;
    float metallic;
    float roughness;
    float ambient_occlusion;
} Material;

layout(set = FRAG_SAMPLER_SET, binding = 0) uniform sampler2D shadow_map;
layout(set = FRAG_SAMPLER_SET, binding = 1) uniform sampler2D diffuse;
layout(set = FRAG_SAMPLER_SET, binding = 2) uniform samplerCube irradiance_map;
layout(set = FRAG_SAMPLER_SET, binding = 3) uniform samplerCube prefiltered_map;
layout(set = FRAG_SAMPLER_SET, binding = 4) uniform sampler2D brdf_lut;

const int pcf_count = 4;
const int pcf_total_texels = (pcf_count * 2 + 1) * (pcf_count * 2 + 1);
const float map_size = 2048.0;
const float texel_size = 1.0 / map_size;
const vec3 ambient_color = vec3(0.529, 0.808, 0.922);

const float constant = 1.0;
const float linear = 0.5;
const float quadratic = 0.02;

float shadow(vec4 shadow_coord, vec3 l) {
    vec3 proj_coords = In.pos_light_space.xyz / In.pos_light_space.w;
    vec2 uv = proj_coords.xy * 0.5 + 0.5;
    uv.y = 1 - uv.y;
    float current = proj_coords.z;
    float x = 1.0 - max(dot(In.normal, l), 0.0);
    float bias = max(2.5 * x, 1.0) * texel_size;

    int total = 0;
    for(int x = -pcf_count; x <= pcf_count; x++) {
        for(int y = -pcf_count; y <= pcf_count; y++) {
            float closest = texture(shadow_map, uv + vec2(x, y) * texel_size).r;        
            if (current - bias > closest) {
                total += 1;
            }
        }
    }
    float result = float(total) / float(pcf_total_texels);
    return 1.0 - result;
}

float distribution(vec3 n, vec3 h, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float nh = max(dot(n, h), 0.0);
    float nh2 = nh * nh;

    float denom = (nh2 * (a2 - 1.0) + 1.0);

    return a2 / (PI * denom * denom);
}

float ggx(float nv, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    return nv / (nv * (1.0 - k) + k);
}

float geometry(vec3 n, vec3 v, vec3 l, float roughness) {
    float nv = max(dot(n, v), 0.0);
    float nl = max(dot(n, l), 0.0);

    return ggx(nv, roughness) * ggx(nl, roughness);
}

// Fresnel Schlick
vec3 fresnel(float cos_theta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

vec3 fresnel_roughness(float cos_theta, vec3 F0, float roughness) {
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

void main() {

    vec3 position = In.world_position.xyz;
    vec3 normal = normalize(In.normal);
    vec3 view = normalize(camera.camera_position - position);

    vec3 F0 = mix(vec3(0.04), Material.albedo, Material.metallic);


    vec3 lo = vec3(0.0);
    for(int i = 0; i < camera.light_count; i++) {
        Light light = camera.lights[i];
        vec3 light_dir;

        vec3 radiance;
        if(light.kind == 0) { // Directional
            light_dir = -light.position_or_direction;
            radiance = light.color.xyz;
        } else { // Point
            light_dir = normalize(light.position_or_direction - position);
            float dist = length(light.position_or_direction - position);
            float attenuation = 1.0 / (dist * dist);
            radiance = light.color.xyz * attenuation;
        }
        float cos_theta = max(dot(normal, light_dir), 0.0);
        
        vec3 half_way_vector = normalize(view + light_dir);

        float NDF = distribution(normal, half_way_vector, Material.roughness);
        float G   = geometry(normal, view, light_dir, Material.roughness);
        vec3  F   = fresnel(max(dot(half_way_vector, view), 0.0), F0);

        vec3 kD = vec3(1.0) - F;
        kD *= 1.0 - Material.metallic;

        vec3 a = NDF * G * F;
        float b = 4.0 * max(dot(normal, view), 0.0) * cos_theta;
        vec3 specular = a / (b + 0.0001); 

        lo += (kD * Material.albedo / PI + specular) * radiance * cos_theta;
    }

    // Ambient -- IBL
    vec3 F = fresnel_roughness(max(dot(normal, view), 0.0), F0, Material.roughness);
    vec3 kS = F;
    vec3 kD = 1.0 - kS;
    kD *= 1.0 - Material.metallic;

    vec3 irradiance = texture(irradiance_map, normal).rgb;
    vec3 diffuse = irradiance * Material.albedo;

    vec3 r = reflect(-view, normal);
    const float MAX_REFLECTION_LOD = 4.0;
    vec3 prefiltered_color = textureLod(prefiltered_map, r, Material.roughness * MAX_REFLECTION_LOD).rgb;
    vec2 envBRDF = texture(brdf_lut, vec2(max(dot(normal, view), 0.0), Material.roughness)).rg;
    vec3 specular = prefiltered_color * (F * envBRDF.x + envBRDF.y);

    vec3 ambient = (kD * diffuse + specular) * Material.ambient_occlusion;
    vec3 color = ambient + lo;

    // Gamma
    out_color = vec4(color, 1.0);
}

