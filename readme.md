# ratgraph
![Icon](icon.png)

Graphics code.

## Using this library
        git submodule update --init --recursive
        zig build run

## Depends on
* [zalgebra](https://github.com/kooparse/zalgebra)
* [stb](https://github.com/nothings/stb)
* [libsbng](https://github.com/randy408/libspng)
* [freetype](https://freetype.org/)

### Current functionality
* AABB collision detection
* Opengl drawing, font loading
* A unfinished Imgui
* A basic ecs used in a mario clone
* Helper functions and structures for texture atlas generation

### Todo
* Finish a basic GUI
* Remove the old `Context` from graphics.zig and replace with `NewCtx`
