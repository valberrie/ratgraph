const std = @import("std");
const graph = @import("graphics.zig");
const gui = @import("gui.zig");
const V2f = graph.Vec2f;

const pow = std.math.pow;
const sqrt = std.math.sqrt;

const gui_app = @import("gui_app.zig");

threadlocal var lua_draw: *LuaDraw = undefined;
const LuaDraw = struct {
    const Lua = graph.Lua;

    draw: *graph.ImmediateDrawingContext,
    win: *graph.SDL.Window,
    font: *graph.Font,
    vm: *Lua,
    clear_color: u32 = 0xff,

    data: Data,
    pub const Data = struct {
        name_scancode_map: std.StringHashMap(graph.SDL.keycodes.Scancode),
        tex_map: std.ArrayList(graph.Texture),
        alloc: std.mem.Allocator,
        pub fn init(alloc: std.mem.Allocator) !@This() {
            var m = std.StringHashMap(graph.SDL.keycodes.Scancode).init(alloc);
            inline for (@typeInfo(graph.SDL.keycodes.Scancode).Enum.fields) |f| {
                try m.put(f.name, @enumFromInt(f.value));
            }

            return .{
                .tex_map = std.ArrayList(graph.Texture).init(alloc),
                .name_scancode_map = m,
                .alloc = alloc,
            };
        }
        pub fn deinit(self: *@This()) void {
            self.name_scancode_map.deinit();
            self.tex_map.deinit();
        }
    };

    pub const Api = struct {
        pub export fn loadTexture(L: Lua.Ls) c_int {
            const self = lua_draw;
            Lua.c.lua_settop(L, 1);
            const str = self.vm.getArg(L, []const u8, 1);
            const id = self.data.tex_map.items.len;
            self.data.tex_map.append(graph.Texture.initFromImgFile(
                self.data.alloc,
                std.fs.cwd(),
                str,
                .{},
            ) catch return 0) catch return 0;

            Lua.pushV(L, id);
            return 1;
        }

        pub export fn setBgColor(L: Lua.Ls) c_int {
            const self = lua_draw;
            const num_args = Lua.c.lua_gettop(L);
            self.clear_color = blk: {
                switch (num_args) {
                    4 => {
                        const r = self.vm.getArg(L, u8, 1);
                        const g = self.vm.getArg(L, u8, 2);
                        const b = self.vm.getArg(L, u8, 3);
                        const a = self.vm.getArg(L, u8, 4);
                        break :blk graph.ptypes.charColorToInt(graph.CharColor.new(r, g, b, a));
                    },
                    1 => {
                        if (Lua.c.lua_isinteger(L, 1) == 1) {
                            break :blk self.vm.getArg(L, u32, 1);
                        } else {
                            const color_name = self.vm.getArg(L, []const u8, 1);
                            const cinfo = @typeInfo(graph.Colori);
                            inline for (cinfo.Struct.decls) |d| {
                                if (std.mem.eql(u8, d.name, color_name)) {
                                    break :blk @field(graph.Colori, d.name);
                                }
                            }
                            _ = Lua.c.luaL_error(L, "unknown color");
                            return 0;
                        }
                    },
                    else => {
                        _ = Lua.c.luaL_error(L, "invalid arguments");
                        return 0;
                    },
                }
            };
            return 0;
        }

        pub export fn text(L: Lua.Ls) c_int {
            const self = lua_draw;
            const x = self.vm.getArg(L, graph.Vec2f, 1);
            //const y = self.vm.getArg(L, f32, 2);
            const str = self.vm.getArg(L, []const u8, 2);
            const sz = self.vm.getArg(L, f32, 3);
            self.draw.text(x, str, self.font, sz, 0xffffffff);
            return 0;
        }

        pub export fn mousePos(L: Lua.Ls) c_int {
            const self = lua_draw;
            Lua.pushV(L, self.win.mouse.pos);
            return 1;
        }

        pub export fn getScreenSize(L: Lua.Ls) c_int {
            const self = lua_draw;
            Lua.pushV(L, self.win.screen_dimensions);
            return 1;
        }

        pub export fn keydown(L: Lua.Ls) c_int {
            const self = lua_draw;
            Lua.c.lua_settop(L, 1);
            const str = self.vm.getArg(L, []const u8, 1);
            if (self.data.name_scancode_map.get(str)) |v| {
                Lua.pushV(L, self.win.keydown(v));
                return 1;
            }
            _ = Lua.c.luaL_error(L, "Unknown key");
            return 0;
        }

        pub export fn rectTex(L: Lua.Ls) c_int {
            const self = lua_draw;
            const r: graph.Rect = blk: {
                if (Lua.c.lua_istable(L, 1)) {
                    defer Lua.c.lua_remove(L, 1);
                    break :blk self.vm.getArg(L, graph.Rect, 1);
                } else {
                    const x = self.vm.getArg(L, f32, 1);
                    const y = self.vm.getArg(L, f32, 2);
                    const w = self.vm.getArg(L, f32, 3);
                    const h = self.vm.getArg(L, f32, 4);
                    Lua.c.lua_remove(L, 1);
                    Lua.c.lua_remove(L, 2);
                    Lua.c.lua_remove(L, 3);
                    Lua.c.lua_remove(L, 4);
                    break :blk graph.Rect.new(x, y, w, h);
                }
            };
            const id = self.vm.getArg(L, u32, 1);

            const tex = self.data.tex_map.items[@intCast(id)];
            self.draw.rectTex(
                r,
                tex.rect(),
                tex,
            );
            return 0;
        }

        pub export fn rect(L: Lua.Ls) c_int {
            const self = lua_draw;
            const r: graph.Rect = blk: {
                if (Lua.c.lua_istable(L, 1)) {
                    break :blk self.vm.getArg(L, graph.Rect, 1);
                } else {
                    const x = self.vm.getArg(L, f32, 1);
                    const y = self.vm.getArg(L, f32, 2);
                    const w = self.vm.getArg(L, f32, 3);
                    const h = self.vm.getArg(L, f32, 4);
                    break :blk graph.Rect.new(x, y, w, h);
                }
            };

            self.draw.rect(r, 0xffffffff);
            return 0;
        }
    };
};

