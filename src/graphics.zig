const std = @import("std");
pub const c = @import("c.zig");
pub const za = @import("zalgebra");

pub const Tiled = @import("tiled.zig");

const Alloc = std.mem.Allocator;
const Dir = std.fs.Dir;

const lcast = std.math.lossyCast;
pub const Gui = @import("gui.zig");
pub const SparseSet = @import("sparse_set.zig").SparseSet;
pub const MarioData = @import("data_mario.zig");
pub const Collision = @import("col.zig");
pub const Ecs = @import("registry.zig");
pub const Lua = @import("lua.zig");
//TODO write functions for
//drawing debug information on the screen. Lots of strings, some sort of table.
//like minecraft f3
//drawing text is expensive.
//write all strings to buffer. compare frame to frame using hash
//only redraw when needed
//can be done line by line or something so that fast changing numbers don't wreck the entire caching idea.

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

pub const glID = c.GLuint;

pub const keycodes = @import("keycodes.zig");

pub const V3 = za.Vec3;

pub fn reduceU32Mask(items: []const u32) u32 {
    var result: u32 = 0;
    for (items) |item| {
        result |= item;
    }
    return result;
}

pub const Orientation = enum {
    horizontal,
    vertical,

    pub fn vec2fComponent(self: Orientation, v: Vec2f) f32 {
        return switch (self) {
            .horizontal => v.x,
            .vertical => v.y,
        };
    }

    pub fn rectH(self: Orientation, r: Rect) Rect {
        return switch (self) {
            .horizontal => r,
            .vertical => r.swapAxis(),
        };
    }
};

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

    pub fn Zero() @This() {
        return .{ .x = 0, .y = 0 };
    }

    pub fn new(x: anytype, y: anytype) @This() {
        return .{
            .x = std.math.lossyCast(f32, x),
            .y = std.math.lossyCast(f32, y),
        };
    }

    pub fn mul(s: @This(), b: @This()) @This() {
        return .{ .x = s.x * b.x, .y = s.y * b.y };
    }

    pub fn inv(s: @This()) @This() {
        return .{ .x = 1 / s.x, .y = 1 / s.y };
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
            .x = @as(I, @intFromFloat(s.x)),
            .y = @as(I, @intFromFloat(s.y)),
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

pub const Vec2i = struct {
    const Self = @This();
    x: i32,
    y: i32,

    pub fn toF(self: Self) Vec2f {
        return .{ .x = @floatFromInt(self.x), .y = @floatFromInt(self.y) };
    }
};

pub fn RecV(pos: Vec2f, w: f32, h: f32) Rect {
    return .{ .x = pos.x, .y = pos.y, .w = w, .h = h };
}

pub fn IRec(x: i32, y: i32, w: i32, h: i32) Rect {
    return .{
        .x = @as(f32, @floatFromInt(x)),
        .y = @as(f32, @floatFromInt(y)),
        .w = @as(f32, @floatFromInt(w)),
        .h = @as(f32, @floatFromInt(h)),
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
    // zig fmt: off
    if (neg) {
        return .{
            vertexTexturedDir(plane, p.x,     p.y + h, p.z, un.x       , un.y + un.h, col),
            vertexTexturedDir(plane, p.x + w, p.y + h, p.z, un.x       , un.y       , col),
            vertexTexturedDir(plane, p.x + w, p.y,     p.z, un.x + un.w, un.y       , col),
            vertexTexturedDir(plane, p.x,     p.y,     p.z, un.x + un.w, un.y + un.h, col),
        };
    } else {
        return .{
            vertexTexturedDir(plane, p.x,     p.y,     p.z, un.x + un.w, un.y + un.h, col),
            vertexTexturedDir(plane, p.x + w, p.y,     p.z, un.x + un.w, un.y       , col),
            vertexTexturedDir(plane, p.x + w, p.y + h, p.z, un.x       , un.y       , col),
            vertexTexturedDir(plane, p.x,     p.y + h, p.z, un.x       , un.y + un.h, col),
        };
    }
    // zig fmt: on
}

pub const Camera2D = struct {
    const Self = @This();

    cam_area: Rect,
    screen_area: Rect,

    pub fn factor(self: Self) Vec2f {
        const fx = (self.cam_area.w / self.screen_area.w);
        const fy = (self.cam_area.h / self.screen_area.h);
        return .{ .x = fx, .y = fy };
    }

    pub fn toWorld(self: *Self, local: Rect) Rect {
        const f = self.factor().inv();
        const cam_area = self.cam_area.pos();
        return local.subVec(cam_area).vmul(f).addVec(self.screen_area.pos());
    }

    pub fn toWorldV(self: *Self, local: Vec2f) Vec2f {
        const f = self.factor().inv();
        const cam_area = self.cam_area.pos();
        return local.sub(cam_area).mul(f).add(self.screen_area.pos());
    }

    pub fn toCamV(self: *Self, world: Vec2f) Vec2f {
        const f = self.factor();
        const cam_area = self.cam_area.pos();
        const v = world.sub(self.screen_area.pos()).mul(f).add(cam_area);
        return v;
    }

    pub fn toCam(self: *Self, world: Rect) Rect {
        const f = self.factor();
        const cam_area = self.cam_area.pos();
        const v = world.subVec(self.screen_area.pos()).vmul(f).addVec(cam_area);
        return v;
    }

    pub fn zoom(self: *Self, dist: f32, zoom_target: Vec2f) void {
        if (@fabs(dist) > 0.00001) {
            const m_init = self.toCamV(zoom_target);
            const h = self.cam_area.w * dist;
            const v = self.cam_area.h * dist;
            self.cam_area.x += h;
            self.cam_area.w -= h * 2;

            self.cam_area.y += v;
            self.cam_area.h -= v * 2;
            const m_final = self.toCamV(zoom_target);
            self.cam_area = self.cam_area.subVec(m_final.sub(m_init));
        }
    }

    pub fn pan(self: *Self, mouse_delta: Vec2f) void {
        self.cam_area = self.cam_area.subVec(mouse_delta.mul(self.factor()));
    }
};

pub const Camera3D = struct {
    const Self = @This();
    pos: za.Vec3 = za.Vec3.new(0, 0, 0),
    front: za.Vec3 = za.Vec3.new(0, 0, 0),
    yaw: f32 = 0,
    pitch: f32 = 0,
    move_speed: f32 = 0.1,

    pub fn update(self: *Self, win: *const SDL.Window) void {
        var move_vec = za.Vec3.new(0, 0, 0);
        if (win.keydown(.LSHIFT))
            move_vec = move_vec.add(za.Vec3.new(0, -1, 0));
        if (win.keydown(.SPACE))
            move_vec = move_vec.add(za.Vec3.new(0, 1, 0));
        if (win.keydown(.W))
            move_vec = move_vec.add(self.front);
        if (win.keydown(.S))
            move_vec = move_vec.add(self.front.scale(-1));
        if (win.keydown(.A))
            move_vec = move_vec.add(self.front.cross(.{ .data = .{ 0, 1, 0 } }).norm().scale(-1));
        if (win.keydown(.D))
            move_vec = move_vec.add(self.front.cross(.{ .data = .{ 0, 1, 0 } }).norm());

        self.pos = self.pos.add(move_vec.norm().scale(self.move_speed));
        const mdelta = win.mouse.delta.smul(0.1);
        self.move_speed = std.math.clamp(self.move_speed + win.mouse.wheel_delta.y * (self.move_speed / 10), 0.01, 10);

        self.yaw += mdelta.x;
        self.yaw = @mod(self.yaw, 360);
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

    pub fn getMatrix(self: Self, aspect_ratio: f32, fov: f32, near: f32, far: f32) za.Mat4 {
        const la = za.lookAt(self.pos, self.pos.add(self.front), za.Vec3.new(0, 1, 0));
        const perp = za.perspective(fov, aspect_ratio, near, far);
        return perp.mul(la);
    }
};

pub fn basicGraphUsage() void {
    const graph = @This();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = &gpa.allocator();

    var binds = graph.Bind(&.{.{ "my_bind", "a" }}).init();

    var win = try graph.SDL.Window.createWindow("My window");
    defer win.destroyWindow();

    var ctx = try graph.GraphicsContext.init(alloc, 163);
    defer ctx.deinit();

    var dpix: u32 = @intFromFloat(win.getDpi());
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

pub fn writeBmp(file_name: [*c]const u8, w: i32, h: i32, component_count: i32, data: []const u8) void {
    _ = c.stbi_write_bmp(file_name, w, h, component_count, &data[0]);
}

//Ideally I don't want to make any c.SDL calls in my application
pub const SDL = struct {
    const log = std.log.scoped(.SDL);
    /// These names are less ambiguous than "pressed" "released" "held"
    pub const ButtonState = enum {
        rising,
        high,
        falling,
        low,

        ///From frame to frame, correctly set state of a button given a binary input (up, down)
        pub fn set(self: *ButtonState, pressed: bool) void {
            if (pressed) {
                self.* = switch (self.*) {
                    .rising, .high => .high,
                    .low, .falling => .rising,
                };
            } else {
                self.* = switch (self.*) {
                    .rising, .high => .falling,
                    .low, .falling => .low,
                };
            }
        }
    };

    pub const MouseState = struct {
        left: ButtonState,
        right: ButtonState,
        middle: ButtonState,
        x1: ButtonState,
        x2: ButtonState,

        pos: Vec2f,
        delta: Vec2f,

        wheel_delta: Vec2f,

        pub fn setButtons(self: *MouseState, sdl_button_mask: u32) void {
            const b = sdl_button_mask;
            self.left.set(b & c.SDL_BUTTON_LMASK != 0);
            self.right.set(b & c.SDL_BUTTON_RMASK != 0);
            self.middle.set(b & c.SDL_BUTTON_MMASK != 0);
            self.x1.set(b & c.SDL_BUTTON_X1MASK != 0);
            self.x2.set(b & c.SDL_BUTTON_X2MASK != 0);
        }
    };

    pub const KeyState = struct {
        state: ButtonState,
        scancode: keycodes.Scancode,
    };

    pub fn getKeyFromScancode(scancode: keycodes.Scancode) keycodes.Keycode {
        return @enumFromInt(c.SDL_GetKeyFromScancode(@intFromEnum(scancode)));
    }

    pub fn getScancodeFromKey(key: keycodes.Keycode) keycodes.Scancode {
        return @enumFromInt(c.SDL_GetScancodeFromKey(@intFromEnum(key)));
    }

    pub const Window = struct {
        const Self = @This();
        pub const KeyboardStateT = std.bit_set.IntegerBitSet(c.SDL_NUM_SCANCODES);
        pub const KeysT = std.BoundedArray(KeyState, 16);

        win: *c.SDL_Window,
        ctx: *anyopaque,

        //TODO move to a vector
        screen_dimensions: Vec2i = .{ .x = 0, .y = 0 },

        should_exit: bool = false,

        mouse: MouseState = undefined,

        key_state: [c.SDL_NUM_SCANCODES]ButtonState = [_]ButtonState{.low} ** c.SDL_NUM_SCANCODES,
        keys: KeysT = KeysT.init(0) catch unreachable,
        keyboard_state: KeyboardStateT = KeyboardStateT.initEmpty(),
        last_frame_keyboard_state: KeyboardStateT = KeyboardStateT.initEmpty(),

        text_input_buffer: [32]u8 = undefined,
        text_input: []const u8,

        fn sdlLogErr() void {
            log.err("{s}", .{c.SDL_GetError()});
        }

        fn setAttr(attr: c.SDL_GLattr, val: c_int) !void {
            if (c.SDL_GL_SetAttribute(attr, val) < 0) {
                sdlLogErr();
                return error.SDLSetAttr;
            }
        }

        pub fn grabMouse(self: *const Self, should: bool) void {
            _ = self;
            _ = c.SDL_SetRelativeMouseMode(if (should) c.SDL_TRUE else c.SDL_FALSE);
            //c.SDL_SetWindowMouseGrab(self.win, if (should) 1 else 0);
            //_ = c.SDL_ShowCursor(if (!should) 1 else 0);
        }

        //pub fn screenshotGL(self: *const Self,alloc: Alloc,  )void{

        //}

        pub fn createWindow(title: [*c]const u8, options: struct {
            window_size: Vec2i = .{ .x = 1280, .y = 960 },
            double_buffer: bool = true,
            gl_profile: enum { core, compat, es } = .core,
            stencil_buffer_depth: ?i32 = 8,
            gl_major_version: i32 = 4,
            gl_minor_version: i32 = 6,
            frame_sync: enum(i32) {
                vsync = 1,
                ///FreeSync, G-Sync
                adaptave_vsync = -1,
                immediate = 0,
            } = .vsync,
            extra_gl_attributes: []const struct { attr: c.SDL_GLattr, val: i32 } = &.{},
            gl_flags: []const u32 = &.{c.SDL_GL_CONTEXT_DEBUG_FLAG},
            window_flags: []const u32 = &.{},
        }) !Self {
            log.info("Attempting to create window: {s}", .{title});
            if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
                sdlLogErr();
                return error.SDLInit;
            }
            errdefer c.SDL_Quit();

            try setAttr(c.SDL_GL_CONTEXT_PROFILE_MASK, switch (options.gl_profile) {
                .core => c.SDL_GL_CONTEXT_PROFILE_CORE,
                .compat => c.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY,
                .es => c.SDL_GL_CONTEXT_PROFILE_ES,
            });
            try setAttr(c.SDL_GL_DOUBLEBUFFER, if (options.double_buffer) 1 else 0);
            try setAttr(c.SDL_GL_CONTEXT_MAJOR_VERSION, options.gl_major_version);
            try setAttr(c.SDL_GL_CONTEXT_MINOR_VERSION, options.gl_minor_version);
            try setAttr(c.SDL_GL_CONTEXT_FLAGS, @as(i32, @intCast(reduceU32Mask(options.gl_flags))));
            if (options.stencil_buffer_depth) |sdepth|
                try setAttr(c.SDL_GL_STENCIL_SIZE, sdepth);
            for (options.extra_gl_attributes) |attr| {
                try setAttr(attr.attr, attr.val);
            }

            const win = c.SDL_CreateWindow(
                title,
                c.SDL_WINDOWPOS_UNDEFINED,
                c.SDL_WINDOWPOS_UNDEFINED,
                options.window_size.x,
                options.window_size.y,
                @as(u32, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE) |
                    @as(u32, @intCast(reduceU32Mask(options.window_flags))),
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

            {
                log.info("gl renderer: {s}", .{c.glGetString(c.GL_RENDERER)});
                log.info("gl vendor: {s}", .{c.glGetString(c.GL_VENDOR)});
                log.info("gl version: {s}", .{c.glGetString(c.GL_VERSION)});
                log.info("gl shader version: {s}", .{c.glGetString(c.GL_SHADING_LANGUAGE_VERSION)});

                //var num_ext: i64 = 0;
                //c.glGetInteger64v(c.GL_NUM_EXTENSIONS, &num_ext);
                //for (0..@intCast(num_ext)) |i| {
                //    log.info("ext: {s}", .{c.glGetStringi(c.GL_EXTENSIONS, @intCast(i))});
                //}
            }

            if (c.SDL_GL_SetSwapInterval(@intFromEnum(options.frame_sync)) < 0) {
                sdlLogErr();
                if (options.frame_sync == .adaptave_vsync) {
                    log.warn("Failed to set adaptive sync, attempting to set vsync", .{});
                    if (c.SDL_GL_SetSwapInterval(1) < 0) {
                        sdlLogErr();
                        return error.SetSwapInterval;
                    }
                } else {
                    return error.SetSwapInterval;
                }
            }
            c.glEnable(c.GL_MULTISAMPLE);
            c.glEnable(c.GL_DEPTH_TEST);
            //c.glEnable(c.GL_STENCIL_TEST);
            c.glEnable(c.GL_DEBUG_OUTPUT);

            return Self{
                .win = win,
                .ctx = context,
                .text_input = "",
            };
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

        pub fn enableNativeIme(self: *const Self, enable: bool) bool {
            _ = self;
            //_ = c.SDL_SetHint("SDL_HINT_IME_INTERNAL_EDITING", "1");
            return (c.SDL_SetHint("SDL_HINT_IME_SHOW_UI", if (enable) "1" else "0") == 1);
        }

        pub fn getKeyboardState(self: *Self, len: *usize) []const u8 {
            _ = self;
            var l: i32 = 0;
            const ret = c.SDL_GetKeyboardState(&l);
            len.* = @intCast(l);
            return ret[0..@intCast(l)];
        }

        pub fn pumpEvents(self: *Self) void {
            c.SDL_PumpEvents();
            {
                var x: c_int = undefined;
                var y: c_int = undefined;
                self.mouse.setButtons(c.SDL_GetMouseState(&x, &y));
                self.mouse.pos = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };

                _ = c.SDL_GetRelativeMouseState(&x, &y);

                self.mouse.delta = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };

                self.mouse.wheel_delta = .{ .x = 0, .y = 0 };
            }
            for (&self.key_state) |*k| {
                k.* = .low;
            }

            self.keys.resize(0) catch unreachable;
            self.last_frame_keyboard_state = self.keyboard_state;
            self.keyboard_state.mask = 0;
            {
                var l: i32 = 0;
                const ret = c.SDL_GetKeyboardState(&l)[0..@intCast(l)];
                //ret[0..@intCast(usize, l)];
                for (ret, 0..) |key, i| {
                    if (key == 1) {
                        self.keyboard_state.set(i);
                        self.key_state[i] = .high;
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

                        const scancode = c.SDL_GetScancodeFromKey(event.key.keysym.sym);
                        if (!self.last_frame_keyboard_state.isSet(scancode))
                            self.key_state[scancode] = .rising;
                        self.keys.append(.{
                            .state = .rising,
                            .scancode = @enumFromInt(scancode),
                        }) catch unreachable;
                    },
                    c.SDL_KEYUP => {
                        const scancode = c.SDL_GetScancodeFromKey(event.key.keysym.sym);
                        self.key_state[scancode] = .falling;
                    },
                    c.SDL_TEXTEDITING => {
                        const ed = event.edit;
                        const slice = std.mem.sliceTo(&ed.text, 0);
                        _ = slice;
                    },
                    c.SDL_TEXTINPUT => {
                        const slice = std.mem.sliceTo(&event.text.text, 0);
                        std.mem.copy(u8, &self.text_input_buffer, slice);
                        self.text_input = self.text_input_buffer[0..slice.len];
                    },
                    c.SDL_KEYMAPCHANGED => {
                        log.warn("keymap changed", .{});
                    },
                    c.SDL_MOUSEWHEEL => {
                        self.mouse.wheel_delta = Vec2f.new(event.wheel.preciseX, event.wheel.preciseY);
                    },
                    c.SDL_MOUSEMOTION => {},
                    c.SDL_MOUSEBUTTONDOWN => {},
                    c.SDL_MOUSEBUTTONUP => {},
                    c.SDL_WINDOWEVENT => {
                        switch (event.window.event) {
                            c.SDL_WINDOWEVENT_RESIZED => {
                                self.screen_dimensions.x = event.window.data1;
                                self.screen_dimensions.y = event.window.data2;
                                c.glViewport(0, 0, self.screen_dimensions.x, self.screen_dimensions.y);
                            },
                            c.SDL_WINDOWEVENT_SIZE_CHANGED => {},
                            c.SDL_WINDOWEVENT_CLOSE => self.should_exit = true,
                            else => {},
                        }
                        var x: c_int = undefined;
                        var y: c_int = undefined;
                        c.SDL_GetWindowSize(self.win, &x, &y);
                        self.screen_dimensions.x = x;
                        self.screen_dimensions.y = y;
                        c.glViewport(0, 0, self.screen_dimensions.x, self.screen_dimensions.y);
                    },
                    else => continue,
                }
            }
        }

        pub fn centerWindow(self: *Self) void {
            c.SDL_SetWindowPosition(self.win, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED);
        }

        pub fn setWindowSize(self: *Self, w: i32, h: i32) void {
            c.SDL_SetWindowSize(self.win, w, h);
        }

        pub fn glScissor(self: *Self, x: i32, y: i32, w: i32, h: i32) void {
            _ = self;
            c.glScissor(x, h - y, w, h);
        }

        pub fn bindScreenFramebuffer(self: *Self) void {
            c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
            c.glViewport(0, 0, self.screen_width, self.screen_height);
        }

        pub fn startTextInput(self: *const Self) void {
            _ = self;
            const rec = c.SDL_Rect{ .x = 50, .y = 500, .w = 300, .h = 72 };
            c.SDL_SetTextInputRect(&rec);
            c.SDL_StartTextInput();
        }

        pub fn stopTextInput(self: *const Self) void {
            _ = self;
            c.SDL_StopTextInput();
        }

        pub fn keyPressed(self: *const Self, scancode: keycodes.Scancode) bool {
            return self.key_state[@intFromEnum(scancode)] == .rising;
        }

        pub fn keyReleased(self: *const Self, scancode: keycodes.Scancode) bool {
            return self.key_state[@intFromEnum(scancode)] == .falling;
        }

        pub fn keydown(self: *const Self, scancode: keycodes.Scancode) bool {
            return self.keyboard_state.isSet(@intFromEnum(scancode));
        }
    };
};

///Rectangle packing
///Usage:
///init()
///appendRect()s
///pack();
///rects.items now contains the arranged rectangles.
///deinit()
pub const RectPack = struct {
    const Self = @This();
    const RectType = c.stbrp_rect;
    const RectDimType = c_int;
    const NodeType = c.stbrp_node;
    const ExtraNodeCount = 200;
    const InitRectPos = 50;

    rects: std.ArrayList(RectType),
    nodes: std.ArrayList(NodeType),

    pub fn init(alloc: Alloc) Self {
        return Self{
            .rects = std.ArrayList(RectType).init(alloc),
            .nodes = std.ArrayList(NodeType).init(alloc),
        };
    }

    pub fn deinit(self: Self) void {
        self.rects.deinit();
        self.nodes.deinit();
    }

    pub fn appendRect(self: *Self, id: anytype, w: anytype, h: anytype) !void {
        try self.rects.append(.{
            .was_packed = 0,
            .id = @intCast(id),
            .x = InitRectPos,
            .y = InitRectPos,
            .w = std.math.lossyCast(RectDimType, w),
            .h = std.math.lossyCast(c_int, h),
        });
    }

    pub fn pack(self: *Self, parent_area_w: u32, parent_area_h: u32) !void {
        if (self.rects.items.len == 0)
            return;

        try self.nodes.resize(parent_area_w + ExtraNodeCount);
        var rect_ctx: c.stbrp_context = undefined;

        c.stbrp_init_target(
            &rect_ctx,
            @intCast(parent_area_w),
            @intCast(parent_area_h),
            @ptrCast(self.nodes.items[0..self.nodes.items.len]),
            @intCast(self.nodes.items.len),
        );

        const pack_err = c.stbrp_pack_rects(
            &rect_ctx,
            @ptrCast(self.rects.items[0 .. self.rects.items.len - 1]),
            @intCast(self.rects.items.len),
        );
        if (pack_err != 1)
            return error.rectPackFailed;
    }
};

pub const MarioBgColor = 0x9290ffff;
pub const MarioBgColor2 = 0x9494ffff;
pub const MarioBgColor3 = 0x00298cff;

pub const BakedAtlas = struct {
    const Self = @This();
    const ImgIdBitShift = 16;
    const TsetT = std.StringHashMap(usize);

    pub const Tile = struct {
        si: usize,
        ti: usize,
    };

    texture: Texture,
    bitmap: Bitmap,
    tilesets: std.ArrayList(SubTileset),
    tilesets_map: TsetT,

    alloc: Alloc,

    fn rectSortFnLessThan(ctx: u8, lhs: RectPack.RectType, rhs: RectPack.RectType) bool {
        _ = ctx;
        return (lhs.id >> ImgIdBitShift) < (rhs.id >> ImgIdBitShift);
    }

    pub fn fromTiled(dir: Dir, tiled_tileset_list: []const Tiled.TilesetRef, alloc: Alloc) !Self {
        var pack_ctx = RectPack.init(alloc);
        defer pack_ctx.deinit();

        var tsets_json = std.ArrayList(std.json.Parsed(Tiled.Tileset)).init(alloc);
        defer {
            for (tsets_json.items) |*jitem| {
                jitem.deinit();
            }
            tsets_json.deinit();
        }

        var running_area: i32 = 0;
        for (tiled_tileset_list, 0..) |set, i| {
            const json_slice = try dir.readFileAlloc(alloc, set.source, std.math.maxInt(usize));
            defer alloc.free(json_slice);
            try tsets_json.append(try std.json.parseFromSlice(Tiled.Tileset, alloc, json_slice, .{ .allocate = .alloc_always }));
            const ts = tsets_json.items[tsets_json.items.len - 1].value;
            running_area += ts.count * ts.tileheight * ts.tilewidth;
            try pack_ctx.appendRect(i, ts.imagewidth, ts.imageheight);
        }

        const atlas_size: i32 = @intFromFloat(@sqrt(@as(f32, @floatFromInt(running_area)) * 2));
        try pack_ctx.pack(atlas_size, atlas_size);
        var bit = try Bitmap.initBlank(alloc, atlas_size, atlas_size, .rgba_8);

        _ = bit;
        unreachable;
    }

    pub fn fromAtlas(dir: Dir, data: Atlas.AtlasJson, alloc: Alloc) !Self {
        const texture_size = null;
        const pad = 2;

        var pack_ctx = RectPack.init(alloc);
        defer pack_ctx.deinit();

        var tilesets = std.ArrayList(SubTileset).init(alloc);
        var tsets = TsetT.init(alloc);

        var running_area: i32 = 0;
        for (data.sets, 0..) |img_set, img_index| {
            for (img_set.tilesets, 0..) |ts, ts_index| {
                running_area += ts.tw * ts.num.x * ts.th * ts.num.y;
                try pack_ctx.appendRect(
                    (img_index << ImgIdBitShift) + ts_index,
                    ts.num.x * (ts.tw + pad),
                    ts.num.y * (ts.th + pad),
                );
            }
        }
        const atlas_size: u32 = blk: {
            if (texture_size) |ts| {
                break :blk ts;
            } else {
                break :blk @intFromFloat(@sqrt(@as(f32, @floatFromInt(running_area)) * 2));
            }
        };

        try pack_ctx.pack(atlas_size, atlas_size);
        std.sort.insertion(RectPack.RectType, pack_ctx.rects.items, @as(u8, 0), rectSortFnLessThan);
        var bit = try Bitmap.initBlank(alloc, atlas_size, atlas_size, .rgba_8);

        var img_dir = try dir.openDir(data.img_dir_path, .{});
        defer img_dir.close();

        var loaded_img_index: ?u16 = null;
        var loaded_img_bitmap: ?Bitmap = null;
        defer if (loaded_img_bitmap) |bmp| {
            bmp.deinit();
        };
        for (pack_ctx.rects.items) |rect| {
            const img_index: usize = @intCast(rect.id >> ImgIdBitShift);
            const set_index: usize = @intCast(rect.id & std.math.maxInt(std.meta.Int(.unsigned, ImgIdBitShift)));
            if (loaded_img_index == null or img_index != loaded_img_index.?) {
                loaded_img_index = @intCast(img_index);
                if (loaded_img_bitmap) |*lbmp|
                    lbmp.deinit();

                loaded_img_bitmap = try Bitmap.initFromPngFile(alloc, img_dir, data.sets[img_index].filename);
            }

            const set = data.sets[img_index].tilesets[set_index];

            //tilesets.items[set_index].start = .{ .x = rect.x, .y = rect.y };
            const ts = SubTileset{
                .description = try alloc.dupe(u8, set.description),
                .start = .{ .x = rect.x, .y = rect.y },
                .tw = set.tw,
                .th = set.th,
                .pad = .{ .x = pad, .y = pad }, //Reset padding because it is removed when copying
                .num = set.num,
                .count = set.count,
            };
            try tsets.put(ts.description, tilesets.items.len);
            try tilesets.append(ts);
            for (0..set.count) |ui| {
                const i: i32 = @intCast(ui);
                Bitmap.copySub(
                    &loaded_img_bitmap.?,
                    @intCast(set.start.x + @mod(i, set.num.x) * (set.tw + set.pad.x)),
                    @intCast(set.start.y + @divFloor(i, set.num.x) * (set.th + set.pad.y)),
                    @intCast(set.tw),
                    @intCast(set.th),
                    &bit,
                    @as(u32, @intCast(rect.x)) + @as(u32, @intCast(@mod(i, set.num.x) * (set.tw + pad))),
                    @as(u32, @intCast(rect.y)) + @as(u32, @intCast(@divFloor(i, set.num.x) * (set.th + pad))),
                );
            }
        }

        bit.replaceColor(MarioBgColor, 0x0);
        bit.replaceColor(MarioBgColor2, 0x0);
        bit.replaceColor(MarioBgColor3, 0x0);
        return Self{ .bitmap = bit, .alloc = alloc, .tilesets = tilesets, .tilesets_map = tsets, .texture = Texture.initFromBitmap(
            bit,
            .{ .mag_filter = c.GL_NEAREST },
        ) };
    }

    pub fn getTexRec(self: Self, si: usize, ti: usize) Rect {
        return self.tilesets.items[si].getTexRec(ti);
    }

    pub fn getTexRecTile(self: Self, t: Tile) Rect {
        return self.tilesets.items[t.si].getTexRec(t.ti);
    }

    pub fn getSi(self: *Self, name: []const u8) usize {
        return self.tilesets_map.get(name) orelse {
            std.debug.print("Couldn't find {s}\n", .{name});
            unreachable;
        };
    }

    pub fn getTile(self: *Self, name: []const u8, ti: usize) Tile {
        return .{ .si = self.getSi(name), .ti = ti };
    }

    pub fn deinit(self: *Self) void {
        self.tilesets_map.deinit();
        for (self.tilesets.items) |*ts| {
            self.alloc.free(ts.description);
        }
        self.tilesets.deinit();
        self.bitmap.deinit();
    }
};

pub const Atlas = struct {
    const Self = @This();
    pub const AtlasJson = struct {
        pub const SetJson = struct {
            filename: []u8,
            tilesets: []SubTileset,
        };

        img_dir_path: []u8,
        sets: []SetJson,

        pub fn initFromJsonFile(dir: Dir, json_filename: []const u8, alloc: Alloc) !AtlasJson {
            const json_slice = try dir.readFileAlloc(alloc, json_filename, std.math.maxInt(usize));
            defer alloc.free(json_slice);

            const json_p = try std.json.parseFromSlice(AtlasJson, alloc, json_slice, .{ .allocate = .alloc_always });
            const json = json_p.value;
            defer json_p.deinit();
            const sets_to_load = json.sets;

            const cpy = std.mem.copy;
            var ret_j: AtlasJson = AtlasJson{ .img_dir_path = try alloc.alloc(u8, json.img_dir_path.len), .sets = try alloc.alloc(AtlasJson.SetJson, json.sets.len) };
            cpy(u8, ret_j.img_dir_path, json.img_dir_path);

            if (sets_to_load.len == 0) return error.noSets;

            for (sets_to_load, 0..) |item, i| {
                ret_j.sets[i] = .{ .filename = try alloc.alloc(u8, item.filename.len), .tilesets = try alloc.alloc(SubTileset, item.tilesets.len) };
                cpy(u8, ret_j.sets[i].filename, item.filename);
                for (item.tilesets, 0..) |ts, j| {
                    ret_j.sets[i].tilesets[j] = ts;
                    ret_j.sets[i].tilesets[j].description = try alloc.dupe(u8, ts.description);
                    //ret_j.sets[i].tilesets[j].description = try alloc.alloc(u8, ts.description.len);
                    //cpy(u8, ret_j.sets[i].tilesets[j].description, ts.description);
                }
            }

            return ret_j;
        }

        pub fn deinit(m: AtlasJson, alloc: Alloc) void {
            alloc.free(m.img_dir_path);
            for (m.sets) |*s| {
                alloc.free(s.filename);
                for (s.tilesets) |*ts| {
                    alloc.free(ts.description);
                }
                alloc.free(s.tilesets);
            }
            alloc.free(m.sets);
        }
    };

    atlas_data: AtlasJson,

    textures: std.ArrayList(Texture),
    img_dir: Dir,

    alloc: Alloc,

    pub fn initFromJsonFile(dir: Dir, json_filename: []const u8, alloc: Alloc) !Atlas {
        const json_slice = try dir.readFileAlloc(alloc, json_filename, std.math.maxInt(usize));
        defer alloc.free(json_slice);
        const json_p = try std.json.parseFromSlice(AtlasJson, alloc, json_slice, .{ .allocate = .alloc_always });
        const json = json_p.value;
        defer json_p.deinit();
        const sets_to_load = json.sets;

        const cpy = std.mem.copy;
        var ret_j: AtlasJson = AtlasJson{ .img_dir_path = try alloc.alloc(u8, json.img_dir_path.len), .sets = try alloc.alloc(AtlasJson.SetJson, json.sets.len) };
        cpy(u8, ret_j.img_dir_path, json.img_dir_path);

        if (sets_to_load.len == 0) return error.noSets;

        var img_dir = try dir.openDir(json.img_dir_path, .{});
        //defer img_dir.close();

        var textures = std.ArrayList(Texture).init(alloc);

        for (sets_to_load, 0..) |item, i| {
            try textures.append(try Texture.initFromImgFile(alloc, img_dir, item.filename, .{ .mag_filter = c.GL_NEAREST, .min_filter = c.GL_NEAREST }));

            ret_j.sets[i] = .{ .filename = try alloc.alloc(u8, item.filename.len), .tilesets = try alloc.alloc(SubTileset, item.tilesets.len) };
            cpy(u8, ret_j.sets[i].filename, item.filename);
            for (item.tilesets, 0..) |ts, j| {
                ret_j.sets[i].tilesets[j] = ts;
                ret_j.sets[i].tilesets[j].description = try alloc.alloc(u8, ts.description.len);
                cpy(u8, ret_j.sets[i].tilesets[j].description, ts.description);
            }
        }

        return .{ .alloc = alloc, .textures = textures, .atlas_data = ret_j, .img_dir = img_dir };
    }

    pub fn getTexRec(m: @This(), si: usize, ti: usize) Rect {
        return m.sets.items[si].getTexRec(ti);
    }

    pub fn addSet(self: *@This(), img_filename: []const u8) !void {
        //add an AtlasJson entry
        //add a textures entry

        const texture = (try Texture.initFromImgFile(self.alloc, self.img_dir, img_filename, .{ .mag_filter = c.GL_NEAREST, .min_filter = c.GL_NEAREST }));
        const num = self.atlas_data.sets.len;
        self.atlas_data.sets = try self.alloc.realloc(self.atlas_data.sets, num + 1);
        //self.textures = try self.alloc.realloc(self.textures, num + 1);

        const ts = try self.alloc.alloc(SubTileset, 1);
        ts[0] = .{
            .start = .{ .x = 0, .y = 0 },
            .pad = .{ .x = 0, .y = 0 },
            .num = .{ .x = 1, .y = 1 },
            .count = 1,
            .tw = 16,
            .th = 16,
        };
        self.atlas_data.sets[num] = .{ .filename = try self.alloc.dupe(u8, img_filename), .tilesets = ts };
        try self.textures.append(texture);
    }

    pub fn writeToTiled(dir: Dir, json_filename: []const u8, out_dir: Dir, alloc: Alloc) !void {
        const json_slice = try dir.readFileAlloc(alloc, json_filename, std.math.maxInt(usize));
        defer alloc.free(json_slice);
        const json_p = try std.json.parseFromSlice(AtlasJson, alloc, json_slice, .{ .allocate = .alloc_always });
        const json = json_p.value;
        defer json_p.deinit();

        var img_filename = std.ArrayList(u8).init(alloc);
        defer img_filename.deinit();
        var fout_buf: [100]u8 = undefined;
        var fbs = std.io.FixedBufferStream([]u8){ .buffer = &fout_buf, .pos = 0 };
        const img_dir = try dir.openDir(json.img_dir_path, .{});
        //iterate sets
        //for each sts output a png and tsj json file
        for (json.sets) |set| {
            var bmp = try Bitmap.initFromPngFile(alloc, img_dir, set.filename);
            defer bmp.deinit();
            for (set.tilesets) |ts| {
                var out_bmp = try Bitmap.initBlank(alloc, ts.num.x * ts.tw, ts.num.y * ts.th, .rgba_8);
                defer out_bmp.deinit();
                try img_filename.resize(0);
                try img_filename.writer().print("{s}.png", .{ts.description});
                fbs.reset();
                try fbs.writer().print("{s}.json", .{ts.description});
                var out_json = try out_dir.createFile(fbs.getWritten(), .{});
                defer out_json.close();
                const tsj = Tiled.Tileset{
                    .class = "",
                    .name = ts.description,
                    .columns = ts.num.x,
                    .firstgid = 1,
                    .imageheight = @intCast(out_bmp.h),
                    .imagewidth = @intCast(out_bmp.w),
                    .margin = 0,
                    .spacing = 0,
                    .tilecount = @intCast(ts.count),
                    .tileheight = ts.th,
                    .tilewidth = ts.tw,

                    .fillmode = "",
                    .backgroundcolor = "",
                    .image = img_filename.items,
                };
                try std.json.stringify(tsj, .{}, out_json.writer());
                for (0..ts.count) |ui| {
                    const i: i32 = @intCast(ui);
                    if (i >= ts.num.x * ts.num.y)
                        break;
                    Bitmap.copySub(
                        &bmp,
                        @intCast(ts.start.x + @mod(i, ts.num.x) * (ts.tw + ts.pad.x)),
                        @intCast(ts.start.y + @divFloor(i, ts.num.x) * (ts.th + ts.pad.y)),
                        @intCast(ts.tw),
                        @intCast(ts.th),
                        &out_bmp,
                        @as(u32, @intCast(@mod(i, ts.num.x) * ts.tw)),
                        @as(u32, @intCast(@divFloor(i, ts.num.x) * ts.th)),
                    );
                }
                try out_bmp.writeToPngFile(out_dir, img_filename.items);
            }
        }
    }

    pub fn deinit(m: Atlas) void {
        m.alloc.free(m.atlas_data.img_dir_path);
        for (m.atlas_data.sets) |*s| {
            m.alloc.free(s.filename);
            for (s.tilesets) |*ts| {
                m.alloc.free(ts.description);
            }
            if (s.tilesets.len > 0)
                m.alloc.free(s.tilesets);
        }
        m.alloc.free(m.atlas_data.sets);
        m.textures.deinit();
    }
};

///A structure that maps indices to a rectangle within a larger rectangle based on various parameters.
///Useful for tilemaps that include padding
pub const SubTileset = struct {
    const Self = @This();

    description: []u8 = "",
    start: Vec2i, //xy of first tile
    tw: i32, //width of tile
    th: i32,
    pad: Vec2i, //xy spacing between tiles
    num: Vec2i, //number of cols, rows
    count: usize, //Total number of tiles, useful if last row is short

    pub fn getTexRec(self: Self, index: usize) Rect {
        const i: i32 = @intCast(index % self.count);
        return Rec(
            self.start.x + @mod(i, self.num.x) * (self.tw + self.pad.x),
            self.start.y + @divFloor(i, self.num.x) * (self.th + self.pad.y),
            self.tw,
            self.th,
        );
    }

    pub fn getBounds(self: Self) Rect {
        return Rec(
            self.start.x,
            self.start.y,
            self.num.x * (self.tw + self.pad.x),
            self.num.y * (self.th + self.pad.y),
        );
    }
};

///A Fixed width bitmap font structure
pub const FixedBitmapFont = struct {
    const Self = @This();

    texture: Texture,
    sts: SubTileset,

    translation_table: [128]u8 = [_]u8{127} ** 128,

    // each index of this decode_string corresponds to the index of the character in subTileSet
    pub fn init(texture: Texture, sts: SubTileset, decode_string: []const u8) Self {
        var ret = Self{
            .texture = texture,
            .sts = sts,
        };
        for (decode_string, 0..) |ch, i| {
            ret.translation_table[ch] = @as(u8, @intCast(i));
        }

        return ret;
    }
};

pub const Bitmap = struct {
    const Self = @This();
    pub const ImageFormat = enum {
        rgba_8,
        rgb_8,
        g_8, //grayscale, 8 bit
    };
    pub const FormatCompCount = std.enums.directEnumArray(ImageFormat, usize, 0, .{
        .rgba_8 = 4,
        .g_8 = 1,
        .rgb_8 = 3,
    });

    format: ImageFormat = .rgba_8,
    data: std.ArrayList(u8),
    w: u32,
    h: u32,

    pub fn initBlank(alloc: Alloc, width: anytype, height: anytype, format: ImageFormat) !Self {
        var ret = Self{ .format = format, .data = std.ArrayList(u8).init(alloc), .w = lcast(u32, width), .h = lcast(u32, height) };
        const num_comp = FormatCompCount[@intFromEnum(format)];
        try ret.data.appendNTimes(0, num_comp * @as(usize, @intCast(width * height)));
        return ret;
    }

    pub fn initFromBuffer(alloc: Alloc, buffer: []const u8, width: anytype, height: anytype, format: ImageFormat) !Bitmap {
        const copy = try alloc.dupe(u8, buffer);
        return Bitmap{ .data = std.ArrayList(u8).fromOwnedSlice(alloc, copy), .w = lcast(u32, width), .h = lcast(u32, height), .format = format };
    }

    pub fn initFromPngBuffer(alloc: Alloc, buffer: []const u8) !Bitmap {
        var pngctx = c.spng_ctx_new(0);
        defer c.spng_ctx_free(pngctx);
        _ = c.spng_set_png_buffer(pngctx, &buffer[0], buffer.len);

        var ihdr: c.spng_ihdr = undefined;
        _ = c.spng_get_ihdr(pngctx, &ihdr);

        var out_size: usize = 0;
        _ = c.spng_decoded_image_size(pngctx, c.SPNG_FMT_RGBA8, &out_size);
        //TODO use the SPNG_FMT provided by ihdr
        // if (ihdr.color_type != c.SPNG_FMT_RGBA8)
        //     return error.unsupportedColorFormat;

        const decoded_data = try alloc.alloc(u8, out_size);

        _ = c.spng_decode_image(pngctx, &decoded_data[0], out_size, c.SPNG_FMT_RGBA8, 0);

        return Bitmap{ .w = ihdr.width, .h = ihdr.height, .data = std.ArrayList(u8).fromOwnedSlice(alloc, decoded_data) };
    }

    pub fn initFromPngFile(alloc: Alloc, dir: Dir, sub_path: []const u8) !Bitmap {
        const file_slice = try dir.readFileAlloc(alloc, sub_path, std.math.maxInt(usize));
        defer alloc.free(file_slice);

        return try initFromPngBuffer(alloc, file_slice);
    }

    pub fn initFromImageFile(alloc: Alloc, dir: Dir, sub_path: []const u8) !Bitmap {
        const file_slice = try dir.readFileAlloc(alloc, sub_path, std.math.maxInt(usize));
        defer alloc.free(file_slice);

        return try initFromImageBuffer(alloc, file_slice);
    }

    pub fn initFromImageBuffer(alloc: Alloc, buffer: []const u8) !Bitmap {
        //TODO check errors
        var x: c_int = 0;
        var y: c_int = 0;
        var num_channel: c_int = 0;
        const img_buf = c.stbi_load_from_memory(&buffer[0], @intCast(buffer.len), &x, &y, &num_channel, 4);
        const len = @as(usize, @intCast(num_channel * x * y));
        const decoded = try alloc.alloc(u8, len);
        defer alloc.free(decoded);
        std.mem.copy(u8, decoded, img_buf[0..len]);

        return try initFromBuffer(alloc, decoded, x, y, switch (num_channel) {
            4 => .rgba_8,
            3 => .rgb_8,
            1 => .g_8,
            else => return error.unsupportedFormat,
        });
    }

    pub fn deinit(self: Self) void {
        self.data.deinit();
    }

    pub fn replaceColor(self: *Self, color: u32, replacement: u32) void {
        //TODO support other formats
        if (self.format != .rgba_8) unreachable;
        const search = intToColor(color);
        const rep = intToColor(replacement);
        for (0..(self.data.items.len / 4)) |i| {
            const d = self.data.items[i * 4 .. i * 4 + 4];
            if (d[0] == search.r and d[1] == search.g and d[2] == search.b) {
                d[0] = rep.r;
                d[1] = rep.g;
                d[2] = rep.b;
                d[3] = rep.a;
            }
        }
    }

    pub fn writeToBmpFile(self: *Self, alloc: Alloc, dir: Dir, file_name: []const u8) !void {
        if (self.format != .rgba_8) return error.unsupportedFormat;
        var path = std.ArrayList(u8).fromOwnedSlice(alloc, try dir.realpathAlloc(alloc, file_name));
        defer path.deinit();
        try path.append(0);

        _ = c.stbi_write_bmp(@as([*c]const u8, @ptrCast(path.items)), @as(c_int, @intCast(self.w)), @as(c_int, @intCast(self.h)), 4, @as([*c]u8, @ptrCast(self.data.items[0..self.data.items.len])));
    }

    pub fn writeToPngFile(self: *Self, dir: Dir, sub_path: []const u8) !void {
        var out_file = try dir.createFile(sub_path, .{});
        defer out_file.close();
        var pngctx = c.spng_ctx_new(c.SPNG_CTX_ENCODER);
        defer c.spng_ctx_free(pngctx);

        _ = c.spng_set_option(pngctx, c.SPNG_ENCODE_TO_BUFFER, 1);

        var ihdr = c.spng_ihdr{
            .width = self.w,
            .height = self.h,
            .bit_depth = 8,
            .color_type = switch (self.format) {
                .rgb_8 => c.SPNG_COLOR_TYPE_TRUECOLOR,
                .rgba_8 => c.SPNG_COLOR_TYPE_TRUECOLOR_ALPHA,
                .g_8 => c.SPNG_COLOR_TYPE_GRAYSCALE,
            },
            .compression_method = 0,
            .filter_method = 0,
            .interlace_method = 0,
        };
        var err: c_int = 0;
        err = c.spng_set_ihdr(pngctx, &ihdr);
        if (err != 0)
            std.debug.print("PNG error {s}\n", .{c.spng_strerror(err)});

        err = c.spng_encode_image(pngctx, &self.data.items[0], self.data.items.len, c.SPNG_FMT_PNG, c.SPNG_ENCODE_FINALIZE);
        if (err != 0)
            std.debug.print("PNG error {s}\n", .{c.spng_strerror(err)});
        var png_size: usize = 0;
        const data = c.spng_get_png_buffer(pngctx, &png_size, &err);
        if (err != 0)
            std.debug.print("PNG error {s}\n", .{c.spng_strerror(err)});
        if (data) |d| {
            const sl = @as([*]u8, @ptrCast(d));
            _ = try out_file.writer().write(sl[0..png_size]);
            var c_alloc = std.heap.raw_c_allocator;
            c_alloc.free(sl[0..png_size]);
        } else {
            return error.failedToEncodePng;
        }
    }

    //TODO use self.format
    pub fn copySubR(num_component: u8, dest: *Self, des_x: u32, des_y: u32, source: *Self, src_x: u32, src_y: u32, src_w: u32, src_h: u32) void {
        var sy = src_y;
        while (sy < src_y + src_h) : (sy += 1) {
            var sx = src_x;
            while (sx < src_x + src_w) : (sx += 1) {
                const source_i = ((sy * source.w) + sx) * num_component;

                const rel_y = sy - src_y;
                const rel_x = sx - src_x;

                const dest_i = (((des_y + rel_y) * dest.w) + rel_x + des_x) * num_component;

                var i: usize = 0;
                while (i < num_component) : (i += 1) {
                    dest.data.items[dest_i + i] = source.data.items[source_i + i];
                }
            }
        }
    }

    //TODO should the source and dest be swapped, copy functions usually have the destination argument before the source
    pub fn copySub(source: *Self, srect_x: u32, srect_y: u32, srect_w: u32, srect_h: u32, dest: *Self, des_x: u32, des_y: u32) void {
        if (source.format != dest.format) unreachable;
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

pub const GL = struct {
    const log = std.log.scoped(GL);
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
            log.warn("glGetError: {s}", .{str});
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
            @as(c_long, @intCast(slice.len)) * @sizeOf(item),
            slice.ptr,
            c.GL_STATIC_DRAW,
        );
        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    }

    fn generateVertexAttributes(vao: c_uint, vbo: c_uint, comptime T: anytype) void {
        const info = @typeInfo(T);
        switch (info) {
            .Struct => {
                const st = info.Struct;
                if (st.layout != .Packed) @compileError("generateVertexAttributes only supports packed structs");
                inline for (st.fields, 0..) |field, f_i| {
                    switch (field.type) {
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
            @as(c_long, @intCast(offset)) * @sizeOf(item),
            @as(c_long, @intCast(len)) * @sizeOf(item),
            &slice[offset],
        );

        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    }

    fn intVertexAttrib(vao: glID, vbo: glID, index: u32, num_elem: u32, comptime item: type, comptime starting_field: []const u8, int_type: c.GLenum) void {
        c.glBindVertexArray(vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
        defer c.glBindVertexArray(0);
        defer c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

        const byte_offset = @offsetOf(item, starting_field);
        c.glVertexAttribIPointer(
            index,
            @as(c_int, @intCast(num_elem)),
            int_type,
            @sizeOf(item),
            if (byte_offset != 0) @as(*const anyopaque, @ptrFromInt(byte_offset)) else null,
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
            @as(c_int, @intCast(size)),
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(item),
            if (byte_offset != 0) @as(*const anyopaque, @ptrFromInt(byte_offset)) else null,
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

        c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(batch.indicies.items.len)), c.GL_UNSIGNED_INT, null);
        //c.glBindVertexArray(0);

    }
};

//Handle dpi
//More 3d primitives
//TODO defer errors to end of frame. not drawing is not fatal, ergonomically much nicer to not "try draw.*"
//The point of this drawing context is to get common 2d primitives drawn to the screen with as little boilerplate as possible.
//This means:
//  Loading a default font
//  easy depth?
//  functions should have terse but descriptive names
//  Don't mess with gl state to much so other drawing is easy
//
//  Loading a default font:
//  Ideally we know the dpi we are using. either assume camera is always screen space or do something?
//  One font always loaded from init
//  we can load other fonts in other threads and notify once ready.
//  The point of this is to draw text with native scaling as it has no artifacting.
//
pub const NewCtx = struct {
    const Self = @This();

    pub const VtxFmt = struct {
        pub const Color_2D = packed struct { pos: Vec2f, z: u16, color: u32 };
        pub const Color_Texture_2D = packed struct { pos: Vec2f, uv: Vec2f, z: u16, color: u32 }; // 22 bytes
        pub const Color_3D = packed struct { pos: Vec3f, color: u32 };

        //idea for a small vertex, xy are 14.2 or 13.3 fixed point. 2^13 allows for up to 8k with 8 subpixel positions
        //uv are also some fixed point maybe 13.3. These would not be normalized?
        pub const SmallTex = packed struct { x: u16, y: u16, u: u16, v: u16, z: u16 };
        //Total size: 10bytes
    };

    pub const Batches = union(enum) {
        color_tri: NewBatch(VtxFmt.Color_2D, .{ .index_buffer = true, .primitive_mode = .triangles }),
        color_tri_tex: NewBatch(VtxFmt.Color_Texture_2D, .{ .index_buffer = true, .primitive_mode = .triangles }),
        color_line3D: NewBatch(VtxFmt.Color_3D, .{ .index_buffer = false, .primitive_mode = .lines }),
        color_line: NewBatch(VtxFmt.Color_2D, .{ .index_buffer = false, .primitive_mode = .lines }),
    };

    const MapT = std.AutoArrayHashMap(MapKey, Batches);
    const MapKey = struct {
        batch_kind: @typeInfo(Batches).Union.tag_type.?,
        params: DrawParams,
    };
    const MapKeySortCtx = struct {
        items: []const MapKey,
        pub fn lessThan(ctx: MapKeySortCtx, l: usize, r: usize) bool {
            return ctx.items[l].params.draw_priority < ctx.items[r].params.draw_priority;
        }
    };

    batches: MapT,

    zindex: u16 = 0,
    font_shader: c_uint,
    colored_tri_shader: c_uint,
    colored_line3d_shader: c_uint,
    textured_tri_shader: c_uint,
    dpi: f32,

    alloc: Alloc,
    //TODO comptime function where you specify the indicies or verticies you want to append to by a string name, handles setting error flags and everything

    //TODO actually check this and log or panic
    draw_fn_error: enum {
        //TODO maybe have different?
        no,
        yes,
    } = .no,

    screen_dimensions: Vec2f = .{ .x = 0, .y = 0 },

    pub fn init(alloc: Alloc, dpi: f32) Self {
        return Self{
            .alloc = alloc,
            .batches = MapT.init(alloc),
            .dpi = dpi,

            .colored_tri_shader = Shader.simpleShader(NewTri.shader_test_vert, NewTri.shader_test_frag),
            .colored_line3d_shader = Shader.simpleShader(@embedFile("shader/line3d.vert"), @embedFile("shader/colorquad.frag")),
            .textured_tri_shader = Shader.simpleShader(@embedFile("shader/tex_tri2d.vert"), @embedFile("shader/tex_tri2d.frag")),

            .font_shader = Shader.simpleShader(@embedFile("shader/tex_tri2d.vert"), @embedFile("shader/tex_tri2d_alpha.frag")),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.batches.values()) |*b| {
            inline for (@typeInfo(Batches).Union.fields, 0..) |ufield, i| {
                if (i == @intFromEnum(b.*)) {
                    @field(b, ufield.name).deinit();
                }
            }
        }
        self.batches.deinit();
    }
    //TODO function that takes anytype used to draw

    pub fn getBatch(self: *Self, key: MapKey) !*Batches {
        const res = try self.batches.getOrPut(key);
        if (!res.found_existing) {
            inline for (@typeInfo(Batches).Union.fields, 0..) |ufield, i| {
                if (i == @intFromEnum(key.batch_kind)) {
                    res.value_ptr.* = @unionInit(Batches, ufield.name, ufield.type.init(self.alloc));
                    res.key_ptr.* = key;
                    break;
                }
            }
        }
        return res.value_ptr;
    }

    pub fn clearBuffers(self: *Self) !void {
        for (self.batches.values()) |*b| {
            inline for (@typeInfo(Batches).Union.fields, 0..) |ufield, i| {
                if (i == @intFromEnum(b.*)) {
                    try @field(b, ufield.name).clear();
                }
            }
        }
    }

    pub fn begin(self: *Self, bg_color: u32, screen_dim: Vec2f) !void {
        self.screen_dimensions = screen_dim;
        try self.clearBuffers();

        self.zindex = 1;
        std.time.sleep(16 * std.time.ns_per_ms);

        const color = intToColorF(bg_color);
        c.glClearColor(color[0], color[1], color[2], color[3]);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
    }

    pub fn rectPt(self: *Self, rpt: Rect, color: u32) void {
        self.rect(rpt.mul(self.dpi / 72.0), color);
    }

    pub fn rectV(self: *Self, pos: Vec2f, dim: Vec2f, color: u32) void {
        self.rect(Rect.newV(pos, dim), color);
    }

    pub fn rect(self: *Self, rpt: Rect, color: u32) void {
        const r = rpt;
        const b = &(self.getBatch(.{ .batch_kind = .color_tri, .params = .{ .shader = self.colored_tri_shader } }) catch unreachable).color_tri;
        const z = self.zindex;
        self.zindex += 1;
        b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len)))) catch {
            self.draw_fn_error = .yes;
            return;
        };
        b.vertices.appendSlice(&.{
            .{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .color = color },
            .{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .color = color },
            .{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .color = color },
            .{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .color = color },
        }) catch {
            self.draw_fn_error = .yes;
            return;
        };
    }

    pub fn rectTex(self: *Self, r: Rect, tr: Rect, col: u32, texture: Texture) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_tri_tex, .params = .{ .shader = self.textured_tri_shader, .texture = texture.id } }) catch return).color_tri_tex;
        const z = self.zindex;
        self.zindex += 1;
        const un = normalizeTexRect(tr, texture.w, texture.h);

        b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len)))) catch return;
        b.vertices.appendSlice(&.{
            .{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y + un.h }, .color = col }, //0
            .{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y }, .color = col }, //1
            .{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .uv = .{ .x = un.x, .y = un.y }, .color = col }, //2
            .{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x, .y = un.y + un.h }, .color = col }, //3
        }) catch return;
    }

    pub fn text(self: *Self, pos: Vec2f, str: []const u8, font: *Font, pt_size: f32, col: u32) void {
        const SF = (pt_size / font.font_size);
        const fac = 1;
        const x = pos.x;
        const y = pos.y;

        const b = &(self.getBatch(.{
            .batch_kind = .color_tri_tex,
            //Text should always be drawn last for best transparency
            .params = .{ .shader = self.font_shader, .texture = font.texture.id, .draw_priority = 0xff },
        }) catch unreachable).color_tri_tex;

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
            const fpad = @as(f32, @floatFromInt(Font.padding)) / 2;
            const pad = @as(f32, @floatFromInt(Font.padding));

            const r = Rect{
                .x = vx + (g.offset_x - fpad) * SF,
                .y = vy - (g.offset_y + fpad) * SF,
                .w = (pad + g.width) * SF,
                .h = (pad + g.height) * SF,
            };

            // try self.rect(r, 0xffffffff);

            b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len)))) catch unreachable;
            const un = normalizeTexRect(g.tr, font.texture.w, font.texture.h);
            const z = self.zindex;
            b.vertices.appendSlice(&.{
                .{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y + un.h }, .color = col }, //0
                .{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y }, .color = col }, //1
                .{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .uv = .{ .x = un.x, .y = un.y }, .color = col }, //2
                .{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x, .y = un.y + un.h }, .color = col }, //3
            }) catch return;

            vx += (g.advance_x) * SF;
        }
        self.zindex += 1;
    }

    pub fn textFmt(self: *Self, pos: Vec2f, comptime fmt: []const u8, args: anytype, font: *Font, pt_size: f32, color: u32) void {
        var buf: [256]u8 = undefined;
        var fbs = std.io.FixedBufferStream([]u8){ .pos = 0, .buffer = &buf };
        fbs.writer().print(fmt, args) catch return;
        self.text(pos, fbs.getWritten(), font, pt_size, color);
    }

    pub fn line3D(self: *Self, start_point: Vec3f, end_point: Vec3f, color: u32) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_line3D, .params = .{ .shader = self.colored_line3d_shader } }) catch unreachable).color_line3D;
        b.vertices.append(.{ .pos = start_point, .color = color }) catch return;
        b.vertices.append(.{ .pos = end_point, .color = color }) catch return;
    }

    //TODO what is the winding order
    pub fn triangle(self: *Self, v1: Vec2f, v2: Vec2f, v3: Vec2f, color: u32) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_tri, .params = .{ .shader = self.colored_tri_shader } }) catch unreachable).color_tri;
        const z = self.zindex;
        const i: u32 = @intCast(b.vertices.items.len);
        b.indicies.appendSlice(&.{ i, i + 1, i + 2 }) catch return;
        b.vertices.appendSlice(&.{
            .{ .pos = v1, .z = z, .color = color },
            .{ .pos = v2, .z = z, .color = color },
            .{ .pos = v3, .z = z, .color = color },
        }) catch return;
    }

    //TODO
    // fn fixedBitmapText?

    pub fn line(self: *Self, start_p: Vec2f, end_p: Vec2f, color: u32) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_line, .params = .{ .shader = self.colored_tri_shader } }) catch unreachable).color_line;
        const z = self.zindex;
        self.zindex += 1;
        b.vertices.appendSlice(&.{
            .{ .pos = start_p, .z = z, .color = color },
            .{ .pos = end_p, .z = z, .color = color },
        }) catch return;
    }

    pub fn flush(self: *Self) !void {
        const view = za.orthographic(0, self.screen_dimensions.x, self.screen_dimensions.y, 0, -100000, 1);
        const model = za.Mat4.identity();
        //TODO annotate batches with camera or view

        const sortctx = MapKeySortCtx{ .items = self.batches.keys() }; // Sort the batches by params.draw_priority
        self.batches.sort(sortctx);
        var b_it = self.batches.iterator();
        while (b_it.next()) |b| {
            inline for (@typeInfo(Batches).Union.fields, 0..) |ufield, i| {
                if (i == @intFromEnum(b.value_ptr.*)) {
                    @field(b.value_ptr.*, ufield.name).pushVertexData();
                    @field(b.value_ptr.*, ufield.name).draw(b.key_ptr.params, view, model);
                }
            }
        }
        try self.clearBuffers();
    }

    pub fn end(self: *Self) !void {
        try self.flush();
    }
};

