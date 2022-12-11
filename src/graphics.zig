const std = @import("std");
const za = @import("zalgebra");
const c = @import("c.zig");

pub const SparseSet = @import("sparse_set.zig").SparseSet;

const ini = @import("ini.zig");

pub const glID = c.GLuint;

pub const Vec2f = struct {
    x: f32,
    y: f32,
};

pub const Vec2i = struct { x: i32, y: i32 };

pub fn RecV(pos: Vec2f, w: f32, h: f32) Rect {
    return .{ .x = pos.x, .y = pos.y, .w = w, .h = h };
}

pub fn Rec(x: f32, y: f32, w: f32, h: f32) Rect {
    return .{ .x = x, .y = y, .w = w, .h = h };
}

//Ideally I don't want to make any c.SDL calls in my application
//TODO detect dpi changes
pub const SDL = struct {
    pub const MouseState = struct {
        left: bool,
        right: bool,
        middle: bool,

        left_down: bool,

        pos: Vec2f,
        delta: Vec2f,

        wheel_delta: f32,
    };

    pub const KeyState = struct {
        pub const State = enum {
            pressed,
            released,
            held,
        };

        state: State,
        scancode: usize,
    };

    pub const Window = struct {
        const Self = @This();

        win: *c.SDL_Window,
        ctx: *anyopaque,

        screen_width: i32 = 0,
        screen_height: i32 = 0,

        should_exit: bool = false,

        mouse: MouseState = undefined,

        keys: std.BoundedArray(KeyState, 16) = std.BoundedArray(KeyState, 16).init(0) catch unreachable,
        keyboard_state: std.bit_set.IntegerBitSet(c.SDL_NUM_SCANCODES) = std.bit_set.IntegerBitSet(c.SDL_NUM_SCANCODES).initEmpty(),

        fn sdlLogErr() void {
            std.debug.print("SDL ERROR:\n{s}\n", .{c.SDL_GetError()});
        }

        fn setAttr(attr: c.SDL_GLattr, val: c_int) !void {
            if (c.SDL_GL_SetAttribute(attr, val) < 0) {
                sdlLogErr();
                return error.SDLSetAttr;
            }
        }

        pub fn createWindow(title: [*c]const u8) !Self {
            //This does not seem to be needed
            //No errors occur
            //Event handling still functions
            if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
                sdlLogErr();
                return error.SDLInit;
            }
            errdefer c.SDL_Quit();

            const win = c.SDL_CreateWindow(
                title,
                c.SDL_WINDOWPOS_UNDEFINED,
                c.SDL_WINDOWPOS_UNDEFINED,
                1280,
                960,
                c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE,
            ) orelse {
                sdlLogErr();
                return error.SDLInit;
            };
            errdefer c.SDL_DestroyWindow(win);

            try setAttr(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
            try setAttr(c.SDL_GL_DOUBLEBUFFER, 1);
            try setAttr(c.SDL_GL_CONTEXT_MAJOR_VERSION, 4);
            try setAttr(c.SDL_GL_CONTEXT_MINOR_VERSION, 2);
            try setAttr(c.SDL_GL_CONTEXT_FLAGS, c.SDL_GL_CONTEXT_DEBUG_FLAG);

            const context = c.SDL_GL_CreateContext(win) orelse {
                sdlLogErr();
                return error.SDLCreatingContext;
            };
            errdefer c.SDL_GL_DeleteContext(context);

            try setAttr(c.SDL_GL_MULTISAMPLEBUFFERS, 1);
            try setAttr(c.SDL_GL_MULTISAMPLESAMPLES, 16);
            c.glEnable(c.GL_MULTISAMPLE);

            if (c.SDL_GL_SetSwapInterval(1) < 0) {
                sdlLogErr();
                return error.SetSwapInterval;
            }
            c.glEnable(c.GL_DEPTH_TEST);
            c.glEnable(c.GL_DEBUG_OUTPUT);

            //_ = c.SDL_SetRelativeMouseMode(c.SDL_TRUE);

            return Self{ .win = win, .ctx = context };
        }

        pub fn destroyWindow(self: Self) void {
            c.SDL_GL_DeleteContext(self.ctx);
            c.SDL_DestroyWindow(self.win);
            c.SDL_Quit();
        }

        pub fn getScancodeFromName(self: *Self, name: [*c]const u8) usize {
            _ = self;
            return c.SDL_GetScancodeFromName(name);
        }

        pub fn swap(self: *Self) void {
            c.SDL_GL_SwapWindow(self.win);
        }

        pub fn fuck(self: *Self, k: usize) i32 {
            _ = self;
            return c.SDL_GetKeyFromScancode(@intCast(c_uint, k));
        }

        pub fn getKeyboardState(self: *Self, len: *usize) []const u8 {
            _ = self;
            var l: i32 = 0;
            const ret = c.SDL_GetKeyboardState(&l);
            len.* = @intCast(usize, l);
            return ret[0..@intCast(usize, l)];
        }

        pub fn pumpEvents(self: *Self) void {
            c.SDL_PumpEvents();
            {
                var x: c_int = undefined;
                var y: c_int = undefined;
                const button = c.SDL_GetMouseState(&x, &y);
                self.mouse.pos = .{ .x = @intToFloat(f32, x), .y = @intToFloat(f32, y) };

                const old_left = self.mouse.left;

                self.mouse.left = button & c.SDL_BUTTON_LMASK != 0;
                self.mouse.right = button & c.SDL_BUTTON_RMASK != 0;
                self.mouse.middle = button & c.SDL_BUTTON_MMASK != 0;
                _ = c.SDL_GetRelativeMouseState(&x, &y);
                self.mouse.delta = .{ .x = @intToFloat(f32, x), .y = @intToFloat(f32, y) };

                self.mouse.left_down = !self.mouse.left_down and self.mouse.left and !old_left;
                self.mouse.wheel_delta = 0;
            }

            self.keys.resize(0) catch unreachable;
            self.keyboard_state.mask = 0;
            {
                var l: i32 = 0;
                const ret = c.SDL_GetKeyboardState(&l)[0..@intCast(usize, l)];
                //ret[0..@intCast(usize, l)];
                for (ret) |key, i| {
                    if (key == 1) {
                        self.keyboard_state.set(i);
                        //self.keys.append(.{ .state = .held, .scancode = i }) catch unreachable;
                    }
                }
            }

            var event: c.SDL_Event = undefined;
            while (c.SDL_PollEvent(&event) != 0) {
                switch (event.type) {
                    c.SDL_QUIT => self.should_exit = true,
                    c.SDL_KEYDOWN => {
                        if (event.key.keysym.sym == c.SDLK_ESCAPE)
                            self.should_exit = true;

                        self.keys.append(.{ .state = .pressed, .scancode = c.SDL_GetScancodeFromKey(event.key.keysym.sym) }) catch unreachable;
                    },
                    c.SDL_KEYUP => {},
                    c.SDL_TEXTEDITING => {},
                    c.SDL_TEXTINPUT => {},
                    c.SDL_KEYMAPCHANGED => {},
                    c.SDL_MOUSEWHEEL => {
                        self.mouse.wheel_delta = event.wheel.preciseY;
                    },
                    c.SDL_MOUSEMOTION => {
                        //const m = event.motion;
                        //self.mouse.delta = .{ .x = @intToFloat(f32, m.xrel), .y = @intToFloat(f32, m.yrel) };
                        //self.mouse.pos = .{ .x = @intToFloat(f32, m.x), .y = @intToFloat(f32, m.y) };
                        //self.mouse.left = m.state & c.SDL_BUTTON_LMASK != 0;
                        //self.mouse.right = m.state & c.SDL_BUTTON_RMASK != 0;
                        //self.mouse.middle = m.state & c.SDL_BUTTON_MMASK != 0;
                    },
                    c.SDL_MOUSEBUTTONDOWN => {},
                    c.SDL_MOUSEBUTTONUP => {},
                    c.SDL_WINDOWEVENT => {
                        //std.debug.print("Window event!\n", .{});
                        switch (event.window.event) {
                            c.SDL_WINDOWEVENT_RESIZED => {
                                self.screen_width = event.window.data1;
                                self.screen_height = event.window.data2;
                                c.glViewport(0, 0, self.screen_width, self.screen_height);
                            },
                            c.SDL_WINDOWEVENT_CLOSE => self.should_exit = true,
                            else => {},
                        }
                        var x: c_int = undefined;
                        var y: c_int = undefined;
                        c.SDL_GetWindowSize(self.win, &x, &y);
                        self.screen_width = x;
                        self.screen_height = y;
                        c.glViewport(0, 0, self.screen_width, self.screen_height);
                    },
                    else => continue,
                }
            }
        }
    };
};

