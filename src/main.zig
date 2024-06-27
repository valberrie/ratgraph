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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    var arg_it = try std.process.argsWithAllocator(alloc);
    defer arg_it.deinit();

    const Arg = graph.ArgGen.Arg;
    const args = try graph.ArgGen.parseArgs(&.{
        Arg("model", .string, "model to load"),
        Arg("texture", .string, "texture to load"),
        Arg("scale", .number, "scale the model"),
    }, &arg_it);

    var win = try graph.SDL.Window.createWindow("zig-game-engine", .{});
    defer win.destroyWindow();

    const init_size = 72;
    var font = try graph.Font.init(alloc, std.fs.cwd(), "fonts/roboto.ttf", init_size, win.getDpi(), .{});
    defer font.deinit();

    var draw = graph.ImmediateDrawingContext.init(alloc, win.getDpi());
    defer draw.deinit();

    var camera = graph.Camera3D{};
    const tex = try graph.Texture.initFromImgFile(alloc, std.fs.cwd(), args.texture orelse "white.png", .{});

    var cubes = graph.Cubes.init(alloc, tex, draw.textured_tri_3d_shader);
    defer cubes.deinit();

    const obj = try std.fs.cwd().openFile(args.model orelse return, .{});
    const sl = try obj.reader().readAllAlloc(alloc, std.math.maxInt(usize));
    var uvs = std.ArrayList(graph.Vec2f).init(alloc);
    defer uvs.deinit();
    var verts = std.ArrayList(graph.Vec3f).init(alloc);
    defer verts.deinit();
    defer alloc.free(sl);
    var line_it = std.mem.splitAny(u8, sl, "\n\r");
    const scale = args.scale orelse 0.2;
    while (line_it.next()) |line| {
        var tok = std.mem.tokenizeAny(u8, line, " \t");
        const com = tok.next() orelse continue;
        const eql = std.mem.eql;
        if (eql(u8, com, "v")) {
            errdefer std.debug.print("{s}\n", .{line});
            const x = try std.fmt.parseFloat(f32, tok.next().?);
            const y = try std.fmt.parseFloat(f32, tok.next().?);
            const z = try std.fmt.parseFloat(f32, tok.next().?);
            try verts.append(.{ .x = x, .y = y, .z = z });
        } else if (eql(u8, com, "vt")) {
            const u = try std.fmt.parseFloat(f32, tok.next().?);
            const v = try std.fmt.parseFloat(f32, tok.next().?);
            try uvs.append(.{ .x = u, .y = v });
        } else if (eql(u8, com, "f")) {
            var count: usize = 0;
            const vi: u32 = @intCast(cubes.vertices.items.len);
            while (tok.next()) |v| {
                count += 1;
                var sp = std.mem.splitScalar(u8, v, '/');
                const ind = try std.fmt.parseInt(usize, sp.next().?, 10);
                const uv = blk: {
                    if (sp.next()) |uv| {
                        if (uv.len > 0) {
                            const uind = try std.fmt.parseInt(usize, uv, 10);
                            break :blk uvs.items[uind - 1];
                        }
                    }
                    break :blk graph.Vec2f{ .x = 0, .y = 0 };
                };
                const ver = verts.items[@intCast(ind - 1)];
                try cubes.vertices.append(.{
                    .x = scale * ver.x,
                    .y = scale * ver.y,
                    .z = scale * ver.z,
                    .u = uv.x,
                    .v = 1 - uv.y,
                    .r = 1,
                    .g = 1,
                    .b = 1,
                    .a = 1,
                });
                //try cubes.indicies.append(@intCast(cubes.vertices.items.len - 1));
            }
            switch (count) {
                0...2 => unreachable,
                3 => try cubes.indicies.appendSlice(&.{
                    vi, vi + 1, vi + 2,
                }),
                4 => try cubes.indicies.appendSlice(&.{
                    vi,
                    vi + 1,
                    vi + 2,
                    vi + 3,
                    vi,
                    vi + 2,
                }),
                else => {
                    std.debug.print("weird {d}\n", .{count});
                },
            }
        } else if (eql(u8, com, "s")) {} else if (eql(u8, com, "vn")) {} else {
            std.debug.print("{s}\n", .{line});
        }
    }
    cubes.setData();
    win.grabMouse(true);

    while (!win.should_exit) {
        try draw.begin(0x3fbaeaff, win.screen_dimensions.toF());
        win.pumpEvents();
        camera.updateDebugMove(.{
            .down = win.keydown(.LSHIFT),
            .up = win.keydown(.SPACE),
            .left = win.keydown(.A),
            .right = win.keydown(.D),
            .fwd = win.keydown(.W),
            .bwd = win.keydown(.S),
            .mouse_delta = win.mouse.delta,
            .scroll_delta = win.mouse.wheel_delta.y,
        });
        const cmatrix = camera.getMatrix(3840.0 / 2160.0, 85, 0.1, 100000);
        cubes.draw(win.screen_dimensions, cmatrix);
        try draw.end();
        win.swap();
    }
}
