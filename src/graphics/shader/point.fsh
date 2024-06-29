#version 420 core
layout (location = 0) in vec4 color;
layout (location = 0) out vec4 FragColor;


void main()
{
    //Make the point a circle rather than a square
   float r = 1 - abs(length(gl_PointCoord - vec2(0.5)) );
   if(r < 0.5){
        discard;
   }
   FragColor = color;
};
