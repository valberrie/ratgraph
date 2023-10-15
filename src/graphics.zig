const std = @import("std");
pub const za = @import("zalgebra");
pub const c = @import("c.zig");

pub const SparseSet = @import("sparse_set.zig").SparseSet;
//TODO for the graphics api
//texture creation helper functions
//it should be easy to create a texture with the following paramaters
//color depths
//number of channels
//mipmap generation
//filters, min mag
//wrapping behavior
//border color

//TODO Write text rendering for NewCtx
//TODO Should we switch to using only zalgebra vectors?

//TODO Write draw functions for both point and pixel usage
//write function that takes a list of keybindings and draws a display documenting all keys and functions
//Allow typeless entry of data for draw fn's. Support common vector and rectangle types with both integer and floating point

const ini = @import("ini.zig");

pub const glID = c.GLuint;

pub const keycodes = @import("keycodes.zig");

pub const V3 = za.Vec3;

pub fn RingBuffer(comptime size: u32, comptime T: type, comptime default: T) type {
    return struct {
        const Self = @This();
        items: [size]T = [_]T{default} ** size,

        index: usize = 0,

        pub fn put(self: *Self, item: T) void {
            self.items[self.index] = item;
            self.index = (self.index + 1) % self.items.len;
        }

        pub fn avg(self: *Self) T {
            var count: T = 0;
            for (self.items) |item| {
                count += item;
            }
            return count / self.items.len;
        }
    };
}

