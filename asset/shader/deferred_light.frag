#version 460 core
out vec4 FragColor;

in vec2 TexCoords;

layout(binding = 0) uniform sampler2D g_pos;
layout(binding = 1) uniform sampler2D g_norm;
layout(binding = 2) uniform sampler2D g_albedo;

layout(binding = 3) uniform sampler2DArray shadow_map;

layout (std140, binding = 0) uniform LightSpaceMatrices {
    mat4 lightSpaceMatrices[16];
};

uniform float cascadePlaneDistances[16];
uniform mat4 view;
uniform vec3 view_pos;
uniform vec3 light_dir;
uniform vec3 light_color;
uniform float exposure;
uniform float gamma = 2.2;
int CASCADE_COUNT = 4;

float shadowCalculation(vec3 fp, vec3 norm){
    vec4 fp_vs = view * vec4(fp, 1.0);
    float depth = abs(fp_vs.z);
    int layer = CASCADE_COUNT - 1;
    for(int i = 0; i < CASCADE_COUNT; i++){
        if(depth < cascadePlaneDistances[i]){
            layer = i;
            break;
        }
    }
    mat4 ls = lightSpaceMatrices[layer];
    //vec4 frag_pos_ls = lightSpaceMatrices[layer] * vec4(fp, 1.0);
    vec4 frag_pos_ls = ls * vec4(fp, 1.0);
    vec3 proj_coord = frag_pos_ls.xyz / frag_pos_ls.w;
    //vec3 proj_coord = frag_pos_ls.xyz ;
    proj_coord = proj_coord * 0.5 + 0.5;
    //float current_depth = proj_coord.z;
    //if(current_depth > 1.0){
    //    return 0.0;
    //}

    float bias = max(0.005 * (1.0 - dot(norm, light_dir)), 0.005);
    const float bias_mod = 0.5;
    bias *= 1 / (cascadePlaneDistances[layer] * bias_mod);

    float closest_depth = texture(shadow_map, vec3(proj_coord.xy, layer)).r;
    float current_depth = proj_coord.z;
    float shadow = current_depth - bias > closest_depth ? 0.9: 0.0;


    shadow = 0.0;
    vec2 texel_size = 1.0 / vec2(textureSize(shadow_map, 0));
    for(int x = -1; x <= 1; x++){
        for(int y = -1; y <= 1; y++){
            float pcf_depth = texture(shadow_map, vec3(proj_coord.xy  + vec2(x,y) * texel_size, layer)).r;
            shadow += (current_depth - bias) > pcf_depth ? 1.0: 0.0;
        }
    }
    shadow /= 9.0;
    return shadow;
}

vec2 crtCurve(vec2 uv, float warp){
    vec2 dc = abs(0.5 - uv);
    dc *= dc;
    uv.x -= 0.5; uv.x *= 1.0+(dc.y*(0.3*warp)); uv.x += 0.5;
    uv.y -= 0.5; uv.y *= 1.0+(dc.x*(0.4*warp)); uv.y += 0.5;

    if (uv.y > 1.0 || uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0){
        //FragColor = vec4(1,0.0,0.0,1.0);
        FragColor = vec4(1, 0.973, 0.906, 1.0);
    }
    return uv;
}

void main(){
    vec2 uv = TexCoords;

    vec3 frag_pos = texture(g_pos, uv).rgb;
    vec3 normal = texture(g_norm, uv).rgb;
    vec3 diffuse = texture(g_albedo, uv).rgb;

    float ambient_strength = 0.3;
    vec3 ambient_color = vec3(135 / 255.0, 172 / 255.0, 180 / 255.0 );
    float specular_strength = 0.5;

    float diff = max(dot(normal, light_dir), 0.0);
    vec3 diffuse1 = diff * light_color;

    vec3 view_dir = normalize(view_pos - frag_pos);
    vec3 reflect_dir = reflect(-light_dir, normal);
    float spec = pow(max(dot(view_dir, reflect_dir), 0.0), 32);
    vec3 specular = specular_strength * spec * light_color;

    float shadow = shadowCalculation(frag_pos, normal);


    vec3 ambient = ambient_strength * ambient_color;
    vec3 result = (ambient + (1.0 - shadow) * (diffuse1 + specular)) * diffuse;


    //vec3 mapped = result / (result + vec3(1.0));
    vec3 mapped = vec3(1.0) - exp(-result * exposure);
    mapped = pow(mapped, vec3(1.0/gamma));
    FragColor = vec4(mapped, 1.0);
    //FragColor = vec4(result,1.0);
    //FragColor.rgb = pow(FragColor.rgb, vec3(1.0/gamma));
}