pub fn main() !void {
    if (true) {
        try gui_app.main();
        return;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    var win = try graph.SDL.Window.createWindow("zig-game-engine", .{});
    defer win.destroyWindow();

    const init_size = 72;
    var font = try graph.Font.init(alloc, std.fs.cwd(), "fonts/roboto.ttf", init_size, win.getDpi(), .{});
    defer font.deinit();

    var draw = graph.ImmediateDrawingContext.init(alloc, win.getDpi());
    defer draw.deinit();

    const cam = graph.Camera2D{
        .cam_area = graph.Rec(0, 0, 20, 20),
        .screen_area = graph.Rec(0, 0, 800, 600),
    };

    var lvm = graph.Lua.init();
    lvm.registerAllStruct(LuaDraw.Api);
    var ldraw = LuaDraw{
        .draw = &draw,
        .win = &win,
        .vm = &lvm,
        .font = &font,
        .data = try LuaDraw.Data.init(alloc),
    };
    defer ldraw.data.deinit();
    lua_draw = &ldraw;
    lvm.loadAndRunFile("test.lua");

    while (!win.should_exit) {
        try draw.begin(ldraw.clear_color, win.screen_dimensions.toF());
        win.pumpEvents();
        draw.rect(cam.screen_area, 0x222222ff);
        try draw.flush(null);
        draw.rect(graph.Rec(10, 10, 20, 20), 0xffffffff);

        draw.setViewport(cam.screen_area);
        try draw.flush(cam.cam_area);
        draw.setViewport(null);

        //try lvm.callLuaFunction("loop");

        try draw.end();
        win.swap();
    }
}