pub const Vec2f = packed struct {
    x: f32,
    y: f32,

    pub fn new(x: f32, y: f32) @This() {
        return @This(){ .x = x, .y = y };
    }

    pub fn smul(s: @This(), scalar: f32) @This() {
        return .{ .x = s.x * scalar, .y = s.y * scalar };
    }

    pub fn add(a: @This(), b: @This()) @This() {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    /// a - b
    pub fn sub(a: @This(), b: @This()) @This() {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn toI(s: @This(), comptime I: type, comptime V: type) V {
        return V{
            .x = @floatToInt(I, s.x),
            .y = @floatToInt(I, s.y),
        };
    }
};

pub const Vec3f = packed struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn new(x: f32, y: f32, z: f32) @This() {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn fromZa(v: za.Vec3) @This() {
        return .{
            .x = v.data[0],
            .y = v.data[1],
            .z = v.data[2],
        };
    }
};

pub inline fn ptToPx(dpi: f32, pt: f32) f32 {
    return pt / 72 * dpi;
}

pub inline fn pxToPt(dpi: f32, px: f32) f32 {
    return px * 72 / dpi;
}

pub const Vec2i = struct { x: i32, y: i32 };

pub fn RecV(pos: Vec2f, w: f32, h: f32) Rect {
    return .{ .x = pos.x, .y = pos.y, .w = w, .h = h };
}

pub fn IRec(x: i32, y: i32, w: i32, h: i32) Rect {
    return .{
        .x = @intToFloat(f32, x),
        .y = @intToFloat(f32, y),
        .w = @intToFloat(f32, w),
        .h = @intToFloat(f32, h),
    };
}

pub fn Rec(x: anytype, y: anytype, w: anytype, h: anytype) Rect {
    return .{
        .x = std.math.lossyCast(f32, x),
        .y = std.math.lossyCast(f32, y),
        .w = std.math.lossyCast(f32, w),
        .h = std.math.lossyCast(f32, h),
    };
}

pub fn rectContainsPoint(r: anytype, p: anytype) bool {
    return (p.x >= r.x and p.x <= r.x + r.w and p.y >= r.y and p.y <= r.y + r.h);
}

pub const Plane = enum { xy, yz, xz };
pub fn vertexTexturedDir(plane: Plane, x: f32, y: f32, z: f32, u: f32, v: f32, col: Color) VertexTextured {
    const p: struct { x: f32, y: f32, z: f32, u: f32, v: f32 } = switch (plane) {
        .xy => .{ .x = x, .y = y, .z = z, .u = u, .v = v },
        .yz => .{ .x = y, .y = z, .z = x, .u = u, .v = v },
        .xz => .{ .x = x, .y = z, .z = y, .u = u, .v = v },
    };
    return .{ .x = p.x, .y = p.y, .z = p.z, .u = p.u, .v = p.v, .r = col[0], .g = col[1], .b = col[2], .a = col[3] };
}

pub fn quadTex(pos: V3, w: f32, h: f32, plane: Plane, neg: bool, tr: Rect, tx_w: u32, tx_h: u32, color: CharColor) [4]VertexTextured {
    const un = normalizeTexRect(tr, tx_w, tx_h);
    const col = charColorToFloat(color);
    const p: struct { x: f32, y: f32, z: f32 } = .{ .x = pos.data[0], .y = pos.data[1], .z = pos.data[2] };
    if (neg) {
        return .{
            // zig fmt: off
            vertexTexturedDir(plane, p.x,     p.y + h, p.z, un.x       , un.y + un.h, col),
            vertexTexturedDir(plane, p.x + w, p.y + h, p.z, un.x       , un.y       , col),
            vertexTexturedDir(plane, p.x + w, p.y,     p.z, un.x + un.w, un.y       , col),
            vertexTexturedDir(plane, p.x,     p.y,     p.z, un.x + un.w, un.y + un.h, col),
            //zig fmt: on
        };
    } else {
        return .{
            // zig fmt: off
            vertexTexturedDir(plane, p.x,     p.y,     p.z, un.x + un.w, un.y + un.h, col),
            vertexTexturedDir(plane, p.x + w, p.y,     p.z, un.x + un.w, un.y       , col),
            vertexTexturedDir(plane, p.x + w, p.y + h, p.z, un.x       , un.y       , col),
            vertexTexturedDir(plane, p.x,     p.y + h, p.z, un.x       , un.y + un.h, col),
            //zig fmt: on
        };
    }
}

pub const Camera2D = struct {
    screen_area: Rect,
    canvas_area:Rect,
};

pub const Camera3D = struct {
    const Self = @This(); 
    pos: za.Vec3 = za.Vec3.new(0,0,0),
    front: za.Vec3 = za.Vec3.new(0,0,0),
    yaw:f32 = 0,
    pitch:f32 = 0,
    move_speed:f32 = 0.1,

    pub fn update(self: *Self, win:*const SDL.Window)void{
            var move_vec  = za.Vec3.new(0,0,0);
            if (win.keydown(.LSHIFT))
                move_vec = move_vec.add(za.Vec3.new(0, -1, 0));
            if (win.keydown(.SPACE))
                move_vec = move_vec.add(za.Vec3.new(0, 1, 0));
            if (win.keydown(.COMMA))
                move_vec = move_vec.add(self.front);
            if (win.keydown(.O))
                move_vec = move_vec.add(self.front.scale(-1));
            if (win.keydown(.A))
                move_vec = move_vec.add(self.front.cross(.{ .data = .{ 0, 1, 0 } }).norm().scale(-1));
            if (win.keydown(.E))
                move_vec = move_vec.add(self.front.cross(.{ .data = .{ 0, 1, 0 } }).norm());

            self.pos = self.pos.add(move_vec.norm().scale(self.move_speed));
            const mdelta = win.mouse.delta.smul(0.1);
            self.move_speed = std.math.clamp(self.move_speed + win.mouse.wheel_delta * (self.move_speed / 10), 0.01, 10);

            self.yaw += mdelta.x;
            self.pitch = std.math.clamp(self.pitch - mdelta.y, -89, 89);

            const sin = std.math.sin;
            const rad = std.math.degreesToRadians;
            const cos = std.math.cos;
            const dir = za.Vec3.new(
                cos(rad(f32, self.yaw)) * cos(rad(f32, self.pitch)),
                sin(rad(f32, self.pitch)),
                sin(rad(f32, self.yaw)) * cos(rad(f32, self.pitch)),
            );
            self.front = dir.norm();

    }

    pub fn getMatrix(self:Self, aspect_ratio: f32, fov: f32, near:f32, far:f32)za.Mat4{
        const la = za.lookAt(self.pos, self.pos.add(self.front), za.Vec3.new(0, 1, 0));
        const perp = za.perspective(fov, aspect_ratio, near, far);
        return perp.mul(la);
    }
};

pub fn basicGraphUsage()void{
    const graph = @This();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = &gpa.allocator();

    var binds = graph.Bind(&.{.{ "my_bind", "a" }}).init();

    var win = try graph.SDL.Window.createWindow("My window");
    defer win.destroyWindow();

    var ctx = try graph.GraphicsContext.init(alloc, 163);
    defer ctx.deinit();

    var dpix: u32 = @floatToInt(u32, win.getDpi());
    const init_size = 18;
    var font = try graph.Font.init("fonts/sfmono.otf", alloc, init_size, dpix, &(graph.Font.CharMaps.AsciiBasic ++ graph.Font.CharMaps.Apple), null);

    while (!win.should_exit) {
        try ctx.beginDraw(intToColor(0x2f2f2fff));
        win.pumpEvents(); //Important that this is called after beginDraw for input lag reasons
        for (win.keys.slice()) |key| {
            switch (binds.get(key.scancode)) {
                .my_bind => std.debug.print("bind pressed\n", .{}),
                else => {},
            }
        }

            ctx.drawText(50, 300, "Hello", &font, 16, intToColor(0xffffffff));
        ctx.endDraw(win.screen_width, win.screen_height);
        win.swap();
    }


}

pub fn writeBmp(file_name: [*c]const u8, w:i32, h:i32,component_count:i32, data: []const u8)void{
    _ = c.stbi_write_bmp(file_name, w,h,component_count,&data[0]);
}

//Ideally I don't want to make any c.SDL calls in my application
//TODO detect dpi changes
pub const SDL = struct {
    pub const MouseState = struct {
        left: bool,
        right: bool,
        middle: bool,

        //TODO rename and add other mouse buttons
        //each button has 4 states, Click, Hold, Up, Release
        //This mouse state structure can be used by Gui
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

    pub fn getKeyFromScancode(scancode: keycodes.Scancode) keycodes.Keycode {
        return @intToEnum(keycodes.Keycode, c.SDL_GetKeyFromScancode(@enumToInt(scancode)));
    }

    pub fn getScancodeFromKey(key: keycodes.Keycode) keycodes.Scancode {
        return @intToEnum(keycodes.Scancode, c.SDL_GetScancodeFromKey(@enumToInt(key)));
    }

    //TODO check for ibus support on linux and log if not avail
    pub const Window = struct {
        const Self = @This();
        pub const KeyboardStateT = std.bit_set.IntegerBitSet(c.SDL_NUM_SCANCODES);
        pub const KeysT = std.BoundedArray(KeyState, 16);

        win: *c.SDL_Window,
        ctx: *anyopaque,

        //TODO move to a vector
        screen_width: i32 = 0,
        screen_height: i32 = 0,

        should_exit: bool = false,

        mouse: MouseState = undefined,

        keys: KeysT = KeysT.init(0) catch unreachable,
        keyboard_state: KeyboardStateT = KeyboardStateT.initEmpty(),

        text_input_buffer:[32]u8 = undefined,
        text_input:[]const u8  ,

        fn sdlLogErr() void {
            std.debug.print("SDL ERROR:\n{s}\n", .{c.SDL_GetError()});
        }

        fn setAttr(attr: c.SDL_GLattr, val: c_int) !void {
            if (c.SDL_GL_SetAttribute(attr, val) < 0) {
                sdlLogErr();
                return error.SDLSetAttr;
            }
        }

        pub fn grabMouse(self: *const Self, should: bool) void {
            _ = self;
            _ = c.SDL_SetRelativeMouseMode(if (should) 1 else 0);
            //c.SDL_SetWindowMouseGrab(self.win, if (should) 1 else 0);
            //_ = c.SDL_ShowCursor(if (!should) 1 else 0);
        }

        //pub fn screenshotGL(self: *const Self,alloc: std.mem.Allocator,  )void{

        //}

        pub fn createWindow(title: [*c]const u8) !Self {
            //This does not seem to be needed
            //No errors occur
            //Event handling still functions
            if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
                sdlLogErr();
                return error.SDLInit;
            }
            errdefer c.SDL_Quit();

            try setAttr(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
            try setAttr(c.SDL_GL_DOUBLEBUFFER, 1);
            try setAttr(c.SDL_GL_CONTEXT_MAJOR_VERSION, 4);
            try setAttr(c.SDL_GL_CONTEXT_MINOR_VERSION, 6);
            try setAttr(c.SDL_GL_CONTEXT_FLAGS, c.SDL_GL_CONTEXT_DEBUG_FLAG);
            try setAttr(c.SDL_GL_STENCIL_SIZE, 8);
            try setAttr(c.SDL_GL_MULTISAMPLEBUFFERS, 1);
            try setAttr(c.SDL_GL_MULTISAMPLESAMPLES, 16);

            const win = c.SDL_CreateWindow(
                title,
                c.SDL_WINDOWPOS_UNDEFINED,
                c.SDL_WINDOWPOS_UNDEFINED,
                1280,
                960,
                c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE ,
            ) orelse {
                sdlLogErr();
                return error.SDLInit;
            };
            errdefer c.SDL_DestroyWindow(win);

            const context = c.SDL_GL_CreateContext(win) orelse {
                sdlLogErr();
                return error.SDLCreatingContext;
            };
            errdefer c.SDL_GL_DeleteContext(context);

            c.glEnable(c.GL_MULTISAMPLE);

            if (c.SDL_GL_SetSwapInterval(1) < 0) {
                sdlLogErr();
                return error.SetSwapInterval;
            }
            c.glEnable(c.GL_DEPTH_TEST);
            c.glEnable(c.GL_STENCIL_TEST);
            c.glEnable(c.GL_DEBUG_OUTPUT);

            //_ = c.SDL_SetRelativeMouseMode(c.SDL_TRUE);

            return Self{ .win = win, .ctx = context, .text_input = "", };
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

        pub fn getDpi(self: *Self) f32 {
            var dpi: f32 = 0;

            var hdpi: f32 = 0;
            var vdpi: f32 = 0;
            _ = c.SDL_GetDisplayDPI(c.SDL_GetWindowDisplayIndex(self.win), &dpi, &hdpi, &vdpi);
            return dpi;
        }

        pub fn enableNativeIme(self: *const Self,enable:bool )bool{
            _ = self;
            _ = c.SDL_SetHint("SDL_HINT_IME_INTERNAL_EDITING", "1");
            return (c.SDL_SetHint("SDL_HINT_IME_SHOW_UI", if(enable) "1" else "0") == 1);
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
                    }
                }
            }
            self.text_input = "";

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
                    c.SDL_TEXTEDITING => {
                        const ed = event.edit;
                        const slice = std.mem.sliceTo(&ed.text, 0);
                        std.debug.print("{s} start: {d} length: {d}\n",.{slice, ed.start, ed.length}); 
                    },
                    c.SDL_TEXTINPUT => {
                        const slice = std.mem.sliceTo(&event.text.text, 0);
                        std.mem.copy(u8, &self.text_input_buffer, slice);
                        self.text_input = self.text_input_buffer[0..slice.len];
                        //std.debug.print("SLICE {s}\n",.{slice}); 
                    },
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

        pub fn glScissor(self: *Self,x:i32, y:i32,w: i32, h:i32 )void{
            _ = self;
            c.glScissor(x,h - y,w, h);
        }

        pub fn bindScreenFramebuffer(self: *Self)void{
            c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
            c.glViewport(0,0,self.screen_width, self.screen_height);
        }

        pub fn startTextInput(self: *const Self)void{
            _ = self;
            const rec = c.SDL_Rect{.x = 50,.y = 500, .w = 300, .h = 72};
            c.SDL_SetTextInputRect(&rec);
            c.SDL_StartTextInput();
        }
        
        pub fn stopTextInput(self: *const Self)void{
            _ = self;
                c.SDL_StopTextInput();
        }

        pub fn keydown(self: *const Self, scancode: keycodes.Scancode) bool {
            return self.keyboard_state.isSet(@enumToInt(scancode));
        }
    };
};

pub const Atlas = struct {
    pub const AtlasJson = struct {
        pub const SetJson = struct {
            filename: []const u8,
            tilesets: []const SubTileset,
        };

        img_dir_path:[]const u8,
        sets: []const SetJson,
    };

    texture: Texture,

    sets: std.ArrayList(SubTileset),

    //TODO determine optimal texture_size
    pub fn initFromJsonFile(json_filename: []const u8, alloc: std.mem.Allocator, texture_size: ?u32) !Atlas {
        const cwd = std.fs.cwd();
        const json_slice = try cwd.readFileAlloc(alloc,json_filename,  std.math.maxInt(usize));
        defer alloc.free(json_slice);

        {
        const json = try parseJson(AtlasJson, json_slice, .{.allocator = alloc,});
        defer json.parseFree();
        const img_path = json.data.img_dir_path;
        const sets_to_load = json.data.sets;

        if(sets_to_load.len == 0) return error.noSets;


        var packing_rects = std.ArrayList(c.stbrp_rect).init(alloc);
        defer packing_rects.deinit();

        var running_area:i32 = 0;
        var sets = std.ArrayList(SubTileset).init(alloc);
        var id_len: usize = 0;
        for (sets_to_load) |item| {
            for (item.tilesets) |ts, j| {
                running_area += ts.tw * ts.num.x * ts.th * ts.num.y;
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
                    .w = @intCast(c_ushort, ts.num.x * ts.tw),
                    .h = @intCast(c_ushort, ts.num.y * ts.th),
                    .x = 50,
                    .y = 50,
                    .was_packed = 1,
                });
            }
            id_len += item.tilesets.len;
        }
        const atlas_size = blk: {
            if(texture_size)|ts|{
                break :blk ts;
            }
            else{
                break :blk @floatToInt(u32,@sqrt(@intToFloat(f32, running_area) * 2));
                
            }
        };

        var nodes = std.ArrayList(c.stbrp_node).init(alloc);
        defer nodes.deinit();
        try nodes.appendNTimes(undefined, atlas_size + 200); //TODO MAGICNUM
        var rect_context: c.stbrp_context = undefined;

        c.stbrp_init_target(
            &rect_context,
            @intCast(c_int, atlas_size),
            @intCast(c_int, atlas_size),
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

        var bitmap = std.ArrayList(u8).init(alloc);
        defer bitmap.deinit();
        try bitmap.appendNTimes(0, 4 * atlas_size * atlas_size);

        var bit = Bitmap{ .data = bitmap, .w = atlas_size, .h = atlas_size };

        var full_filename = std.ArrayList(u8).init(alloc);
        defer full_filename.deinit();
        try full_filename.appendSlice(img_path);
        for (packing_rects.items) |rect| {
            var in: usize = 0;
            var j: usize = @intCast(usize, rect.id);
            while (j >= sets_to_load[in].tilesets.len) : (in += 1) {
                j -= sets_to_load[in].tilesets.len;
            }

            const set = sets_to_load[in].tilesets[j];

            try full_filename.appendSlice(sets_to_load[in].filename);
            var ts_bmp = try loadPng(full_filename.items, alloc);
            try full_filename.resize(img_path.len);
            defer ts_bmp.data.deinit();

            sets.items[@intCast(usize, rect.id)].start = .{ .x = rect.x, .y = rect.y };

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
        writeBmp("debug/atlas.bmp", @intCast(c_int, atlas_size), @intCast(c_int, atlas_size), 4, bitmap.items);

        return Atlas{
            .texture = Texture.fromArray(bitmap.items, @intCast(i32,atlas_size), @intCast(i32,atlas_size), .{}),
            .sets = sets,
        };
        }
    }

    pub fn getTexRec(m: @This(), si: usize, ti: usize) Rect {
        return m.sets.items[si].getTexRec(ti);
    }

    pub fn deinit(m: Atlas) void {
        m.sets.deinit();
    }
};

///A structure that maps indices to a rectangle within a larger rectangle based on various parameters.
///Useful for tilemaps that include padding
pub const SubTileset = struct {
    const Self = @This();

    description: []const u8 = "", 
    start: Vec2i, //xy of first tile
    tw: i32,      //width of tile
    th: i32,
    pad: Vec2i,   //xy spacing between tiles
    num: Vec2i,   //number of cols, rows
    count: usize, //Total number of tiles, useful if last row is short

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

///A Fixed width bitmap font structure
//TODO make this a part of Font. Functions that accept a font should accept this too
pub const FixedBitmapFont = struct {
    const Self = @This();

    texture: Texture,
    sts: SubTileset,

    // zig fmt: on
    translation_table: [128]u8 = [_]u8{127} ** 128,

    // each index of this decode_string corresponds to the index of the character in subTileSet
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

pub const Bitmap = struct {
    const m = @This();
    //TODO add support for different types: rgba only for now
    data: std.ArrayList(u8),
    w: u32,
    h: u32,

    //TODO actually initalize the memory
    pub fn initBlank(alloc: std.mem.Allocator, width: u32, height: u32) !m {
        var ret = m{ .data = std.ArrayList(u8).init(alloc), .w = width, .h = height };
        try ret.data.resize(4 * width * height);
        return ret;
    }

    pub fn writeToBmpFile(self: *const m, alloc: std.mem.Allocator, file_name: []const u8) !void {
        var null_str_buf = std.ArrayList(u8).init(alloc);
        defer null_str_buf.deinit();
        try null_str_buf.appendSlice(file_name);
        try null_str_buf.append(0);

        _ = c.stbi_write_bmp(@ptrCast([*c]const u8, null_str_buf.items), @intCast(c_int, self.w), @intCast(c_int, self.h), 4, @ptrCast([*c]u8, self.data.items[0..self.data.items.len]));
    }

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

pub fn loadPngBitmap(relative_path: []const u8, alloc: std.mem.Allocator) !Bitmap {
    const cwd = std.fs.cwd();
    const png_file = try cwd.openFile(relative_path, .{});
    defer png_file.close();

    var buf = std.ArrayList(u8).init(alloc);
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

    return Bitmap{ .w = ihdr.width, .h = ihdr.height, .data = std.ArrayList(u8).fromOwnedSlice(alloc, decoded_data) };

    //#9494ff background color

}

pub fn loadPng(relative_path: []const u8, alloc: std.mem.Allocator) !Bitmap {
    const cwd = std.fs.cwd();
    const png_file = try cwd.openFile(relative_path, .{});
    defer png_file.close();

    var buf = std.ArrayList(u8).init(alloc);
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

    return Bitmap{ .w = ihdr.width, .h = ihdr.height, .data = std.ArrayList(u8).fromOwnedSlice(alloc, decoded_data) };

    //#9494ff background color

}

pub const GL = struct {
    pub const PrimitiveMode = enum(u32) {
        points = c.GL_POINTS,
        line_strip = c.GL_LINE_STRIP,
        line_loop = c.GL_LINE_LOOP,
        lines = c.GL_LINES,
        line_strip_adjacency = c.GL_LINE_STRIP_ADJACENCY,
        lines_adjacency = c.GL_LINES_ADJACENCY,
        triangle_strip = c.GL_TRIANGLE_STRIP,
        triangle_fan = c.GL_TRIANGLE_FAN,
        triangles = c.GL_TRIANGLES,
        triangle_strip_adjacency = c.GL_TRIANGLE_STRIP_ADJACENCY,
        triangles_adjacency = c.GL_TRIANGLES_ADJACENCY,
        patches = c.GL_PATCHES,
    };

    pub fn checkError() void {
        var err = c.glGetError();
        // zig fmt: on
        while (err != c.GL_NO_ERROR) : (err = c.glGetError()) {
            const str = switch (err) {
                c.GL_INVALID_ENUM => "An unacceptable value is specified for an enumerated argument. The offending command is ignored and has no other side effect than to set the error flag.",
                c.GL_INVALID_VALUE => "A numeric argument is out of range. The offending command is ignored and has no other side effect than to set the error flag.",
                c.GL_INVALID_OPERATION => "The specified operation is not allowed in the current state. The offending command is ignored and has no other side effect than to set the error flag.",
                c.GL_INVALID_FRAMEBUFFER_OPERATION => "The framebuffer object is not complete. The offending command is ignored and has no other side effect than to set the error flag.",
                c.GL_OUT_OF_MEMORY => "There is not enough memory left to execute the command. The state of the GL is undefined, except for the state of the error flags, after this error is recorded.",
                c.GL_STACK_UNDERFLOW => "An attempt has been made to perform an operation that would cause an internal stack to underflow.",
                c.GL_STACK_OVERFLOW => "An attempt has been made to perform an operation that would cause an internal stack to overflow.",
                else => unreachable,
            };
            std.debug.print("glGetError: {s}\n", .{str});
        }
    }

    fn passUniform(shader: c_uint, uniform_name: [*c]const u8, data: anytype) void {
        const uniform_location = c.glGetUniformLocation(shader, uniform_name);
        switch (@TypeOf(data)) {
            za.Mat4 => c.glUniformMatrix4fv(uniform_location, 1, c.GL_FALSE, &data.data[0][0]),
            else => @compileError("GL.passUniform type not implemented: " ++ @typeName(@TypeOf(data))),
        }
    }

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

    //TODO should this output a string specifiing GLSL input layouts that can be catted with our shader
    fn generateVertexAttributes(vao: c_uint, vbo: c_uint, comptime T: anytype) void {
        const info = @typeInfo(T);
        switch (info) {
            .Struct => {
                const st = info.Struct;
                if (st.layout != .Packed) @compileError("generateVertexAttributes only supports packed structs");
                inline for (st.fields) |field, f_i| {
                    switch (field.field_type) {
                        Vec2f => floatVertexAttrib(vao, vbo, f_i, 2, T, field.name),
                        Vec3f => floatVertexAttrib(vao, vbo, f_i, 3, T, field.name),
                        u16 => intVertexAttrib(vao, vbo, f_i, 1, T, field.name, c.GL_UNSIGNED_SHORT),
                        u32 => intVertexAttrib(vao, vbo, f_i, 1, T, field.name, c.GL_UNSIGNED_INT),
                        else => @compileError("generateVertexAttributes struct field type not supported: " ++ @typeName(field.field_type)),
                    }
                }
            },
            else => @compileError("generateVertexAttributes expects a struct"),
        }
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

    //TODO once our generateVertexAttributes function works, these functions should not deal with vao or vbo they should assume they have been bound already
    fn intVertexAttrib(vao: glID, vbo: glID, index: u32, num_elem: u32, comptime item: type, comptime starting_field: []const u8, int_type: c.GLenum) void {
        c.glBindVertexArray(vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
        defer c.glBindVertexArray(0);
        defer c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

        const byte_offset = @offsetOf(item, starting_field);
        c.glVertexAttribIPointer(
            index,
            @intCast(c_int, num_elem),
            int_type,
            @sizeOf(item),
            if (byte_offset != 0) @intToPtr(*const anyopaque, byte_offset) else null,
        );
        c.glEnableVertexAttribArray(index);
    }

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

        GL.passUniform(batch.shader, "view", view);
        GL.passUniform(batch.shader, "model", model);

        c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, batch.indicies.items.len), c.GL_UNSIGNED_INT, null);
        //c.glBindVertexArray(0);

    }
};

//TODO have a default font that gets loaded
//Handle dpi
//More 3d primitives
pub const NewCtx = struct {
    const Self = @This();
    pub const ColorTriVert = packed struct { pos: Vec2f, z: u16, color: u32 };
    pub const Line3DVert = packed struct { pos: Vec3f, color: u32 };
    pub const TexTriVert = packed struct { pos: Vec2f, uv: Vec2f, z: u16, color: u32 };

    const ColorTriBatch = NewBatch(ColorTriVert, .{ .index_buffer = true, .primitive_mode = .triangles });
    const ColorLine3DBatch = NewBatch(Line3DVert, .{ .index_buffer = false, .primitive_mode = .lines });
    const TextureTriBatch = NewBatch(TexTriVert, .{ .index_buffer = true, .primitive_mode = .triangles });
    const FontBatch = NewBatch(TexTriVert, .{ .index_buffer = true, .primitive_mode = .triangles });

    batch_colored_line3D: ColorLine3DBatch,
    batch_colored_tri: ColorTriBatch,
    batch_font: FontBatch,

    batch_textured_tri_map: std.AutoHashMap(c_uint, TextureTriBatch),

    zindex: u16 = 0,
    font_shader: c_uint,
    colored_tri_shader: c_uint,
    colored_line3d_shader: c_uint,
    textured_tri_shader: c_uint,
    dpi: f32,

    delete_me_font_tex: ?Texture = null,

    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, dpi: f32) Self {
        return Self{
            .alloc = alloc,
            .dpi = dpi,
            .batch_colored_tri = ColorTriBatch.init(alloc),
            .batch_colored_line3D = ColorLine3DBatch.init(alloc),
            .batch_textured_tri_map = std.AutoHashMap(c_uint, TextureTriBatch).init(alloc),
            .batch_font = FontBatch.init(alloc),

            .colored_tri_shader = Shader.simpleShader(NewTri.shader_test_vert, NewTri.shader_test_frag),
            .colored_line3d_shader = Shader.simpleShader(@embedFile("shader/line3d.vert"), @embedFile("shader/colorquad.frag")),
            .textured_tri_shader = Shader.simpleShader(@embedFile("shader/tex_tri2d.vert"), @embedFile("shader/tex_tri2d.frag")),

            .font_shader = Shader.simpleShader(@embedFile("shader/tex_tri2d.vert"), @embedFile("shader/tex_tri2d_alpha.frag")),
        };
    }

    pub fn deinit(self: *Self) void {
        self.batch_colored_tri.deinit();
        self.batch_font.deinit();
        self.batch_colored_line3D.deinit();
        var tex_it = self.batch_textured_tri_map.valueIterator();
        var v = tex_it.next();
        while (v) |joj| : (v = tex_it.next()) {
            _ = joj;
            v.?.deinit();
        }
        self.batch_textured_tri_map.deinit();
    }
    //TODO function that takes anytype used to draw

    fn getTexturedTriBatch(self: *Self, tex_id: c_uint) !*TextureTriBatch {
        const res = try self.batch_textured_tri_map.getOrPut(tex_id);
        if (!res.found_existing) {
            res.value_ptr.* = TextureTriBatch.init(self.alloc);
            res.key_ptr.* = tex_id;
            try res.value_ptr.clear();
        }
        return res.value_ptr;
    }

    pub fn begin(self: *Self, bg: CharColor) !void {
        try self.batch_colored_tri.clear();
        try self.batch_colored_line3D.clear();
        try self.batch_font.clear();
        var tex_it = self.batch_textured_tri_map.valueIterator();
        var vo = tex_it.next();
        while (vo) |v| : (vo = tex_it.next()) {
            try v.clear();
        }

        self.zindex = 1;
        std.time.sleep(16 * std.time.ns_per_ms);

        const color = charColorToFloat(bg);
        c.glClearColor(color[0], color[1], color[2], color[3]);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
    }

    pub fn rectPt(self: *Self, rpt: Rect, color: u32) !void {
        try self.rect(rpt.mul(self.dpi / 72.0), color);
    }

    //TODO defer errors to end of frame when fn end() called
    pub fn rect(self: *Self, rpt: Rect, color: u32) !void {
        const r = rpt;
        const b = &self.batch_colored_tri;
        const z = self.zindex;
        self.zindex += 1;
        try b.indicies.appendSlice(&genQuadIndices(@intCast(u32, b.vertices.items.len)));
        try b.vertices.appendSlice(&.{
            ColorTriVert{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .color = color },
            ColorTriVert{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .color = color },
            ColorTriVert{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .color = color },
            ColorTriVert{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .color = color },
        });
    }

    pub fn rectTex(self: *Self, r: Rect, tr: Rect, col: u32, texture: Texture) !void {
        const b = try self.getTexturedTriBatch(texture.id);
        const z = self.zindex;
        self.zindex += 1;
        const un = normalizeTexRect(tr, texture.w, texture.h);

        try b.indicies.appendSlice(&genQuadIndices(@intCast(u32, b.vertices.items.len)));
        try b.vertices.appendSlice(&.{
            TexTriVert{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y + un.h }, .color = col }, //0
            TexTriVert{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y }, .color = col }, //1
            TexTriVert{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .uv = .{ .x = un.x, .y = un.y }, .color = col }, //2
            TexTriVert{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x, .y = un.y + un.h }, .color = col }, //3
        });
    }

    pub fn text(self: *Self, pos: Vec2f, str: []const u8, font: *Font, pt_size: f32, col: u32) !void {
        self.delete_me_font_tex = font.texture;
        const SF = (pt_size / font.font_size);
        const fac = 1;
        const x = pos.x;
        const y = pos.y;

        const b = &self.batch_font;

        b.vertices.ensureUnusedCapacity(str.len * 4) catch unreachable;
        b.indicies.ensureUnusedCapacity(str.len * 6) catch unreachable;

        var it = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };

        var vx = x * fac;
        var vy = y * fac + ((font.ascent + font.descent) * SF);
        var cho = it.nextCodepoint();
        while (cho != null) : (cho = it.nextCodepoint()) {
            const ch = cho orelse unreachable;
            if (ch == '\n') {
                vy += font.line_gap * SF;
                vx = x * fac;
                continue;
            }

            const g = font.glyph_set.get(ch) catch |err|
                switch (err) {
                error.invalidIndex => font.glyph_set.get(std.unicode.replacement_character) catch unreachable,
            };
            const fpad = @intToFloat(f32, Font.padding) / 2;
            const pad = @intToFloat(f32, Font.padding);

            const r = Rect{
                .x = vx + (g.offset_x - fpad) * SF,
                .y = vy - (g.offset_y + fpad) * SF,
                .w = (pad + g.width) * SF,
                .h = (pad + g.height) * SF,
            };

            // try self.rect(r, 0xffffffff);

            b.indicies.appendSlice(&genQuadIndices(@intCast(u32, b.vertices.items.len))) catch unreachable;
            const un = normalizeTexRect(g.tr, font.texture.w, font.texture.h);
            const z = self.zindex;
            try b.vertices.appendSlice(&.{
                TexTriVert{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y + un.h }, .color = col }, //0
                TexTriVert{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y }, .color = col }, //1
                TexTriVert{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .uv = .{ .x = un.x, .y = un.y }, .color = col }, //2
                TexTriVert{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x, .y = un.y + un.h }, .color = col }, //3
            });

            vx += (g.advance_x) * SF;
        }
        self.zindex += 1;
    }

    pub fn line3D(self: *Self, start_point: Vec3f, end_point: Vec3f, color: u32) !void {
        const b = &self.batch_colored_line3D;
        try b.vertices.append(.{ .pos = start_point, .color = color });
        try b.vertices.append(.{ .pos = end_point, .color = color });
    }

    pub fn end(self: *Self, screenW: i32, screenH: i32, camera: za.Mat4) void {
        const view = za.orthographic(0, @intToFloat(f32, screenW), @intToFloat(f32, screenH), 0, -100000, 1);
        const model = za.Mat4.identity();

        self.batch_colored_tri.pushVertexData();
        self.batch_colored_tri.draw(.{}, self.colored_tri_shader, view, model);

        self.batch_colored_line3D.pushVertexData();
        self.batch_colored_line3D.draw(.{}, self.colored_line3d_shader, camera, model);

        var tex_it = self.batch_textured_tri_map.iterator();
        var vo = tex_it.next();
        while (vo) |v| : (vo = tex_it.next()) {
            v.value_ptr.pushVertexData();
            v.value_ptr.draw(.{ .texture = v.key_ptr.* }, self.textured_tri_shader, view, model);
        }
        self.batch_font.pushVertexData();
        self.batch_font.draw(.{ .texture = self.delete_me_font_tex.?.id }, self.font_shader, view, model);
    }
};

