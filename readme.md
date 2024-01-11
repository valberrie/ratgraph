# ratgraph
![Icon](icon.png)

## Using this library
        git submodule update --init --recursive
        zig build run

## Depends on
[zalgebra](https://github.com/kooparse/zalgebra)
[stb](https://github.com/nothings/stb)
[libsbng](https://github.com/randy408/libspng)
[freetype](https://freetype.org/)

### History
Started as a cpp project that used SDL and opengl to draw 2d primitives. 
This version did not get very far.
Later I wrote a basic freetype/stb_truetype loader for opengl in cpp.
Once I started using zig I ported that font loader over and wrote a simple instant mode drawing library like raylib.
The issue with using raylib from zig is the null terminated strings so I wanted something to replace raylib.
Whenever I have written something I think is usefull I add it to this repository so I can use it in other projects.

### Current functionality
* AABB collision detection
* Opengl drawing, font loading
* A unfinished Imgui
* A basic ecs used in a mario clone
* Helper functions and structures for texture atlas generation
