#version 420 core
layout (location = 0) in vec2 pos;
layout (location = 1) in uint z;
layout (location = 2) in uint color;

layout (location = 0) out vec4 out_color;
uniform mat4 model = mat4(1.0f);
uniform mat4 view = mat4(1.0f);
void main()
{
   gl_Position = view * model * vec4(pos, z, 1.0f);

   //out_color = vec4(1,1,1,1);
   out_color = unpackUnorm4x8(color).abgr;
};
