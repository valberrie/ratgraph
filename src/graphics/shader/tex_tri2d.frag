#version 420 core
layout (location = 0) in vec4 color;
layout (location = 1) in vec2 texcoord;
layout (location = 0) out vec4 FragColor;

uniform sampler2D text;

void main() {
    FragColor = texture(text, texcoord) * color;
};
