//Modified from original: https://www.shadertoy.com/user/kbjwes77

#version 420 core
layout (location = 0) in vec4 color;
layout (location = 1) in vec2 texcoord;
layout (location = 0) out vec4 FragColor;

uniform sampler2D text;
uniform vec3 textColor;

float warp = 0.35; // simulate curvature of CRT monitor
float scan = 0.35; // simulate darkness between scanlines

//vec2 res = vec2(, );

in vec4 gl_FragCoord;

void main(){
    vec2 uv = texcoord;
    //vec2 uv = texcoord.xy/res.xy;
    vec2 dc = abs(0.5-uv);
    dc *= dc;

    uv.x -= 0.5; uv.x *= 1.0+(dc.y*(0.3*warp)); uv.x += 0.5;
    uv.y -= 0.5; uv.y *= 1.0+(dc.x*(0.4*warp)); uv.y += 0.5;

    if (uv.y > 1.0 || uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0){
        //FragColor = vec4(1,0.0,0.0,1.0);
        FragColor = vec4(1, 0.973, 0.906, 1.0);
    }
    else{
        float apply = abs(sin(gl_FragCoord.y)*0.5*scan);
    	FragColor = vec4(mix(texture(text,uv).rgb,vec3(0.0),apply),1.0);

    }
    FragColor.bg *= 0.8;
    //FragColor.r *= 1.2;
}