pub const BatchOptions = struct {
    index_buffer: bool,
    primitive_mode: GL.PrimitiveMode,
};
pub fn NewBatch(comptime vertex_type: type, comptime batch_options: BatchOptions) type {
    const IndexType = u32;
    return struct {
        pub const Self = @This();
        pub const DrawParams = struct {
            texture: ?c_uint = null,
        };

        vbo: c_uint,
        vao: c_uint,
        ebo: if (batch_options.index_buffer) c_uint else void,
        vertices: std.ArrayList(vertex_type),
        indicies: if (batch_options.index_buffer) std.ArrayList(IndexType) else void,
        primitive_mode: GL.PrimitiveMode = batch_options.primitive_mode,

        pub fn init(alloc: std.mem.Allocator) @This() {
            var ret = @This(){
                .vertices = std.ArrayList(vertex_type).init(alloc),
                .indicies = if (batch_options.index_buffer) std.ArrayList(IndexType).init(alloc) else {},
                .ebo = if (batch_options.index_buffer) 0 else {},
                .vao = 0,
                .vbo = 0,
            };

            c.glGenVertexArrays(1, &ret.vao);
            c.glGenBuffers(1, &ret.vbo);
            if (batch_options.index_buffer) c.glGenBuffers(1, &ret.ebo);

            GL.generateVertexAttributes(ret.vao, ret.vbo, vertex_type);

            return ret;
        }

        pub fn deinit(self: *Self) void {
            self.vertices.deinit();
            if (batch_options.index_buffer)
                self.indicies.deinit();
        }

        pub fn pushVertexData(self: *Self) void {
            c.glBindVertexArray(self.vao);
            GL.bufferData(c.GL_ARRAY_BUFFER, self.vbo, vertex_type, self.vertices.items);
            if (batch_options.index_buffer)
                GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, self.ebo, u32, self.indicies.items);
        }

        pub fn clear(self: *Self) !void {
            try self.vertices.resize(0);
            if (batch_options.index_buffer)
                try self.indicies.resize(0);
        }

        pub fn draw(self: *Self, params: DrawParams, shader: c_uint, view: za.Mat4, model: za.Mat4) void {
            c.glUseProgram(shader);
            c.glBindVertexArray(self.vao);
            if (params.texture) |texture| {
                c.glBindTexture(c.GL_TEXTURE_2D, texture);
            }
            GL.passUniform(shader, "view", view);
            GL.passUniform(shader, "model", model);

            if (batch_options.index_buffer) {
                //TODO primitive generic
                c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, self.indicies.items.len), c.GL_UNSIGNED_INT, null);
            } else {
                c.glLineWidth(3.0);
                c.glDrawArrays(c.GL_LINES, 0, @intCast(c_int, self.vertices.items.len));
            }
        }
    };
}

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

