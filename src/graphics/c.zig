pub usingnamespace @cImport({
    //DLLs
    @cInclude("SDL2/SDL.h");
    @cInclude("epoxy/gl.h");
    @cInclude("freetype_init.h");
    @cInclude("spng.h");

    @cInclude("AL/al.h");
    @cInclude("AL/alc.h");

    //Static
    @cInclude("stb_rect_pack.h");
    @cInclude("stb_vorbis.h");
    @cInclude("stb_image.h");
    @cInclude("stb_truetype.h");
    @cInclude("stb_image_write.h");
});
