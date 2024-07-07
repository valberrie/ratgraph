#version 460 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec2 texcoord;
layout (location = 2) in vec3 normal;
layout (location = 3) in uint color;

layout (location = 0) out vec4 out_color;
layout (location = 1) out vec2 out_texcoord;
layout (location = 2) out vec3 out_normal;
layout (location = 3) out vec3 frag_pos;

uniform mat4 model = mat4(1.0f);
uniform mat4 view = mat4(1.0f);

void main() {
    vec4 world_pos = model * vec4(aPos,1.0);
    frag_pos = world_pos.xyz;
    out_color = unpackUnorm4x8(color).abgr;
    out_texcoord = texcoord;
    out_normal = transpose(inverse(mat3(model))) * normal;
    gl_Position =   view * world_pos;
};