pub const Atlas = struct {
    texture: Texture,

    sets: std.ArrayList(SubTileset),

    pub fn init(sets_to_load: []const struct { filename: []const u8, tilesets: []const SubTileset }, alloc: *const std.mem.Allocator, texture_size: u32) !Atlas {
        var packing_rects = std.ArrayList(c.stbrp_rect).init(alloc.*);
        defer packing_rects.deinit();

        var nodes = std.ArrayList(c.stbrp_node).init(alloc.*);
        defer nodes.deinit();
        try nodes.appendNTimes(undefined, texture_size + 200); //TODO MAGICNUM
        var rect_context: c.stbrp_context = undefined;

        c.stbrp_init_target(
            &rect_context,
            @intCast(c_int, texture_size),
            @intCast(c_int, texture_size),
            @ptrCast([*c]c.stbrp_node, nodes.items[0..nodes.items.len]),
            @intCast(c_int, nodes.items.len),
        );

        var sets = std.ArrayList(SubTileset).init(alloc.*);
        var id_len: usize = 0;
        for (sets_to_load) |item| {
            for (item.tilesets) |ts, j| {
                try sets.append(SubTileset{
                    .start = ts.start,
                    .tw = ts.tw,
                    .th = ts.th,
                    .pad = .{ .x = 0, .y = 0 }, //Reset padding because it is removed when copying
                    .num = ts.num,
                    .count = ts.count,
                });
                try packing_rects.append(.{
                    .id = @intCast(i32, id_len + j),
                    //.w = @intCast(c_ushort, ts.num.x * (ts.pad.x + ts.tw) - ts.pad.x),
                    //.h = @intCast(c_ushort, ts.num.y * (ts.pad.y + ts.th) - ts.pad.y),
                    .w = @intCast(c_ushort, ts.num.x * ts.tw),
                    .h = @intCast(c_ushort, ts.num.y * ts.th),
                    .x = 50,
                    .y = 50,
                    .was_packed = 1,
                });
            }
            id_len += item.tilesets.len;
        }
        const pack_err = c.stbrp_pack_rects(
            &rect_context,
            @ptrCast([*c]c.stbrp_rect, packing_rects.items[0 .. packing_rects.items.len - 1]),
            @intCast(c_int, packing_rects.items.len),
        );
        if (pack_err != 1)
            std.debug.print("RECT PACK UNSUCC\n", .{});

        var bitmap = std.ArrayList(u8).init(alloc.*);
        defer bitmap.deinit();
        //try bitmap.resize(4 * texture_size * texture_size);
        try bitmap.appendNTimes(0, 4 * texture_size * texture_size);

        var bit = Bitmap{ .data = bitmap, .w = texture_size, .h = texture_size };

        for (packing_rects.items) |rect| {
            var in: usize = 0;
            var j: usize = @intCast(usize, rect.id);
            while (j >= sets_to_load[in].tilesets.len) : (in += 1) {
                j -= sets_to_load[in].tilesets.len;
            }

            const set = sets_to_load[in].tilesets[j];
            var ts_bmp = try loadPng(sets_to_load[in].filename, alloc);
            defer ts_bmp.data.deinit();
            //const bmp = ts_bmp.data.items;

            sets.items[@intCast(usize, rect.id)].start = .{ .x = rect.x, .y = rect.y };
            //try sets.append(SubTileset{ .start = .{ .x = rect.x, .y = rect.y }, .tw = set.tw, .th = set.th, .pad = .{ .x = 0, .y = 0 }, .num = set.num, .count = set.count });

            var i: i32 = 0;
            while (i < set.count) : (i += 1) {
                Bitmap.copySub(
                    &ts_bmp,
                    @intCast(u32, set.start.x + @mod(i, set.num.x) * (set.tw + set.pad.x)),
                    @intCast(u32, set.start.y + @divFloor(i, set.num.x) * (set.th + set.pad.y)),
                    @intCast(u32, set.tw),
                    @intCast(u32, set.th),
                    &bit,
                    @intCast(u32, rect.x) + @intCast(u32, @mod(i, set.num.x) * set.tw),
                    @intCast(u32, rect.y) + @intCast(u32, @divFloor(i, set.num.x) * set.th),
                );
            }
        }
        _ = c.stbi_write_bmp(
            "debug/atlas.bmp",
            @intCast(c_int, texture_size),
            @intCast(c_int, texture_size),
            4,
            @ptrCast([*c]u8, bitmap.items[0..bitmap.items.len]),
        );

        return Atlas{
            .texture = Texture.fromBitmap(Bitmap{ .data = bitmap, .w = texture_size, .h = texture_size }),
            .sets = sets,
        };
    }

    pub fn getTexRec(m: @This(), si: usize, ti: usize) Rect {
        return m.sets.items[si].getTexRec(ti);
    }

    pub fn deinit(m: Atlas) void {
        m.sets.deinit();
    }
};

pub const SubTileset = struct {
    const Self = @This();

    start: Vec2i,
    tw: i32,
    th: i32,
    pad: Vec2i,
    num: Vec2i,
    count: usize,

    pub fn getTexRec(self: Self, index: usize) Rect {
        const i = @intCast(i32, index % self.count);
        return Rec(
            @intToFloat(f32, self.start.x + @mod(i, self.num.x) * (self.tw + self.pad.x)),
            @intToFloat(f32, self.start.y + @divFloor(i, self.num.x) * (self.th + self.pad.y)),
            @intToFloat(f32, self.tw),
            @intToFloat(f32, self.th),
        );
    }
};

pub const FixedBitmapFont = struct {
    const Self = @This();

    texture: Texture,
    sts: SubTileset,

    translation_table: [128]u8 = [_]u8{127} ** 128,

    pub fn init(texture: Texture, sts: SubTileset, decode_string: []const u8) Self {
        var ret = Self{
            .texture = texture,
            .sts = sts,
        };
        for (decode_string) |ch, i| {
            ret.translation_table[ch] = @intCast(u8, i);
        }

        return ret;
    }
};

const Bitmap = struct {
    const m = @This();
    //TODO add support for different types: rgba only for now
    data: std.ArrayList(u8),
    w: u32,
    h: u32,

    pub fn copySub(source: *m, srect_x: u32, srect_y: u32, srect_w: u32, srect_h: u32, dest: *m, des_x: u32, des_y: u32) void {
        const num_comp = 4;

        var sy = srect_y;

        while (sy < srect_y + srect_h) : (sy += 1) {
            var sx = srect_x;
            while (sx < srect_x + srect_w) : (sx += 1) {
                const source_i = ((sy * source.w) + sx) * num_comp;

                const rel_y = sy - srect_y;
                const rel_x = sx - srect_x;

                const dest_i = (((des_y + rel_y) * dest.w) + rel_x + des_x) * num_comp;

                var i: usize = 0;
                while (i < num_comp) : (i += 1) {
                    dest.data.items[dest_i + i] = source.data.items[source_i + i];
                }
            }
        }
    }
};

pub fn loadPng(relative_path: []const u8, alloc: *const std.mem.Allocator) !Bitmap {
    const cwd = std.fs.cwd();
    const png_file = try cwd.openFile(relative_path, .{});
    defer png_file.close();

    var buf = std.ArrayList(u8).init(alloc.*);
    defer buf.deinit();

    try png_file.reader().readAllArrayList(&buf, 1024 * 1024 * 1024);

    var pngctx = c.spng_ctx_new(0);
    defer c.spng_ctx_free(pngctx);

    _ = c.spng_set_png_buffer(pngctx, &buf.items[0], buf.items.len);

    var ihdr: c.spng_ihdr = undefined;
    _ = c.spng_get_ihdr(pngctx, &ihdr);

    //std.debug.print("width: {d} height: {d}\n bit depth: {d}\n color type: {d}\n \n", .{
    //    ihdr.width, ihdr.height, ihdr.bit_depth, ihdr.color_type,
    //});

    var out_size: usize = 0;
    _ = c.spng_decoded_image_size(pngctx, c.SPNG_FMT_RGBA8, &out_size);

    const decoded_data = try alloc.alloc(u8, out_size);

    _ = c.spng_decode_image(pngctx, &decoded_data[0], out_size, c.SPNG_FMT_RGBA8, 0);

    {
        var i: usize = 0;
        while (i < decoded_data.len) : (i += 4) {
            if (decoded_data[i] == 0x94 and
                decoded_data[i + 1] == 0x94 and
                decoded_data[i + 2] == 0xff)
            {
                decoded_data[i + 3] = 0x00;
            }

            if (decoded_data[i] == 0x92 and decoded_data[i + 1] == 0x90 and decoded_data[i + 2] == 0xff)
                decoded_data[i + 3] = 0x00;
        }
    }

    return Bitmap{ .w = ihdr.width, .h = ihdr.height, .data = std.ArrayList(u8).fromOwnedSlice(alloc.*, decoded_data) };

    //#9494ff background color

}

pub fn loadPngFromPath(relative_path: []const u8, alloc: *const std.mem.Allocator) !Texture {
    const cwd = std.fs.cwd();
    const png_file = try cwd.openFile(relative_path, .{});
    defer png_file.close();

    var buf = std.ArrayList(u8).init(alloc.*);
    defer buf.deinit();

    try png_file.reader().readAllArrayList(&buf, 1024 * 1024 * 1024);

    var pngctx = c.spng_ctx_new(0);
    defer c.spng_ctx_free(pngctx);

    _ = c.spng_set_png_buffer(pngctx, &buf.items[0], buf.items.len);

    var ihdr: c.spng_ihdr = undefined;
    _ = c.spng_get_ihdr(pngctx, &ihdr);

    std.debug.print("width: {d} height: {d}\n bit depth: {d}\n color type: {d}\n \n", .{
        ihdr.width, ihdr.height, ihdr.bit_depth, ihdr.color_type,
    });

    var out_size: usize = 0;
    _ = c.spng_decoded_image_size(pngctx, c.SPNG_FMT_RGBA8, &out_size);

    const decoded_data = try alloc.alloc(u8, out_size);
    defer alloc.free(decoded_data);

    _ = c.spng_decode_image(pngctx, &decoded_data[0], out_size, c.SPNG_FMT_RGBA8, 0);
    std.debug.print("Blue of first pixel {d}\n", .{decoded_data[2]});

    {
        var i: usize = 0;
        while (i < decoded_data.len) : (i += 4) {
            if (decoded_data[i] == 0x94 and
                decoded_data[i + 1] == 0x94 and
                decoded_data[i + 2] == 0xff)
            {
                decoded_data[i + 3] = 0x00;
            }

            if (decoded_data[i] == 0x92 and decoded_data[i + 1] == 0x90 and decoded_data[i + 2] == 0xff)
                decoded_data[i + 3] = 0x00;
        }
    }

    //#9494ff background color

    var tex_id: glID = 0;
    c.glGenTextures(1, &tex_id);
    c.glBindTexture(c.GL_TEXTURE_2D, tex_id);
    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        c.GL_RGBA,
        @intCast(i32, ihdr.width),
        @intCast(i32, ihdr.height),
        0,
        c.GL_RGBA,
        c.GL_UNSIGNED_BYTE,
        &decoded_data[0],
    );
    c.glGenerateMipmap(c.GL_TEXTURE_2D);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_BORDER);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_BORDER);

    //c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST_MIPMAP_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);

    const border_color: [4]f32 = .{ 0, 0, 0, 1.0 };
    c.glTexParameterfv(c.GL_TEXTURE_2D, c.GL_TEXTURE_BORDER_COLOR, &border_color);

    c.glBindTexture(c.GL_TEXTURE_2D, 0);

    return Texture{ .id = tex_id, .w = ihdr.width, .h = ihdr.height };
}