pub const BatchOptions = struct {
    index_buffer: bool,
    primitive_mode: GL.PrimitiveMode,
};
pub const DrawParams = struct {
    texture: ?c_uint = null,
    ///The higher the number, the later the batch gets drawn.
    draw_priority: u8 = 0,
    shader: c_uint,
};
pub fn NewBatch(comptime vertex_type: type, comptime batch_options: BatchOptions) type {
    const IndexType = u32;
    return struct {
        pub const Self = @This();

        vbo: c_uint,
        vao: c_uint,
        ebo: if (batch_options.index_buffer) c_uint else void,
        vertices: std.ArrayList(vertex_type),
        indicies: if (batch_options.index_buffer) std.ArrayList(IndexType) else void,
        primitive_mode: GL.PrimitiveMode = batch_options.primitive_mode,

        pub fn init(alloc: Alloc) @This() {
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

        pub fn draw(self: *Self, params: DrawParams, view: za.Mat4, model: za.Mat4) void {
            c.glUseProgram(params.shader);
            c.glBindVertexArray(self.vao);
            if (params.texture) |texture| {
                c.glBindTexture(c.GL_TEXTURE_2D, texture);
            }
            GL.passUniform(params.shader, "view", view);
            GL.passUniform(params.shader, "model", model);

            const prim: u32 = @intFromEnum(self.primitive_mode);
            if (batch_options.index_buffer) {
                c.glDrawElements(prim, @as(c_int, @intCast(self.indicies.items.len)), c.GL_UNSIGNED_INT, null);
            } else {
                c.glLineWidth(3.0);
                c.glDrawArrays(prim, 0, @as(c_int, @intCast(self.vertices.items.len)));
            }
        }
    };
}

pub const Shader = struct {
    fn checkShaderErr(shader: glID, comporlink: c_uint) void {
        var success: c_int = undefined;
        var infoLog: [512]u8 = undefined;
        c.glGetShaderiv(shader, comporlink, &success);
        if (success == 0) {
            var len: c_int = 0;
            c.glGetShaderInfoLog(shader, 512, &len, &infoLog);
            std.debug.panic("ERROR::SHADER::\n{s}\n", .{infoLog[0..@as(usize, @intCast(len))]});
        }
    }

    fn compShader(src: [*c]const u8, s_type: c_uint) glID {
        const vert = c.glCreateShader(s_type);
        c.glShaderSource(vert, 1, &src, null);
        c.glCompileShader(vert);
        checkShaderErr(vert, c.GL_COMPILE_STATUS);
        return vert;
    }

    pub fn simpleShader(vert_src: [*c]const u8, frag_src: [*c]const u8) glID {
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

pub const Colori = struct {
    pub const White = 0xffffffff;
    pub const Black = 0x000000ff;
    pub const Gray = 0x808080ff;
    pub const DarkGray = 0xA9A9A9ff;
    pub const Purple = 0x800080ff;
    pub const Blue = 0x0000FFff;
    pub const Red = 0xFF0000ff;
    pub const Orange = 0xFFA500ff;
};

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
//TODO orginize colors, we have 4 different types of colors
//hsva, (4 f32)
//u32
//Rgba (4 u8)
//Rgba (4 F32)

pub const Hsva = struct {
    h: f32,
    s: f32,
    v: f32,
    a: f32,
};

pub fn colorToHsva(color: CharColor) Hsva {
    const fl = charColorToFloat(color);
    const max = @max(fl[0], fl[1], fl[2]);
    const min = @max(fl[0], fl[1], fl[2]);
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
    const rgb1 = switch (@as(u32, @intFromFloat(hp))) {
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
        @as(u8, @intFromFloat((M + rgb1.data[0]) * 255)),
        @as(u8, @intFromFloat((M + rgb1.data[1]) * 255)),
        @as(u8, @intFromFloat((M + rgb1.data[2]) * 255)),
        @as(u8, @intFromFloat(hsva.a * 255)),
    );
}

pub fn charColorToFloat(col: CharColor) Color {
    return .{
        @as(f32, @floatFromInt(col.r)) / 255.0,
        @as(f32, @floatFromInt(col.g)) / 255.0,
        @as(f32, @floatFromInt(col.b)) / 255.0,
        @as(f32, @floatFromInt(col.a)) / 255.0,
    };
}

pub fn charColorToInt(co: CharColor) u32 {
    return (@as(u32, @intCast(co.r)) << 24) | (@as(u32, @intCast(co.g)) << 16) | (@as(u32, @intCast(co.b)) << 8) | co.a;
}

pub const itc = intToColor;

pub fn intToColor(color: u32) CharColor {
    return .{
        .r = @as(u8, @intCast((color >> 24) & 0xff)),
        .g = @as(u8, @intCast((color >> 16) & 0xff)),
        .b = @as(u8, @intCast((color >> 8) & 0xff)),
        .a = @as(u8, @intCast((color) & 0xff)),
    };
}

pub fn intToColorF(color: u32) Color {
    return charColorToFloat(intToColor(color));
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
        return .{ .x = @as(f32, @floatFromInt(self.x)), .y = @as(f32, @floatFromInt(self.y)), .w = @as(f32, @floatFromInt(self.w)), .h = @as(f32, @floatFromInt(self.h)) };
    }
};

pub const Padding = struct {
    const Self = @This();
    top: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,
    right: f32 = 0,

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

    pub fn overlap(r1: Self, r2: Self) bool {
        return !(r1.x > r2.x + r2.w or r2.x > r1.x + r1.w or r1.y > r2.y + r2.h or r2.y > r1.y + r1.h);
    }

    pub fn newV(_pos: Vec2f, dim_: Vec2f) @This() {
        return .{ .x = _pos.x, .y = _pos.y, .w = dim_.x, .h = dim_.y };
    }

    pub fn addV(self: @This(), x: anytype, y: anytype) @This() {
        return .{ .x = self.x + lcast(f32, x), .y = self.y + lcast(f32, y), .w = self.w, .h = self.h };
    }

    pub fn subVec(self: Self, s: Vec2f) Self {
        return .{ .x = self.x - s.x, .y = self.y - s.y, .w = self.w, .h = self.h };
    }

    pub fn addVec(self: @This(), v: Vec2f) @This() {
        return .{ .x = self.x + v.x, .y = self.y + v.y, .w = self.w, .h = self.h };
    }

    pub fn mul(self: Self, scalar: f32) Self {
        return .{ .x = self.x * scalar, .y = self.y * scalar, .w = self.w * scalar, .h = self.h * scalar };
    }

    pub fn vmul(self: Self, v: Vec2f) @This() {
        return .{ .x = self.x * v.x, .y = self.y * v.y, .w = self.w * v.x, .h = self.h * v.y };
    }

    pub fn inset(self: Self, amount: f32) Self {
        return .{ .x = self.x + amount, .y = self.y + amount, .w = self.w - amount * 2, .h = self.h - amount * 2 };
    }

    pub fn insetV(self: Self, ax: f32, ay: f32) Self {
        return .{ .x = self.x + ax, .y = self.y + ay, .w = self.w - ax * 2, .h = self.h - ay * 2 };
    }

    pub fn dimR(self: Self) Self {
        return .{ .x = 0, .y = 0, .w = self.w, .h = self.h };
    }

    pub fn dim(self: Self) Vec2f {
        return Vec2f.new(self.w, self.h);
    }

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

    pub fn toAbsoluteRect(self: Self) Rect {
        return Rec(self.x, self.y, self.x + self.w, self.y + self.h);
    }

    pub fn eql(a: Self, b: Self) bool {
        return (a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h);
    }

    pub fn hull(a: Self, b: Self) Self {
        const x = @min(a.x, b.x);
        const y = @min(a.y, b.y);
        return Rec(x, y, @max(a.farX(), b.farX()) - x, @max(a.farY(), b.farY()) - y);
    }

    /// cpos is where the cut should occur, relative to the rectangles origin
    pub fn split(a: Self, orientation: Orientation, cpos: f32) struct { Self, Self } {
        return switch (orientation) {
            .vertical => .{ Self.new(a.x, a.y, cpos, a.h), Self.new(a.x + cpos, a.y, a.w - cpos, a.h) },
            .horizontal => .{ Self.new(a.x, a.y, a.w, cpos), Self.new(a.x, a.y + cpos, a.w, a.h - cpos) },
        };
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
            .x = @as(int_type, @intFromFloat(self.x)),
            .y = @as(int_type, @intFromFloat(self.y)),
            .w = @as(int_type, @intFromFloat(self.w)),
            .h = @as(int_type, @intFromFloat(self.h)),
        };
    }

    pub fn swapAxis(self: Self) Self {
        return Rec(self.y, self.x, self.h, self.w);
    }

    pub fn invX(self: Self) Self {
        return Rec(self.x + self.w, self.y, -self.w, self.h);
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
    const tw = @as(f32, @floatFromInt(tx_w));
    const th = @as(f32, @floatFromInt(tx_h));
    return .{
        .x = tr.x / tw,
        .y = tr.y / th,
        .w = tr.w / tw,
        .h = tr.h / th,
    };
}

//pub fn shaded_cube()[24]VertexTextured

pub fn cube(px: f32, py: f32, pz: f32, sx: f32, sy: f32, sz: f32, tr: Rect, tx_w: u32, tx_h: u32, colorsopt: ?[]const CharColor) [24]VertexTextured {
    const colors = if (colorsopt) |cc| cc else &[6]CharColor{
        itc(0x888888ff), //Front
        itc(0x888888ff), //Back
        itc(0x666666ff), //Bottom
        itc(0xffffffff), //Top
        itc(0xaaaaaaff),
        itc(0xaaaaaaff),
    };
    const un = normalizeTexRect(tr, @as(i32, @intCast(tx_w)), @as(i32, @intCast(tx_h)));
    // zig fmt: off
    return [_]VertexTextured{
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


    };
    // zig fmt: on

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
    // zig fmt: off
    return [_]VertexTextured {
        vertexTextured(r.x + r.w, r.y + r.h, z, un.x + un.w, un.y + un.h, color), //0
        vertexTextured(r.x + r.w, r.y      , z, un.x + un.w, un.y       , color), //1
        vertexTextured(r.x      , r.y      , z, un.x       , un.y       , color), //2
        vertexTextured(r.x      , r.y + r.h, z, un.x       , un.y + un.h, color), //3
    };
    // zig fmt: on
}

pub const RenderTexture = struct {
    const Self = @This();
    fb: c_uint,
    depth_rb: c_uint,
    stencil_rb: c_uint,
    texture: Texture,
    w: i32,
    h: i32,

    pub fn init(w: i32, h: i32) !Self {
        var ret = Self{
            .w = w,
            .h = h,
            .fb = 0,
            .depth_rb = 0,
            .stencil_rb = 0,
            .texture = Texture.initFromBuffer(null, w, h, .{ .min_filter = c.GL_LINEAR, .mag_filter = c.GL_NEAREST, .generate_mipmaps = false }),
            //.texture = Texture.
        };
        c.glGenFramebuffers(1, &ret.fb);
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, ret.fb);

        //c.glGenRenderbuffers(1, &ret.depth_rb);
        //c.glBindRenderbuffer(c.GL_RENDERBUFFER, ret.depth_rb);
        //c.glRenderbufferStorage(c.GL_RENDERBUFFER, c.GL_DEPTH_COMPONENT, w, h);
        //c.glFramebufferRenderbuffer(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_RENDERBUFFER, ret.depth_rb);

        c.glGenRenderbuffers(1, &ret.stencil_rb);
        c.glBindRenderbuffer(c.GL_RENDERBUFFER, ret.stencil_rb);
        c.glRenderbufferStorage(c.GL_RENDERBUFFER, c.GL_DEPTH_STENCIL, w, h);
        c.glFramebufferRenderbuffer(c.GL_FRAMEBUFFER, c.GL_STENCIL_ATTACHMENT, c.GL_RENDERBUFFER, ret.stencil_rb);

        c.glFramebufferTexture(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, ret.texture.id, 0);
        const draw_buffers = [_]c.GLenum{c.GL_COLOR_ATTACHMENT0};
        c.glDrawBuffers(draw_buffers.len, &draw_buffers[0]);

        if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) return error.framebufferCreateFailed;

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        c.glBindRenderbuffer(c.GL_RENDERBUFFER, 0);

        return ret;
    }

    pub fn setSize(self: *Self, w: i32, h: i32) !void {
        if (w != self.w or h != self.h) {
            self.deinit();
            self.* = try RenderTexture.init(w, h);
        }
    }

    pub fn rect(self: *Self) Rect {
        const r = self.texture.rect();
        return Rec(r.x, r.y + r.h, r.w, -r.h);
    }

    pub fn deinit(self: *Self) void {
        c.glDeleteFramebuffers(1, &self.fb);
        c.glDeleteRenderbuffers(1, &self.depth_rb);
        c.glDeleteRenderbuffers(1, &self.stencil_rb);
        c.glDeleteTextures(1, &self.texture.id);
    }

    pub fn bind(self: *Self, clear: bool) void {
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.fb);
        c.glViewport(0, 0, self.w, self.h);
        if (clear)
            c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glClear(c.GL_DEPTH_BUFFER_BIT);
    }
};

