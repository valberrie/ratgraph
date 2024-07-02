
#version 420 core
layout (location = 0) in vec4 color;
layout (location = 1) in vec2 texcoord;
layout (location = 2) in vec3 normal;

in vec3 frag_pos;
in vec4 frag_pos_lightspace;

layout (location = 0) out vec4 FragColor;


uniform sampler2D diffuse_texture;
uniform sampler2D shadow_map;

uniform vec3 view_pos;

    float pitch = radians(70.0);
    float yaw = radians(148) ;
    vec3 light_dir = normalize(vec3(cos(pitch), sin(pitch), sin(yaw)));

float shadowCalculation(vec4 fp_ls){
    float bias = max(0.05 * (1.0 - dot(normal, light_dir)), 0.005);
    vec3 proj_coord = fp_ls.xyz / fp_ls.w;
    proj_coord = proj_coord * 0.5 + 0.5;

    float closest_depth = texture(shadow_map, proj_coord.xy).r;
    float current_depth = proj_coord.z;
    float shadow = current_depth - bias > closest_depth ? 0.9: 0.0;
    return shadow;
}

void main() {
    vec3 lightpos = vec3(10,10,10);
    float ambient_strength = 0.3;
    vec3 light_color = vec3(240/255.0, 187/255.0, 117/255.0  );
    vec3 ambient_color = vec3(135 / 255.0, 172 / 255.0, 180 / 255.0 );
    float specular_strength = 0.5;

    vec3 norm = normalize(normal);
    float diff = max(dot(norm, light_dir), 0.0);
    vec3 diffuse = diff * light_color;

    vec3 view_dir = normalize(view_pos - frag_pos);
    vec3 reflect_dir = reflect(-light_dir, norm);
    float spec = pow(max(dot(view_dir, reflect_dir), 0.0), 32);
    vec3 specular = specular_strength * spec * light_color;

    float shadow = shadowCalculation(frag_pos_lightspace);


    vec3 ambient = ambient_strength * ambient_color;
    vec3 result = (ambient + (1.0 - shadow) * (diffuse + specular)) * color.rgb * texture(diffuse_texture, texcoord).rgb;


    //FragColor = texture(diffuse_texture, texcoord) * color * vec4(ambient,1.0);
    FragColor = vec4(result,1.0);
};