pub fn reDataTextureRGBA(id: glID, w: u32, h: u32, data: []u8) void {
    c.glBindTexture(c.GL_TEXTURE_2D, id);
    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        c.GL_RGBA,
        @intCast(i32, w),
        @intCast(i32, h),
        0,
        c.GL_RGBA,
        c.GL_UNSIGNED_BYTE,
        &data[0],
    );
    c.glBindTexture(c.GL_TEXTURE_2D, 0);
}

//Tiny wrapper of gl calls to avoid inevitable bugs of having to repeat GL_ARRAY_BUFFER 3 times for each function call
//or forgetting to bind relevant buffers etc
pub const GL = struct {
    fn bufferData(buffer_type: glID, handle: glID, comptime item: type, slice: []item) void {
        c.glBindBuffer(buffer_type, handle);
        c.glBufferData(
            buffer_type,
            @intCast(c_long, slice.len) * @sizeOf(item),
            slice.ptr,
            c.GL_STATIC_DRAW,
        );
        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    }

    fn bufferSubData(buffer_type: glID, handle: glID, offset: usize, len: usize, comptime item: type, slice: []item) void {
        c.glBindBuffer(buffer_type, handle);
        c.glBufferSubData(
            buffer_type,
            @intCast(c_long, offset) * @sizeOf(item),
            @intCast(c_long, len) * @sizeOf(item),
            &slice[offset],
        );

        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    }

    pub fn colorTexture(w: usize, h: usize, data: []u8) glID {
        var texid: glID = 0;

        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        c.glGenTextures(1, &texid);
        c.glBindTexture(c.GL_TEXTURE_2D, texid);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            @intCast(i32, w),
            @intCast(i32, h),
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            @ptrCast([*c]u8, data[0..data.len]),
        );
        // set texture options
        c.glGenerateMipmap(c.GL_TEXTURE_2D);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);

        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        c.glBlendEquation(c.GL_FUNC_ADD);
        return texid;
    }

    fn grayscaleTexture(w: u32, h: u32, data: []u8) glID {
        var texid: glID = 0;

        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        c.glGenTextures(1, &texid);
        c.glBindTexture(c.GL_TEXTURE_2D, texid);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RED,
            @intCast(i32, w),
            @intCast(i32, h),
            0,
            c.GL_RED,
            c.GL_UNSIGNED_BYTE,
            @ptrCast([*c]u8, data[0..data.len]),
        );
        // set texture options
        c.glGenerateMipmap(c.GL_TEXTURE_2D);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);

        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        c.glBlendEquation(c.GL_FUNC_ADD);
        return texid;
    }

    //The vertexAttribPointer functions can be hard to understand
    //I don't know how fleixible this is but for now it is better than making 3 calls too ensure state is correct
    //ONLY USE FOR floats
    fn floatVertexAttrib(vao: glID, vbo: glID, index: u32, size: u32, comptime item: type, comptime starting_field: []const u8) void {
        c.glBindVertexArray(vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
        defer c.glBindVertexArray(0);
        defer c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

        const byte_offset = @offsetOf(item, starting_field);
        c.glVertexAttribPointer(
            index,
            @intCast(c_int, size),
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(item),
            if (byte_offset != 0) @intToPtr(*const anyopaque, byte_offset) else null,
        );
        c.glEnableVertexAttribArray(index);
    }

    fn simpleDrawBatch(view: za.Mat4, model: za.Mat4, batch: anytype, has_ebo: bool) void {
        c.glUseProgram(batch.shader);
        c.glBindVertexArray(batch.vao);

        GL.bufferData(c.GL_ARRAY_BUFFER, batch.vbo, Vertex, batch.vertices.items);
        if (has_ebo)
            GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, batch.ebo, u32, batch.indicies.items);

        c.glBindTexture(c.GL_TEXTURE_2D, 0);

        const view_loc = c.glGetUniformLocation(batch.shader, "view");
        c.glUniformMatrix4fv(view_loc, 1, c.GL_FALSE, &view.data[0][0]);

        const model_loc = c.glGetUniformLocation(batch.shader, "model");
        c.glUniformMatrix4fv(model_loc, 1, c.GL_FALSE, &model.data[0][0]);

        c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, batch.indicies.items.len), c.GL_UNSIGNED_INT, null);
        //c.glBindVertexArray(0);

    }
};

const Shader = struct {
    fn checkShaderErr(shader: glID, comporlink: c_uint) void {
        var success: c_int = undefined;
        var infoLog: [512]u8 = undefined;
        c.glGetShaderiv(shader, comporlink, &success);
        if (success == 0) {
            var len: c_int = 0;
            c.glGetShaderInfoLog(shader, 512, &len, &infoLog);
            std.debug.panic("ERROR::SHADER::\n{s}\n", .{infoLog[0..@intCast(usize, len)]});
        }
    }

    fn compShader(src: [*c]const u8, s_type: c_uint) glID {
        const vert = c.glCreateShader(s_type);
        c.glShaderSource(vert, 1, &src, null);
        c.glCompileShader(vert);
        checkShaderErr(vert, c.GL_COMPILE_STATUS);
        return vert;
    }

    fn simpleShader(vert_src: [*c]const u8, frag_src: [*c]const u8) glID {
        const vert = compShader(vert_src, c.GL_VERTEX_SHADER);
        defer c.glDeleteShader(vert);

        const frag = compShader(frag_src, c.GL_FRAGMENT_SHADER);
        defer c.glDeleteShader(frag);

        const shader = c.glCreateProgram();
        c.glAttachShader(shader, vert);
        c.glAttachShader(shader, frag);
        c.glLinkProgram(shader);
        checkShaderErr(shader, c.GL_LINK_STATUS);

        return shader;
    }

    fn defaultQuadShader() glID {
        return simpleShader(@embedFile("shader/colorquad.vert"), @embedFile("shader/colorquad.frag"));
    }

    fn defaultQuadTexShader() glID {
        return simpleShader(@embedFile("shader/alpha_texturequad.vert"), @embedFile("shader/texturequad.frag"));
    }

    fn defaultFontShader() glID {
        return simpleShader(@embedFile("shader/alpha_texturequad.vert"), @embedFile("shader/alpha_texturequad.frag"));
    }
};

fn genQuadIndices(index: u32) [6]u32 {
    return [_]u32{
        index + 0,
        index + 1,
        index + 3,
        index + 1,
        index + 2,
        index + 3,
    };
}

pub const CharColor = struct { r: u8, g: u8, b: u8, a: u8 };

pub fn charColorToFloat(col: CharColor) Color {
    return .{
        @intToFloat(f32, col.r) / 255.0,
        @intToFloat(f32, col.g) / 255.0,
        @intToFloat(f32, col.b) / 255.0,
        @intToFloat(f32, col.a) / 255.0,
    };
}

pub fn intToColor(color: u32) CharColor {
    return .{
        .r = @intCast(u8, (color >> 24) & 0xff),
        .g = @intCast(u8, (color >> 16) & 0xff),
        .b = @intCast(u8, (color >> 8) & 0xff),
        .a = @intCast(u8, (color >> 0) & 0xff),
    };
}

pub const WHITE = intToColor(0xffffffff);
pub const GREEN = intToColor(0x00ff00ff);

pub const Rect = struct { x: f32, y: f32, w: f32, h: f32 };

pub const Color = [4]f32;
pub const Pos = [3]f32;
pub const Size = [2]f32;

pub fn createQuad(r: Rect, z: f32, color: Color) [4]Vertex {
    //TODO move z out into function
    return [_]Vertex{
        vertex(r.x + r.w, r.y + r.h, z, color),
        vertex(r.x + r.w, r.y, z, color),
        vertex(r.x, r.y, z, color),
        vertex(r.x, r.y + r.h, z, color),
    };
}

pub fn normalizeTexRect(tr: Rect, tx_w: u32, tx_h: u32) Rect {
    const tw = @intToFloat(f32, tx_w);
    const th = @intToFloat(f32, tx_h);
    return .{
        .x = tr.x / tw,
        .y = tr.y / th,
        .w = tr.w / tw,
        .h = tr.h / th,
    };
}

pub fn createQuadTextured(r: Rect, z: f32, tr: Rect, tx_w: u32, tx_h: u32, color: Color) [4]VertexTextured {
    const un = normalizeTexRect(tr, tx_w, tx_h);
    return [_]VertexTextured{
        vertexTextured(r.x + r.w, r.y + r.h, z, un.x + un.w, un.y + un.h, color), //0
        vertexTextured(r.x + r.w, r.y, z, un.x + un.w, un.y, color), //1
        vertexTextured(r.x, r.y, z, un.x, un.y, color), //2
        vertexTextured(r.x, r.y + r.h, z, un.x, un.y + un.h, color), //3

        //vertexTextured(r.x + r.w, r.y + r.h, z, un.x + un.w, un.y, color), //0
        //vertexTextured(r.x + r.w, r.y, z, un.x + un.w, un.y + un.h, color), //1
        //vertexTextured(r.x, r.y, z, un.x, un.y + un.h, color), //2
        //vertexTextured(r.x, r.y + r.h, z, un.x, un.y, color), //3
    };
}