pub const Texture = struct {
    id: glID,
    w: i32,
    h: i32,

    pub fn rect(t: Texture) Rect {
        return Rec(0, 0, t.w, t.h);
    }

    pub fn aspectRatio(t: Texture) f32 {
        return @as(f32, @floatFromInt(t.w)) / @as(f32, @floatFromInt(t.h));
    }

    pub const Options = struct {
        internal_format: c.GLint = c.GL_RGBA,
        pixel_format: c.GLenum = c.GL_RGBA,
        pixel_type: c.GLenum = c.GL_UNSIGNED_BYTE,
        pixel_store_alignment: c.GLint = 4,
        target: c.GLenum = c.GL_TEXTURE_2D,

        wrap_u: c.GLint = c.GL_REPEAT,
        wrap_v: c.GLint = c.GL_REPEAT,

        generate_mipmaps: bool = true,
        min_filter: c.GLint = c.GL_LINEAR_MIPMAP_LINEAR,
        mag_filter: c.GLint = c.GL_LINEAR,
        border_color: [4]f32 = .{ 0, 0, 0, 1.0 },
    };

    //Todo write tests does this actually work
    pub fn initFromImgFile(alloc: Alloc, dir: Dir, sub_path: []const u8, o: Options) !Texture {
        var file = try dir.openFile(sub_path, .{});
        defer file.close();
        var header: [8]u8 = undefined;
        const len = try file.read(&header);
        const sl = header[0..len];
        const eql = std.mem.eql;
        if (eql(u8, &.{ 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a }, sl)) {
            var bmp = try Bitmap.initFromPngFile(alloc, dir, sub_path);
            defer bmp.deinit();
            return initFromBitmap(bmp, o);
        } else {
            var bmp = try Bitmap.initFromImageFile(alloc, dir, sub_path);
            defer bmp.deinit();
            return initFromBitmap(bmp, o);
        }
        return error.unrecognizedImageFileFormat;
    }

    pub fn initFromBuffer(buffer: ?[]const u8, w: i32, h: i32, o: Options) Texture {
        var tex_id: glID = 0;
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, o.pixel_store_alignment);
        c.glGenTextures(1, &tex_id);
        c.glBindTexture(o.target, tex_id);
        c.glTexImage2D(
            o.target,
            0, //Level of detail number
            o.internal_format,
            w,
            h,
            0, //khronos.org: this value must be 0
            o.pixel_format,
            o.pixel_type,
            if (buffer) |bmp| &bmp[0] else null,
        );
        if (o.generate_mipmaps)
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

    pub fn initFromBitmap(bitmap: Bitmap, o: Options) Texture {
        return initFromBuffer(bitmap.data.items, @intCast(bitmap.w), @intCast(bitmap.h), o);
    }

    pub fn initEmpty() Texture {
        return .{ .w = 0, .h = 0, .id = 0 };
    }

    pub fn deinit(self: *Texture) void {
        c.glDeleteTextures(1, &self.id);
    }
};

