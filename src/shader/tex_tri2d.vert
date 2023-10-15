#version 420 core
layout (location = 0) in vec2 pos;
layout (location = 1) in vec2 uv;
layout (location = 2) in uint z;
layout (location = 3) in uint color;

layout (location = 0) out vec4 out_color;
layout (location = 1) out vec2 out_texcoord;

uniform mat4 model = mat4(1.0f);
uniform mat4 view = mat4(1.0f);
void main() {
   out_texcoord = uv;
   gl_Position = view * model * vec4(pos, z, 1.0f);
   out_color = unpackUnorm4x8(color);
};