pub const Texture = struct {
    id: glID,
    w: u32,
    h: u32,

    pub fn fromBitmap(bitmap: Bitmap) Texture {
        var tex_id: glID = 0;
        c.glGenTextures(1, &tex_id);
        c.glBindTexture(c.GL_TEXTURE_2D, tex_id);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            @intCast(i32, bitmap.w),
            @intCast(i32, bitmap.h),
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            &bitmap.data.items[0],
        );
        c.glGenerateMipmap(c.GL_TEXTURE_2D);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_BORDER);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_BORDER);

        //c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST_MIPMAP_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);

        const border_color: [4]f32 = .{ 0, 0, 0, 1.0 };
        c.glTexParameterfv(c.GL_TEXTURE_2D, c.GL_TEXTURE_BORDER_COLOR, &border_color);

        c.glBindTexture(c.GL_TEXTURE_2D, 0);

        return Texture{ .w = bitmap.w, .h = bitmap.h, .id = tex_id };
    }
};

pub const Glyph = struct {
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    advance_x: f32 = 0,
    tr: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    width: f32 = 0,
    height: f32 = 0,
    i: u21 = 0,
};

pub const CharMapEntry = union(enum) {
    unicode: u21, //A single codepoint
    range: [2]u21, //A range of codepoints (inclusive)
};

pub const CharMaps = struct {
    pub const AsciiUpperAlpha = [_]CharMapEntry{.{ .range = .{ 65, 90 } }};
    pub const AsciiLowerAlpha = [_]CharMapEntry{.{ .range = .{ 97, 122 } }};
    pub const AsciiNumeric = [_]CharMapEntry{.{ .range = .{ 48, 57 } }};
    pub const AsciiPunctiation = [_]CharMapEntry{ .{ .range = .{ 32, 47 } }, .{ .range = .{ 58, 64 } }, .{ .range = .{ 91, 96 } }, .{ .range = .{ 123, 126 } } };

    pub const AsciiExtended = [_]CharMapEntry{.{ .range = .{ 128, 254 } }};

    pub const AsciiBasic = AsciiUpperAlpha ++ AsciiLowerAlpha ++ AsciiNumeric ++ AsciiPunctiation;

    pub const Apple = [_]CharMapEntry{
        .{ .unicode = 0xF8FF },
        .{ .unicode = 0x1001B8 },
    };
};

//TODO Support multiple non scaled sizes
//Layouting
//  Word wrap
//  line beak
//
//Cool unicode selection tool:
//  render pages of unicode points using freetype directly to opengl texture for rendering
//  to allow me to select what codepoints I want to include in the backed bitmap