pub const OptionalFileWriter = struct {
    writer: ?std.fs.File.Writer = null,

    pub fn print(self: *OptionalFileWriter, comptime fmt: []const u8, args: anytype) !void {
        if (self.writer) |wr| {
            try wr.print(fmt, args);
        }
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
    height: i32,
    ascent: f32, //Farthest the font ascends above baseline
    descent: f32, //Farthest the font descends below baseline
    line_gap: f32, //Distance between one rows descent and next rows ascent
    //to get next baseline: ascent - descent + line_gap
    max_advance: f32,

    texture: Texture,

    dpi: f32,

    const Self = @This();
    //const START_CHAR: usize = 32;
    const padding: i32 = 2;

    fn freetypeLogErr(stream: anytype, error_code: c_int) !void {
        if (error_code == 0)
            return;

        var found = false;
        inline for (c.ft_errors) |err| {
            if (err.err_code == error_code) {
                found = true;
                if (err.err_msg) |msg| {
                    stream.print("Freetype: Error {s}\n", .{msg}) catch return;
                }

                break;
            }
        }

        if (!found)
            stream.print("Freetype: Error code not found in table: {d}\n", .{error_code}) catch return;

        return error.freetype;
    }

    pub fn init(alloc: Alloc, dir: Dir, filename: []const u8, point_size: f32, dpi: u32, options: struct {
        codepoints_to_load: []const CharMapEntry = &(CharMaps.AsciiBasic),
        pack_factor: f32 = 1.3,
        debug_dir: ?Dir = null,
    }) !Self {
        const codepoints: []Glyph = blk: {
            var codepoint_list = std.ArrayList(Glyph).init(alloc);
            try codepoint_list.append(.{ .i = std.unicode.replacement_character });
            for (options.codepoints_to_load) |codepoint| {
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
            break :blk try codepoint_list.toOwnedSlice();
        };

        var log = OptionalFileWriter{};
        if (options.debug_dir) |ddir| {
            ddir.makeDir("debug") catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
            ddir.makeDir("debug/bitmaps") catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
            const font_log = try ddir.createFile("debug/fontgen.log", .{ .truncate = true });
            log.writer = font_log.writer();
            //defer font_log.close();
            try log.print("zig: Init font with arguments:\nfilename: \"{s}\"\npoint_size: {d}\ndpi: {d}\n", .{
                filename,
                point_size,
                dpi,
            });
            try log.print("px_size: {d}\n", .{point_size * (@as(f32, @floatFromInt(dpi)) / 72)});
        }
        var result = Font{
            .height = 0,
            .dpi = @as(f32, @floatFromInt(dpi)),
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

        const stderr = std.io.getStdErr().writer();

        var ftlib: c.FT_Library = undefined;
        try freetypeLogErr(stderr, c.FT_Init_FreeType(&ftlib));

        var face: c.FT_Face = undefined;
        {
            var path = std.ArrayList(u8).fromOwnedSlice(alloc, try dir.realpathAlloc(alloc, filename));
            defer path.deinit();
            try path.append(0);

            //FT_New_Face loads font file from filepathname
            //the face pointer should be destroyed with FT_Done_Face()
            {
                const err_code = c.FT_New_Face(ftlib, @as([*:0]const u8, @ptrCast(path.items)), 0, &face);
                switch (err_code) {
                    c.FT_Err_Cannot_Open_Resource => return error.fucked,
                    else => try freetypeLogErr(stderr, err_code),
                }
            }

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

            //const xw = face.*.max_advance_width

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
                @as(c_int, @intFromFloat(point_size)) * 64, //expects a size in 1/64 of points, font_size is in points
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
                try log.print("[{x} {u}] ", .{ charcode, @as(u21, @intCast(charcode)) });

                charcode = c.FT_Get_Next_Char(face, charcode, &agindex);
            }
            try log.print("\n", .{});
        }

        const fr = face.*;

        result.ascent = @as(f32, @floatFromInt(fr.size.*.metrics.ascender)) / 64;
        result.descent = @as(f32, @floatFromInt(fr.size.*.metrics.descender)) / 64;
        result.max_advance = @as(f32, @floatFromInt(fr.size.*.metrics.max_advance)) / 64;
        result.line_gap = @as(f32, @floatFromInt(fr.size.*.metrics.height)) / 64;
        result.height = @intFromFloat(result.ascent - result.descent);
        //result.line_gap = result.ascent;

        try log.print("Freetype face: ascender:  {d}px\n", .{result.ascent});
        try log.print("Freetype face: descender:  {d}px\n", .{result.descent});
        try log.print("Freetype face: line_gap:  {d}px\n", .{result.line_gap});
        try log.print("Freetype face: x_ppem: {d}px\n", .{@as(f32, @floatFromInt(fr.size.*.metrics.x_ppem))});
        try log.print("Freetype face: y_ppem: {d}px\n", .{@as(f32, @floatFromInt(fr.size.*.metrics.y_ppem))});

        var pack_ctx = RectPack.init(alloc);
        defer pack_ctx.deinit();

        var bitmaps = std.ArrayList(Bitmap).init(alloc);
        defer {
            for (bitmaps.items) |*bitmap|
                bitmap.deinit();
            bitmaps.deinit();
        }

        var timer = try std.time.Timer.start();
        for (result.glyph_set.dense.items) |*codepoint| {
            const glyph_i = c.FT_Get_Char_Index(face, codepoint.i);
            if (glyph_i == 0) {
                //std.debug.print("Undefined char index: {d} {x}\n", .{ codepoint.i, codepoint.i });
                continue;
            }

            try freetypeLogErr(stderr, c.FT_Load_Glyph(face, glyph_i, c.FT_LOAD_DEFAULT));
            try freetypeLogErr(stderr, c.FT_Render_Glyph(face.*.glyph, c.FT_RENDER_MODE_NORMAL));
            //freetypeLogErr(stderr, c.FT_Render_Glyph(face.*.glyph, c.FT_RENDER_MODE_LCD));

            const bitmap = &(face.*.glyph.*.bitmap);

            if (bitmap.width != 0 and bitmap.rows != 0) {
                if (options.debug_dir != null) {
                    var buf: [255]u8 = undefined;
                    var fbs = std.io.FixedBufferStream([]u8){ .buffer = &buf, .pos = 0 };
                    try fbs.writer().print("debug/bitmaps/{d}.bmp", .{glyph_i});
                    try fbs.writer().writeByte(0);
                    _ = c.stbi_write_bmp(
                        @as([*c]const u8, @ptrCast(fbs.getWritten())),
                        @as(c_int, @intCast(bitmap.width)),
                        @as(c_int, @intCast(bitmap.rows)),
                        1,
                        @as([*c]u8, @ptrCast(bitmap.buffer[0 .. bitmap.rows * bitmap.width])),
                    );
                }
                try bitmaps.append(try Bitmap.initFromBuffer(alloc, bitmap.buffer[0 .. bitmap.width * bitmap.rows], bitmap.width, bitmap.rows, .g_8));

                try pack_ctx.appendRect(codepoint.i, bitmap.width + padding + padding, bitmap.rows + padding + padding);
            }
            const metrics = &face.*.glyph.*.metrics;
            {
                const g: u21 = @intCast(codepoint.i);
                try log.print("Freetype glyph: {u} 0x{x}\n", .{ g, g });
                try log.print("\twidth:  {d} (1/64 px), {d} px\n", .{ metrics.width, @divFloor(metrics.width, 64) });
                try log.print("\theight: {d} (1/64 px), {d} px\n", .{ metrics.height, @divFloor(metrics.height, 64) });
                try log.print("\tbearingX: {d} (1/64 px), {d} px\n", .{ metrics.horiBearingX, @divFloor(metrics.horiBearingX, 64) });
                try log.print("\tbearingY: {d} (1/64 px), {d} px\n", .{ metrics.horiBearingY, @divFloor(metrics.horiBearingY, 64) });
                try log.print("\tadvance: {d} (1/64 px), {d} px\n", .{ metrics.horiAdvance, @divFloor(metrics.horiAdvance, 64) });
                //try log.print("\twidth: {d}\n", .{metrics.width});
            }

            const fpad = @as(f32, @floatFromInt(padding));
            var glyph = Glyph{
                .tr = .{ .x = -1, .y = -1, .w = @as(f32, @floatFromInt(bitmap.width)) + fpad, .h = @as(f32, @floatFromInt(bitmap.rows)) + fpad },
                .offset_x = @as(f32, @floatFromInt(metrics.horiBearingX)) / 64,
                .offset_y = @as(f32, @floatFromInt(metrics.horiBearingY)) / 64,
                .advance_x = @as(f32, @floatFromInt(metrics.horiAdvance)) / 64,
                .width = @as(f32, @floatFromInt(metrics.width)) / 64,
                .height = @as(f32, @floatFromInt(metrics.height)) / 64,
                .i = codepoint.i,
            };
            codepoint.* = glyph;
        }

        const elapsed = timer.read();
        try log.print("Rendered {d} glyphs in {d} ms, {d} ms avg\n", .{ result.glyph_set.dense.items.len, @as(f32, @floatFromInt(elapsed)) / std.time.ns_per_ms, @as(f32, @floatFromInt(elapsed)) / std.time.ns_per_ms / @as(f32, @floatFromInt(result.glyph_set.dense.items.len)) });
        if (false) {
            var num_pixels: usize = 0;
            for (pack_ctx.rects.items) |r| {
                num_pixels += (@as(usize, @intCast(r.w)) * @as(usize, @intCast(r.h)));
            }
            result.texture.w = @as(i32, @intFromFloat(@sqrt(@as(f32, @floatFromInt(num_pixels)) * options.pack_factor)));
            result.texture.h = @as(i32, @intFromFloat(@sqrt(@as(f32, @floatFromInt(num_pixels)) * options.pack_factor)));
            try log.print("Texture size: {d} x {d}\n", .{ result.texture.w, result.texture.h });

            try pack_ctx.pack(@intCast(result.texture.w), @intCast(result.texture.h));

            {
                var texture_bitmap = try Bitmap.initBlank(alloc, result.texture.w, result.texture.h, .g_8);
                defer texture_bitmap.deinit();

                for (pack_ctx.rects.items, 0..) |rect, i| {
                    const g = try result.glyph_set.getPtr(@as(u21, @intCast(rect.id)));
                    g.tr.x = @as(f32, @floatFromInt(@as(u32, @intCast(rect.x)) + padding)) - @as(f32, @floatFromInt(padding)) / 2;
                    g.tr.y = @as(f32, @floatFromInt(@as(u32, @intCast(rect.y)) + padding)) - @as(f32, @floatFromInt(padding)) / 2;
                    const bitmap = &bitmaps.items[i];
                    if (bitmap.data.items.len > 0) {
                        var row: usize = 0;
                        var col: usize = 0;
                        while (row < rect.h) : (row += 1) {
                            while (col < rect.w) : (col += 1) {
                                if (row < bitmap.h + padding and col < bitmap.w + padding and row >= padding and col >= padding) {
                                    const dat = bitmap.data.items[((row - padding) * bitmap.w) + col - padding];
                                    texture_bitmap.data.items[(@as(u32, @intCast(result.texture.w)) * (row + @as(usize, @intCast(rect.y)))) + col + @as(usize, @intCast(rect.x))] = dat;
                                } else {
                                    texture_bitmap.data.items[(@as(u32, @intCast(result.texture.h)) * (row + @as(usize, @intCast(rect.y)))) + col + @as(usize, @intCast(rect.x))] = 0;
                                }
                            }
                            col = 0;
                        }
                    }
                }

                if (options.debug_dir) |ddir|
                    try texture_bitmap.writeToPngFile(ddir, "debug/freetype.png");

                result.texture = Texture.initFromBitmap(texture_bitmap, .{
                    .pixel_store_alignment = 1,
                    .internal_format = c.GL_RED,
                    .pixel_format = c.GL_RED,
                    .min_filter = c.GL_LINEAR,
                    .mag_filter = c.GL_LINEAR,
                });
            }
        } else {
            //Each glyph takes up result.max_advance x result.line_gap + padding
            const w_c: i32 = @intFromFloat(@ceil(@sqrt(@as(f32, @floatFromInt(pack_ctx.rects.items.len)))));
            const g_width: i32 = @intFromFloat(result.max_advance);
            const g_height = result.height;
            result.texture.w = w_c * (padding + @as(i32, @intFromFloat(result.max_advance)));
            result.texture.h = w_c * (padding + g_height);
            var texture_bitmap = try Bitmap.initBlank(alloc, result.texture.w, result.texture.h, .g_8);
            defer texture_bitmap.deinit();

            //var xi:u32 = 0;
            //var yi:u32 = 0;
            const w_ci: i32 = @intCast(w_c);
            for (pack_ctx.rects.items, 0..) |rect, i| {
                const ii: i32 = @intCast(i);
                const gbmp = &bitmaps.items[i];
                const cx: u32 = @intCast(@mod(ii, w_ci) * (g_width + padding));
                const cy: u32 = @intCast(@divFloor(ii, w_ci) * (g_height + padding));
                const g = try result.glyph_set.getPtr(@as(u21, @intCast(rect.id)));
                g.tr.x = @floatFromInt(cx);
                g.tr.y = @floatFromInt(cy);
                Bitmap.copySubR(1, &texture_bitmap, cx, cy, gbmp, 0, 0, gbmp.w, gbmp.h);
            }
            if (options.debug_dir) |ddir| {
                try texture_bitmap.writeToPngFile(ddir, "debug/freetype.png");
            }

            result.texture = Texture.initFromBitmap(texture_bitmap, .{
                .pixel_store_alignment = 1,
                .internal_format = c.GL_RED,
                .pixel_format = c.GL_RED,
                .min_filter = c.GL_LINEAR,
                .mag_filter = c.GL_LINEAR,
            });
        }

        return result;
    }

    pub fn nearestGlyphX(self: *Self, string: []const u8, size_px: f32, rel_coord: Vec2f) ?usize {
        //const scale = (size_px / self.dpi * 72) / self.font_size;
        const scale = size_px / @as(f32, @floatFromInt(self.height));

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
                    //const y = rel_coord.y;
                    //if (x < x_bound + xw and x > x_bound and y < bounds.y + yw and y > bounds.y) {
                    if (x < x_bound + xw and x > x_bound) {
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

    pub fn textBounds(self: *Self, string: []const u8, size_px: anytype) Vec2f {
        //const scale = (lcast(f32, size_px) / self.dpi * 72) / self.font_size;
        const scale = size_px / @as(f32, @floatFromInt(self.height));

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
        return @as(f32, @floatFromInt(coord)) / @as(f32, @floatFromInt(self.texture_size));
    }
};

const AvgBuf = struct {
    const Self = @This();
    const len = 100;

    pos: u32 = 0,
    buf: [len]f32 = .{0} ** len,

    fn insert(self: *Self, val: f32) void {
        self.buf[self.pos] = val;
        self.pos = (self.pos + 1) % @as(u32, @intCast(self.buf.len));
    }

    fn avg(self: *Self) f32 {
        var res: f32 = 0;
        for (self.buf) |it| {
            res += it;
        }
        return res / @as(f32, @floatFromInt(self.buf.len));
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

//TODO I want to destroy GraphicsContext
//What projects are using it?
//What is NewCtx missing:
//  Multiple font support
//  a few draw functions
//  a few utility functions, flush(), setviewport()
//
//Projects:
//  Gui
//  mario
pub const GraphicsContext = struct {
    const Self = @This();
    const do_debug_batch_size: bool = true;
    pub var debug_batch_size: usize = 0;

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
    alloc: Alloc,

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

    pub fn init(alloc: Alloc, dpi: f32) !Self {
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
        c.glViewport(0, 0, screen_w, screen_h);
        self.call_count = 0;
        self.fps_time = self.fps_timer.read();
        self.fpsavg.insert(std.time.ns_per_s / @as(f32, @floatFromInt(self.fps_time)));
        self.fps_timer.reset();
        //self.last_memcpy_time = self.memcpy_time;
        self.memcpy_time = 1; //prevent divide by zero with 1ns

        if (false) {
            const desired_frametime = @as(u64, @intFromFloat((1.0 / 63.0) * @as(f32, @floatFromInt(std.time.ns_per_s))));
            if (self.last_frame_time < desired_frametime) {
                std.time.sleep(desired_frametime - self.last_frame_time);
            }
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

    pub fn setViewport(self: *Self, vo: ?Rect) void {
        const sb = self.screen_bounds.toF32();
        if (vo) |v| {
            c.glViewport(
                @as(i32, @intFromFloat(v.x)),
                @as(i32, @intFromFloat(sb.h - (v.y + v.h))),
                @as(i32, @intFromFloat(v.w)),
                @as(i32, @intFromFloat(v.h)),
            );
        } else {
            self.setViewport(sb);
        }
    }

    pub fn flush(self: *Self, offset: Vec2f, custom_camera: ?Rect) !void {
        const camera_bounds = if (custom_camera) |cc| cc else self.screen_bounds.toF32();

        if (do_debug_batch_size) {
            for (self.batches.items) |batch| {
                debug_batch_size += switch (batch) {
                    .TriTex => @sizeOf(VertexTextured) * batch.TriTex.vertices.items.len + batch.TriTex.indicies.items.len * 4,
                    .Tri => @sizeOf(Vertex) * batch.Tri.vertices.items.len + batch.Tri.indicies.items.len * 4,
                    else => 0,
                };
            }
        }

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

        self.flush(.{ .x = 0, .y = 0 }, custom_camera) catch unreachable;
        //for (self.batches.items) |*batch| {
        //    switch (batch.*) {
        //        .TriTex => {},
        //        else => batch.draw(camera_bounds, .{ .x = 0, .y = 0 }, self.colored_tri_shader, self.tex_shad),
        //    }
        //}
        //for (self.batches.items) |*batch| {
        //    switch (batch.*) {
        //        .TriTex => batch.draw(camera_bounds, .{ .x = 0, .y = 0 }, self.colored_tri_shader, self.tex_shad),
        //        else => {},
        //    }
        //}
        //self.call_count += self.batches.items.len;
        self.call_count += 1;

        if (draw_time) |*dt|
            self.draw_time = dt.read();

        self.last_frame_time = self.frame_timer.read();
        self.lftavg.insert(1.0 / (std.time.ns_per_us / @as(f32, @floatFromInt(self.last_frame_time))));
        self.last_memcpy_time = self.memcpy_time;
    }

    pub fn drawFPS(self: *Self, x: f32, y: f32, font: *Font) void {
        {
            var buf: [70]u8 = undefined;
            var fbs = std.io.FixedBufferStream([]u8){ .buffer = buf[0..], .pos = 0 };
            fbs.writer().print("FPS: {d}\nFT: {d}us\nDT: {d}us\nMPT: {d}", .{
                //fbs.writer().print("FPS: {d}\nFT: {d}us", .{
                @as(i32, @intFromFloat(std.time.ns_per_s / @as(f32, @floatFromInt(self.fps_time)) / 10)) * 10,
                //@floatToInt(i32, self.fpsavg.avg() / 10) * 10,
                @as(i32, @intFromFloat(1.0 / (std.time.ns_per_us / @as(f32, @floatFromInt(self.last_frame_time))) / 100)) * 100,
                //@floatToInt(i32, self.lftavg.avg()),
                @as(i32, @intFromFloat(1.0 / (std.time.ns_per_us / @as(f32, @floatFromInt(self.draw_time))))),
                @as(i32, @intFromFloat(1.0 / (std.time.ns_per_us / @as(f64, @floatFromInt(self.last_memcpy_time))))),
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
            try b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len))));
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
        b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(index)))) catch {
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
        b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(index)))) catch {
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
        try b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(index))));
        self.z_st += 0.1;

        self.memcpy_time += timer.read();
    }

    pub fn drawFixedBitmapText(self: *Self, x: f32, y: f32, h: f32, str: []const u8, font: FixedBitmapFont, col: CharColor) !void {
        const batch = (try self.getBatch(.{ .mode = .triangles, .texture = font.texture.id, .shader = self.tex_shad }));
        const b = &batch.TriTex;

        var i: u32 = 0;
        for (str) |char| {
            if (char == ' ' or char == '_') {
                i += 1;
                continue;
            }

            const ind = font.translation_table[std.ascii.toUpper(char)];
            const fi = @as(f32, @floatFromInt(i));
            try b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len))));
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

    pub fn drawTextFmt(self: *Self, x: f32, y: f32, comptime fmt: []const u8, args: anytype, font: *Font, size: anytype, col: CharColor) void {
        var buf: [256]u8 = undefined;
        var fbs = std.io.FixedBufferStream([]u8){ .pos = 0, .buffer = &buf };
        fbs.writer().print(fmt, args) catch unreachable;
        const slice = fbs.getWritten();
        self.drawText(x, y, slice, font, lcast(f32, size), col);
    }

    pub fn draw9Border(self: *Self, r: Rect, tr: Rect, texture: Texture, scale: f32, cutout_start: f32, cutout_end: f32) !void {
        //Similar to a 9 slice but we don't draw the center and draw two halves for the top middle peice.
        //This creates a cutout to put a text label

        const W = CharColor.White;
        const w: f32 = tr.w / 3;
        const h: f32 = tr.h / 3;
        const sw = w * scale;
        const sh = h * scale;

        const t = Rect.new(tr.x, tr.y, w, h);

        try self.drawRectTex(Rect.newV(r.pos(), .{ .x = sw, .y = sh }), t, W, texture);

        //Cutout lines:
        try self.drawRectTex(Rect.new(r.x + sw, r.y, cutout_start, sh), t.addV(w, 0), W, texture);
        try self.drawRectTex(Rect.new(r.x + sw + cutout_end, r.y, r.w - sw - cutout_end, sh), t.addV(w, 0), W, texture);

        //try self.drawRectTex(Rect.new(r.x + sw, r.y, r.w - sw * 2, sh), t.addV(w, 0), W, texture);
        try self.drawRectTex(Rect.new(r.x + r.w - sw, r.y, sw, sh), t.addV(w * 2, 0), W, texture);

        const mh = r.h - sh * 2;
        try self.drawRectTex(Rect.new(r.x, r.y + sh, sw, mh), t.addV(0, h), W, texture);
        //try self.drawRectTex(Rect.new(r.x + sw, r.y + sh, r.w - sw * 2, mh), t.addV(w, h), W, texture);
        try self.drawRectTex(Rect.new(r.x + r.w - sw, r.y + sh, sw, mh), t.addV(w * 2, h), W, texture);

        const yy = r.y + r.h - sh;
        try self.drawRectTex(Rect.new(r.x, yy, sw, sh), t.addV(0, h * 2), W, texture);
        try self.drawRectTex(Rect.new(r.x + sw, yy, r.w - sw * 2, sh), t.addV(w, h * 2), W, texture);
        try self.drawRectTex(Rect.new(r.x + r.w - sw, yy, sw, sh), t.addV(w * 2, h * 2), W, texture);
    }

    pub fn draw9Slice(self: *Self, r: Rect, tr: Rect, texture: Texture, scale: f32) !void {
        const W = CharColor.White;
        const w: f32 = tr.w / 3;
        const h: f32 = tr.h / 3;
        const sw = w * scale;
        const sh = h * scale;

        const xv = [4]f32{ r.x, r.x + w, r.x + r.w - w, r.x + r.w };
        const yv = [4]f32{ r.y, r.y + h, r.y + r.h - h, r.y + r.h };
        const x_uv = [4]f32{ 0, w, w * 2, w * 3 };
        const y_uv = [4]f32{ 0, h, h * 2, h * 3 };
        _ = yv;
        _ = xv;
        _ = x_uv;
        _ = y_uv;
        //TODO draw this more efficently by exploiting the common verts
        //A vertex is 9 * 4 bytes = 36
        //Naive implementation uses 9 rects or 36 verts and 54 indices, (36 * 36) bytes + 4 * 54, 1512 bytes
        //Using 16 common verts: (16 * 36) + 54 * 4 = 792. Almost half reduction
        //
        //Newctx uses 22bytes per vertex. 568 bytes per, 2.66 times smaller.
        //In theory we could get it to 10 bytes per vertex. so 160 + 216 = 376 bytes per 9slice
        //if we limit ourselves to a 16bit index. 108 + 160 268 bytes. 5.68 times smaller
        const t = Rect.new(tr.x, tr.y, w, h);

        try self.drawRectTex(Rect.newV(r.pos(), .{ .x = sw, .y = sh }), t, W, texture);
        try self.drawRectTex(Rect.new(r.x + sw, r.y, r.w - sw * 2, sh), t.addV(w, 0), W, texture);
        try self.drawRectTex(Rect.new(r.x + r.w - sw, r.y, sw, sh), t.addV(w * 2, 0), W, texture);

        const mh = r.h - sh * 2;
        try self.drawRectTex(Rect.new(r.x, r.y + sh, sw, mh), t.addV(0, h), W, texture);
        try self.drawRectTex(Rect.new(r.x + sw, r.y + sh, r.w - sw * 2, mh), t.addV(w, h), W, texture);
        try self.drawRectTex(Rect.new(r.x + r.w - sw, r.y + sh, sw, mh), t.addV(w * 2, h), W, texture);

        const yy = r.y + r.h - sh;
        try self.drawRectTex(Rect.new(r.x, yy, sw, sh), t.addV(0, h * 2), W, texture);
        try self.drawRectTex(Rect.new(r.x + sw, yy, r.w - sw * 2, sh), t.addV(w, h * 2), W, texture);
        try self.drawRectTex(Rect.new(r.x + r.w - sw, yy, sw, sh), t.addV(w * 2, h * 2), W, texture);
    }

    //TODO Split this off into a function that draws a single unicode codepoint
    //TODO have a function that takes pts and one that takes pixels,(this one takes pixels)
    pub fn drawText(self: *Self, x: f32, y: f32, str: []const u8, font: *Font, size: f32, col: CharColor) void {
        const fh: f32 = @floatFromInt(font.height);
        const SF = size / @as(f32, @floatFromInt(font.height));
        //const SF = (size / self.dpi * 72) / font.font_size;
        const fac = 1;

        const batch = (self.getBatch(.{ .mode = .triangles, .texture = font.texture.id, .shader = self.font_shad }) catch unreachable);
        const b = &batch.TriTex;

        b.vertices.ensureUnusedCapacity(str.len * 4) catch unreachable;
        b.indicies.ensureUnusedCapacity(str.len * 6) catch unreachable;

        var it = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };

        var vx = x * fac;
        var vy = y + (font.ascent * SF);
        var cho = it.nextCodepoint();
        while (cho != null) : (cho = it.nextCodepoint()) {
            const ch = cho orelse unreachable;
            switch (ch) {
                '\t' => {
                    vx += 4 * font.max_advance * SF;
                    continue;
                },
                '\n' => {
                    vy += fh * SF;
                    vx = x * fac;
                    continue;
                },
                else => {},
            }

            //if (ch < Font.START_CHAR)
            //continue;
            //const g_i = ch - Font.START_CHAR;
            //const g = font.glyphs.items[g_i];
            const g = font.glyph_set.get(ch) catch |err|
                switch (err) {
                error.invalidIndex => font.glyph_set.get(std.unicode.replacement_character) catch unreachable,
            };
            if (ch == ' ') {
                vx += g.advance_x * SF;
                continue;
            }
            const fpad = @as(f32, @floatFromInt(Font.padding)) / 2;
            const pad = @as(f32, @floatFromInt(Font.padding));

            const r = Rect{
                .x = vx + (g.offset_x - fpad) * SF,
                .y = vy - (g.offset_y + fpad) * SF,
                .w = (pad + g.width) * SF,
                .h = (pad + g.height) * SF,
            };

            var timer = std.time.Timer.start() catch unreachable;
            const index = b.vertices.items.len;
            b.vertices.appendSlice(&createQuadTextured(r, self.z_st, g.tr, font.texture.w, font.texture.h, charColorToFloat(col))) catch unreachable;
            b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(index)))) catch unreachable;
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
            const ratio_inc: f32 = 1.0 / @as(f32, @floatFromInt(steps));

            var last_point = a;

            var i: u32 = 1;
            while (i <= steps) : (i += 1) {
                const rat = ratio_inc * @as(f32, @floatFromInt(i));
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
                const vx = r * @cos(@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps)) * std.math.tau);
                const vy = r * @sin(@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps)) * std.math.tau);
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

