#version 460 core
layout (location = 0) out vec4 g_pos;
layout (location = 1) out vec4 g_norm;
layout (location = 2) out vec4 g_albedo;


layout (location = 0) in vec4 in_color;
layout (location = 1) in vec2 in_texcoord;
layout (location = 2) in vec3 in_normal;
layout (location = 3) in vec3 in_frag_pos;

layout (binding = 0) uniform sampler2D diffuse_texture;
layout (binding = 1) uniform sampler2D normal_texture;


void main(){
    g_pos = vec4(in_frag_pos,1);
    //g_norm = vec4(texture(normal_texture, in_texcoord).rgb, 1);
    g_norm = vec4(normalize(in_normal),1);
    g_albedo.rgb = in_color.rgb * texture(diffuse_texture, in_texcoord).rgb;
    g_albedo.a = 1;
}