pub const Font = struct {
    font_size: f32,

    glyph_set: SparseSet(Glyph, u21),

    ascent: f32, //Farthest the font ascends above baseline
    descent: f32, //Farthest the font descends below baseline
    line_gap: f32, //Distance between one rows descent and next rows ascent
    //to get next baseline: ascent - descent + line_gap
    max_advance: f32,

    texture: Texture,

    dpi: f32,

    const Self = @This();
    const START_CHAR: usize = 32;
    const END_CHAR: usize = 127;
    const NUM_CHARS: usize = END_CHAR - START_CHAR;
    const padding: usize = 10;

    //TODO is there a more specific type than anytype for streams?
    fn freetypeLogErr(stream: anytype, error_code: c_int) void {
        if (error_code == 0)
            return;

        var found = false;
        for (c.ft_errors) |err| {
            if (err.err_code == error_code) {
                found = true;
                if (err.err_msg) |msg|
                    stream.print("Freetype: Error {s}\n", .{msg}) catch return;

                break;
            }
        }

        if (!found)
            stream.print("Freetype: Error code not found in table: {d}\n", .{error_code}) catch return;
    }

    //TODO pass both dpix and dpiy, and specify argument units for more clarity.
    pub fn init(filename: []const u8, alloc: std.mem.Allocator, point_size: f32, dpi: u32, codepoints_to_load: []const CharMapEntry, opt_pack_factor: ?f32) !Self {
        const codepoints = blk: {
            var codepoint_list = std.ArrayList(Glyph).init(alloc);
            for (codepoints_to_load) |codepoint| {
                switch (codepoint) {
                    .range => |range| {
                        var i = range[0];
                        while (i <= range[1]) : (i += 1) {
                            try codepoint_list.append(.{ .i = i });
                        }
                    },
                    .unicode => |cp| {
                        try codepoint_list.append(.{ .i = cp });
                    },
                }
            }
            break :blk codepoint_list.toOwnedSlice();
        };

        const dir = std.fs.cwd();
        const font_log = try dir.createFile("debug/fontgen.log", .{ .truncate = true });
        const log = font_log.writer();
        defer font_log.close();
        try log.print("zig: Init font with arguments:\nfilename: \"{s}\"\npoint_size: {d}\ndpi: {d}\n", .{ filename, point_size, dpi });

        var result = Font{
            .dpi = @intToFloat(f32, dpi),
            .max_advance = 0,
            .glyph_set = try SparseSet(Glyph, u21).fromOwnedDenseSlice(alloc, codepoints),
            .font_size = point_size,
            .texture = .{ .id = 0, .w = 0, .h = 0 },
            .ascent = 0,
            .descent = 0,
            .line_gap = 0,
        };
        std.debug.print("len of sparse: {d}\n", .{result.glyph_set.sparse.items.len});

        //TODO switch to using a grid rather than rect packing
        const pack_factor = opt_pack_factor orelse 1.3;

        const stderr = std.io.getStdErr().writer();

        var ftlib: c.FT_Library = undefined;
        freetypeLogErr(stderr, c.FT_Init_FreeType(&ftlib));

        var face: c.FT_Face = undefined;
        {
            var strbuf = std.ArrayList(u8).init(alloc);
            defer strbuf.deinit();

            try strbuf.appendSlice(filename);
            try strbuf.append(0);

            //FT_New_Face loads font file from filepathname
            //the face pointer should be destroyed with FT_Done_Face()
            freetypeLogErr(stderr, c.FT_New_Face(ftlib, @ptrCast([*:0]const u8, strbuf.items), 0, &face));

            try log.print("Freetype face: num_faces:  {d}\n", .{face.*.num_faces});
            try log.print("Freetype face: num_glyphs:  {d}\n", .{face.*.num_glyphs});
            try log.print("Freetype face: family_name:  {s}\n", .{face.*.family_name});
            try log.print("Freetype face: style_name:  {s}\n", .{face.*.style_name});
            try log.print("Freetype face: units_per_EM:  {d}\n", .{face.*.units_per_EM});
            try log.print("Freetype face: ascender :  {d}fu\n", .{face.*.ascender});
            try log.print("Freetype face: descender :  {d}fu\n", .{face.*.descender});
            try log.print("Freetype face: height :  {d}fu\n", .{face.*.height});
            try log.print("Freetype face: calculated height :  {d}fu\n", .{face.*.ascender - face.*.descender});
            try log.print("Freetype face: max_advance_width:  {d}fu\n", .{face.*.max_advance_width});
            try log.print("Freetype face: underline_position:  {d}fu\n", .{face.*.underline_position});
            try log.print("Freetype face: underline_thickness:  {d}fu\n", .{face.*.underline_thickness});

            {
                const mask_item = struct { mask: c_long, str: []const u8 };

                const mask_list = [_]mask_item{
                    .{ .mask = c.FT_FACE_FLAG_SCALABLE, .str = "FT_FACE_FLAG_SCALABLE          " },
                    .{ .mask = c.FT_FACE_FLAG_FIXED_SIZES, .str = "FT_FACE_FLAG_FIXED_SIZES       " },
                    .{ .mask = c.FT_FACE_FLAG_FIXED_WIDTH, .str = "FT_FACE_FLAG_FIXED_WIDTH       " },
                    .{ .mask = c.FT_FACE_FLAG_SFNT, .str = "FT_FACE_FLAG_SFNT              " },
                    .{ .mask = c.FT_FACE_FLAG_HORIZONTAL, .str = "FT_FACE_FLAG_HORIZONTAL        " },
                    .{ .mask = c.FT_FACE_FLAG_VERTICAL, .str = "FT_FACE_FLAG_VERTICAL          " },
                    .{ .mask = c.FT_FACE_FLAG_KERNING, .str = "FT_FACE_FLAG_KERNING           " },
                    .{ .mask = c.FT_FACE_FLAG_FAST_GLYPHS, .str = "FT_FACE_FLAG_FAST_GLYPHS       " },
                    .{ .mask = c.FT_FACE_FLAG_MULTIPLE_MASTERS, .str = "FT_FACE_FLAG_MULTIPLE_MASTERS  " },
                    .{ .mask = c.FT_FACE_FLAG_GLYPH_NAMES, .str = "FT_FACE_FLAG_GLYPH_NAMES       " },
                    .{ .mask = c.FT_FACE_FLAG_EXTERNAL_STREAM, .str = "FT_FACE_FLAG_EXTERNAL_STREAM   " },
                    .{ .mask = c.FT_FACE_FLAG_HINTER, .str = "FT_FACE_FLAG_HINTER            " },
                    .{ .mask = c.FT_FACE_FLAG_CID_KEYED, .str = "FT_FACE_FLAG_CID_KEYED         " },
                    .{ .mask = c.FT_FACE_FLAG_TRICKY, .str = "FT_FACE_FLAG_TRICKY            " },
                    .{ .mask = c.FT_FACE_FLAG_COLOR, .str = "FT_FACE_FLAG_COLOR             " },
                    .{ .mask = c.FT_FACE_FLAG_VARIATION, .str = "FT_FACE_FLAG_VARIATION         " },
                    .{ .mask = c.FT_FACE_FLAG_SVG, .str = "FT_FACE_FLAG_SVG               " },
                    .{ .mask = c.FT_FACE_FLAG_SBIX, .str = "FT_FACE_FLAG_SBIX              " },
                    .{ .mask = c.FT_FACE_FLAG_SBIX_OVERLAY, .str = "FT_FACE_FLAG_SBIX_OVERLAY      " },
                };
                const flags = face.*.face_flags;
                try log.print("Freetype face_flags mask: {b}\n", .{flags});
                for (mask_list) |mask| {
                    if ((mask.mask & flags) != 0) {
                        try log.print("Freetype: {s}\n", .{mask.str});
                    }
                }
            }
        }

        freetypeLogErr(
            stderr,
            //FT_Set_Char_Size:
            c.FT_Set_Char_Size(
                face,
                0,
                @floatToInt(c_int, point_size) * 64, //expects a size in 1/64 of points, font_size is in points
                dpi,
                dpi,
            ),
        );

        {
            var agindex: c.FT_UInt = 0;
            var charcode = c.FT_Get_First_Char(face, &agindex);
            var col: usize = 0;
            while (agindex != 0) {
                col += 1;
                if (col > 15) {
                    col = 0;
                    try log.print("\n", .{});
                }
                try log.print("[{x} {u}] ", .{ charcode, @intCast(u21, charcode) });

                charcode = c.FT_Get_Next_Char(face, charcode, &agindex);
            }
        }

        const fr = face.*;

        result.ascent = @intToFloat(f32, fr.size.*.metrics.ascender) / 64;
        result.descent = @intToFloat(f32, fr.size.*.metrics.descender) / 64;
        result.max_advance = @intToFloat(f32, fr.size.*.metrics.max_advance) / 64;
        //result.scale_factor = @intToFloat(f32, size_metrics.y_scale) / 65536.0;
        result.line_gap = @intToFloat(f32, fr.size.*.metrics.height) / 64;
        try log.print("Freetype face: ascender:  {d}px\n", .{result.ascent});
        try log.print("Freetype face: descender:  {d}px\n", .{result.descent});
        try log.print("Freetype face: height:  {d}px\n", .{result.line_gap});

        var packing_rects = std.ArrayList(c.stbrp_rect).init(alloc);
        defer packing_rects.deinit();

        const GlyphBitmap = struct {
            buffer: std.ArrayList(u8),
            w: usize,
            h: usize,
        };
        var bitmaps = std.ArrayList(GlyphBitmap).init(alloc);
        defer {
            for (bitmaps.items) |*bitmap|
                bitmap.buffer.deinit();
            bitmaps.deinit();
        }
        //try result.glyphs.append(.{ .value = ' ', .tr = .{ .x = 0, .y = 0, .w = 0, .h = 0 }, .advance_x = point_size, .width = point_size, .height = 0, .offset_x = 0, .offset_y = 0 });

        //var char = @intCast(c_ulong, START_CHAR + 1);
        //while (char < END_CHAR) : (char += 1) {
        var timer = try std.time.Timer.start();
        for (result.glyph_set.dense.items) |*codepoint| {
            const glyph_i = c.FT_Get_Char_Index(face, codepoint.i);
            if (glyph_i == 0) {
                std.debug.print("Undefined char index: {d}\n", .{codepoint.i});
                continue;
            }

            freetypeLogErr(stderr, c.FT_Load_Glyph(face, glyph_i, c.FT_LOAD_DEFAULT));
            freetypeLogErr(stderr, c.FT_Render_Glyph(face.*.glyph, c.FT_RENDER_MODE_NORMAL));

            const bitmap = &(face.*.glyph.*.bitmap);
            if (bitmap.width != 0 and bitmap.rows != 0) {
                const ind = bitmaps.items.len;
                try bitmaps.append(GlyphBitmap{
                    .buffer = std.ArrayList(u8).init(alloc),
                    .w = bitmap.width,
                    .h = bitmap.rows,
                });
                try bitmaps.items[ind].buffer.appendSlice(bitmap.buffer[0 .. bitmap.width * bitmap.rows]);

                try packing_rects.append(.{
                    //.id = @intCast(c_int, ind),
                    .id = codepoint.i,
                    .w = @intCast(c_ushort, bitmap.width + padding + padding),
                    .h = @intCast(c_ushort, bitmap.rows + padding + padding),
                    .x = 50,
                    .y = 50,
                    .was_packed = 1,
                });
            }
            const metrics = &face.*.glyph.*.metrics;
            {
                try log.print("Freetype glyph: {u}\n", .{@intCast(u21, codepoint.i)});
                try log.print("\twidth:  {d} (1/64 px), {d} px\n", .{ metrics.width, @divFloor(metrics.width, 64) });
                try log.print("\theight: {d} (1/64 px), {d} px\n", .{ metrics.height, @divFloor(metrics.height, 64) });
                try log.print("\tbearingX: {d} (1/64 px), {d} px\n", .{ metrics.horiBearingX, @divFloor(metrics.horiBearingX, 64) });
                try log.print("\tbearingY: {d} (1/64 px), {d} px\n", .{ metrics.horiBearingY, @divFloor(metrics.horiBearingY, 64) });
                try log.print("\tadvance: {d} (1/64 px), {d} px\n", .{ metrics.horiAdvance, @divFloor(metrics.horiAdvance, 64) });
                //try log.print("\twidth: {d}\n", .{metrics.width});
            }

            const fpad = @intToFloat(f32, padding);
            var glyph = Glyph{
                .tr = .{ .x = -1, .y = -1, .w = @intToFloat(f32, bitmap.width) + fpad, .h = @intToFloat(f32, bitmap.rows) + fpad },
                .offset_x = @intToFloat(f32, metrics.horiBearingX) / 64,
                .offset_y = @intToFloat(f32, metrics.horiBearingY) / 64,
                .advance_x = @intToFloat(f32, metrics.horiAdvance) / 64,
                .width = @intToFloat(f32, metrics.width) / 64,
                .height = @intToFloat(f32, metrics.height) / 64,
                .i = codepoint.i,
            };
            codepoint.* = glyph;
        }
        const elapsed = timer.read();
        try log.print("Rendered {d} glyphs in {d} ms\n", .{ result.glyph_set.dense.items.len, @intToFloat(f32, elapsed) / std.time.ns_per_ms });
        {
            var num_pixels: usize = 0;
            for (packing_rects.items) |r| {
                num_pixels += (@intCast(usize, r.w) * @intCast(usize, r.h));
            }
            result.texture.w = @floatToInt(u32, @sqrt(@intToFloat(f32, num_pixels) * pack_factor));
            result.texture.h = @floatToInt(u32, @sqrt(@intToFloat(f32, num_pixels) * pack_factor));
            try log.print("Texture size: {d} x {d}\n", .{ result.texture.w, result.texture.h });

            var nodes = std.ArrayList(c.stbrp_node).init(alloc);
            defer nodes.deinit();
            try nodes.appendNTimes(undefined, result.texture.w + 200); //TODO MAGICNUM
            var rect_context: c.stbrp_context = undefined;
            c.stbrp_init_target(
                &rect_context,
                @intCast(c_int, result.texture.w),
                @intCast(c_int, result.texture.h),
                @ptrCast([*c]c.stbrp_node, nodes.items[0..nodes.items.len]),
                @intCast(c_int, nodes.items.len),
            );

            const pack_err = c.stbrp_pack_rects(
                &rect_context,
                @ptrCast([*c]c.stbrp_rect, packing_rects.items[0 .. packing_rects.items.len - 1]),
                @intCast(c_int, packing_rects.items.len),
            );
            if (pack_err != 1)
                std.debug.print("RECT PACK UNSUCC\n", .{});

            {
                var texture_bitmap = std.ArrayList(u8).init(alloc);
                defer texture_bitmap.deinit();
                try texture_bitmap.appendNTimes(0, result.texture.w * result.texture.h);

                for (packing_rects.items) |rect, i| {
                    //const g = &result.glyphs.items[@intCast(usize, rect.id) + 1];
                    const g = try result.glyph_set.getPtr(@intCast(u21, rect.id));
                    g.tr.x = @intToFloat(f32, @intCast(u32, rect.x) + padding) - @intToFloat(f32, padding) / 2;
                    g.tr.y = @intToFloat(f32, @intCast(u32, rect.y) + padding) - @intToFloat(f32, padding) / 2;
                    const bitmap = &bitmaps.items[i];
                    if (bitmap.buffer.items.len > 0) {
                        var row: usize = 0;
                        var col: usize = 0;
                        while (row < rect.h) : (row += 1) {
                            while (col < rect.w) : (col += 1) {
                                if (row < bitmap.h + padding and col < bitmap.w + padding and row >= padding and col >= padding) {
                                    const dat = bitmap.buffer.items[((row - padding) * bitmap.w) + col - padding];
                                    texture_bitmap.items[(result.texture.w * (row + @intCast(usize, rect.y))) + col + @intCast(usize, rect.x)] = dat;
                                } else {
                                    texture_bitmap.items[(result.texture.h * (row + @intCast(usize, rect.y))) + col + @intCast(usize, rect.x)] = 0;
                                }
                            }
                            col = 0;
                        }
                    }
                }

                _ = c.stbi_write_bmp(
                    "debug/freetype.bmp",
                    @intCast(c_int, result.texture.w),
                    @intCast(c_int, result.texture.h),
                    1,
                    @ptrCast([*c]u8, texture_bitmap.items[0..texture_bitmap.items.len]),
                );
                result.texture.id = GL.grayscaleTexture(result.texture.w, result.texture.h, texture_bitmap.items);
            }
        }

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.glyph_set.deinit();
    }

    pub fn measureText(self: *Self, string: []const u8) f32 {
        var it = std.unicode.Utf8Iterator{ .bytes = string, .i = 0 };
        var cho = it.nextCodepoint();

        var len: f32 = 0;
        while (cho != null) : (cho = it.nextCodepoint()) {
            const ch = cho orelse unreachable;

            if (ch == '\n') {
                unreachable;
            }

            const g = self.glyph_set.get(ch) catch |err| {
                switch (err) {
                    error.invalidIndex => {
                        continue;
                    },
                }
            };

            len += g.advance_x;
        }
        return len;
    }

    pub fn ptToPixel(self: *Self, pt: f32) f32 {
        return pt * (self.dpi / 72.0);
    }

    pub fn normalizeUV(self: *Self, coord: u32) f32 {
        return @intToFloat(f32, coord) / @intToFloat(f32, self.texture_size);
    }
};