pub const VertexTextured = packed struct { x: f32, y: f32, z: f32, u: f32, v: f32, r: f32, g: f32, b: f32, a: f32 };
pub const Vertex = packed struct { x: f32, y: f32, z: f32, r: f32, g: f32, b: f32, a: f32 };

pub fn vertex(x: f32, y: f32, z: f32, col: Color) Vertex {
    return .{ .x = x, .y = y, .z = z, .r = col[0], .g = col[1], .b = col[2], .a = col[3] };
}

pub fn vertexTextured(x: f32, y: f32, z: f32, u: f32, v: f32, col: Color) VertexTextured {
    return .{ .x = x, .y = y, .z = z, .u = u, .v = v, .r = col[0], .g = col[1], .b = col[2], .a = col[3] };
}

//TODO destroy this
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

    pub fn init(alloc: Alloc) @This() {
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
        try self.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(self.vertices.items.len))));
        try self.vertices.appendSlice(&.{
            Vert{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .color = color },
            Vert{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .color = color },
            Vert{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .color = color },
            Vert{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .color = color },
        });
    }

    pub fn draw(b: *Self, screenw: i32, screenh: i32) void {
        const view = za.orthographic(0, @as(f32, @floatFromInt(screenw)), @as(f32, @floatFromInt(screenh)), 0, -100000, 1);

        //c.glViewport(0, 0, screenw, screenh);
        const model = za.Mat4.identity();
        c.glUseProgram(b.shader);
        c.glBindVertexArray(b.vao);
        GL.bufferData(c.GL_ARRAY_BUFFER, b.vbo, Vert, b.vertices.items);
        GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, b.ebo, u32, b.indicies.items);

        GL.passUniform(b.shader, "view", view);
        GL.passUniform(b.shader, "model", model);

        c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(b.indicies.items.len)), c.GL_UNSIGNED_INT, null);
        c.glBindVertexArray(0);
    }
};

