const std = @import("std");
const graph = @import("graphics.zig");
const gui = @import("gui.zig");
const V2f = graph.Vec2f;
const V3f = graph.za.Vec3;
const Rec = graph.Rec;
const Col3d = @import("col3d.zig");

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

//making it work
//selecting an item in 3d.
//Raycast and choose closest intersection.
//but how???

//Zig port of:
//Fast Ray-Box Intersection
//by Andrew Woo
//from "Graphics Gems", Academic Press, 1990
//
//returns null or the point of intersection in slice form
fn doesRayIntersectBoundingBox(comptime numdim: usize, comptime ft: type, min_b: [numdim]ft, max_b: [numdim]ft, ray_origin: [numdim]ft, ray_dir: [numdim]ft) ?[numdim]ft {
    const RIGHT = 0;
    const LEFT = 1;
    const MIDDLE = 2;

    const zeros = [_]ft{0} ** numdim;
    var quadrant = zeros;
    var candidate_plane = zeros;
    var inside = true;
    var max_t = zeros;

    // Find candidate planes; this loop can be avoided if
    // rays cast all from the eye(assume perpsective view)
    for (0..numdim) |i| {
        if (ray_origin[i] < min_b[i]) {
            quadrant[i] = LEFT;
            candidate_plane[i] = min_b[i];
            inside = false;
        } else if (ray_origin[i] > max_b[i]) {
            quadrant[i] = RIGHT;
            candidate_plane[i] = max_b[i];
            inside = false;
        } else {
            quadrant[i] = MIDDLE;
        }
    }

    // Ray origin inside bounding box
    if (inside)
        return ray_origin;

    // Calculate T distances to candidate planes
    for (0..numdim) |i| {
        if (quadrant[i] != MIDDLE and ray_dir[i] != 0) {
            max_t[i] = (candidate_plane[i] - ray_origin[i]) / ray_dir[i];
        } else {
            max_t[i] = -1;
        }
    }

    // Get largest of the maxT's for final choice of intersection
    var which_plane: usize = 0;
    for (1..numdim) |i| {
        if (max_t[which_plane] < max_t[i])
            which_plane = i;
    }

    // Check final candidate actually inside box
    if (max_t[which_plane] < 0)
        return null;

    var coord = zeros;
    for (0..numdim) |i| {
        if (which_plane != i) {
            coord[i] = ray_origin[i] + max_t[which_plane] * ray_dir[i];
            if (coord[i] < min_b[i] or coord[i] > max_b[i])
                return null;
        } else {
            coord[i] = candidate_plane[i];
        }
    }

    return coord;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    var arena_alloc = std.heap.ArenaAllocator.init(alloc);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    var arg_it = try std.process.argsWithAllocator(alloc);
    defer arg_it.deinit();
    const ColType = Col3d.CollisionType(graph.Rect, graph.za.Vec3);

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
    camera.pos = V3f.new(1, 3, 1);
    const tex = try graph.Texture.initFromImgFile(alloc, std.fs.cwd(), args.texture orelse "two4.png", .{});
    const ggrid = try graph.Texture.initFromImgFile(alloc, std.fs.cwd(), args.texture orelse "graygrid.png", .{});
    const sky_tex = try graph.Texture.initFromImgFile(alloc, std.fs.cwd(), args.texture orelse "sky06.png", .{
        .mag_filter = graph.c.GL_NEAREST,
    });

    var cubes_st = graph.Cubes.init(alloc, sky_tex, draw.textured_tri_3d_shader);
    defer cubes_st.deinit();
    graph.c.glEnable(graph.c.GL_CULL_FACE);
    graph.c.glCullFace(graph.c.GL_BACK);

    var cubes_grnd = graph.Cubes.init(alloc, ggrid, draw.textured_tri_3d_shader);
    defer cubes_grnd.deinit();
    try cubes_grnd.cube(-1000, -1, -1000, 2000, 1, 2000, graph.Rec(0, 0, ggrid.w * 2000, ggrid.h * 2000), null);
    cubes_grnd.setData();

    var cubes = graph.Cubes.init(alloc, tex, draw.textured_tri_3d_shader);
    defer cubes.deinit();

    var cubes_im = graph.Cubes.init(alloc, tex, draw.textured_tri_3d_shader);
    defer cubes_im.deinit();

    var lumber = std.ArrayList(ColType.Cube).init(alloc);
    defer lumber.deinit();

    var uvs = std.ArrayList(graph.Vec2f).init(alloc);
    defer uvs.deinit();
    var verts = std.ArrayList(graph.Vec3f).init(alloc);
    defer verts.deinit();
    const itm = 0.0254;
    {
        //Units are meter
        //const extent = graph.Vec3f.new(38, 0, 89);
        //Winding order default is CCW

        const xw = 12 * 4 * itm;
        const yw = 12 * 8 * itm;
        for (0..5) |x| {
            for (0..5) |y| {
                try lumber.append(.{ .pos = V3f.new(@as(f32, @floatFromInt(x)) * xw, 0, @as(f32, @floatFromInt(y)) * yw), .ext = V3f.new(12 * 4, 0.75, 12 * 8).scale(itm) });
            }
        }
        for (0..6) |i| {
            const fi: f32 = @floatFromInt(i);
            try lumber.append(.{ .pos = V3f.new(fi * 12 * itm, -1, 0), .ext = V3f.new(0.038, 8 * 18 * itm, 0.089) });
        }

        //try cubes.cubeVec(V3f.new(50, 0, 0), V3f.new(38, 300, 89), tex.rect());
        //try cubes.cubeVec(V3f.new(0, -100, 0), V3f.new(25.4 * 4 * 12, 0.75 * 25.4, 25.4 * 8 * 12), tex.rect());

    }

    const obj = try std.fs.cwd().openFile("sky.obj", .{});
    const sl = try obj.reader().readAllAlloc(alloc, std.math.maxInt(usize));
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
            const vi: u32 = @intCast(cubes_st.vertices.items.len);
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
                try cubes_st.vertices.append(.{
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
                3 => try cubes_st.indicies.appendSlice(&.{
                    vi, vi + 1, vi + 2,
                }),
                4 => try cubes_st.indicies.appendSlice(&.{
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
    cubes_st.setData();
    win.grabMouse(true);

    var tool: enum {
        none,
        pencil,
    } = .none;

    var pencil: struct {
        state: enum { p1, p2 } = .p1,
        p1: V3f = V3f.zero(),
        p2: V3f = V3f.zero(),
    } = .{};

    var mode: enum {
        look,
        manipulate,
    } = .look;
    var sel_index: usize = 0;
    var sel_dist: f32 = 0;
    var sel_resid = V3f.new(0, 0, 0);
    const sel_snap: f32 = 12 * itm;

    var p_velocity = V3f.new(0, 0, 0);
    var grounded = false;

    while (!win.should_exit) {
        const dt = 1.0 / 60.0;
        _ = arena_alloc.reset(.retain_capacity);
        try draw.begin(0x3fbaeaff, win.screen_dimensions.toF());
        cubes_im.clear();
        cubes.clear();
        for (lumber.items) |l| {
            try cubes.cube(l.pos.x(), l.pos.y(), l.pos.z(), l.ext.x(), l.ext.y(), l.ext.z(), tex.rect(), null);
        }
        win.pumpEvents();

        const old_pos = camera.pos;
        switch (mode) {
            .look => {
                var vx: f32 = 0;
                var vz: f32 = 0;
                const pspeed = 4 * dt;
                if (win.keydown(.W)) {
                    const m = camera.front.mul(V3f.new(1, 0, 1)).norm();
                    vx += m.x();
                    vz += m.z();
                }
                if (win.keydown(.S)) {
                    const m = camera.front.mul(V3f.new(-1, 0, -1)).norm();
                    vx += m.x();
                    vz += m.z();
                }
                if (win.keydown(.A)) {
                    const m = camera.front.cross(.{ .data = .{ 0, -1, 0 } }).norm();
                    vx += m.x();
                    vz += m.z();
                }
                if (win.keydown(.D)) {
                    const m = camera.front.cross(.{ .data = .{ 0, 1, 0 } }).norm();
                    vx += m.x();
                    vz += m.z();
                }

                const xz_vel = V3f.new(vx, 0, vz).norm().scale(pspeed);
                p_velocity.xMut().* = xz_vel.x();
                p_velocity.zMut().* = xz_vel.z();

                if (grounded and win.keydown(.SPACE))
                    p_velocity.yMut().* = 0.1;

                if (!grounded)
                    p_velocity.yMut().* -= 0.01;

                camera.pos = camera.pos.add(p_velocity);

                camera.updateDebugMove(.{
                    .down = false,
                    .up = false,
                    .left = false,
                    .right = false,
                    .fwd = false,
                    .bwd = false,
                    .mouse_delta = win.mouse.delta,
                    .scroll_delta = win.mouse.wheel_delta.y,
                });
            },
            .manipulate => {},
        }

        if (win.keyPressed(._1))
            tool = .none;
        if (win.keyPressed(._2)) {
            tool = .pencil;
            pencil = .{};
        }

        const sc = 1;

        const pex = 0.3;
        const bb_offset = V3f.new(-pex, -1.6, -pex);
        var cam_bb = ColType.Cube{ .pos = old_pos.add(bb_offset), .ext = V3f.new(2 * pex, 1.7, 2 * pex) };
        {
            grounded = false;
            var delta = camera.pos.sub(old_pos);
            while (delta.length() > 0) {
                var cols = std.ArrayList(ColType.CollisionResult).init(arena);
                for (lumber.items) |lum| {
                    if (ColType.detectCollision(cam_bb, lum, delta)) |col| {
                        try cols.append(col);
                        //cam_bb.pos = old_pos.add()
                        //using col.normal, set that component of touch to cam_bb.pos
                        //same for goal then repeat
                        //cam_bb.pos
                    }
                }
                if (cols.items.len > 0) {
                    std.sort.heap(ColType.CollisionResult, cols.items, {}, ColType.CollisionResult.lessThan);
                    const col = &cols.items[0];
                    delta = delta.sub(delta.scale(col.ti));
                    if (col.normal.x() != 0) {
                        delta.xMut().* = 0;
                    }
                    if (col.normal.y() != 0) {
                        delta.yMut().* = 0;
                        grounded = true;
                    }
                    if (col.normal.z() != 0) {
                        delta.zMut().* = 0;
                    }
                    cam_bb.pos = col.touch;
                    camera.pos = cam_bb.pos.sub(bb_offset);

                    //for (col.normal.toArray(), 0..) |n, i| {
                    //    if (n != 0) {
                    //        (&delta.toArray())[i] = 0;
                    //        cam_bb.pos.toArray()[i] = col.touch.toArray()[i] - bb_offset.toArray()[i];
                    //    }
                    //}
                } else {
                    cam_bb.pos = cam_bb.pos.add(delta);
                    camera.pos = cam_bb.pos.sub(bb_offset);
                    delta = V3f.zero();
                }
            }
            //for each collidable
            //  col_list append(detectCollision)
            //
            //sort col_list by nearest
            //
            //for col_list
            //  move player to "touch" positions
            //  zero velocity for the normal
            //  goto top with new velocity/goal
            //
        }
        var third_cam = camera;
        //third_cam.pos = third_cam.pos.sub(third_cam.front.scale(3));
        const cmatrix = third_cam.getMatrix(3840.0 / 2160.0, 85, 0.1, 100000);

        var point = V3f.zero();
        switch (mode) {
            .look => {
                var nearest_i: ?usize = null;
                var nearest: f32 = 0;

                for (lumber.items, 0..) |lum, i| {
                    if (doesRayIntersectBoundingBox(3, f32, lum.pos.data, lum.pos.add(lum.ext).data, camera.pos.data, camera.front.data)) |int| {
                        const p = V3f.new(int[0], int[1], int[2]);
                        if (nearest_i == null) {
                            nearest_i = i;
                            nearest = p.distance(camera.pos);
                            point = p;
                        } else {
                            const dist = p.distance(camera.pos);
                            if (nearest > dist) {
                                nearest = dist;
                                nearest_i = i;
                                point = p;
                            }
                        }
                    }
                }
                if (nearest_i) |i| {
                    if (win.mouse.left == .high) {
                        mode = .manipulate;
                        sel_index = i;
                        sel_dist = nearest;
                    }
                    const lum = &lumber.items[i];
                    {
                        var norm: @Vector(3, f32) = @splat(0);
                        const p = point.toArray();
                        const ex = lum.ext.toArray();
                        for (lum.pos.toArray(), 0..) |dim, ind| {
                            if (dim == p[ind]) {
                                norm[ind] = -1;
                                break;
                            }
                            if (dim + ex[ind] == p[ind]) {
                                norm[ind] = 1;
                                break;
                            }
                        }

                        const n = V3f{ .data = norm };
                        draw.line3D(
                            point,
                            point.add(n),
                            0x00ff00ff,
                        );

                        if (win.keyPressed(.R))
                            lum.* = lum.addInDir(6 * itm, n);
                        if (win.keyPressed(.F))
                            lum.* = lum.addInDir(-6 * itm, n);
                    }
                    // determine normal

                    //line-plane intersection
                    //try cubes_im.cube(
                    //    lum.pos.x() - 0.01,
                    //    lum.pos.y() - 0.01,
                    //    lum.pos.z() - 0.01,
                    //    lum.ext.x() + 0.02,
                    //    lum.ext.y() + 0.02,
                    //    lum.ext.z() + 0.02,
                    //    tex.rect(),
                    //    &[_]graph.CharColor{
                    //        graph.itc(0x00ff00ff),
                    //        graph.itc(0x00ff00ff),
                    //        graph.itc(0x00ff00ff),
                    //        graph.itc(0x00ff00ff),
                    //        graph.itc(0x00ff00ff),
                    //        graph.itc(0x00ff00ff),
                    //    },
                    //);
                }
            },
            .manipulate => {
                if (win.mouse.left != .high)
                    mode = .look;
                const lum = &lumber.items[sel_index];
                //lum.origin = lum.origin.add(V3f.new(win.mouse.delta.y * 0.01, 0, win.mouse.delta.x * 0.01)); //win.mouse.delta.x
                const sin = std.math.sin;
                const rad = std.math.degreesToRadians;
                const cos = std.math.cos;
                const yw = rad(camera.yaw);
                const pf: f32 = if (camera.pitch < 0) -1.0 else 1.0;

                const fac = sel_dist / 1000;
                const lx = win.keydown(.LCTRL);
                const lz = win.keydown(.LSHIFT);
                if (win.keydown(.A)) { //Rotate
                } else {
                    const x: f32 = if (lx) 0 else (sin(yw) * -win.mouse.delta.x + cos(yw) * win.mouse.delta.y * pf) * fac + sel_resid.x();
                    const z: f32 = if (lz) 0 else (sin(yw) * win.mouse.delta.y * pf + cos(yw) * win.mouse.delta.x) * fac + sel_resid.z();
                    const y: f32 = if (lx and lz) -win.mouse.delta.y * fac + sel_resid.y() else 0;
                    const rx = @divFloor(x, sel_snap) * sel_snap;
                    const ry = @divFloor(y, sel_snap) * sel_snap;
                    const rz = @divFloor(z, sel_snap) * sel_snap;
                    sel_resid = V3f.new(
                        @mod(x, sel_snap),
                        @mod(y, sel_snap),
                        @mod(z, sel_snap),
                    );
                    const r = V3f.new(rx, ry, rz);

                    if (win.keydown(.D) and r.length() > 0) {
                        try lumber.append(lum.*);
                        lumber.items[lumber.items.len - 1].pos = lum.pos.add(r);
                    } else {
                        //lum.origin = lum.origin.add(V3f.new(0, 0, win.mouse.delta.x * sel_dist / 100)); //win.mouse.delta.x
                        lum.pos = lum.pos.add(r); //win.mouse.delta.x
                    }
                }
            },
        }
        {
            try cubes.cube(cam_bb.pos.x(), cam_bb.pos.y(), cam_bb.pos.z(), cam_bb.ext.x(), cam_bb.ext.y(), cam_bb.ext.z(), Rec(0, 0, 1, 1), null);
        }
        cubes.setData();
        cubes.draw(win.screen_dimensions, cmatrix, graph.za.Mat4.identity().scale(graph.za.Vec3.new(sc, sc, sc)));
        cubes_im.setData();
        const cim = 1;
        cubes_im.draw(win.screen_dimensions, cmatrix, graph.za.Mat4.identity().scale(graph.za.Vec3.new(cim, cim, cim)));

        draw.rect(Rec(@divTrunc(win.screen_dimensions.x, 2), @divTrunc(win.screen_dimensions.y, 2), 10, 10), 0xffffffff);
        draw.textFmt(.{ .x = 0, .y = 400 }, "yaw: {d}\npitch: {d}\ngrounded {any}\ntool: {s}", .{
            camera.yaw,
            camera.pitch,
            grounded,
            @tagName(tool),
        }, &font, 12, 0xffffffff);

        cubes_st.draw(win.screen_dimensions, cmatrix, graph.za.Mat4.identity().scale(graph.za.Vec3.new(1000, 1000, 1000)));
        cubes_grnd.draw(win.screen_dimensions, cmatrix, graph.za.Mat4.identity().scale(graph.za.Vec3.new(1, 1, 1)));
        graph.c.glClear(graph.c.GL_DEPTH_BUFFER_BIT);
        if (false) {
            var origin = cam_bb.pos.add(cam_bb.ext.scale(0.5));
            origin.data = @divFloor(origin.data, @as(@Vector(3, f32), @splat(sel_snap))) * @as(@Vector(3, f32), @splat(sel_snap));
            origin.yMut().* = point.y();
            const num_lines = 30;
            for (0..num_lines + 1) |x| {
                const half = @divTrunc(num_lines, 2) * sel_snap;
                const xd: f32 = @as(f32, @floatFromInt(x)) * sel_snap;
                const start = origin.add(V3f.new(xd - half, 0, -half));
                const starty = origin.add(V3f.new(-half, 0, xd - half));
                draw.line3D(start, start.add(V3f.new(0, 0, sel_snap * num_lines)), 0x00ff00ff);
                draw.line3D(starty, starty.add(V3f.new(sel_snap * num_lines, 0, 0)), 0x00ff00ff);
            }
        }
        try draw.end(camera);
        win.swap();
    }
}