const AvgBuf = struct {
    const Self = @This();
    const len = 100;

    pos: u32 = 0,
    buf: [len]f32 = .{0} ** len,

    fn insert(self: *Self, val: f32) void {
        self.buf[self.pos] = val;
        self.pos = (self.pos + 1) % @intCast(u32, self.buf.len);
    }

    fn avg(self: *Self) f32 {
        var res: f32 = 0;
        for (self.buf) |it| {
            res += it;
        }
        return res / @intToFloat(f32, self.buf.len);
    }
};

fn lerp(start: f32, end: f32, ratio: f32) f32 {
    return start + (end - start) * ratio;
}

fn lerpVec(start: Vec2f, end: Vec2f, ratio: f32) Vec2f {
    return (.{ .x = lerp(start.x, end.x, ratio), .y = lerp(start.y, end.y, ratio) });
}

fn logErr(msg: []const u8) void {
    std.debug.print("ERROR: {s}\n", .{msg});
}

pub const GraphicsContext = struct {
    const Self = @This();

    const State = struct {
        const Mode = enum {
            triangles,
            lines,
            points,
        };

        mode: Mode,
        texture: glID,
        shader: glID,
        //bound_shader: usize,
        //bound_matrix: usize,
    };

    last_batch: ?*Batch = null,

    batches: std.ArrayList(Batch),
    alloc: *const std.mem.Allocator,

    z_st: f32 = 0,

    colored_tri_shader: glID,
    tex_shad: glID,
    font_shad: glID,

    last_frame_time: u64 = 1000,
    frame_timer: std.time.Timer,
    lftavg: AvgBuf = .{},

    fps_timer: std.time.Timer,
    fps_time: u64 = 1000,
    fpsavg: AvgBuf = .{},

    draw_time: u64 = 1000,
    memcpy_time: u64 = 0,
    last_memcpy_time: u64 = 1000,

    pub fn init(alloc: *const std.mem.Allocator) !Self {
        var ret: Self = .{
            .batches = std.ArrayList(Batch).init(alloc.*),
            .alloc = alloc,
            .colored_tri_shader = 0,
            .tex_shad = 0,
            .font_shad = 0,
            .frame_timer = try std.time.Timer.start(),
            .fps_timer = try std.time.Timer.start(),
        };

        ret.colored_tri_shader = Shader.defaultQuadShader();
        //ret.colored_tri_shader = Shader.defaultQuadShader();
        ret.tex_shad = Shader.defaultQuadTexShader();
        ret.font_shad = Shader.defaultFontShader();

        return ret;
    }

    pub fn deinit(self: *Self) void {
        for (self.batches.items) |*batch| {
            batch.deinit();
        }
        self.batches.deinit();
    }

    //TODO grayscale only currently

    fn getBatch(self: *Self, state: State) !*Batch {
        for (self.batches.items) |*batch| {
            var bstate: State = switch (batch.*) {
                .TriTex => |b| .{ .mode = .triangles, .texture = b.texture, .shader = b.shader },
                .Line => |b| .{ .mode = .lines, .texture = 0, .shader = b.shader },
                .Tri => |b| .{ .mode = .triangles, .texture = 0, .shader = b.shader },
            };
            if (state.mode == bstate.mode and state.texture == bstate.texture and state.shader == bstate.shader) {
                return batch;
            }
        }

        try self.batches.append(switch (state.mode) {
            .triangles => if (state.texture != 0) Batch{ .TriTex = TriangleBatchTex.init(self.alloc, state.texture, state.shader) } else Batch{ .Tri = TriangleBatch.init(self.alloc, state.shader) },
            .lines => Batch{ .Line = LineBatch.init(self.alloc, state.shader) },
            else => unreachable,
        });

        const b = &self.batches.items[self.batches.items.len - 1];
        return b;
    }

    pub fn beginDraw(self: *Self, bg: CharColor) !void {
        self.fps_time = self.fps_timer.read();
        self.fpsavg.insert(std.time.ns_per_s / @intToFloat(f32, self.fps_time));
        self.fps_timer.reset();
        //self.last_memcpy_time = self.memcpy_time;
        self.memcpy_time = 1; //prevent divide by zero with 1ns

        const desired_frametime = @floatToInt(u64, (1.0 / 63.0) * @intToFloat(f32, std.time.ns_per_s));
        if (self.last_frame_time < desired_frametime) {
            std.time.sleep(desired_frametime - self.last_frame_time);
        }
        self.frame_timer.reset();

        const color = charColorToFloat(bg);
        c.glClearColor(color[0], color[1], color[2], color[3]);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
        self.z_st = 0;
        for (self.batches.items) |*batch| {
            try batch.reset();
        }
    }

    pub fn endDraw(self: *Self, screenW: i32, screenH: i32) void {
        var draw_time = std.time.Timer.start() catch null;
        const camera_bounds = Rec(
            0,
            0,
            @intToFloat(f32, screenW),
            @intToFloat(f32, screenH),
        );

        for (self.batches.items) |*batch| {
            switch (batch.*) {
                .TriTex => {},
                else => batch.draw(camera_bounds, .{ .x = 0, .y = 0 }, self.colored_tri_shader, self.tex_shad),
            }
        }
        for (self.batches.items) |*batch| {
            switch (batch.*) {
                .TriTex => batch.draw(camera_bounds, .{ .x = 0, .y = 0 }, self.colored_tri_shader, self.tex_shad),
                else => {},
            }
        }

        if (draw_time) |*dt|
            self.draw_time = dt.read();

        self.last_frame_time = self.frame_timer.read();
        self.lftavg.insert(1.0 / (std.time.ns_per_us / @intToFloat(f32, self.last_frame_time)));
        self.last_memcpy_time = self.memcpy_time;
    }

    pub fn beginCameraDraw(self: *Self, screenW: i32, screenH: i32) !void {
        const camera_bounds = .{
            .x = 0,
            .y = 0,
            .w = @intToFloat(f32, screenW),
            .h = @intToFloat(f32, screenH),
        };
        for (self.batches.items) |*batch| {
            switch (batch.*) {
                .TriTex => {},
                else => batch.draw(camera_bounds, .{ .x = 0, .y = 0 }, self.colored_tri_shader, self.tex_shad),
            }
        }
        for (self.batches.items) |*batch| {
            switch (batch.*) {
                .TriTex => batch.draw(camera_bounds, .{ .x = 0, .y = 0 }, self.colored_tri_shader, self.tex_shad),
                else => {},
            }
        }

        for (self.batches.items) |*batch| {
            try batch.reset();
        }
    }

    pub fn endCameraDraw(self: *Self, camera_bounds: Rect, translate: Vec2f) !void {
        for (self.batches.items) |*batch| {
            switch (batch.*) {
                .TriTex => {},
                else => batch.draw(camera_bounds, translate, self.colored_tri_shader, self.tex_shad),
            }
        }
        for (self.batches.items) |*batch| {
            switch (batch.*) {
                .TriTex => batch.draw(camera_bounds, translate, self.colored_tri_shader, self.tex_shad),
                else => {},
            }
        }
        for (self.batches.items) |*batch| {
            try batch.reset();
        }
    }

    pub fn drawFPS(self: *Self, x: f32, y: f32, font: *Font) void {
        {
            var buf: [70]u8 = undefined;
            var fbs = std.io.FixedBufferStream([]u8){ .buffer = buf[0..], .pos = 0 };
            fbs.writer().print("FPS: {d}\nFT: {d}us\nDT: {d}us\nMPT: {d}", .{
                //fbs.writer().print("FPS: {d}\nFT: {d}us", .{
                @floatToInt(i32, std.time.ns_per_s / @intToFloat(f32, self.fps_time) / 10) * 10,
                //@floatToInt(i32, self.fpsavg.avg() / 10) * 10,
                @floatToInt(i32, 1.0 / (std.time.ns_per_us / @intToFloat(f32, self.last_frame_time)) / 100) * 100,
                //@floatToInt(i32, self.lftavg.avg()),
                @floatToInt(i32, 1.0 / (std.time.ns_per_us / @intToFloat(f32, self.draw_time))),
                @floatToInt(i32, 1.0 / (std.time.ns_per_us / @intToFloat(f64, self.last_memcpy_time))),
            }) catch return;
            self.drawText(x, y, buf[0..fbs.pos], font, 16, intToColor(0xffffffff));
        }
    }

    pub fn dRect(self: *Self, x: f32, y: f32, w: f32, h: f32, col: CharColor) void {
        self.drawRect(.{ .x = x, .y = y, .w = w, .h = h }, col);
    }

    pub fn drawRectOutlineThick(self: *Self, r: Rect, thickness: f32, col: CharColor) !void {
        const batch = (try self.getBatch(.{ .mode = .triangles, .texture = 0, .shader = self.colored_tri_shader }));
        const b = &batch.Tri;

        const rects = [_]Rect{
            Rect{ .x = r.x, .y = r.y, .w = r.w, .h = thickness },
            Rect{ .x = r.x + r.w - thickness, .y = r.y + thickness, .w = thickness, .h = r.h - thickness * 2 },
            Rect{ .x = r.x, .y = r.y + thickness, .w = thickness, .h = r.h - thickness * 2 },
            Rect{ .x = r.x, .y = r.y + r.h - thickness, .w = r.w, .h = thickness },
        };

        for (rects) |rl| {
            try b.indicies.appendSlice(&genQuadIndices(@intCast(u32, b.vertices.items.len)));
            try b.vertices.appendSlice(&createQuad(rl, self.z_st, charColorToFloat(col)));
        }

        self.z_st += 0.1;
    }

    pub fn drawRect(self: *Self, r: Rect, col: CharColor) void {
        const batch = self.getBatch(.{ .mode = .triangles, .texture = 0, .shader = self.colored_tri_shader }) catch {
            logErr("batch");
            return;
        };

        const b = &batch.Tri;
        const index = b.vertices.items.len;

        b.vertices.appendSlice(&createQuad(r, self.z_st, charColorToFloat(col))) catch {
            logErr("vert");
            return;
        };
        b.indicies.appendSlice(&genQuadIndices(@intCast(u32, index))) catch {
            logErr("indicies");
            return;
        };
        self.z_st += 0.1;
    }

    pub fn drawRectTex(
        self: *Self,
        r: Rect,
        tr: Rect,
        col: CharColor,
        texture: Texture,
    ) !void {
        const batch = (try self.getBatch(.{ .mode = .triangles, .texture = texture.id, .shader = self.tex_shad }));
        const b = &batch.TriTex;

        const index = b.vertices.items.len;

        var timer = try std.time.Timer.start();

        try b.vertices.appendSlice(&createQuadTextured(r, self.z_st, tr, texture.w, texture.h, charColorToFloat(col)));
        try b.indicies.appendSlice(&genQuadIndices(@intCast(u32, index)));
        self.z_st += 0.1;

        self.memcpy_time += timer.read();
    }

    pub fn drawFixedBitmapText(self: *Self, x: f32, y: f32, h: f32, str: []const u8, font: FixedBitmapFont, col: CharColor) !void {
        const batch = (try self.getBatch(.{ .mode = .triangles, .texture = font.texture.id, .shader = self.tex_shad }));
        const b = &batch.TriTex;

        for (str) |char, i| {
            if (char == ' ')
                continue;

            const ind = font.translation_table[std.ascii.toUpper(char)];
            const fi = @intToFloat(f32, i);
            try b.indicies.appendSlice(&genQuadIndices(@intCast(u32, b.vertices.items.len)));
            try b.vertices.appendSlice(&createQuadTextured(Rec(
                x + fi * h,
                y,
                h,
                h,
            ), self.z_st, font.sts.getTexRec(if (ind == 127) font.sts.count - 1 else ind), font.texture.w, font.texture.h, charColorToFloat(col)));
        }

        self.z_st += 0.1;
    }

    pub fn drawText(self: *Self, x: f32, y: f32, str: []const u8, font: *Font, size: f32, col: CharColor) void {
        //TODO investigae index ob when nothing happens in a drawcall
        const SF = size / font.font_size;

        const batch = (self.getBatch(.{ .mode = .triangles, .texture = font.texture.id, .shader = self.font_shad }) catch unreachable);
        const b = &batch.TriTex;

        b.vertices.ensureUnusedCapacity(str.len * 4) catch unreachable;
        b.indicies.ensureUnusedCapacity(str.len * 6) catch unreachable;

        var it = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };

        var vx = x;
        var vy = y;
        var cho = it.nextCodepoint();
        while (cho != null) : (cho = it.nextCodepoint()) {
            const ch = cho orelse unreachable;
            //for (str) |ch| {
            if (ch == '\n') {
                //vy += (font.ascent - font.descent + font.line_gap) * SF * font.scale_factor;
                vy += font.line_gap * SF;
                vx = x;
                continue;
            }

            if (ch < Font.START_CHAR)
                continue;
            //const g_i = ch - Font.START_CHAR;
            //const g = font.glyphs.items[g_i];
            const g = font.glyph_set.get(ch) catch |err| {
                switch (err) {
                    error.invalidIndex => {
                        continue;
                    },
                }
            };
            //if (ch == ' ') {
            //    vx += g.advance_x * SF;
            //    continue;
            //}
            const fpad = @intToFloat(f32, Font.padding) / 2;
            const pad = @intToFloat(f32, Font.padding);

            const r = Rect{
                .x = vx + (g.offset_x - fpad) * SF,
                .y = vy - (g.offset_y + fpad) * SF,
                .w = (pad + g.width) * SF,
                .h = (pad + g.height) * SF,
            };

            var timer = std.time.Timer.start() catch unreachable;
            const index = b.vertices.items.len;
            b.vertices.appendSlice(&createQuadTextured(r, self.z_st, g.tr, font.texture.w, font.texture.h, charColorToFloat(col))) catch unreachable;
            b.indicies.appendSlice(&genQuadIndices(@intCast(u32, index))) catch unreachable;
            self.memcpy_time += timer.read();

            vx += (g.advance_x) * SF;
            //vx += (g.width) * SF;
        }
        self.z_st += 0.1;
    }

    pub fn drawLine(self: *Self, p1: Vec2f, p2: Vec2f, col: CharColor) !void {
        const batch = try self.getBatch(.{ .mode = .lines, .texture = 0, .shader = self.colored_tri_shader });
        const bat = &batch.Line;
        const cc = charColorToFloat(col);

        const verts = [_]Vertex{
            vertex(p1.x, p1.y, self.z_st, cc),
            vertex(p2.x, p2.y, self.z_st, cc),
        };

        try bat.vertices.appendSlice(&verts);
        self.z_st += 0.1;
    }

    pub fn drawBezier(self: *Self, a: Vec2f, b: Vec2f, control: Vec2f, col: CharColor) !void {
        const batch = try self.getBatch(.{ .mode = .lines, .texture = 0, .shader = self.colored_tri_shader });
        const bat = &batch.Line;
        const cc = charColorToFloat(col);

        {
            const steps = 14;
            const ratio_inc: f32 = 1.0 / @intToFloat(f32, steps);

            var last_point = a;

            var i: u32 = 1;
            while (i <= steps) : (i += 1) {
                const rat = ratio_inc * @intToFloat(f32, i);
                const pa = lerpVec(a, control, rat);
                const pb = lerpVec(control, b, rat);
                const bez = lerpVec(pa, pb, rat);
                try bat.vertices.append(vertex(last_point.x, last_point.y, self.z_st, cc));
                try bat.vertices.append(vertex(bez.x, bez.y, self.z_st, cc));
                last_point = bez;
            }
        }

        const verts = [_]Vertex{
            vertex(a.x, a.y, self.z_st, cc),
            vertex(control.x, control.y, self.z_st, cc),
            vertex(control.x, control.y, self.z_st, cc),
            vertex(b.x, b.y, self.z_st, cc),

            //vertex(pa.x, pa.y, self.z_st, cc),
            //vertex(pb.x, pb.y, self.z_st, cc),
        };

        try bat.vertices.appendSlice(&verts);
        self.z_st += 0.1;
    }

    pub fn drawRectOutline(self: *Self, r: Rect, col: CharColor) !void {
        const batch = try self.getBatch(.{ .mode = .lines, .texture = 0, .shader = self.colored_tri_shader });
        const b = &batch.Line;
        const cc = charColorToFloat(col);

        const verts = [_]Vertex{
            vertex(r.x, r.y, self.z_st, cc),
            vertex(r.x + r.w, r.y, self.z_st, cc),
            vertex(r.x + r.w, r.y, self.z_st, cc),
            vertex(r.x + r.w, r.y + r.h, self.z_st, cc),
            vertex(r.x + r.w, r.y + r.h, self.z_st, cc),
            vertex(r.x, r.y + r.h, self.z_st, cc),
            vertex(r.x, r.y + r.h, self.z_st, cc),
            vertex(r.x, r.y, self.z_st, cc),
        };

        try b.vertices.appendSlice(&verts);
    }

    pub fn drawCircle(self: *Self, x: f32, y: f32, r: f32, col: CharColor) !void {
        const batch = try self.getBatch(.{ .mode = .lines, .texture = 0, .shader = self.colored_tri_shader });
        const b = &batch.Line;
        const cc = charColorToFloat(col);

        const steps = 100;

        var verts: [steps]Vertex = undefined;
        {
            var i: usize = 0;
            while (i < steps) : (i += 1) {
                const vx = r * @cos(@intToFloat(f32, i) / @intToFloat(f32, steps) * std.math.tau);
                const vy = r * @sin(@intToFloat(f32, i) / @intToFloat(f32, steps) * std.math.tau);
                verts[i] = vertex(x + vx, y + vy, self.z_st, cc);
                if (i != 0 and i != steps - 1) {
                    verts[i + 1] = verts[i];
                    i += 1;
                }
            }
            verts[steps - 1] = verts[0];
        }

        var timer = try std.time.Timer.start();

        try b.vertices.appendSlice(&verts);
        self.memcpy_time += timer.read();
    }
};