pub const Cubes = struct {
    const Self = @This();
    vertices: std.ArrayList(VertexTextured),
    indicies: std.ArrayList(u32),

    shader: glID,
    texture: Texture,
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

        c.glBindTexture(c.GL_TEXTURE_2D, b.texture.id);

        GL.passUniform(b.shader, "view", view);
        GL.passUniform(b.shader, "model", model);

        c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(b.indicies.items.len)), c.GL_UNSIGNED_INT, null);
    }

    pub fn init(alloc: Alloc, texture: Texture, shader: glID) @This() {
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

    //pub fn shaded_cube(self: *Self, pos: Vec3f, extents: Vec3f, tr: Rect) !void {
    //    const p = pos;
    //    const e = extents;
    //    const white = charColorToFloat(itc(0xffffffff));
    //    const u = normalizeTexRect(tr, @as(i32, @intCast(self.texture.w)), @as(i32, @intCast(self.texture.h)));
    //    try self.vertices.appendSlice(&.{
    //        vertexTextured(p.x, p.y, p.z, u.x, u.y, white),
    //        vertexTextured(p.x, p.y, p.z + e.z, u.x, u.y, white),
    //    });
    //}

    pub fn cube(self: *Self, px: f32, py: f32, pz: f32, sx: f32, sy: f32, sz: f32, tr: Rect, colorsopt: ?[]const CharColor) !void {
        const tx_w = self.texture.w;
        const tx_h = self.texture.h;
        const colors = if (colorsopt) |cc| cc else &[6]CharColor{
            itc(0x888888ff), //Front
            itc(0x888888ff), //Back
            itc(0x666666ff), //Bottom
            itc(0xffffffff), //Top
            itc(0xaaaaaaff),
            itc(0xaaaaaaff),
        };
        const un = normalizeTexRect(tr, @as(i32, @intCast(tx_w)), @as(i32, @intCast(tx_h)));
        try self.indicies.appendSlice(&genCubeIndicies(@as(u32, @intCast(self.vertices.items.len))));
        // zig fmt: off
        try self.vertices.appendSlice(&.{
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


        });
    // zig fmt: on

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

    pub fn init(alloc: Alloc, texture: glID, shader: glID) @This() {
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

    pub fn init(alloc: Alloc, shader: glID) @This() {
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

    pub fn init(alloc: Alloc, shader: glID) @This() {
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
        const vb = view_bounds;
        const view = za.orthographic(vb.x, vb.x + vb.w, vb.h + vb.y, vb.y, -10000, 1);
        //const view = za.orthographic(
        //    view_bounds.x,
        //    view_bounds.w,
        //    view_bounds.h,
        //    view_bounds.y,
        //    -100000,
        //    1,
        //);
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

                c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(b.indicies.items.len)), c.GL_UNSIGNED_INT, null);
            },
            .Line => |*b| {
                c.glUseProgram(shader_program);
                c.glBindVertexArray(b.vao);
                GL.bufferData(c.GL_ARRAY_BUFFER, b.vbo, Vertex, b.vertices.items);

                GL.passUniform(b.shader, "view", view);
                GL.passUniform(b.shader, "model", model);

                //c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, b.indicies.items.len), c.GL_UNSIGNED_INT, null);
                c.glDrawArrays(c.GL_LINES, 0, @as(c_int, @intCast(b.vertices.items.len)));
            },
            //else => {
            //    std.debug.print("Batch draw not implemented!\n", .{});
            //},
        }
    }
};

