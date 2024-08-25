#version 420 core
layout (location = 0) in vec4 color;
layout (location = 1) in vec2 texcoord;
layout (location = 0) out vec4 FragColor;


uniform sampler2D text;
uniform vec3 textColor;

void main() {
    //FragColor = texture(text, texcoord);

    vec4 sampled = vec4(1.0, 1.0, 1.0, texture(text, texcoord).r);
    FragColor = color * sampled;
    //FragColor.rgb = pow(FragColor.rgb, vec3(1.0 / 1.8));
    //if(FragColor.a < (40.0 / 255.0)){

    //    discard;
    //}
};
