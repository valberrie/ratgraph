#version 420 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec4 color;

layout (location = 0) out vec4 out_color;
uniform mat4 model = mat4(1.0f);
uniform mat4 view = mat4(1.0f);
void main()
{
   //gl_Position = vec4(aPos.x + 0.2, aPos.y, aPos.z, 1.0f);
   gl_Position = view * model * vec4(aPos, 1.0f);

    //gl_Position = vec4(0.5, 0,0,1.0f);
   out_color = color;
};