pub fn genQuadIndices(index: u32) [6]u32 {
    return [_]u32{
        index + 0,
        index + 1,
        index + 3,
        index + 1,
        index + 2,
        index + 3,
    };
}

pub fn contrastColor(color: CharColor) CharColor {
    var hsva = colorToHsva(color);
    hsva.h = @mod(hsva.h + 180, 360);
    //hsva.v = 1;
    hsva.v = @mod(hsva.v + 0.5, 1);
    return hsvaToColor(hsva);
}

pub const CharColor = struct {
    pub const DarkGreen = itc(0x006400ff);
    pub const Green = itc(0x008000ff);
    pub const DarkOliveGreen = itc(0x556B2Fff);
    pub const ForestGreen = itc(0x228B22ff);
    pub const SeaGreen = itc(0x2E8B57ff);
    pub const Olive = itc(0x808000ff);
    pub const OliveDrab = itc(0x6B8E23ff);
    pub const MediumSeaGreen = itc(0x3CB371ff);
    pub const LimeGreen = itc(0x32CD32ff);
    pub const Lime = itc(0x00FF00ff);
    pub const SpringGreen = itc(0x00FF7Fff);
    pub const MediumSpringGreen = itc(0x00FA9Aff);
    pub const DarkSeaGreen = itc(0x8FBC8Fff);
    pub const MediumAquamarine = itc(0x66CDAAff);
    pub const YellowGreen = itc(0x9ACD32ff);
    pub const LawnGreen = itc(0x7CFC00ff);
    pub const Chartreuse = itc(0x7FFF00ff);
    pub const LightGreen = itc(0x90EE90ff);
    pub const GreenYellow = itc(0xADFF2Fff);
    pub const PaleGreen = itc(0x98FB98ff);
    pub const MistyRose = itc(0xFFE4E1ff);
    pub const AntiqueWhite = itc(0xFAEBD7ff);
    pub const Linen = itc(0xFAF0E6ff);
    pub const Beige = itc(0xF5F5DCff);
    pub const WhiteSmoke = itc(0xF5F5F5ff);
    pub const LavenderBlush = itc(0xFFF0F5ff);
    pub const OldLace = itc(0xFDF5E6ff);
    pub const AliceBlue = itc(0xF0F8FFff);
    pub const Seashell = itc(0xFFF5EEff);
    pub const GhostWhite = itc(0xF8F8FFff);
    pub const Honeydew = itc(0xF0FFF0ff);
    pub const FloralWhite = itc(0xFFFAF0ff);
    pub const Azure = itc(0xF0FFFFff);
    pub const MintCream = itc(0xF5FFFAff);
    pub const Snow = itc(0xFFFAFAff);
    pub const Ivory = itc(0xFFFFF0ff);
    pub const White = itc(0xFFFFFFff);
    pub const Black = itc(0x000000ff);
    pub const DarkSlateGray = itc(0x2F4F4Fff);
    pub const DimGray = itc(0x696969ff);
    pub const SlateGray = itc(0x708090ff);
    pub const Gray = itc(0x808080ff);
    pub const LightSlateGray = itc(0x778899ff);
    pub const DarkGray = itc(0xA9A9A9ff);
    pub const Silver = itc(0xC0C0C0ff);
    pub const LightGray = itc(0xD3D3D3ff);
    pub const Gainsboro = itc(0xDCDCDCff);
    pub const Indigo = itc(0x4B0082ff);
    pub const Purple = itc(0x800080ff);
    pub const DarkMagenta = itc(0x8B008Bff);
    pub const DarkViolet = itc(0x9400D3ff);
    pub const DarkSlateBlue = itc(0x483D8Bff);
    pub const BlueViolet = itc(0x8A2BE2ff);
    pub const DarkOrchid = itc(0x9932CCff);
    pub const Fuchsia = itc(0xFF00FFff);
    pub const Magenta = itc(0xFF00FFff);
    pub const SlateBlue = itc(0x6A5ACDff);
    pub const MediumSlateBlue = itc(0x7B68EEff);
    pub const MediumOrchid = itc(0xBA55D3ff);
    pub const MediumPurple = itc(0x9370DBff);
    pub const Orchid = itc(0xDA70D6ff);
    pub const Violet = itc(0xEE82EEff);
    pub const Plum = itc(0xDDA0DDff);
    pub const Thistle = itc(0xD8BFD8ff);
    pub const Lavender = itc(0xE6E6FAff);
    pub const MidnightBlue = itc(0x191970ff);
    pub const Navy = itc(0x000080ff);
    pub const DarkBlue = itc(0x00008Bff);
    pub const MediumBlue = itc(0x0000CDff);
    pub const Blue = itc(0x0000FFff);
    pub const RoyalBlue = itc(0x4169E1ff);
    pub const SteelBlue = itc(0x4682B4ff);
    pub const DodgerBlue = itc(0x1E90FFff);
    pub const DeepSkyBlue = itc(0x00BFFFff);
    pub const CornflowerBlue = itc(0x6495EDff);
    pub const SkyBlue = itc(0x87CEEBff);
    pub const LightSkyBlue = itc(0x87CEFAff);
    pub const LightSteelBlue = itc(0xB0C4DEff);
    pub const LightBlue = itc(0xADD8E6ff);
    pub const PowderBlue = itc(0xB0E0E6ff);
    pub const Teal = itc(0x008080ff);
    pub const DarkCyan = itc(0x008B8Bff);
    pub const LightSeaGreen = itc(0x20B2AAff);
    pub const CadetBlue = itc(0x5F9EA0ff);
    pub const DarkTurquoise = itc(0x00CED1ff);
    pub const MediumTurquoise = itc(0x48D1CCff);
    pub const Turquoise = itc(0x40E0D0ff);
    pub const Aqua = itc(0x00FFFFff);
    pub const Cyan = itc(0x00FFFFff);
    pub const Aquamarine = itc(0x7FFFD4ff);
    pub const PaleTurquoise = itc(0xAFEEEEff);
    pub const LightCyan = itc(0xE0FFFFff);
    pub const MediumVioletRed = itc(0xC71585ff);
    pub const DeepPink = itc(0xFF1493ff);
    pub const PaleVioletRed = itc(0xDB7093ff);
    pub const HotPink = itc(0xFF69B4ff);
    pub const LightPink = itc(0xFFB6C1ff);
    pub const Pink = itc(0xFFC0CBff);
    pub const DarkRed = itc(0x8B0000ff);
    pub const Red = itc(0xFF0000ff);
    pub const Firebrick = itc(0xB22222ff);
    pub const Crimson = itc(0xDC143Cff);
    pub const IndianRed = itc(0xCD5C5Cff);
    pub const LightCoral = itc(0xF08080ff);
    pub const Salmon = itc(0xFA8072ff);
    pub const DarkSalmon = itc(0xE9967Aff);
    pub const LightSalmon = itc(0xFFA07Aff);
    pub const OrangeRed = itc(0xFF4500ff);
    pub const Tomato = itc(0xFF6347ff);
    pub const DarkOrange = itc(0xFF8C00ff);
    pub const Coral = itc(0xFF7F50ff);
    pub const Orange = itc(0xFFA500ff);
    pub const DarkKhaki = itc(0xBDB76Bff);
    pub const Gold = itc(0xFFD700ff);
    pub const Khaki = itc(0xF0E68Cff);
    pub const PeachPuff = itc(0xFFDAB9ff);
    pub const Yellow = itc(0xFFFF00ff);
    pub const PaleGoldenrod = itc(0xEEE8AAff);
    pub const Moccasin = itc(0xFFE4B5ff);
    pub const PapayaWhip = itc(0xFFEFD5ff);
    pub const LightGoldenrodYellow = itc(0xFAFAD2ff);
    pub const LemonChiffon = itc(0xFFFACDff);
    pub const LightYellow = itc(0xFFFFE0ff);
    pub const Maroon = itc(0x800000ff);
    pub const Brown = itc(0xA52A2Aff);
    pub const SaddleBrown = itc(0x8B4513ff);
    pub const Sienna = itc(0xA0522Dff);
    pub const Chocolate = itc(0xD2691Eff);
    pub const DarkGoldenrod = itc(0xB8860Bff);
    pub const Peru = itc(0xCD853Fff);
    pub const RosyBrown = itc(0xBC8F8Fff);
    pub const Goldenrod = itc(0xDAA520ff);
    pub const SandyBrown = itc(0xF4A460ff);
    pub const Tan = itc(0xD2B48Cff);
    pub const Burlywood = itc(0xDEB887ff);
    pub const Wheat = itc(0xF5DEB3ff);
    pub const NavajoWhite = itc(0xFFDEADff);
    pub const Bisque = itc(0xFFE4C4ff);
    pub const BlanchedAlmond = itc(0xFFEBCDff);
    pub const Cornsilk = itc(0xFFF8DCff);

    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub fn CharColorNew(r: u8, g: u8, b: u8, a: u8) CharColor {
    return .{ .r = r, .g = g, .b = b, .a = a };
}

pub const Hsva = struct {
    h: f32,
    s: f32,
    v: f32,
    a: f32,
};

pub fn colorToHsva(color: CharColor) Hsva {
    const fl = charColorToFloat(color);
    const max = std.math.max3(fl[0], fl[1], fl[2]);
    const min = std.math.min3(fl[0], fl[1], fl[2]);
    const C = max - min;

    const r = fl[0];
    const g = fl[1];
    const b = fl[2];

    const M = 0.001;
    const hue: f32 = 60 * blk: {
        if (@fabs(C) < M) {
            break :blk 0;
        } else if (@fabs(max - r) < M) {
            break :blk @mod((g - b) / C, 6);
        } else if (@fabs(max - g) < M) {
            break :blk ((b - r) / C) + 2;
        } else if (@fabs(max - b) < M) {
            break :blk ((r - g) / C) + 4;
        }
        unreachable;
    };

    const sat: f32 = if (@fabs(max) < M) 0 else C / max;
    return .{ .h = hue, .s = sat, .v = max, .a = fl[3] };
}

pub fn hsvaToColor(hsva: Hsva) CharColor {
    //HSV
    //S is the x axis
    //V is the y axis
    const H = hsva.h;
    const S = hsva.s;
    const V = hsva.v;

    const C = V * S;
    const hp = (@mod(H, 360)) / 60.0;
    const X = C * (1 - @fabs(@mod(hp, 2) - 1));
    const rgb1 = switch (@floatToInt(u32, hp)) {
        0 => za.Vec3.new(C, X, 0),
        1 => za.Vec3.new(X, C, 0),
        2 => za.Vec3.new(0, C, X),
        3 => za.Vec3.new(0, X, C),
        4 => za.Vec3.new(X, 0, C),
        5 => za.Vec3.new(C, 0, X),
        else => unreachable,
    };
    const M = V - C;

    return CharColorNew(
        @floatToInt(u8, (M + rgb1.data[0]) * 255),
        @floatToInt(u8, (M + rgb1.data[1]) * 255),
        @floatToInt(u8, (M + rgb1.data[2]) * 255),
        @floatToInt(u8, hsva.a * 255),
    );
}

pub fn charColorToFloat(col: CharColor) Color {
    return .{
        @intToFloat(f32, col.r) / 255.0,
        @intToFloat(f32, col.g) / 255.0,
        @intToFloat(f32, col.b) / 255.0,
        @intToFloat(f32, col.a) / 255.0,
    };
}

pub const itc = intToColor;

pub fn intToColor(color: u32) CharColor {
    return .{
        .r = @intCast(u8, (color >> 24) & 0xff),
        .g = @intCast(u8, (color >> 16) & 0xff),
        .b = @intCast(u8, (color >> 8) & 0xff),
        .a = @intCast(u8, (color >> 0) & 0xff),
    };
}

pub const IRect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn new(x: i32, y: i32, w: i32, h: i32) @This() {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn toF32(self: @This()) Rect {
        return .{ .x = @intToFloat(f32, self.x), .y = @intToFloat(f32, self.y), .w = @intToFloat(f32, self.w), .h = @intToFloat(f32, self.h) };
    }
};

pub const Padding = struct {
    const Self = @This();
    top: f32,
    bottom: f32,
    left: f32,
    right: f32,

    pub fn new(t: f32, b: f32, l: f32, r: f32) Self {
        return .{ .top = t, .bottom = b, .left = l, .right = r };
    }

    pub fn vertical(self: Self) f32 {
        return self.top + self.bottom;
    }

    pub fn horizontal(self: Self) f32 {
        return self.left + self.right;
    }
};

pub const Rect = struct {
    const Self = @This();

    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn new(x: f32, y: f32, w: f32, h: f32) @This() {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn newV(_pos: Vec2f, dim: Vec2f) @This() {
        return .{ .x = _pos.x, .y = _pos.y, .w = dim.x, .h = dim.y };
    }

    pub fn addV(self: @This(), x: f32, y: f32) @This() {
        return .{ .x = self.x + x, .y = self.y + y, .w = self.w, .h = self.h };
    }

    pub fn addVec(self: @This(), v: Vec2f) @This() {
        return .{ .x = self.x + v.x, .y = self.y + v.y, .w = self.w, .h = self.h };
    }

    pub fn mul(self: Self, scalar: f32) Self {
        return .{ .x = self.x * scalar, .y = self.y * scalar, .w = self.w * scalar, .h = self.h * scalar };
    }

    pub fn inset(self: Self, amount: f32) Self {
        return .{ .x = self.x + amount, .y = self.y + amount, .w = self.w - amount * 2, .h = self.h - amount * 2 };
    }

    //TODO remove in favor of topL()
    pub fn pos(self: Self) Vec2f {
        return .{ .x = self.x, .y = self.y };
    }

    pub fn topL(self: Self) Vec2f {
        return .{ .x = self.x, .y = self.y };
    }

    pub fn topR(self: Self) Vec2f {
        return .{ .x = self.x + self.w, .y = self.y };
    }

    pub fn botL(self: Self) Vec2f {
        return .{ .x = self.x, .y = self.y + self.h };
    }

    pub fn botR(self: Self) Vec2f {
        return .{ .x = self.x + self.w, .y = self.y + self.h };
    }

    pub fn farY(self: Self) f32 {
        return self.y + self.h;
    }

    pub fn farX(self: Self) f32 {
        return self.x + self.w;
    }

    pub fn toAbsRect(self: Self) Rect {
        return Rec(self.x, self.y, self.x + self.w, self.y + self.h);
    }

    //pub fn param(
    //    self: Self,
    //) @This() {
    //    return .{
    //        .x = parseParam(self.x, xop),
    //        .y = parseParam(self.y, yop),
    //        .w = parseParam(self.w, wop),
    //        .h = parseParam(self.h, hop),
    //    };
    //}

    pub fn toIntRect(self: @This(), comptime int_type: type, comptime vec_type: type) vec_type {
        return vec_type{
            .x = @floatToInt(int_type, self.x),
            .y = @floatToInt(int_type, self.y),
            .w = @floatToInt(int_type, self.w),
            .h = @floatToInt(int_type, self.h),
        };
    }

    pub fn swapAxis(self: Self) Self {
        return Rec(self.y, self.x, self.h, self.w);
    }
};

pub const Color = [4]f32;

pub fn createQuadColor(r: Rect, z: f32, color: [4]CharColor) [4]Vertex {
    return [_]Vertex{
        vertex(r.x + r.w, r.y + r.h, z, charColorToFloat(color[2])), //low right
        vertex(r.x + r.w, r.y, z, charColorToFloat(color[3])), //up right
        vertex(r.x, r.y, z, charColorToFloat(color[0])), //up left
        vertex(r.x, r.y + r.h, z, charColorToFloat(color[1])), //low left
    };
}

pub fn createQuad(r: Rect, z: f32, color: Color) [4]Vertex {
    return [_]Vertex{
        vertex(r.x + r.w, r.y + r.h, z, color),
        vertex(r.x + r.w, r.y, z, color),
        vertex(r.x, r.y, z, color),
        vertex(r.x, r.y + r.h, z, color),
    };
}

pub fn normalizeTexRect(tr: Rect, tx_w: i32, tx_h: i32) Rect {
    const tw = @intToFloat(f32, tx_w);
    const th = @intToFloat(f32, tx_h);
    return .{
        .x = tr.x / tw,
        .y = tr.y / th,
        .w = tr.w / tw,
        .h = tr.h / th,
    };
}

pub fn cube(px: f32, py: f32, pz: f32, sx: f32, sy: f32, sz: f32, tr: Rect, tx_w: u32, tx_h: u32, colorsopt: ?[]const CharColor) [24]VertexTextured {
    const colors = if (colorsopt) |cc| cc else &[6]CharColor{
        itc(0x888888ff), //Front
        itc(0x888888ff), //Back
        itc(0x666666ff), //Bottom
        itc(0xffffffff), //Top
        itc(0xaaaaaaff),
        itc(0xaaaaaaff),
    };
    const un = normalizeTexRect(tr, @intCast(i32, tx_w), @intCast(i32, tx_h));
    return [_]VertexTextured{
        // zig fmt: off
        // front
        vertexTextured(px + sx, py + sy, pz, un.x + un.w, un.y + un.h, charColorToFloat(colors[0])), //0
        vertexTextured(px + sx, py     , pz, un.x + un.w, un.y       , charColorToFloat(colors[0])), //1
        vertexTextured(px     , py     , pz, un.x       , un.y       , charColorToFloat(colors[0])), //2
        vertexTextured(px     , py + sy, pz, un.x       , un.y + un.h, charColorToFloat(colors[0])), //3

        // back
        vertexTextured(px     , py + sy, pz + sz, un.x       , un.y + un.h, charColorToFloat(colors[1])), //3
        vertexTextured(px     , py     , pz + sz, un.x       , un.y       , charColorToFloat(colors[1])), //2
        vertexTextured(px + sx, py     , pz + sz, un.x + un.w, un.y       , charColorToFloat(colors[1])), //1
        vertexTextured(px + sx, py + sy, pz + sz, un.x + un.w, un.y + un.h, charColorToFloat(colors[1])), //0


        vertexTextured(px + sx, py, pz,      un.x+un.w,un.y + un.h, charColorToFloat(colors[2])),
        vertexTextured(px + sx, py, pz + sz, un.x+un.w,un.y, charColorToFloat(colors[2])),
        vertexTextured(px     , py, pz + sz, un.x,un.y, charColorToFloat(colors[2])),
        vertexTextured(px     , py, pz     , un.x,un.y + un.h, charColorToFloat(colors[2])),

        vertexTextured(px     , py + sy, pz     , un.x,un.y + un.h, charColorToFloat(colors[3])),
        vertexTextured(px     , py + sy, pz + sz, un.x,un.y, charColorToFloat(colors[3])),
        vertexTextured(px + sx, py + sy, pz + sz, un.x + un.w,un.y, charColorToFloat(colors[3])),
        vertexTextured(px + sx, py + sy, pz, un.x + un.w,   un.y + un.h , charColorToFloat(colors[3])),

        vertexTextured(px, py + sy, pz, un.x + un.w,un.y + un.h,charColorToFloat(colors[4])),
        vertexTextured(px, py , pz, un.x + un.w,un.y,charColorToFloat(colors[4])),
        vertexTextured(px, py , pz + sz, un.x,un.y,charColorToFloat(colors[4])),
        vertexTextured(px, py + sy , pz + sz, un.x,un.y + un.h,charColorToFloat(colors[4])),

        vertexTextured(px + sx, py + sy , pz + sz, un.x,un.y + un.h,charColorToFloat(colors[5])),
        vertexTextured(px + sx, py , pz + sz, un.x,un.y,charColorToFloat(colors[5])),
        vertexTextured(px + sx, py , pz, un.x + un.w,un.y,charColorToFloat(colors[5])),
        vertexTextured(px + sx, py + sy, pz, un.x + un.w,un.y + un.h,charColorToFloat(colors[5])),

        // zig fmt: on

    };

}

pub fn genCubeIndicies(index: u32) [36]u32 {
    return [_]u32{
        index + 0,
        index + 1,
        index + 3,
        index + 1,
        index + 2,
        index + 3,

        index + 4,
        index + 5,
        index + 7,
        index + 5,
        index + 6,
        index + 7,

        index + 8,
        index + 9,
        index + 11,
        index + 9,
        index + 10,
        index + 11,

        index + 12,
        index + 13,
        index + 15,
        index + 13,
        index + 14,
        index + 15,

        index + 16,
        index + 17,
        index + 19,
        index + 17,
        index + 18,
        index + 19,

        index + 20,
        index + 21,
        index + 23,
        index + 21,
        index + 22,
        index + 23,
    };
}

pub fn createQuadTextured(r: Rect, z: f32, tr: Rect, tx_w: i32, tx_h: i32, color: Color) [4]VertexTextured {
    const un = normalizeTexRect(tr, tx_w, tx_h);
    return [_]VertexTextured{
        // zig fmt: off
        vertexTextured(r.x + r.w, r.y + r.h, z, un.x + un.w, un.y + un.h, color), //0
        vertexTextured(r.x + r.w, r.y      , z, un.x + un.w, un.y       , color), //1
        vertexTextured(r.x      , r.y      , z, un.x       , un.y       , color), //2
        vertexTextured(r.x      , r.y + r.h, z, un.x       , un.y + un.h, color), //3
        // zig fmt: on
                                                                              };
}

pub const RenderTexture = struct {
    const Self = @This();
    fb: c_uint,
    depth_rb: c_uint,
    texture: Texture,
    w:i32,
    h:i32,

    pub fn init(w: i32, h: i32) !Self {
        var ret = Self{
            .w = w,
            .h = h,
            .fb = 0,
            .depth_rb = 0,
            .texture = Texture.fromArray(null, w, h, .{.min_filter = c.GL_LINEAR, .mag_filter = c.GL_LINEAR,.generate_mipmaps = false }),
        };
        c.glGenFramebuffers(1, &ret.fb);
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, ret.fb);

        c.glGenRenderbuffers(1, &ret.depth_rb);
        c.glBindRenderbuffer(c.GL_RENDERBUFFER, ret.depth_rb);
        c.glRenderbufferStorage(c.GL_RENDERBUFFER, c.GL_DEPTH_COMPONENT, w, h);
        c.glFramebufferRenderbuffer(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_RENDERBUFFER, ret.depth_rb);
        c.glFramebufferTexture(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, ret.texture.id, 0);
        const draw_buffers = [_]c.GLenum{c.GL_COLOR_ATTACHMENT0};
        c.glDrawBuffers(draw_buffers.len, &draw_buffers[0]);

        if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) return error.framebufferCreateFailed;

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        c.glBindRenderbuffer(c.GL_RENDERBUFFER, 0);

        return ret;
    }

    pub fn setSize(self: *Self, w:i32, h:i32)!void{
                    if (w != self.w or h != self.h) {
                        self.deinit();
                        self.* = try RenderTexture.init(w, h);
                    }
    }

    pub fn deinit(self: *Self) void{
        c.glDeleteFramebuffers(1, &self.fb);
        c.glDeleteRenderbuffers(1, &self.depth_rb);
        c.glDeleteTextures(1, &self.texture.id);
    }

    pub fn bind(self: *Self, clear:bool)void{
        c.glBindFramebuffer(c.GL_FRAMEBUFFER,self.fb);
        c.glViewport(0,0,self.w,self.h);
        if(clear)
            c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glClear(c.GL_DEPTH_BUFFER_BIT);
    }
};