//start with mode
//switch mode{
//
//triangleBatches[]

const VertexTextured = packed struct { x: f32, y: f32, z: f32, u: f32, v: f32, r: f32, g: f32, b: f32, a: f32 };
const Vertex = packed struct { x: f32, y: f32, z: f32, r: f32, g: f32, b: f32, a: f32 };

pub fn vertex(x: f32, y: f32, z: f32, col: Color) Vertex {
    return .{ .x = x, .y = y, .z = z, .r = col[0], .g = col[1], .b = col[2], .a = col[3] };
}

pub fn vertexTextured(x: f32, y: f32, z: f32, u: f32, v: f32, col: Color) VertexTextured {
    return .{ .x = x, .y = y, .z = z, .u = u, .v = v, .r = col[0], .g = col[1], .b = col[2], .a = col[3] };
}

//Textured
//colored

//TODO Make a seperate batch specifically for font rendering or something
//Problem:
//Alpha is hard in opengl
//The solution to crappy looking fonts is to draw them last,
//With batched drawing this is hard.
const TriangleBatchTex = struct {
    const Self = @This();
    vertices: std.ArrayList(VertexTextured),
    indicies: std.ArrayList(u32),

    shader: glID,
    texture: glID,
    vao: c_uint = undefined,
    vbo: c_uint = undefined,
    ebo: c_uint = undefined,

    pub fn init(alloc: *const std.mem.Allocator, texture: glID, shader: glID) @This() {
        var ret = Self{
            .vertices = std.ArrayList(VertexTextured).init(alloc.*),
            .indicies = std.ArrayList(u32).init(alloc.*),
            .texture = texture,
            .shader = shader,
        };

        c.glGenVertexArrays(1, &ret.vao);
        c.glGenBuffers(1, &ret.vbo);
        c.glGenBuffers(1, &ret.ebo);

        GL.floatVertexAttrib(ret.vao, ret.vbo, 0, 3, VertexTextured, "x"); //XYZ
        GL.floatVertexAttrib(ret.vao, ret.vbo, 1, 4, VertexTextured, "r"); //RGBA
        GL.floatVertexAttrib(ret.vao, ret.vbo, 2, 2, VertexTextured, "u"); //RGBA

        c.glBindVertexArray(ret.vao);
        GL.bufferData(c.GL_ARRAY_BUFFER, ret.vbo, VertexTextured, ret.vertices.items);
        GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, ret.ebo, u32, ret.indicies.items);
        return ret;
    }

    pub fn deinit(self: *Self) void {
        self.vertices.deinit();
        self.indicies.deinit();
    }
};

