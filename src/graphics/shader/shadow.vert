#version 420 core
layout (location = 0) in vec3 pos;
layout (location = 1) in vec3 normal;
layout (location = 2) in vec2 tex_coord;

out VS_OUT {
    vec3 FragPos;
    vec3 Normal;
    vec3 TexCoord;
    vec3 FragPosLightSpace;
}   vs_out;

uniform mat4 proj;
uniform mat4 view;
uniform mat4 model;
uniform mat4 light_space;

void main(){
    vs_out.FragPos = vec3(model * vec4(pos, 1.0));
    vs_out.Normal = transpose(inverse(mat3(model))) * normal;
    vs_out.TexCoord = tex_coord;
    vs_out.FragPosLightSpace = light_space * vec4(vs_out.FragPos, 1.0);
    gl_Position = proj * view * vec4(vs_out.FragPos, 1.0);
}