pub const Texture = struct {
    id: glID,
    w: i32,
    h: i32,

    pub fn rect(t:Texture)Rect{
        return Rec(0,0,t.w, t.h);
    }

    pub fn aspectRatio(t:Texture)f32{
        return @intToFloat(f32, t.w) / @intToFloat(f32, t.h);
    }

    pub const Options = struct {
        internal_format: c.GLint = c.GL_RGBA,
        pixel_format: c.GLenum = c.GL_RGBA,
        pixel_type: c.GLenum = c.GL_UNSIGNED_BYTE,
        pixel_store_alignment: c.GLint = 4,
        target: c.GLenum = c.GL_TEXTURE_2D,

        wrap_u: c.GLint = c.GL_REPEAT,
        wrap_v: c.GLint = c.GL_REPEAT,

        generate_mipmaps:bool = true,
        min_filter: c.GLint = c.GL_LINEAR_MIPMAP_LINEAR,
        mag_filter: c.GLint = c.GL_LINEAR,
        border_color: [4]f32 = .{0,0,0,1.0},

    };
    //TODO function for texture destruction

    //TODO rename this function to create or new or something
    pub fn fromArray(bitmap: ?[]const u8, w: i32, h:i32, o: Options) Texture {
        var tex_id: glID = 0;
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, o.pixel_store_alignment);
        c.glGenTextures(1, &tex_id);
        c.glBindTexture(o.target, tex_id);
        c.glTexImage2D(
            o.target,
            0,//Level of detail number
            o.internal_format,
            @intCast(i32, w),
            @intCast(i32, h),
            0,//khronos.org: this value must be 0
            o.pixel_format,
            o.pixel_type,
            if(bitmap)|bmp| &bmp[0] else null,
        );
        if(o.generate_mipmaps)
            c.glGenerateMipmap(o.target);

        c.glTexParameteri(o.target, c.GL_TEXTURE_WRAP_S, o.wrap_u);
        c.glTexParameteri(o.target, c.GL_TEXTURE_WRAP_T, o.wrap_v);

        //c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST_MIPMAP_NEAREST);
        c.glTexParameteri(o.target, c.GL_TEXTURE_MIN_FILTER, o.min_filter);
        c.glTexParameteri(o.target, c.GL_TEXTURE_MAG_FILTER, o.mag_filter);

        c.glTexParameterfv(o.target, c.GL_TEXTURE_BORDER_COLOR, &o.border_color);


        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        c.glBlendEquation(c.GL_FUNC_ADD);

        c.glBindTexture(c.GL_TEXTURE_2D, 0);
        return Texture{ .w = w, .h = h, .id = tex_id };
    }

    pub fn fromImage(relative_file_name:[]const u8, alloc: std.mem.Allocator,opts:Options  )!Texture{
        const bmp = try loadPngBitmap(relative_file_name, alloc);
        defer bmp.data.deinit();
        return fromArray(bmp.data.items,@intCast(i32,bmp.w), @intCast(i32,bmp.h) ,opts);
    }
};