const TriangleBatch = struct {
    const Self = @This();
    vertices: std.ArrayList(Vertex),
    indicies: std.ArrayList(u32),

    shader: glID,
    vao: c_uint = undefined,
    vbo: c_uint = undefined,
    ebo: c_uint = undefined,

    pub fn init(alloc: *const std.mem.Allocator, shader: glID) @This() {
        var ret = Self{
            .vertices = std.ArrayList(Vertex).init(alloc.*),
            .indicies = std.ArrayList(u32).init(alloc.*),
            .shader = shader,
        };
        c.glGenVertexArrays(1, &ret.vao);
        c.glGenBuffers(1, &ret.vbo);
        c.glGenBuffers(1, &ret.ebo);

        GL.floatVertexAttrib(ret.vao, ret.vbo, 0, 3, Vertex, "x"); //XYZ
        GL.floatVertexAttrib(ret.vao, ret.vbo, 1, 4, Vertex, "r"); //RGBA
        return ret;
    }

    pub fn deinit(self: *Self) void {
        self.vertices.deinit();
        self.indicies.deinit();
    }
};

const LineBatch = struct {
    const Self = @This();
    vertices: std.ArrayList(Vertex),

    shader: glID,
    vao: c_uint = undefined,
    vbo: c_uint = undefined,

    pub fn init(alloc: *const std.mem.Allocator, shader: glID) @This() {
        var ret = Self{ .vertices = std.ArrayList(Vertex).init(alloc.*), .shader = shader };
        c.glGenVertexArrays(1, &ret.vao);
        c.glGenBuffers(1, &ret.vbo);

        GL.floatVertexAttrib(ret.vao, ret.vbo, 0, 3, Vertex, "x"); //XYZ
        GL.floatVertexAttrib(ret.vao, ret.vbo, 1, 4, Vertex, "r"); //RGBA

        return ret;
    }

    pub fn deinit(self: *Self) void {
        self.vertices.deinit();
    }
};

const Batch = union(enum) {
    const Self = @This();
    TriTex: TriangleBatchTex,
    Tri: TriangleBatch,
    Line: LineBatch,

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .TriTex => |*b| b.deinit(),
            .Tri => |*b| b.deinit(),
            .Line => |*b| b.deinit(),
        }
    }

    pub fn reset(self: *Self) !void {
        switch (self.*) {
            .TriTex => |*b| {
                try b.vertices.resize(0);
                try b.indicies.resize(0);
            },
            .Tri => |*b| {
                try b.vertices.resize(0);
                try b.indicies.resize(0);
            },
            .Line => |*b| {
                try b.vertices.resize(0);
            },
        }
    }

    pub fn draw(self: *Self, view_bounds: Rect, translate: Vec2f, shader_program: glID, texture_shader: glID) void {
        //const view = za.orthographic(0, @intToFloat(f32, scrw), @intToFloat(f32, scrh), 0, -100, 100);
        const view = za.orthographic(view_bounds.x, view_bounds.w, view_bounds.h, view_bounds.y, -100000, 1).translate(za.Vec3.new(0, 0, 0));
        const model = za.Mat4.identity().translate(za.Vec3.new(translate.x, translate.y, 0));

        switch (self.*) {
            .Tri => |*b| {
                GL.simpleDrawBatch(view, model, b, true);
                //    c.glUniformMatrix4fv(view_loc, 1, c.GL_FALSE, &view.data[0][0]);

                //    c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, b.indicies.items.len), c.GL_UNSIGNED_INT, null);
                //    //c.glBindVertexArray(0);
                //}
            },
            .TriTex => |*b| {
                c.glUseProgram(b.shader);
                c.glBindVertexArray(b.vao);
                GL.bufferData(c.GL_ARRAY_BUFFER, b.vbo, VertexTextured, b.vertices.items);
                GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, b.ebo, u32, b.indicies.items);
                //GL.bufferSubData(c.GL_ARRAY_BUFFER, b.vbo, 0, b.vertices.items.len, VertexTextured, b.vertices.items);
                //GL.bufferSubData(c.GL_ELEMENT_ARRAY_BUFFER, b.ebo, 0, b.indicies.items.len, u32, b.indicies.items);

                c.glBindTexture(c.GL_TEXTURE_2D, b.texture);

                const view_loc = c.glGetUniformLocation(texture_shader, "view");
                c.glUniformMatrix4fv(view_loc, 1, c.GL_FALSE, &view.data[0][0]);

                const model_loc = c.glGetUniformLocation(texture_shader, "model");
                c.glUniformMatrix4fv(model_loc, 1, c.GL_FALSE, &model.data[0][0]);

                c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, b.indicies.items.len), c.GL_UNSIGNED_INT, null);
            },
            .Line => |*b| {
                c.glUseProgram(shader_program);
                c.glBindVertexArray(b.vao);
                GL.bufferData(c.GL_ARRAY_BUFFER, b.vbo, Vertex, b.vertices.items);

                const view_loc = c.glGetUniformLocation(texture_shader, "view");
                c.glUniformMatrix4fv(view_loc, 1, c.GL_FALSE, &view.data[0][0]);

                //c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, b.indicies.items.len), c.GL_UNSIGNED_INT, null);
                c.glDrawArrays(c.GL_LINES, 0, @intCast(c_int, b.vertices.items.len));
            },
            //else => {
            //    std.debug.print("Batch draw not implemented!\n", .{});
            //},
        }
    }
};

pub const BindType = [2][]const u8;

pub const BindList = []const BindType;

pub const my_maps: BindList = &.{
    .{ "print", "C" },
    .{ "toggle", "O" },
};

pub fn GenerateBindingEnum(comptime map: BindList) type {
    const TypeInfo = std.builtin.Type;
    var fields: [map.len]TypeInfo.EnumField = undefined;

    inline for (map) |bind, b_i| {
        fields[b_i] = .{ .name = bind[0], .value = b_i };
    }
    return @Type(TypeInfo{ .Enum = .{
        .layout = .Auto,
        .fields = fields[0..],
        .tag_type = u32,
        .decls = &.{},
        .is_exhaustive = true,
    } });
}

pub fn BindingMap(comptime map_enum: type) type {
    return struct {
        const Self = @This();
        map: std.AutoHashMap(usize, map_enum),

        pub fn init(map: BindList, alloc: *const std.mem.Allocator) !Self {
            var hash_map = std.AutoHashMap(usize, map_enum).init(alloc.*);

            for (map) |bind, i| {
                var buffer: [256]u8 = undefined;
                std.mem.copy(u8, buffer[0..], bind[1]);
                buffer[bind[1].len] = 0;
                const sc = c.SDL_GetScancodeFromName(&buffer[0]);
                try hash_map.put(sc, @intToEnum(map_enum, i));
            }

            return Self{ .map = hash_map };
        }

        pub fn get(self: *Self, scancode: usize) ?map_enum {
            return self.map.get(scancode);
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
        }
    };
}

////const TriangleBatch = struct {
//    vertices: []VertexTextured,
//    indicies: []u32,
//
//    texture: usize,
//};

//BUFFER TYPES
// trianglesBuffer
// linesBuffer
// pointsBuffer

//VERTEX TYPES
// Textured:
// xyz uv rgba
// 12  8  4
//
// Plain:
// xyz rgba

//loadTexture()
//unloadTexture()
test "Main test" {
    //const expect = std.testing.expect();
    const alloc = std.testing.allocator;
    var ctx = GraphicsContext.init(&alloc);

    try ctx.beginDraw();

    ctx.deinit();
}
