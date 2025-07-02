#version 420 core
layout (location = 0) in vec4 color;
layout (location = 1) in vec2 texcoord;
layout (location = 0) out vec4 FragColor;


uniform sampler2D text;
uniform vec3 textColor;

void main() {
    vec4 sampled = vec4(1.0, 1.0, 1.0, texture(text, texcoord).r);
    FragColor = color * sampled;
    //if(FragColor.a < (5.0 / 255.0))
    //    discard;
};