pub const BindType = [2][]const u8;
pub const BindList = []const BindType;

///Takes a list of bindings{"name", "key_name"} and generates an enum
///can be used with BindingMap and a switch() to map key input events to actions
pub fn GenerateBindingEnum(comptime map: BindList) type {
    const TypeInfo = std.builtin.Type;
    var fields: [map.len + 1]TypeInfo.EnumField = undefined;

    inline for (map, 0..) |bind, b_i| {
        fields[b_i] = .{ .name = bind[0], .value = b_i };
    }
    fields[map.len] = .{ .name = "no_action", .value = map.len };
    return @Type(TypeInfo{ .Enum = .{
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

        scancode_table: [@intFromEnum(keycodes.Scancode.ODES)]bind_enum,
        bind_table: [map.len]keycodes.Scancode,

        pub fn init() @This() {
            var ret: @This() = undefined;

            for (&ret.scancode_table) |*item|
                item.* = .no_action;

            for (map, 0..) |bind, i| {
                var buffer: [256]u8 = undefined;
                //if (bind.len >= buffer.len)
                //    @compileError("Keybinding name to long");

                std.mem.copy(u8, buffer[0..], bind[1]);
                buffer[bind[1].len] = 0;

                const sc = c.SDL_GetScancodeFromName(&buffer[0]);
                //if (sc == c.SDL_SCANCODE_UNKNOWN) @compileError("Unknown scancode");
                ret.scancode_table[sc] = @as(bind_enum, @enumFromInt(i));
                ret.bind_table[i] = @as(keycodes.Scancode, @enumFromInt(sc));
            }

            return ret;
        }

        pub fn getScancode(self: *const @This(), key: bind_enum) keycodes.Scancode {
            return self.bind_table[@intFromEnum(key)];
        }

        pub fn get(self: *const @This(), scancode: keycodes.Scancode) bind_enum {
            return self.scancode_table[@intFromEnum(scancode)];
        }

        //pub fn draw(self: *const Self, ctx: *NewCtx)
    };
}
