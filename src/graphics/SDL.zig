const std = @import("std");
const ptypes = @import("types.zig");
const Vec2f = ptypes.Vec2f;
const Vec2i = ptypes.Vec2i;
const c = @import("c.zig");
pub const glID = c.GLuint;
pub const keycodes = @import("keycodes.zig");

fn reduceU32Mask(items: []const u32) u32 {
    var result: u32 = 0;
    for (items) |item| {
        result |= item;
    }
    return result;
}

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
    pub const KeyStateT = [c.SDL_NUM_SCANCODES]ButtonState;
    pub const EmptyKeyState: KeyStateT = [_]ButtonState{.low} ** c.SDL_NUM_SCANCODES;

    win: *c.SDL_Window,
    ctx: *anyopaque,

    screen_dimensions: Vec2i = .{ .x = 0, .y = 0 },

    should_exit: bool = false,

    mouse: MouseState = undefined,

    //key_state: [c.SDL_NUM_SCANCODES]ButtonState = [_]ButtonState{.low} ** c.SDL_NUM_SCANCODES,
    key_state: KeyStateT = [_]ButtonState{.low} ** c.SDL_NUM_SCANCODES,
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
        c.glViewport(0, 0, self.screen_dimensions.x, self.screen_dimensions.y);
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

    pub fn rect(self: *const Self) ptypes.Rect {
        return ptypes.Rect.NewAny(0, 0, self.screen_dimensions.x, self.screen_dimensions.y);
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

pub fn Bind(comptime map: BindList) type {
    return struct {
        const Self = @This();
        pub const Map = map;
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

        pub fn heldIterator(self: *const @This(), win: *const Window) struct {
            win: *const Window,
            parent: *const Self,
            index: usize = 0,
            pub fn next(it: *@This()) ?bind_enum {
                if (it.index == it.parent.bind_table.len)
                    return null;
                const sc = it.parent.bind_table[it.index];
                if (it.win.keydown(sc)) {
                    defer it.index += 1;
                    return @enumFromInt(it.index);
                }
                it.index += 1;
                return it.next();
            }
        } {
            return .{
                .win = win,
                .parent = self,
                .index = 0,
            };
        }
    };
}