//TODO Support multiple non scaled sizes
//Layouting
//  Word wrap
//  line beak
//
//Cool unicode selection tool:
//  render pages of unicode points using freetype directly to opengl texture for rendering
//  to allow me to select what codepoints I want to include in the backed bitmap
//
//On the fly atlas generation,
//When encountering a unbaked glyph, display a blank and in a second thread? generate a new texture with it baked in
// zig fmt: on
pub const Font = struct {
    //TODO document all the glyph fields
    pub const Glyph = struct {
        offset_x: f32 = 0,
        offset_y: f32 = 0,
        advance_x: f32 = 0,
        tr: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        width: f32 = 0,
        height: f32 = 0,
        i: u21 = 0,
    };

    ///Used to specify what codepoints are to be loaded
    pub const CharMapEntry = union(enum) {
        unicode: u21, //A single codepoint
        list: []const u21,
        range: [2]u21, //A range of codepoints (inclusive)

        //TODO how does comptime memory work? Is returning a comptime "stack" buffer ub
    };

    ///Define common character sets
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

    font_size: f32, //Native size in points

    //TODO this should be a hashmap
    glyph_set: SparseSet(Glyph, u21),

    //The units for all of these is pixels
    ascent: f32, //Farthest the font ascends above baseline
    descent: f32, //Farthest the font descends below baseline
    line_gap: f32, //Distance between one rows descent and next rows ascent
    //to get next baseline: ascent - descent + line_gap
    max_advance: f32,

    texture: Texture,

    dpi: f32,

    const Self = @This();
    //const START_CHAR: usize = 32;
    const padding: usize = 10;

    //Add zig errors for freetype errors along with correct error defers so init() catch err can be handled correctly
    fn freetypeLogErr(stream: anytype, error_code: c_int) !void {
        if (error_code == 0)
            return;

        _ = c.FT_Err_Cannot_Open_Resource;
        var found = false;
        inline for (c.ft_errors) |err| {
            if (err.err_code == error_code) {
                found = true;
                if (err.err_msg) |msg|
                    stream.print("Freetype: Error {s}\n", .{msg}) catch return;

                break;
            }
        }

        if (!found)
            stream.print("Freetype: Error code not found in table: {d}\n", .{error_code}) catch return;

        return error.freetype;
    }

    //TODO System for loading unicode chars on the fly
    //This system would have to keep freetype or STBTT loaded during the lifetime of a Font. When a glyph isn't found attempt to load
    //Baking glyphs in a fixed grid rather than rect packing simplifies this
    //Store a list of glyphs unavailable in the current font to prevent repeated requests to bake a glyph
    //
    //
    //TODO pass both dpix and dpiy, and specify argument units for more clarity.
    //Better init functions, more default parameters
    //Allow logging and debug to be disabled
    pub fn init(filename: []const u8, alloc: std.mem.Allocator, point_size: f32, dpi: u32, codepoints_to_load: []const CharMapEntry, opt_pack_factor: ?f32) !Self {
        const codepoints = blk: {
            //TODO should we ensure no duplicates?
            var codepoint_list = std.ArrayList(Glyph).init(alloc);
            try codepoint_list.append(.{ .i = std.unicode.replacement_character });
            for (codepoints_to_load) |codepoint| {
                switch (codepoint) {
                    .list => |list| {
                        for (list) |cp| {
                            try codepoint_list.append(.{ .i = cp });
                        }
                    },
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
        const dump_bitmaps = false;

        const dir = std.fs.cwd();
        dir.makeDir("debug") catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const font_log = try dir.createFile("debug/fontgen.log", .{ .truncate = true });
        const log = font_log.writer();
        defer font_log.close();
        try log.print("zig: Init font with arguments:\nfilename: \"{s}\"\npoint_size: {d}\ndpi: {d}\n", .{ filename, point_size, dpi });

        var result = Font{
            .dpi = @intToFloat(f32, dpi),
            .max_advance = 0,
            .glyph_set = try (SparseSet(Glyph, u21).fromOwnedDenseSlice(alloc, codepoints)),
            .font_size = point_size,
            .texture = .{ .id = 0, .w = 0, .h = 0 },
            .ascent = 0,
            .descent = 0,
            .line_gap = 0,
        };
        errdefer result.glyph_set.deinit();

        //TODO switch to using a grid rather than rect packing
        const pack_factor = opt_pack_factor orelse 1.3;

        const stderr = std.io.getStdErr().writer();

        var ftlib: c.FT_Library = undefined;
        try freetypeLogErr(stderr, c.FT_Init_FreeType(&ftlib));

        var face: c.FT_Face = undefined;
        {
            var strbuf = std.ArrayList(u8).init(alloc);
            defer strbuf.deinit();

            try strbuf.appendSlice(filename);
            try strbuf.append(0);

            //FT_New_Face loads font file from filepathname
            //the face pointer should be destroyed with FT_Done_Face()
            try freetypeLogErr(stderr, c.FT_New_Face(ftlib, @ptrCast([*:0]const u8, strbuf.items), 0, &face));

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
        try freetypeLogErr(stderr, c.FT_Library_SetLcdFilter(ftlib, c.FT_LCD_FILTER_DEFAULT));

        try freetypeLogErr(
            stderr,
            c.FT_Set_Char_Size(
                face,
                0,
                @floatToInt(c_int, point_size) * 64, //expects a size in 1/64 of points, font_size is in points
                dpi,
                dpi,
            ),
        );

        { //Logs all the glyphs in this font file
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
        result.line_gap = @intToFloat(f32, fr.size.*.metrics.height) / 64;

        try log.print("Freetype face: ascender:  {d}px\n", .{result.ascent});
        try log.print("Freetype face: descender:  {d}px\n", .{result.descent});
        try log.print("Freetype face: line_gap:  {d}px\n", .{result.line_gap});

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
        if (dump_bitmaps) {
            dir.makeDir("debug/bitmaps") catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
        }

        var timer = try std.time.Timer.start();
        for (result.glyph_set.dense.items) |*codepoint| {
            const glyph_i = c.FT_Get_Char_Index(face, codepoint.i);
            if (glyph_i == 0) {
                std.debug.print("Undefined char index: {d} {x}\n", .{ codepoint.i, codepoint.i });
                continue;
            }

            try freetypeLogErr(stderr, c.FT_Load_Glyph(face, glyph_i, c.FT_LOAD_DEFAULT));
            try freetypeLogErr(stderr, c.FT_Render_Glyph(face.*.glyph, c.FT_RENDER_MODE_NORMAL));
            //freetypeLogErr(stderr, c.FT_Render_Glyph(face.*.glyph, c.FT_RENDER_MODE_LCD));

            const bitmap = &(face.*.glyph.*.bitmap);

            if (bitmap.width != 0 and bitmap.rows != 0) {
                if (dump_bitmaps) {
                    var buf: [255]u8 = undefined;
                    var fbs = std.io.FixedBufferStream([]u8){ .buffer = &buf, .pos = 0 };
                    try fbs.writer().print("debug/bitmaps/{d}.bmp", .{glyph_i});
                    try fbs.writer().writeByte(0);
                    _ = c.stbi_write_bmp(
                        @ptrCast([*c]const u8, fbs.getWritten()),
                        @intCast(c_int, bitmap.width),
                        @intCast(c_int, bitmap.rows),
                        1,
                        @ptrCast([*c]u8, bitmap.buffer[0 .. bitmap.rows * bitmap.width]),
                    );
                }
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
        try log.print("Rendered {d} glyphs in {d} ms, {d} ms avg\n", .{ result.glyph_set.dense.items.len, @intToFloat(f32, elapsed) / std.time.ns_per_ms, @intToFloat(f32, elapsed) / std.time.ns_per_ms / @intToFloat(f32, result.glyph_set.dense.items.len) });
        {
            var num_pixels: usize = 0;
            for (packing_rects.items) |r| {
                num_pixels += (@intCast(usize, r.w) * @intCast(usize, r.h));
            }
            result.texture.w = @floatToInt(i32, @sqrt(@intToFloat(f32, num_pixels) * pack_factor));
            result.texture.h = @floatToInt(i32, @sqrt(@intToFloat(f32, num_pixels) * pack_factor));
            try log.print("Texture size: {d} x {d}\n", .{ result.texture.w, result.texture.h });

            var nodes = std.ArrayList(c.stbrp_node).init(alloc);
            defer nodes.deinit();
            try nodes.appendNTimes(undefined, @intCast(u32, result.texture.w) + 200); //TODO MAGICNUM
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
                return error.needLargerPackingFactor;

            {
                var texture_bitmap = std.ArrayList(u8).init(alloc);
                defer texture_bitmap.deinit();
                try texture_bitmap.appendNTimes(0, @intCast(usize, result.texture.w * result.texture.h));

                for (packing_rects.items) |rect, i| {
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
                                    texture_bitmap.items[(@intCast(u32, result.texture.w) * (row + @intCast(usize, rect.y))) + col + @intCast(usize, rect.x)] = dat;
                                } else {
                                    texture_bitmap.items[(@intCast(u32, result.texture.h) * (row + @intCast(usize, rect.y))) + col + @intCast(usize, rect.x)] = 0;
                                }
                            }
                            col = 0;
                        }
                    }
                }

                if (dump_bitmaps)
                    writeBmp("debug/freetype.bmp", @intCast(c_int, result.texture.w), @intCast(c_int, result.texture.h), 1, texture_bitmap.items);
                result.texture = Texture.fromArray(texture_bitmap.items, result.texture.w, result.texture.h, .{
                    .pixel_store_alignment = 1,
                    .internal_format = c.GL_RED,
                    .pixel_format = c.GL_RED,
                    .min_filter = c.GL_LINEAR,
                    //TODO provide options for these params
                    .mag_filter = c.GL_LINEAR,
                });
                //result.texture.id = GL.grayscaleTexture(result.texture.w, result.texture.h, texture_bitmap.items);
            }
        }

        return result;
    }

    pub fn nearestGlyphX(self: *Self, string: []const u8, size_px: f32, rel_coord: Vec2f) ?usize {
        const scale = (size_px / self.dpi * 72) / self.font_size;

        var x_bound: f32 = 0;
        var bounds = Vec2f{ .x = 0, .y = 0 };

        var it = std.unicode.Utf8Iterator{ .bytes = string, .i = 0 };
        var char = it.nextCodepoint();
        while (char != null) : (char = it.nextCodepoint()) {
            const glyph = self.glyph_set.get(char.?) catch |err|
                switch (err) {
                error.invalidIndex => self.glyph_set.get(std.unicode.replacement_character) catch unreachable,
            };
            const xw = glyph.advance_x * scale;
            const yw = self.line_gap * scale;

            switch (char.?) {
                '\n' => {
                    bounds.y += yw;
                    if (x_bound > bounds.x)
                        bounds.x = x_bound;
                    x_bound = 0;
                },
                else => {
                    const x = rel_coord.x;
                    const y = rel_coord.y;
                    if (x < x_bound + xw and x > x_bound and y < bounds.y + yw and y > bounds.y) {
                        return it.i;
                    }
                },
            }

            x_bound += xw;
        }

        if (x_bound > bounds.x)
            bounds.x = x_bound;

        return null;
    }

    pub fn textBounds(self: *Self, string: []const u8, size_px: f32) Vec2f {
        const scale = (size_px / self.dpi * 72) / self.font_size;

        var x_bound: f32 = 0;
        var bounds = Vec2f{ .x = 0, .y = self.line_gap * scale };

        var it = std.unicode.Utf8Iterator{ .bytes = string, .i = 0 };
        var char = it.nextCodepoint();
        while (char != null) : (char = it.nextCodepoint()) {
            switch (char.?) {
                '\n' => {
                    bounds.y += self.line_gap * scale;
                    if (x_bound > bounds.x)
                        bounds.x = x_bound;
                    x_bound = 0;
                },
                else => {},
            }

            const glyph = self.glyph_set.get(char.?) catch |err|
                switch (err) {
                error.invalidIndex => self.glyph_set.get(std.unicode.replacement_character) catch unreachable,
            };

            x_bound += (glyph.advance_x) * scale;
        }

        if (x_bound > bounds.x)
            bounds.x = x_bound;

        return bounds;
    }

    pub fn deinit(self: *Self) void {
        self.glyph_set.deinit();
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
    alloc: std.mem.Allocator,

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
    call_count: usize = 0,

    draw_time: u64 = 1000,
    memcpy_time: u64 = 0,
    last_memcpy_time: u64 = 1000,

    dpi: f32 = 0,

    screen_bounds: IRect,

    pub fn init(alloc: std.mem.Allocator, dpi: f32) !Self {
        var ret: Self = .{
            .screen_bounds = IRect.new(0, 0, 0, 0),
            .dpi = dpi,
            .batches = std.ArrayList(Batch).init(alloc),
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

    pub fn beginDraw(self: *Self, screen_w: i32, screen_h: i32, bg: CharColor, clear_color: bool) !void {
        self.screen_bounds = IRect.new(0, 0, screen_w, screen_h);
        self.call_count = 0;
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
        if (clear_color)
            c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glClear(c.GL_DEPTH_BUFFER_BIT);
        self.z_st = 0;
        for (self.batches.items) |*batch| {
            try batch.reset();
        }
    }

    //pub fn beginCamera(self: *Self, )

    pub fn setViewport(self: *Self, v: Rect) void {
        _ = self;
        c.glViewport(
            @floatToInt(i32, v.x),
            @floatToInt(i32, v.y),
            @floatToInt(i32, v.w),
            @floatToInt(i32, v.h),
        );
    }

    pub fn flush(self: *Self, offset: Vec2f, custom_camera: ?Rect) !void {
        const camera_bounds = if (custom_camera) |cc| cc else self.screen_bounds.toF32();

        for (self.batches.items) |*batch| {
            switch (batch.*) {
                .TriTex => {},
                else => batch.draw(camera_bounds, offset, self.colored_tri_shader, self.tex_shad),
            }
        }
        for (self.batches.items) |*batch| {
            switch (batch.*) {
                .TriTex => batch.draw(camera_bounds, offset, self.colored_tri_shader, self.tex_shad),
                else => {},
            }
        }
        self.call_count += 1;

        for (self.batches.items) |*batch| {
            try batch.reset();
            //self.call_count += 1;
        }
    }

    pub fn endDraw(self: *Self, custom_camera: ?Rect) void {
        var draw_time = std.time.Timer.start() catch null;
        //const camera_bounds = self.screen_bounds.toF32();
        const camera_bounds = if (custom_camera) |cc| cc else self.screen_bounds.toF32();

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
        //self.call_count += self.batches.items.len;
        self.call_count += 1;

        if (draw_time) |*dt|
            self.draw_time = dt.read();

        self.last_frame_time = self.frame_timer.read();
        self.lftavg.insert(1.0 / (std.time.ns_per_us / @intToFloat(f32, self.last_frame_time)));
        self.last_memcpy_time = self.memcpy_time;
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

    pub fn ptRect(self: *Self, x: f32, y: f32, w: f32, h: f32, col: CharColor) void {
        const fac = self.dpi / 72.0;
        //const fac = pxToPt(self.dpi, 1);
        self.dRect(fac * x, fac * y, fac * w, fac * h, col);
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

    pub fn drawRectCol(self: *Self, r: Rect, col: [4]CharColor) void {
        const batch = self.getBatch(.{ .mode = .triangles, .texture = 0, .shader = self.colored_tri_shader }) catch {
            logErr("batch");
            return;
        };

        const b = &batch.Tri;
        const index = b.vertices.items.len;

        b.vertices.appendSlice(&createQuadColor(r, self.z_st, col)) catch {
            logErr("vert");
            return;
        };
        b.indicies.appendSlice(&genQuadIndices(@intCast(u32, index))) catch {
            logErr("indicies");
            return;
        };
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

        var i: u32 = 0;
        for (str) |char| {
            if (char == ' ') {
                i += 1;
                continue;
            }

            const ind = font.translation_table[std.ascii.toUpper(char)];
            const fi = @intToFloat(f32, i);
            try b.indicies.appendSlice(&genQuadIndices(@intCast(u32, b.vertices.items.len)));
            try b.vertices.appendSlice(&createQuadTextured(Rec(
                x + fi * h,
                y,
                h,
                h,
            ), self.z_st, font.sts.getTexRec(if (ind == 127) continue else ind), font.texture.w, font.texture.h, charColorToFloat(col)));
            i += 1;
        }

        self.z_st += 0.1;
    }

    pub fn drawTextFmt(self: *Self, x: f32, y: f32, comptime fmt: []const u8, args: anytype, font: *Font, size: f32, col: CharColor) void {
        var buf: [256]u8 = undefined;
        var fbs = std.io.FixedBufferStream([]u8){ .pos = 0, .buffer = &buf };
        fbs.writer().print(fmt, args) catch unreachable;
        const slice = fbs.getWritten();
        self.drawText(x, y, slice, font, size, col);
    }

    //TODO Split this off into a function that draws a single unicode codepoint
    //TODO have a function that takes pts and one that takes pixels,(this one takes pixels)
    pub fn drawText(self: *Self, x: f32, y: f32, str: []const u8, font: *Font, size: f32, col: CharColor) void {
        //TODO investigae index ob when nothing happens in a drawcall
        //const SF = size / font.font_size;
        //const SF = size / font.line_gap;
        const SF = (size / self.dpi * 72) / font.font_size;
        //const fac = self.dpi / 72;
        const fac = 1;

        const batch = (self.getBatch(.{ .mode = .triangles, .texture = font.texture.id, .shader = self.font_shad }) catch unreachable);
        const b = &batch.TriTex;

        b.vertices.ensureUnusedCapacity(str.len * 4) catch unreachable;
        b.indicies.ensureUnusedCapacity(str.len * 6) catch unreachable;

        var it = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };

        var vx = x * fac;
        var vy = y * fac + ((font.ascent + font.descent) * SF);
        var cho = it.nextCodepoint();
        while (cho != null) : (cho = it.nextCodepoint()) {
            const ch = cho orelse unreachable;
            //for (str) |ch| {
            if (ch == '\n') {
                //vy += (font.ascent - font.descent + font.line_gap) * SF * font.scale_factor;
                vy += font.line_gap * SF;
                vx = x * fac;
                continue;
            }

            //if (ch < Font.START_CHAR)
            //continue;
            //const g_i = ch - Font.START_CHAR;
            //const g = font.glyphs.items[g_i];
            const g = font.glyph_set.get(ch) catch |err|
                switch (err) {
                error.invalidIndex => font.glyph_set.get(std.unicode.replacement_character) catch unreachable,
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

pub const NewTri = struct {
    const Self = @This();
    const shader_test_frag = @embedFile("shader/colorquad.frag");
    const shader_test_vert = @embedFile("shader/newtri.vert");
    pub const Vert = packed struct {
        pos: Vec2f,
        z: u16,
        color: u32,
    };

    vertices: std.ArrayList(Vert),
    indicies: std.ArrayList(u32),
    shader: c_uint,

    vao: c_uint,
    vbo: c_uint,
    ebo: c_uint,

    pub fn init(alloc: std.mem.Allocator) @This() {
        const Vertu = Vert;
        var ret = Self{
            .vertices = std.ArrayList(Vertu).init(alloc),
            .indicies = std.ArrayList(u32).init(alloc),
            .shader = Shader.simpleShader(shader_test_vert, shader_test_frag),
            .vao = 0,
            .vbo = 0,
            .ebo = 0,
        };

        c.glGenVertexArrays(1, &ret.vao);
        c.glGenBuffers(1, &ret.vbo);
        c.glGenBuffers(1, &ret.ebo);

        GL.generateVertexAttributes(ret.vao, ret.vbo, Vertu);
        return ret;
    }

    pub fn deinit(self: *Self) void {
        self.vertices.deinit();
        self.indicies.deinit();
    }

    pub fn reset(self: *Self) !void {
        try self.vertices.resize(0);
        try self.indicies.resize(0);
    }

    pub fn quad(self: *Self, r: Rect, z: u16) !void {
        const color = 0xffffffff;
        try self.indicies.appendSlice(&genQuadIndices(@intCast(u32, self.vertices.items.len)));
        try self.vertices.appendSlice(&.{
            Vert{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .color = color },
            Vert{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .color = color },
            Vert{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .color = color },
            Vert{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .color = color },
        });
    }

    pub fn draw(b: *Self, screenw: i32, screenh: i32) void {
        const view = za.orthographic(0, @intToFloat(f32, screenw), @intToFloat(f32, screenh), 0, -100000, 1);

        //c.glViewport(0, 0, screenw, screenh);
        const model = za.Mat4.identity();
        c.glUseProgram(b.shader);
        c.glBindVertexArray(b.vao);
        GL.bufferData(c.GL_ARRAY_BUFFER, b.vbo, Vert, b.vertices.items);
        GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, b.ebo, u32, b.indicies.items);

        GL.passUniform(b.shader, "view", view);
        GL.passUniform(b.shader, "model", model);

        c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, b.indicies.items.len), c.GL_UNSIGNED_INT, null);
        c.glBindVertexArray(0);
    }
};

pub const Cubes = struct {
    const Self = @This();
    vertices: std.ArrayList(VertexTextured),
    indicies: std.ArrayList(u32),

    shader: glID,
    texture: glID,
    vao: c_uint = undefined,
    vbo: c_uint = undefined,
    ebo: c_uint = undefined,

    pub fn setData(self: *Self) void {
        c.glBindVertexArray(self.vao);
        GL.bufferData(c.GL_ARRAY_BUFFER, self.vbo, VertexTextured, self.vertices.items);
        GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, self.ebo, u32, self.indicies.items);
    }

    pub fn draw(b: *Self, screenw: i32, screenh: i32, view: za.Mat4) void {
        //const view = za.orthographic(0, @intToFloat(f32, screenw), @intToFloat(f32, screenh), 0, -100000, 1).translate(za.Vec3.new(0, 0, 0));

        c.glViewport(0, 0, screenw, screenh);
        const model = za.Mat4.identity();
        c.glUseProgram(b.shader);
        c.glBindVertexArray(b.vao);

        c.glBindTexture(c.GL_TEXTURE_2D, b.texture);

        GL.passUniform(b.shader, "view", view);
        GL.passUniform(b.shader, "model", model);

        c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, b.indicies.items.len), c.GL_UNSIGNED_INT, null);
    }

    pub fn init(alloc: std.mem.Allocator, texture: glID, shader: glID) @This() {
        var ret = Self{
            .vertices = std.ArrayList(VertexTextured).init(alloc),
            .indicies = std.ArrayList(u32).init(alloc),
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

    pub fn init(alloc: std.mem.Allocator, texture: glID, shader: glID) @This() {
        var ret = Self{
            .vertices = std.ArrayList(VertexTextured).init(alloc),
            .indicies = std.ArrayList(u32).init(alloc),
            .texture = texture,
            .shader = shader,
        };

        c.glGenVertexArrays(1, &ret.vao);
        c.glGenBuffers(1, &ret.vbo);
        c.glGenBuffers(1, &ret.ebo);

        GL.floatVertexAttrib(ret.vao, ret.vbo, 0, 3, VertexTextured, "x"); //XYZ
        GL.floatVertexAttrib(ret.vao, ret.vbo, 1, 4, VertexTextured, "r"); //RGBA
        GL.floatVertexAttrib(ret.vao, ret.vbo, 2, 2, VertexTextured, "u"); //RGBA

        //c.glBindVertexArray(ret.vao);
        //GL.bufferData(c.GL_ARRAY_BUFFER, ret.vbo, VertexTextured, ret.vertices.items);
        //GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, ret.ebo, u32, ret.indicies.items);
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

    pub fn init(alloc: std.mem.Allocator, shader: glID) @This() {
        var ret = Self{
            .vertices = std.ArrayList(Vertex).init(alloc),
            .indicies = std.ArrayList(u32).init(alloc),
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

    pub fn init(alloc: std.mem.Allocator, shader: glID) @This() {
        var ret = Self{ .vertices = std.ArrayList(Vertex).init(alloc), .shader = shader };
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
        const count = switch (self.*) {
            .Tri => |*b| b.vertices.items.len,
            .TriTex => |*b| b.vertices.items.len,
            .Line => |*b| b.vertices.items.len,
        };
        if (count == 0) return;
        const view = za.orthographic(
            view_bounds.x,
            view_bounds.w,
            view_bounds.h,
            view_bounds.y,
            -100000,
            1,
        );
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

                GL.passUniform(texture_shader, "view", view);
                GL.passUniform(texture_shader, "model", model);

                c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, b.indicies.items.len), c.GL_UNSIGNED_INT, null);
            },
            .Line => |*b| {
                c.glUseProgram(shader_program);
                c.glBindVertexArray(b.vao);
                GL.bufferData(c.GL_ARRAY_BUFFER, b.vbo, Vertex, b.vertices.items);

                GL.passUniform(texture_shader, "view", view);

                //c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, b.indicies.items.len), c.GL_UNSIGNED_INT, null);
                c.glDrawArrays(c.GL_LINES, 0, @intCast(c_int, b.vertices.items.len));
            },
            //else => {
            //    std.debug.print("Batch draw not implemented!\n", .{});
            //},
        }
    }
};

pub fn parseJson(comptime T: type, slice: []const u8, parseOptions: std.json.ParseOptions) !struct {
    data: T,
    opts: std.json.ParseOptions,

    pub fn parseFree(self: @This()) void {
        std.json.parseFree(T, self.data, self.opts);
    }
} {
    var ts = std.json.TokenStream.init(slice);
    return .{
        .data = try std.json.parse(T, &ts, parseOptions),
        .opts = parseOptions,
    };
}

pub const BindType = [2][]const u8;
pub const BindList = []const BindType;

//Takes a list of bindings{"name", "key_name"} and generates an enum
//can be used with BindingMap and a switch() to map key input events to actions
//
pub fn GenerateBindingEnum(comptime map: BindList) type {
    const TypeInfo = std.builtin.Type;
    var fields: [map.len + 1]TypeInfo.EnumField = undefined;

    inline for (map) |bind, b_i| {
        fields[b_i] = .{ .name = bind[0], .value = b_i };
    }
    fields[map.len] = .{ .name = "no_action", .value = map.len };
    return @Type(TypeInfo{ .Enum = .{
        .layout = .Auto,
        .fields = fields[0..],
        .tag_type = std.math.IntFittingRange(0, map.len),
        .decls = &.{},
        .is_exhaustive = true,
    } });
}

//var testmap = graph.Bind(&.{.{ "my_key_binding", "a" }}).init();
pub fn Bind(comptime map: BindList) type {
    return struct {
        const bind_enum = GenerateBindingEnum(map);

        scancode_table: [@enumToInt(keycodes.Scancode.ODES)]bind_enum,
        bind_table: [map.len]keycodes.Scancode,

        pub fn init() @This() {
            var ret: @This() = undefined;

            for (ret.scancode_table) |*item|
                item.* = .no_action;

            for (map) |bind, i| {
                var buffer: [256]u8 = undefined;
                //if (bind.len >= buffer.len)
                //    @compileError("Keybinding name to long");

                std.mem.copy(u8, buffer[0..], bind[1]);
                buffer[bind[1].len] = 0;

                const sc = c.SDL_GetScancodeFromName(&buffer[0]);
                //if (sc == c.SDL_SCANCODE_UNKNOWN) @compileError("Unknown scancode");
                ret.scancode_table[sc] = @intToEnum(bind_enum, i);
                ret.bind_table[i] = @intToEnum(keycodes.Scancode, sc);
            }

            return ret;
        }

        pub fn getScancode(self: *const @This(), key: bind_enum) keycodes.Scancode {
            return self.bind_table[@enumToInt(key)];
        }

        pub fn get(self: *const @This(), scancode: usize) bind_enum {
            return self.scancode_table[scancode];
        }

        //pub fn draw(self: *const Self, ctx: *NewCtx)
    };
}
//TODO Write tests for everything

//Use case:
//Drawing 2d graphics using the painters algorithm without having to worry about anything
//IE Raylib
//
//GL Problems:
//Seperate draw modes and shaders etc require different batches.
//The painters algorithm requires us to draw a batch whenever we change that state.
//States:
//  Shader (colored tri, textured tri.
//  Primitive type (triangles, lines, points

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

//OK so new GraphicsContext
//Since our z coordinate is only used for depth, see if a u16 could be used rather than a f32
//triangleBatch, xyz, uv, rgba | xyz, rgba | maybe xyz uv
//xyz: 10
//uv: 8
//rgba: 4
//
//Tris
//Lines
//

//loadTexture()
//unloadTexture()
test "Main test" {
    //const expect = std.testing.expect();
    const alloc = std.testing.allocator;
    var ctx = GraphicsContext.init(&alloc);

    try ctx.beginDraw();
}
