const std = @import("std");
const graph = @import("graphics.zig");
const gui = @import("gui.zig");
const Gui = graph.Gui;
const V2f = graph.Vec2f;
const V3f = graph.za.Vec3;
const Mat4 = graph.za.Mat4;
const Mat3 = graph.za.Mat3;
const Rec = graph.Rec;
const Col3d = @import("col3d.zig");
const ColType = Col3d.CollisionType(graph.Rect, graph.za.Vec3);

const pow = std.math.pow;
const sqrt = std.math.sqrt;
const cos = std.math.cos;
const sin = std.math.sin;
const radians = std.math.degreesToRadians;
const deg = std.math.radiansToDegrees;

const gui_app = @import("gui_app.zig");
const Os9Gui = gui_app.Os9Gui;
const itm = 0.0254;
const c = graph.c;

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

fn doesRayIntersectBBZ(ray_origin: V3f, ray_dir: V3f, min: V3f, max: V3f) ?V3f {
    const ret = doesRayIntersectBoundingBox(3, f32, min.data, max.data, ray_origin.data, ray_dir.data);
    return if (ret) |r| V3f.new(r[0], r[1], r[2]) else null;
}

fn doesRayIntersectPlane(ray_0: V3f, ray_norm: V3f, plane_0: V3f, plane_norm: V3f) ?V3f {
    const ln = ray_norm.dot(plane_norm);
    if (ln == 0)
        return null;

    const d = (plane_0.sub(ray_0).dot(plane_norm)) / ln;
    return ray_0.add(ray_norm.scale(d));
}

fn snapV3(v: V3f, snap: f32) V3f {
    return V3f{ .data = @divFloor(v.data, @as(@Vector(3, f32), @splat(snap))) * @as(@Vector(3, f32), @splat(snap)) };
}

fn snap1(comp: f32, snap: f32) f32 {
    return @divFloor(comp, snap) * snap;
}

fn loadObj(alloc: std.mem.Allocator, dir: std.fs.Dir, filename: []const u8, scale: f32, tex: graph.Texture, shader: c_uint) !graph.Cubes {
    var uvs = std.ArrayList(graph.Vec2f).init(alloc);
    defer uvs.deinit();
    var verts = std.ArrayList(graph.Vec3f).init(alloc);
    defer verts.deinit();

    var norms = std.ArrayList(graph.Vec3f).init(alloc);
    defer norms.deinit();

    var cubes = graph.Cubes.init(alloc, tex, shader);

    const obj = try dir.openFile(filename, .{});
    const sl = try obj.reader().readAllAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(sl);
    var line_it = std.mem.splitAny(u8, sl, "\n\r");
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
        } else if (eql(u8, com, "vn")) {
            const x = try std.fmt.parseFloat(f32, tok.next().?);
            const y = try std.fmt.parseFloat(f32, tok.next().?);
            const z = try std.fmt.parseFloat(f32, tok.next().?);
            try norms.append(.{ .x = x, .y = y, .z = z });
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
                const norm = blk: {
                    if (sp.next()) |n| {
                        if (n.len > 0) {
                            const nind = try std.fmt.parseInt(usize, n, 10);
                            break :blk norms.items[nind - 1];
                        }
                    }
                    break :blk graph.Vec3f{ .x = 0, .y = 1, .z = 0 };
                };
                try cubes.vertices.append(.{
                    .x = scale * ver.x,
                    .y = scale * ver.y,
                    .z = scale * ver.z,
                    .u = uv.x,
                    .v = 1 - uv.y,
                    .nx = norm.x,
                    .ny = norm.y,
                    .nz = norm.z,
                    .color = 0xffffffff,
                });
                //try cubes.indicies.append(@intCast(cubes.vertices.items.len - 1));
            }
            switch (count) {
                0...2 => unreachable,
                3 => {
                    try cubes.indicies.appendSlice(&.{
                        vi, vi + 1, vi + 2,
                    });
                    const v1 = &cubes.vertices.items[vi];
                    const v2 = &cubes.vertices.items[vi + 1];
                    const v3 = &cubes.vertices.items[vi + 2];
                    const e1 = V3f.new(v2.x, v2.y, v2.z).sub(V3f.new(v1.x, v1.y, v1.z));
                    const e2 = V3f.new(v3.x, v3.y, v3.z).sub(V3f.new(v1.x, v1.y, v1.z));
                    const du1 = v2.u - v1.u;
                    const dv1 = v2.v - v1.v;
                    const du2 = v3.u - v1.u;
                    const dv2 = v3.v - v1.v;
                    const f = 1.0 / (du1 * dv2 - du2 * dv1);
                    const tangent = V3f.new(
                        (dv2 * e1.x()) - (dv1 * e2.x()),
                        (dv2 * e1.y()) - (dv1 * e2.y()),
                        (dv2 * e1.z()) - (dv1 * e2.z()),
                    ).scale(f);

                    //const bitangent = V3f.new(
                    //    (-du2 * e1.x()) - (du1 * e2.x()),
                    //    (-du2 * e1.y()) - (du1 * e2.y()),
                    //    (-du2 * e1.z()) - (du1 * e2.z()),
                    //    ).scale(f);
                    v1.tx += tangent.x();
                    v2.tx += tangent.x();
                    v3.tx += tangent.x();
                    v1.ty += tangent.y();
                    v2.ty += tangent.y();
                    v3.ty += tangent.y();
                    v1.tz += tangent.z();
                    v2.tz += tangent.z();
                    v3.tz += tangent.z();
                },
                4 => {
                    try cubes.indicies.appendSlice(&.{
                        vi,
                        vi + 1,
                        vi + 2,
                        vi + 3,
                        vi,
                        vi + 2,
                    });
                },
                else => {
                    std.debug.print("weird {d}\n", .{count});
                },
            }
        } else if (eql(u8, com, "s")) {} else {}
    }
    for (cubes.vertices.items) |*vert| {
        const norm = V3f.new(vert.tx, vert.ty, vert.tz).norm();
        vert.tx = norm.x();
        vert.ty = norm.y();
        vert.tz = norm.z();
    }
    cubes.setData();
    return cubes;
}

const CASCADE_COUNT = 4;

fn getLightMatrices(fov: f32, aspect: f32, near: f32, far: f32, cam_view: Mat4, light_dir: V3f, planes: [CASCADE_COUNT - 1]f32) [CASCADE_COUNT]Mat4 {
    var ret: [CASCADE_COUNT]Mat4 = undefined;
    //fov, aspect, near, far, cam_view, light_Dir
    for (0..CASCADE_COUNT) |i| {
        if (i == 0) {
            ret[i] = getLightMatrix(fov, aspect, near, planes[i], cam_view, light_dir);
        } else if (i < CASCADE_COUNT - 1) {
            ret[i] = getLightMatrix(fov, aspect, planes[i - 1], planes[i], cam_view, light_dir);
        } else {
            ret[i] = getLightMatrix(fov, aspect, planes[i - 1], far, cam_view, light_dir);
        }
    }
    return ret;
}

fn create3DDepthMap(resolution: i32, cascade_count: i32) struct { fbo: c_uint, textures: c_uint, res: i32 } {
    var fbo: c_uint = 0;
    var textures: c_uint = 0;
    c.glGenFramebuffers(1, &fbo);
    c.glGenTextures(1, &textures);
    c.glBindTexture(c.GL_TEXTURE_2D_ARRAY, textures);
    c.glTexImage3D(
        c.GL_TEXTURE_2D_ARRAY,
        0,
        c.GL_DEPTH_COMPONENT32F,
        resolution,
        resolution,
        cascade_count,
        0,
        c.GL_DEPTH_COMPONENT,
        c.GL_FLOAT,
        null,
    );
    c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_BORDER);
    c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_BORDER);

    const border_color = [_]f32{1} ** 4;
    c.glTexParameterfv(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_BORDER_COLOR, &border_color);

    c.glBindFramebuffer(c.GL_FRAMEBUFFER, fbo);
    c.glFramebufferTexture(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, textures, 0);
    c.glDrawBuffer(c.GL_NONE);
    c.glReadBuffer(c.GL_NONE);

    const status = c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER);
    if (status != c.GL_FRAMEBUFFER_COMPLETE)
        std.debug.print("Framebuffer fucked\n", .{});

    c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
    return .{
        .fbo = fbo,
        .textures = textures,
        .res = resolution,
    };
}

fn getFrustumCornersWorldSpace(frustum: Mat4) [8]graph.za.Vec4 {
    const inv = frustum.inv();
    var corners: [8]graph.za.Vec4 = undefined;
    var i: usize = 0;
    for (0..2) |x| {
        for (0..2) |y| {
            for (0..2) |z| {
                const pt = inv.mulByVec4(graph.za.Vec4.new(
                    2 * @as(f32, @floatFromInt(x)) - 1,
                    2 * @as(f32, @floatFromInt(y)) - 1,
                    2 * @as(f32, @floatFromInt(z)) - 1,
                    1.0,
                ));
                corners[i] = pt.scale(1 / pt.w());
                i += 1;
            }
        }
    }
    if (i != 8)
        unreachable;

    return corners;
}

fn getLightMatrix(fov: f32, aspect: f32, near: f32, far: f32, cam_view: Mat4, light_dir: V3f) Mat4 {
    const cam_persp = graph.za.perspective(fov, aspect, near, far);
    const corners = getFrustumCornersWorldSpace(cam_persp.mul(cam_view));
    var center = V3f.zero();
    for (corners) |corner| {
        center = center.add(corner.toVec3());
    }
    center = center.scale(1.0 / @as(f32, @floatFromInt(corners.len)));
    const lview = graph.za.lookAt(
        center.add(light_dir),
        center,
        V3f.new(0, 1, 0),
    );
    var min_x = std.math.floatMax(f32);
    var min_y = std.math.floatMax(f32);
    var min_z = std.math.floatMax(f32);

    var max_x = std.math.floatMin(f32);
    var max_y = std.math.floatMin(f32);
    var max_z = std.math.floatMin(f32);
    for (corners) |corner| {
        const trf = lview.mulByVec4(corner);
        min_x = @min(min_x, trf.x());
        min_y = @min(min_y, trf.y());
        min_z = @min(min_z, trf.z());

        max_x = @max(max_x, trf.x());
        max_y = @max(max_y, trf.y());
        max_z = @max(max_z, trf.z());
    }

    min_z -= 15;
    max_z += 15;
    //min_z -= far / 2;

    //const tw = 20;
    //min_z = if (min_z < 0) min_z * tw else min_z / tw;
    //max_z = if (max_z < 0) max_z / tw else max_z * tw;

    //const ortho = graph.za.orthographic(-20, 20, -20, 20, 0.1, 300).mul(lview);
    const ortho = graph.za.orthographic(min_x, max_x, min_y, max_y, min_z, max_z).mul(lview);
    return ortho;
}

pub fn checkAl() void {
    const err = c.alGetError();
    const msg = switch (err) {
        c.AL_INVALID_NAME => "name",
        c.AL_INVALID_ENUM => "enum",
        c.AL_INVALID_VALUE => "val",
        c.AL_INVALID_OPERATION => "op",
        c.AL_OUT_OF_MEMORY => "OOM",

        else => return,
    };
    std.debug.print("OPEN AL ERR: {s}\n", .{msg});
}

fn loadOgg(alloc: std.mem.Allocator, filename: [*c]const u8, pos: V3f) !c.ALuint {
    var audio_source: c.ALuint = 0;
    c.alGenSources(1, &audio_source);
    c.alSourcef(audio_source, c.AL_PITCH, 1);
    c.alSourcef(audio_source, c.AL_GAIN, 1);
    c.alSource3f(audio_source, c.AL_POSITION, pos.x(), pos.y(), pos.z());
    c.alSource3f(audio_source, c.AL_VELOCITY, 0, 0, 0);
    c.alSourcei(audio_source, c.AL_LOOPING, c.AL_FALSE);
    c.alSourcei(audio_source, c.AL_SOURCE_RELATIVE, c.AL_TRUE);
    var audio_buf: c.ALuint = 0;
    c.alGenBuffers(1, &audio_buf);

    var channels: c_int = 0;
    var sample_rate: c_int = 0;
    const output = try alloc.create(?*c_short);
    const ogg = c.stb_vorbis_decode_filename(filename, &channels, &sample_rate, output);
    std.debug.print("ogg len {d} {d}\n", .{ ogg, sample_rate });

    c.alBufferData(audio_buf, c.AL_FORMAT_MONO16, output.*, @intCast(ogg - @mod(ogg, 4)), sample_rate);
    c.alSourcei(audio_source, c.AL_BUFFER, @intCast(audio_buf));
    return audio_source;
}

const HdrBuffer = struct {
    fb: c_uint = 0,
    color: c_uint = 0,

    scr_w: i32 = 0,
    scr_h: i32 = 0,

    pub fn updateResolution(self: *@This(), new_w: i32, new_h: i32) void {
        if (new_w != self.scr_w or new_h != self.scr_h) {
            c.glDeleteTextures(1, &self.color);
            c.glDeleteFramebuffers(1, &self.fb);
            self.* = create(new_w, new_h);
        }
    }

    pub fn create(scrw: i32, scrh: i32) @This() {
        var ret: HdrBuffer = .{};
        ret.scr_w = scrw;
        ret.scr_h = scrh;

        c.glGenFramebuffers(1, &ret.fb);
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, ret.fb);

        c.glGenTextures(1, &ret.color);
        c.glBindTexture(c.GL_TEXTURE_2D, ret.color);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA16F, scrw, scrh, 0, c.GL_RGBA, c.GL_HALF_FLOAT, null);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, ret.color, 0);

        const attachments = [_]c_int{ c.GL_COLOR_ATTACHMENT0, 0 };
        c.glDrawBuffers(1, @ptrCast(&attachments[0]));

        //c.glGenRenderbuffers(1, &ret.depth);
        //c.glBindRenderbuffer(c.GL_RENDERBUFFER, ret.depth);
        //c.glRenderbufferStorage(c.GL_RENDERBUFFER, c.GL_DEPTH_COMPONENT, scrw, scrh);
        //c.glFramebufferRenderbuffer(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_RENDERBUFFER, ret.depth);
        if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE)
            std.debug.print("gbuffer FBO not complete\n", .{});
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        return ret;
    }
};

const GBuffer = struct {
    buffer: c_uint = 0,
    depth: c_uint = 0,
    pos: c_uint = 0,
    normal: c_uint = 0,
    albedo: c_uint = 0,

    scr_w: i32 = 0,
    scr_h: i32 = 0,

    pub fn updateResolution(self: *@This(), new_w: i32, new_h: i32) void {
        if (new_w != self.scr_w or new_h != self.scr_h) {
            c.glDeleteTextures(1, &self.pos);
            c.glDeleteTextures(1, &self.normal);
            c.glDeleteTextures(1, &self.albedo);
            c.glDeleteRenderbuffers(1, &self.depth);
            c.glDeleteFramebuffers(1, &self.buffer);
            self.* = create(new_w, new_h);
        }
    }

    pub fn create(scrw: i32, scrh: i32) @This() {
        var ret: GBuffer = .{};
        ret.scr_w = scrw;
        ret.scr_h = scrh;
        c.glGenFramebuffers(1, &ret.buffer);
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, ret.buffer);
        const pos_fmt = c.GL_RGBA32F;
        const norm_fmt = c.GL_RGBA16F;

        c.glGenTextures(1, &ret.pos);
        c.glBindTexture(c.GL_TEXTURE_2D, ret.pos);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, pos_fmt, scrw, scrh, 0, c.GL_RGBA, c.GL_FLOAT, null);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, ret.pos, 0);

        // - normal color buffer
        c.glGenTextures(1, &ret.normal);
        c.glBindTexture(c.GL_TEXTURE_2D, ret.normal);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, norm_fmt, scrw, scrh, 0, c.GL_RGBA, c.GL_HALF_FLOAT, null);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT1, c.GL_TEXTURE_2D, ret.normal, 0);

        // - color + specular color buffer
        c.glGenTextures(1, &ret.albedo);
        c.glBindTexture(c.GL_TEXTURE_2D, ret.albedo);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA16F, scrw, scrh, 0, c.GL_RGBA, c.GL_HALF_FLOAT, null);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT2, c.GL_TEXTURE_2D, ret.albedo, 0);

        // - tell OpenGL which color attachments we'll use (of this framebuffer) for rendering
        const attachments = [_]c_int{ c.GL_COLOR_ATTACHMENT0, c.GL_COLOR_ATTACHMENT1, c.GL_COLOR_ATTACHMENT2, 0 };
        c.glDrawBuffers(3, @ptrCast(&attachments[0]));

        c.glGenRenderbuffers(1, &ret.depth);
        c.glBindRenderbuffer(c.GL_RENDERBUFFER, ret.depth);
        c.glRenderbufferStorage(c.GL_RENDERBUFFER, c.GL_DEPTH_COMPONENT, scrw, scrh);
        c.glFramebufferRenderbuffer(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_RENDERBUFFER, ret.depth);
        if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE)
            std.debug.print("gbuffer FBO not complete\n", .{});
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        return ret;
    }
};

pub const DemoJson = struct {
    // store any state changes for keys
    pub const StateChange = struct {
        new: graph.SDL.ButtonState,
        scancode: usize,
    };

    pub const Frame = struct {
        state_changes: []const StateChange,
        mouse_button_state: []const StateChange,
        m_pos: graph.Vec2f,
        m_delta: graph.Vec2f,
        wheel_delta: graph.Vec2f,
    };

    frames: []const Frame,
};

pub const WorldCube = struct {
    cube: ColType.Cube,
};

pub const PointLight = packed struct {
    pos: graph.Vec3f,
    ambient: graph.Vec3f,
    diffuse: graph.Vec3f,
    specular: graph.Vec3f,

    constant: f32,
    linear: f32,
    quadratic: f32,

    pub fn calcRadius(self: @This()) f32 {
        const min: f32 = 1 / 0.1;
        const lmax = @as(f32, @floatFromInt(@max(self.diffuse.x, self.diffuse.y, self.diffuse.z)));
        const radius = (-self.linear + @sqrt(self.linear * self.linear - 4 * self.quadratic * (self.constant - min * lmax))) / (2 * self.quadratic);
        return radius;
    }
};

pub const LightVertex = packed struct {
    // The positions of the vertex in world space
    pos: graph.Vec3f,

    // The position of the light, these should stay constant for all verticies of light volume quad
    lpos: graph.Vec3f,

    ambient: graph.Vec3f,
    diffuse: graph.Vec3f,
    specular: graph.Vec3f,

    constant: f32,
    linear: f32,
    quadratic: f32,

    pub fn newPoint(l: PointLight) [6]@This() {
        var dat = LightVertex{
            .ambient = graph.Vec3f.fromZa(l.ambient),
            .diffuse = graph.Vec3f.fromZa(l.diffuse),
            .specular = graph.Vec3f.fromZa(l.specular),
            .constant = l.constant,
            .linear = l.linear,
            .quadratic = l.quadratic,
            .lpos = graph.Vec3f.fromZa(l.pos),
            .pos = graph.Vec3f.new(0, 0, 0),
        };
        //const r = l.calcRadius();
        //const r2 = r * 2;
        var verts: [6]LightVertex = undefined;
        //const ll = l.pos.sub(V3f.new(r, r, r));
        for ([_]V3f{
            V3f.new(-1, -1, 0),
            V3f.new(1, -1, 0),
            V3f.new(1, 1, 0),

            V3f.new(-1, -1, 0),
            V3f.new(1, 1, 0),
            V3f.new(-1, 1, 0),
            //ll.add(V3f.new(0, 0, r2)),
            //ll.add(V3f.new(r2, 0, r2)),
            //ll.add(V3f.new(r2, r2, r2)),
            //ll.add(V3f.new(0, 0, r2)),
            //ll.add(V3f.new(r2, r2, r2)),
            //ll.add(V3f.new(0, r2, r2)),
            //ll.add(V3f.new(r2, r2, 0)),
            //ll.add(V3f.new(r2, 0, 0)),
            //ll.add(V3f.new(0, 0, 0)),
            //ll.add(V3f.new(0, r2, 0)),
            //ll.add(V3f.new(r2, r2, 0)),
            //ll.add(V3f.new(0, 0, 0)),

            //ll.add(V3f.new(r2, 0, 0)),
            //ll.add(V3f.new(r2, r2, 0)),
            //ll.add(V3f.new(r2, 0, r2)),

            //ll.add(V3f.new(r2, r2, 0)),
            //ll.add(V3f.new(r2, r2, r2)),
            //ll.add(V3f.new(r2, 0, r2)),
        }, 0..) |vert, i| {
            dat.pos = graph.Vec3f.fromZa(vert);
            verts[i] = dat;
        }
        return verts;
    }
};

const LightBatch = graph.NewBatch(LightVertex, .{ .index_buffer = false, .primitive_mode = .triangles });

pub const LightInstanceBatch = struct {
    pub const Vertex = packed struct {
        pos: graph.Vec3f,
    };

    pub const InVertex = packed struct {
        light_pos: graph.Vec3f,
        ambient: graph.Vec3f = graph.Vec3f.new(0.1, 0.1, 0.1),
        diffuse: graph.Vec3f = graph.Vec3f.new(1, 1, 1),
        specular: graph.Vec3f = graph.Vec3f.new(4, 4, 4),

        constant: f32 = 1,
        linear: f32 = 0.7,
        quadratic: f32 = 1.8,
    };

    vbo: c_uint = 0,
    vao: c_uint = 0,
    ebo: c_uint = 0,
    ivbo: c_uint = 0,

    vertices: std.ArrayList(Vertex),
    indicies: std.ArrayList(u32),
    inst: std.ArrayList(InVertex),

    pub fn init(alloc: std.mem.Allocator) @This() {
        var ret = @This(){
            .vertices = std.ArrayList(Vertex).init(alloc),
            .indicies = std.ArrayList(u32).init(alloc),
            .inst = std.ArrayList(InVertex).init(alloc),
        };

        c.glGenVertexArrays(1, &ret.vao);
        c.glGenBuffers(1, &ret.vbo);
        c.glGenBuffers(1, &ret.ebo);
        graph.GL.generateVertexAttributes(ret.vao, ret.vbo, Vertex);
        c.glBindVertexArray(ret.vao);
        c.glGenBuffers(1, &ret.ivbo);
        c.glEnableVertexAttribArray(1);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, ret.ivbo);
        graph.GL.generateVertexAttributesEx(ret.vao, ret.ivbo, InVertex, 1);
        c.glBindVertexArray(ret.vao);
        for (1..8) |i|
            c.glVertexAttribDivisor(@intCast(i), 1);

        //c.glVertexAttribPointer(
        //    1,
        //    3,
        //    c.GL_FLOAT,
        //    c.GL_FALSE,
        //    @sizeOf(Vertex),
        //    null,
        //);
        //c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

        return ret;
    }

    pub fn deinit(self: *@This()) void {
        self.vertices.deinit();
        self.indicies.deinit();
        self.inst.deinit();
    }

    pub fn pushVertexData(self: *@This()) void {
        c.glBindVertexArray(self.vao);
        graph.GL.bufferData(c.GL_ARRAY_BUFFER, self.vbo, Vertex, self.vertices.items);
        graph.GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, self.ebo, u32, self.indicies.items);
        graph.GL.bufferData(c.GL_ARRAY_BUFFER, self.ivbo, InVertex, self.inst.items);
    }

    pub fn draw(self: *@This()) void {
        //c.glBindVertexArray(self.vao);
        //c.glDrawArraysInstanced(c.GL_TRIANGLES, 0, @intCast(self.vertices.items.len), @intCast(self.inst.items.len));
        c.glDrawElementsInstanced(
            c.GL_TRIANGLES,
            @intCast(self.indicies.items.len),
            c.GL_UNSIGNED_INT,
            null,
            @intCast(self.inst.items.len),
        );
        c.glBindVertexArray(0);
    }
};

pub const ScreenSpaceVertHelper = struct {
    pub const SortItem = struct {
        ws: graph.za.Vec3,
        ss: graph.Vec2f,
    };
    reference: graph.Vec2f,
    pub fn sortByDist(ctx: @This(), a: SortItem, b: SortItem) bool {
        return a.ss.sub(ctx.reference).length() < b.ss.sub(ctx.reference).length();
    }
};

pub fn screenSpaceToWorld(cam_matrix: Mat4, screen: graph.Vec2f, win_dim: graph.Vec2f, ndc_z: f32) V3f {
    const sw = win_dim.smul(0.5);
    const pp = screen.sub(sw).mul(sw.inv());
    const t = V3f.new(pp.x, -pp.y, ndc_z);
    const inv = cam_matrix.inv();
    const world = inv.mulByVec4(t.toVec4(1));
    return world.toVec3().scale(1 / world.w());
}

pub fn worldSpaceToScreen(cam_matrix: Mat4, world: V3f, win_dim: graph.Vec2f) graph.Vec2f {
    const tpos = cam_matrix.mulByVec4(world.toVec4(1));
    const w = tpos.w();
    //const z = tpos.z();
    const pp = graph.Vec2f.new(tpos.x() / w, tpos.y() / -w);
    const sw = win_dim.smul(0.5);
    const spos = pp.mul(sw).add(sw);
    return spos;
}

//Solve a system of 2 linear equations in 2 unknowns via Cramer's rule
//a.x * x + b.x * y = c.x
//a.y * x + b.y * y = c.y
//Where x and y are unknowns
pub fn cramers2D(a: graph.Vec2f, b: graph.Vec2f, c_: graph.Vec2f) graph.Vec2f {
    const x = (c_.x * b.y - b.x * c_.y) / (a.x * b.y - b.x * a.y);
    const y = (a.x * c_.y - c_.x * a.y) / (a.x * b.y - b.x * a.y);
    return .{ .x = x, .y = y };
}

pub fn cramers3D(a: V3f, b: V3f, c_: V3f, d: V3f) V3f {
    const r = (Mat3{ .data = .{ a.data, b.data, c_.data } }).det();
    const x = (Mat3{ .data = .{ d.data, b.data, c_.data } }).det() / r;
    const y = (Mat3{ .data = .{ a.data, d.data, c_.data } }).det() / r;
    const z = (Mat3{ .data = .{ a.data, b.data, d.data } }).det() / r;
    return V3f.new(x, y, z);
}

pub fn main() !void {
    const cwd = std.fs.cwd();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    var lifetime_arena = std.heap.ArenaAllocator.init(alloc);
    defer lifetime_arena.deinit();
    const lifetime_alloc = lifetime_arena.allocator();

    var arena_alloc = std.heap.ArenaAllocator.init(alloc);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    var arg_it = try std.process.argsWithAllocator(alloc);
    defer arg_it.deinit();

    const Arg = graph.ArgGen.Arg;
    const args = try graph.ArgGen.parseArgs(&.{
        Arg("model", .string, "model to load"),
        Arg("texture", .string, "texture to load"),
        Arg("scale", .number, "scale the model"),
    }, &arg_it);
    _ = args;

    var win = try graph.SDL.Window.createWindow("zig-game-engine", .{});
    defer win.destroyWindow();

    const device = c.alcOpenDevice(null);
    if (device == null) {
        std.debug.print("shoot\n", .{});
    }

    const al_ctx = c.alcCreateContext(device, null);
    if (c.alcMakeContextCurrent(al_ctx) == 0) {
        std.debug.print("no current\n", .{});
    }
    c.alListener3f(c.AL_POSITION, 0, 0, 0);
    c.alListener3f(c.AL_VELOCITY, 0, 0, 0);
    c.alListenerfv(c.AL_ORIENTATION, &[_]f32{ 0, 0, 1, 0, 1, 0 });

    c.alDistanceModel(c.AL_INVERSE_DISTANCE);
    c.alDopplerFactor(0);
    checkAl();

    var audio_source: c.ALuint = 0;
    c.alGenSources(1, &audio_source);
    c.alSourcef(audio_source, c.AL_PITCH, 1);
    c.alSourcef(audio_source, c.AL_GAIN, 3);
    c.alSource3f(audio_source, c.AL_POSITION, 5, 1, -32);
    c.alSource3f(audio_source, c.AL_VELOCITY, 0, 0, 0);
    c.alSourcei(audio_source, c.AL_LOOPING, c.AL_TRUE);

    var audio_buf: c.ALuint = 0;
    c.alGenBuffers(1, &audio_buf);
    var channels: c_int = 0;
    var sample_rate: c_int = 0;
    var output: ?*c_short = null;
    const ogg = c.stb_vorbis_decode_filename("mono.ogg", &channels, &sample_rate, &output);

    c.alBufferData(audio_buf, c.AL_FORMAT_MONO16, output, @intCast(ogg), sample_rate);
    c.alSourcei(audio_source, c.AL_BUFFER, @intCast(audio_buf));

    var day_timer = try std.time.Timer.start();
    const day_length = std.time.ns_per_s * 60;

    var footstep_timer = try std.time.Timer.start();
    //checkAl();
    const ls = try loadOgg(lifetime_alloc, "stop.ogg", V3f.zero());
    checkAl();
    //c.alSourcePlay(audio_source);

    const init_size = 72;
    var font = try graph.Font.init(alloc, cwd, "fonts/roboto.ttf", init_size, win.getDpi(), .{});
    defer font.deinit();

    var draw = graph.ImmediateDrawingContext.init(alloc, win.getDpi());
    defer draw.deinit();

    var os9gui = try Os9Gui.init(alloc, cwd, 2);
    defer os9gui.deinit();
    var gcfg: struct {
        draw_lighting_spheres: bool = false,
        lighting: bool = true,
        do_daylight_cycle: bool = false,
        tab: enum { main, graphics, keyboard, info, sound } = .main,
        draw_wireframe: bool = false,
        draw_thirdperson: bool = false,
        shadow_map_select: enum { camera, sun, depth } = .camera,
        draw_gbuffer: enum { shaded, pos, normal, albedo } = .shaded,
        sun_perspective_index: usize = 0,
    } = .{};
    var show_gui = false;
    //var tab: enum { main, graphics, keyboard, info, sound } = .main;
    //var draw_wireframe = false;
    //var draw_thirdperson = false;
    //var shadow_map_select: enum { camera, sun, depth } = .camera;
    //var draw_gbuffer: enum { shaded, pos, normal, albedo } = .shaded;
    //var sun_perspective_index: usize = 0;

    var camera = graph.Camera3D{};
    const camera_spawn = V3f.new(1, 3, 1);
    camera.pos = camera_spawn;
    const woodtex = try graph.Texture.initFromImgFile(alloc, cwd, "asset/woodout/color.png", .{});

    var disp_cubes = graph.Cubes.init(alloc, woodtex, draw.textured_tri_3d_shader);
    defer disp_cubes.deinit();

    const woodnormal = try graph.Texture.initFromImgFile(alloc, cwd, "asset/normal.png", .{});
    const tex = try graph.Texture.initFromImgFile(alloc, cwd, "two4.png", .{});
    const ggrid = try graph.Texture.initFromImgFile(alloc, cwd, "graygrid.png", .{});
    const sky_tex = try graph.Texture.initFromImgFile(alloc, cwd, "sky06.png", .{
        .mag_filter = graph.c.GL_NEAREST,
    });
    const light_shader = try graph.Shader.loadFromFilesystem(alloc, cwd, &.{
        .{ .path = "src/graphics/shader/light.vert", .t = .vert },
        .{ .path = "src/graphics/shader/light.frag", .t = .frag },
    });
    const shadow_shader = try graph.Shader.loadFromFilesystem(alloc, cwd, &.{
        .{ .path = "src/graphics/shader/shadow_map.vert", .t = .vert },
        .{ .path = "src/graphics/shader/shadow_map.frag", .t = .frag },
        .{ .path = "src/graphics/shader/shadow_map.geom", .t = .geom },
    });

    const gbuffer_shader = try graph.Shader.loadFromFilesystem(alloc, cwd, &.{
        .{ .path = "asset/shader/gbuffer.vert", .t = .vert },
        .{ .path = "asset/shader/gbuffer.frag", .t = .frag },
    });

    const deferred_light_shader = try graph.Shader.loadFromFilesystem(alloc, cwd, &.{
        .{ .path = "asset/shader/deferred_light.vert", .t = .vert },
        .{ .path = "asset/shader/deferred_light.frag", .t = .frag },
    });

    const def_light_shad = try graph.Shader.loadFromFilesystem(alloc, cwd, &.{
        .{ .path = "asset/shader/light.vert", .t = .vert },
        .{ .path = "asset/shader/light_debug.frag", .t = .frag },
    });

    const def_sun_shad = try graph.Shader.loadFromFilesystem(alloc, cwd, &.{
        .{ .path = "asset/shader/sun.vert", .t = .vert },
        .{ .path = "asset/shader/sun.frag", .t = .frag },
    });

    const hdr_shad = try graph.Shader.loadFromFilesystem(alloc, cwd, &.{
        .{ .path = "asset/shader/hdr.vert", .t = .vert },
        .{ .path = "asset/shader/hdr.frag", .t = .frag },
    });

    const LightQuadBatch = graph.NewBatch(packed struct { pos: graph.Vec3f, uv: graph.Vec2f }, .{ .index_buffer = false, .primitive_mode = .triangles });
    var light_batch = LightQuadBatch.init(alloc);
    defer light_batch.deinit();

    var planes = [_]f32{ 3, 8, 25 };

    var sm = create3DDepthMap(2048, CASCADE_COUNT);
    var sun_yaw: f32 = 225;
    var sun_pitch: f32 = 61;
    var light_dir = V3f.new(-20, 50, -20).norm();
    var sun_color = graph.Hsva.fromInt(0xef8825ff);
    var exposure: f32 = 1.0;
    var gamma: f32 = 2.2;

    var light_mat_ubo: c_uint = 0;
    {
        c.glGenBuffers(1, &light_mat_ubo);
        c.glBindBuffer(c.GL_UNIFORM_BUFFER, light_mat_ubo);
        c.glBufferData(c.GL_UNIFORM_BUFFER, @sizeOf([4][4]f32) * 16, null, c.GL_DYNAMIC_DRAW);
        c.glBindBufferBase(c.GL_UNIFORM_BUFFER, 0, light_mat_ubo);
        c.glBindBuffer(c.GL_UNIFORM_BUFFER, 0);

        const li = c.glGetUniformBlockIndex(light_shader, "LightSpaceMatrices");
        c.glUniformBlockBinding(light_shader, li, 0);
    }

    var gbuffer = GBuffer.create(win.screen_dimensions.x, win.screen_dimensions.y);
    var hdrbuffer = HdrBuffer.create(win.screen_dimensions.x, win.screen_dimensions.y);

    graph.c.glEnable(graph.c.GL_CULL_FACE);
    graph.c.glCullFace(graph.c.GL_BACK);

    var cubes_grnd = graph.Cubes.init(alloc, ggrid, draw.textured_tri_3d_shader);
    defer cubes_grnd.deinit();
    cubes_grnd.setData();

    var cubes = graph.Cubes.init(alloc, woodtex, light_shader);
    defer cubes.deinit();

    var lumber = std.ArrayList(ColType.Cube).init(alloc);
    {
        if (cwd.openFile("lumber.json", .{}) catch null) |infile| {
            const sl = try infile.reader().readAllAlloc(alloc, std.math.maxInt(usize));
            defer alloc.free(sl);
            const j = try std.json.parseFromSlice([]const ColType.Cube, alloc, sl, .{});
            defer j.deinit();
            try lumber.appendSlice(j.value);
            var i: usize = lumber.items.len;
            while (i > 0) : (i -= 1) {
                const l = lumber.items[i - 1];
                if (l.ext.x() < 0 or l.ext.y() < 0 or l.ext.z() < 0) {
                    _ = lumber.swapRemove(i - 1);
                }
            }
            //for(to_remove.items)
        } else {
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
    }
    defer lumber.deinit();
    defer {
        const outfile = cwd.createFile("lumber.json", .{}) catch unreachable;
        std.json.stringify(lumber.items, .{}, outfile.writer()) catch unreachable;
        outfile.close();
    }

    var ico = try loadObj(alloc, cwd, "asset/icosphere.obj", 1, sky_tex, draw.textured_tri_3d_shader);
    defer ico.deinit();
    ico.setData();

    var libatch = LightInstanceBatch.init(alloc);
    defer libatch.deinit();
    for (ico.vertices.items) |v| {
        try libatch.vertices.append(.{ .pos = graph.Vec3f.new(v.x, v.y, v.z) });
    }
    try libatch.indicies.appendSlice(ico.indicies.items);
    try libatch.inst.append(.{ .light_pos = graph.Vec3f.new(-9, 1, 5) });
    try libatch.inst.append(.{ .light_pos = graph.Vec3f.new(10, 1, 3) });
    try libatch.inst.append(.{ .light_pos = graph.Vec3f.new(1, 2, 4) });
    try libatch.inst.append(.{ .light_pos = graph.Vec3f.new(2, -4, 4) });
    try libatch.inst.append(.{ .light_pos = graph.Vec3f.new(8, 1, 23), .diffuse = graph.Vec3f.new(239, 173, 93).scale(1.0 / 20.0) });
    try libatch.inst.append(.{
        .light_pos = graph.Vec3f.new(4.33, 2, -7.44),
        .diffuse = graph.Vec3f.new(3, 0, 0),
        .quadratic = 4,
    });
    try libatch.inst.append(.{
        .light_pos = graph.Vec3f.new(-9.22, 2, 5.77),
        .diffuse = graph.Vec3f.new(1, 0, 0),
    });
    libatch.pushVertexData();

    var cubes_st = try loadObj(alloc, cwd, "sky.obj", 1, sky_tex, draw.textured_tri_3d_shader);
    defer cubes_st.deinit();

    const couch_tex = try graph.Texture.initFromImgFile(alloc, cwd, "drum.png", .{});
    const couch_normal = try graph.Texture.initFromImgFile(alloc, cwd, "asset/oil_drum_normal.png", .{});
    const couch_m = graph.za.Mat4.identity().translate(V3f.new(-9, 0, 6));
    var couch = try loadObj(alloc, cwd, "barrel.obj", 0.03, couch_tex, draw.textured_tri_3d_shader);
    defer couch.deinit();

    const pistol_tex = try graph.Texture.initFromImgFile(alloc, cwd, "asset/pistol/textures/BrowningHP_Albedo.png", .{});
    const pistol_norm = try graph.Texture.initFromImgFile(alloc, cwd, "asset/pistol/textures/BrowningHP_Normal.png", .{});
    var pistol = try loadObj(alloc, cwd, "asset/pistol/untitled.obj", 0.3, pistol_tex, draw.textured_tri_3d_shader);
    defer pistol.deinit();

    cubes_st.setData();
    win.grabMouse(true);

    var tool: enum {
        none,
        pencil,
        erase,
    } = .none;

    var pencil: struct {
        state: enum { init, p1, p2 } = .init,
        grid_y: f32 = 0,
        p1: V3f = V3f.zero(),
        p2: V3f = V3f.zero(),
    } = .{};

    const keys: struct {
        const SC = graph.SDL.keycodes.Scancode;
        delete_selected: SC = .X,
        show_menu: SC = .TAB,
        tool_1: SC = ._1,
        tool_2: SC = ._2,
        tool_3: SC = ._3,
    } = .{};

    var mode: enum {
        look,
        manipulate,
    } = .look;
    var sel_index: ?usize = null;
    var sel_norm: ?V3f = null;
    var sel_int: ?V3f = null;
    var do_camera_move = true;

    var sel_dist: f32 = 0;
    var sel_resid = V3f.new(0, 0, 0);
    var sel_snap: f32 = 12 * itm;

    var p_velocity = V3f.new(0, 0, 0);
    var grounded = false;

    while (!win.should_exit) {
        if (day_timer.read() > day_length) {
            _ = day_timer.reset();
        }
        if (gcfg.do_daylight_cycle) {
            sun_pitch = 360 * @as(f32, @floatFromInt(day_timer.read())) / day_length;
            if (sun_pitch > 180) //cheese the night
                sun_pitch = 0;
        }
        const cc = cos(radians(sun_pitch));
        light_dir = V3f.new(cos(radians(sun_yaw)) * cc, sin(radians(sun_pitch)), sin(radians(sun_yaw)) * cc).norm();
        const dt = 1.0 / 60.0;
        _ = arena_alloc.reset(.retain_capacity);
        try draw.begin(0x3fbaeaff, win.screen_dimensions.toF());
        cubes.clear();
        for (lumber.items) |l| {
            try cubes.cube(
                l.pos.x(),
                l.pos.y(),
                l.pos.z(),
                l.ext.x(),
                l.ext.y(),
                l.ext.z(),
                tex.rect(),
                null,
            );
        }
        if (pencil.state == .p2) {
            const cu = ColType.Cube.fromBounds(pencil.p1, pencil.p2);
            try cubes.cube(cu.pos.x(), cu.pos.y(), cu.pos.z(), cu.ext.x(), cu.ext.y(), cu.ext.z(), tex.rect(), null);
        }
        win.pumpEvents();

        const is: Gui.InputState = .{
            .mouse_pos = win.mouse.pos,
            .mouse_delta = win.mouse.delta,
            .mouse_left_held = win.mouse.left == .high,
            .mouse_left_clicked = win.mouse.left == .rising,
            .mouse_wheel_delta = win.mouse.wheel_delta.y,
            .mouse_wheel_down = win.mouse.middle == .high,
            .key_state = &win.key_state,
            .keys = win.keys.slice(),
            .mod_state = win.mod,
        };
        try os9gui.beginFrame(is, &win);

        if (win.keydown(.H))
            camera.pos = V3f.new(1, 3, 1);

        const old_pos = camera.pos;
        switch (mode) {
            .look => {
                var vx: f32 = 0;
                var vz: f32 = 0;
                const pspeed = 4;
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

                if (xz_vel.length() > 0 and grounded) {
                    if (footstep_timer.read() > std.time.ns_per_ms * 600) {
                        footstep_timer.reset();
                        //c.alSourcePlay(wood1);
                    }
                }

                if (grounded and win.keydown(.SPACE))
                    p_velocity.yMut().* = 5;

                if (!grounded)
                    p_velocity.yMut().* -= 11 * dt;

                camera.pos = camera.pos.add(p_velocity.scale(dt));

                if (!show_gui and do_camera_move)
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

        if (win.keyPressed(keys.show_menu)) {
            show_gui = !show_gui;
            win.grabMouse(!show_gui);
        }

        if (win.keyPressed(keys.tool_1))
            tool = .none;
        if (win.keyPressed(keys.tool_2)) {
            tool = .pencil;
            pencil = .{};
        }
        if (win.keyPressed(keys.tool_3)) {
            tool = .erase;
        }

        if (win.keyPressed(.R))
            sel_snap *= 2;
        if (win.keyPressed(.F))
            sel_snap /= 2;

        if (win.keyPressed(keys.delete_selected)) {
            if (sel_index) |si| {
                //TODO put in an undo buffer
                _ = lumber.swapRemove(si);
                sel_index = null;
            }
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
        if (gcfg.draw_thirdperson)
            third_cam.pos = third_cam.pos.sub(third_cam.front.scale(3));
        const screen_aspect = draw.screen_dimensions.x / draw.screen_dimensions.y;
        const cam_near = 0.1;
        const cam_far = 500;
        const cmatrix = third_cam.getMatrix(screen_aspect, cam_near, cam_far);

        c.alListener3f(c.AL_POSITION, camera.pos.x(), camera.pos.y(), camera.pos.z());
        c.alListenerfv(c.AL_ORIENTATION, &[_]f32{ camera.front.x(), camera.front.y(), camera.front.z(), 0, 1, 0 });
        //CSM

        const mats = getLightMatrices(camera.fov, screen_aspect, cam_near, cam_far, third_cam.getViewMatrix(), light_dir, planes);
        c.glBindBuffer(c.GL_UNIFORM_BUFFER, light_mat_ubo);
        for (mats, 0..) |mat, i| {
            const ms = @sizeOf([4][4]f32);
            c.glBufferSubData(c.GL_UNIFORM_BUFFER, @as(c_long, @intCast(i)) * ms, ms, &mat.data[0][0]);
        }
        c.glBindBuffer(c.GL_UNIFORM_BUFFER, 0);

        //CSM END

        var point = V3f.zero();
        if (false) {
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
                    } else {}
                },
                .manipulate => {
                    if (win.mouse.left != .high)
                        mode = .look;
                    const lum = &lumber.items[sel_index.?];
                    //lum.origin = lum.origin.add(V3f.new(win.mouse.delta.y * 0.01, 0, win.mouse.delta.x * 0.01)); //win.mouse.delta.x
                    const yw = radians(camera.yaw);
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
        }
        {
            try cubes.cube(cam_bb.pos.x(), cam_bb.pos.y(), cam_bb.pos.z(), cam_bb.ext.x(), cam_bb.ext.y(), cam_bb.ext.z(), Rec(0, 0, 1, 1), null);
        }

        const cam_matrix = switch (gcfg.shadow_map_select) {
            .camera => cmatrix,
            else => mats[gcfg.sun_perspective_index],
        };
        cubes.setData();
        { //shadow map

            c.glBindFramebuffer(c.GL_FRAMEBUFFER, sm.fbo);
            c.glViewport(0, 0, sm.res, sm.res);
            c.glClear(c.GL_DEPTH_BUFFER_BIT);

            //const view = light_proj.mul(light_view);
            cubes.shader = shadow_shader;
            couch.shader = shadow_shader;
            const mod = graph.za.Mat4.identity().scale(V3f.new(sc, sc, sc));
            cubes.drawSimple(graph.za.Mat4.identity(), mod, shadow_shader);
            couch.drawSimple(graph.za.Mat4.identity(), couch_m, shadow_shader);
            cubes.shader = light_shader;
            couch.shader = light_shader;

            //render scene from lights perspective

            gbuffer.updateResolution(win.screen_dimensions.x, win.screen_dimensions.y);
            hdrbuffer.updateResolution(win.screen_dimensions.x, win.screen_dimensions.y);
            c.glBindFramebuffer(c.GL_FRAMEBUFFER, gbuffer.buffer);
            c.glViewport(0, 0, gbuffer.scr_w, gbuffer.scr_h);
            c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

            {
                const sh = gbuffer_shader;
                c.glUseProgram(sh);
                const diffuse_loc = c.glGetUniformLocation(sh, "diffuse_texture");

                c.glUniform1i(diffuse_loc, 0);
                c.glBindTextureUnit(0, cubes.texture.id);

                //const shadow_map_loc = c.glGetUniformLocation(sh, "shadow_map");
                //c.glUniform1i(shadow_map_loc, 1);
                //c.glBindTextureUnit(1, sm.textures);
                c.glBindTextureUnit(1, woodnormal.id);

                c.glBindBufferBase(c.GL_UNIFORM_BUFFER, 0, light_mat_ubo);

                graph.GL.passUniform(sh, "view", cam_matrix);
                graph.GL.passUniform(sh, "model", mod);

                c.glBindVertexArray(cubes.vao);
                c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(cubes.indicies.items.len)), c.GL_UNSIGNED_INT, null);

                c.glBindVertexArray(couch.vao);
                c.glBindTextureUnit(1, couch_normal.id);
                c.glUniform1i(diffuse_loc, 0);
                c.glActiveTexture(c.GL_TEXTURE0 + 0);
                graph.GL.passUniform(sh, "model", couch_m);
                c.glBindTexture(c.GL_TEXTURE_2D, couch.texture.id);
                c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(couch.indicies.items.len)), c.GL_UNSIGNED_INT, null);

                c.glBindVertexArray(pistol.vao);
                c.glBindTextureUnit(1, pistol_norm.id);
                c.glUniform1i(diffuse_loc, 0);
                c.glActiveTexture(c.GL_TEXTURE0 + 0);
                graph.GL.passUniform(
                    sh,
                    "model",
                    Mat4.fromTranslate(
                        camera.pos.add(V3f.new(camera.front.x(), -0.3, camera.front.z())),
                    ).rotate(
                        deg(std.math.atan2(camera.front.x(), camera.front.z())),
                        V3f.new(0, 1, 0),
                    ),
                );
                c.glBindTexture(c.GL_TEXTURE_2D, pistol.texture.id);
                //c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(pistol.indicies.items.len)), c.GL_UNSIGNED_INT, null);

                { //draw the heightmap
                    c.glBindVertexArray(disp_cubes.vao);
                    graph.GL.passUniform(
                        sh,
                        "model",
                        graph.za.Mat4.identity().translate(V3f.new(2, 0, 2)),
                    );
                    c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(disp_cubes.indicies.items.len)), c.GL_UNSIGNED_INT, null);
                }
            }
        }
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

        //const rr = graph.Rec(0, 0, win.screen_dimensions.x, win.screen_dimensions.y);
        //const r2 = graph.Rec(0, 0, win.screen_dimensions.x, -win.screen_dimensions.y);
        //draw.rectTex(rr, r2, .{ .w = win.screen_dimensions.x, .h = win.screen_dimensions.y, .id = gbuffer.albedo });
        if (gcfg.draw_gbuffer == .shaded and false) { //Draw lighting quad
            try light_batch.clear();
            try light_batch.vertices.appendSlice(&.{
                .{ .pos = graph.Vec3f.new(-1, 1, 0), .uv = graph.Vec2f.new(0, 1) },
                .{ .pos = graph.Vec3f.new(-1, -1, 0), .uv = graph.Vec2f.new(0, 0) },
                .{ .pos = graph.Vec3f.new(1, 1, 0), .uv = graph.Vec2f.new(1, 1) },
                .{ .pos = graph.Vec3f.new(1, -1, 0), .uv = graph.Vec2f.new(1, 0) },
            });
            light_batch.pushVertexData();
            c.glUseProgram(deferred_light_shader);
            c.glBindVertexArray(light_batch.vao);
            c.glBindTextureUnit(0, gbuffer.pos);
            c.glBindTextureUnit(1, gbuffer.normal);
            c.glBindTextureUnit(2, gbuffer.albedo);
            c.glBindTextureUnit(3, sm.textures);
            graph.GL.passUniform(deferred_light_shader, "view_pos", third_cam.pos);
            graph.GL.passUniform(deferred_light_shader, "exposure", exposure);
            graph.GL.passUniform(deferred_light_shader, "gamma", gamma);
            graph.GL.passUniform(deferred_light_shader, "light_dir", light_dir);
            graph.GL.passUniform(deferred_light_shader, "screenSize", win.screen_dimensions);
            graph.GL.passUniform(deferred_light_shader, "light_color", sun_color.toCharColor().toFloat());
            graph.GL.passUniform(deferred_light_shader, "cascadePlaneDistances[0]", @as(f32, planes[0]));
            graph.GL.passUniform(deferred_light_shader, "cascadePlaneDistances[1]", @as(f32, planes[1]));
            graph.GL.passUniform(deferred_light_shader, "cascadePlaneDistances[2]", @as(f32, planes[2]));
            graph.GL.passUniform(deferred_light_shader, "cascadePlaneDistances[3]", @as(f32, 400));

            graph.GL.passUniform(deferred_light_shader, "cam_view", third_cam.getViewMatrix());

            c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, @as(c_int, @intCast(light_batch.vertices.items.len)));
        }
        if (true) {
            c.glBindFramebuffer(c.GL_FRAMEBUFFER, hdrbuffer.fb);
            c.glViewport(0, 0, hdrbuffer.scr_w, hdrbuffer.scr_h);
            c.glClear(c.GL_COLOR_BUFFER_BIT);
            c.glClearColor(0, 0, 0, 0);
            //graph.c.glDisable(graph.c.GL_CULL_FACE);
            //defer graph.c.glEnable(graph.c.GL_CULL_FACE);
            defer c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

            c.glDepthMask(c.GL_FALSE);
            defer c.glDepthMask(c.GL_TRUE);
            c.glEnable(c.GL_BLEND);
            c.glBlendFunc(c.GL_ONE, c.GL_ONE);
            c.glBlendEquation(c.GL_FUNC_ADD);
            defer c.glDisable(c.GL_BLEND);
            c.glClear(c.GL_COLOR_BUFFER_BIT);
            { //Draw sun
                try light_batch.clear();
                try light_batch.vertices.appendSlice(&.{
                    .{ .pos = graph.Vec3f.new(-1, 1, 0), .uv = graph.Vec2f.new(0, 1) },
                    .{ .pos = graph.Vec3f.new(-1, -1, 0), .uv = graph.Vec2f.new(0, 0) },
                    .{ .pos = graph.Vec3f.new(1, 1, 0), .uv = graph.Vec2f.new(1, 1) },
                    .{ .pos = graph.Vec3f.new(1, -1, 0), .uv = graph.Vec2f.new(1, 0) },
                });
                light_batch.pushVertexData();
                const sh1 = def_sun_shad;
                c.glUseProgram(sh1);
                c.glBindVertexArray(light_batch.vao);
                c.glBindBufferBase(c.GL_UNIFORM_BUFFER, 0, light_mat_ubo);
                c.glBindTextureUnit(0, gbuffer.pos);
                c.glBindTextureUnit(1, gbuffer.normal);
                c.glBindTextureUnit(2, gbuffer.albedo);
                c.glBindTextureUnit(3, sm.textures);
                graph.GL.passUniform(sh1, "view_pos", third_cam.pos);
                graph.GL.passUniform(sh1, "exposure", exposure);
                graph.GL.passUniform(sh1, "gamma", gamma);
                graph.GL.passUniform(sh1, "light_dir", light_dir);
                graph.GL.passUniform(sh1, "screenSize", win.screen_dimensions);
                graph.GL.passUniform(sh1, "light_color", sun_color.toCharColor().toFloat());
                graph.GL.passUniform(sh1, "cascadePlaneDistances[0]", @as(f32, planes[0]));
                graph.GL.passUniform(sh1, "cascadePlaneDistances[1]", @as(f32, planes[1]));
                graph.GL.passUniform(sh1, "cascadePlaneDistances[2]", @as(f32, planes[2]));
                graph.GL.passUniform(sh1, "cascadePlaneDistances[3]", @as(f32, 400));
                graph.GL.passUniform(sh1, "cam_view", third_cam.getViewMatrix());

                c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, @as(c_int, @intCast(light_batch.vertices.items.len)));
            }

            if (gcfg.lighting) {
                graph.c.glCullFace(graph.c.GL_FRONT);
                defer graph.c.glCullFace(graph.c.GL_BACK);
                const sh = def_light_shad;
                c.glUseProgram(sh);
                c.glBindVertexArray(libatch.vao);
                c.glBindTextureUnit(0, gbuffer.pos);
                c.glBindTextureUnit(1, gbuffer.normal);
                c.glBindTextureUnit(2, gbuffer.albedo);
                graph.GL.passUniform(sh, "view_pos", third_cam.pos);
                graph.GL.passUniform(sh, "exposure", exposure);
                graph.GL.passUniform(sh, "gamma", gamma);
                graph.GL.passUniform(sh, "light_dir", light_dir);
                graph.GL.passUniform(sh, "screenSize", win.screen_dimensions);
                graph.GL.passUniform(sh, "light_color", sun_color.toCharColor().toFloat());
                graph.GL.passUniform(sh, "draw_debug", gcfg.draw_lighting_spheres);

                graph.GL.passUniform(sh, "cam_view", third_cam.getViewMatrix());
                graph.GL.passUniform(sh, "view", cmatrix);

                libatch.draw();
            }
        }

        {
            const sh1 = hdr_shad;
            c.glUseProgram(sh1);
            c.glBindVertexArray(light_batch.vao);
            graph.GL.passUniform(sh1, "exposure", exposure);
            graph.GL.passUniform(sh1, "gamma", gamma);
            c.glBindTextureUnit(0, hdrbuffer.color);
            c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, @as(c_int, @intCast(light_batch.vertices.items.len)));
        }
        { //copy depth buffer
            c.glBindFramebuffer(c.GL_READ_FRAMEBUFFER, gbuffer.buffer);
            c.glBindFramebuffer(c.GL_DRAW_FRAMEBUFFER, 0);
            c.glBlitFramebuffer(0, 0, gbuffer.scr_w, gbuffer.scr_h, 0, 0, gbuffer.scr_w, gbuffer.scr_h, c.GL_DEPTH_BUFFER_BIT, c.GL_NEAREST);
            c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        }
        //graph.c.glDisable(graph.c.GL_CULL_FACE);
        //graph.c.glEnable(graph.c.GL_CULL_FACE);

        const cmatrixsky = third_cam.getMatrix(screen_aspect, 0.1, 3000);
        cubes_st.draw(cmatrixsky, graph.za.Mat4.identity().translate(V3f.new(0, -0.5, 0)).scale(graph.za.Vec3.new(1000, 1000, 1000)));
        //ico.draw(cam_matrix, graph.za.Mat4.identity().scale(graph.za.Vec3.new(1000, 1000, 1000)));
        cubes_grnd.draw(cam_matrix, graph.za.Mat4.identity().scale(graph.za.Vec3.new(1, 1, 1)));
        //draw the wireframe
        switch (tool) {
            else => {},
            .pencil => {
                var o = cam_bb.pos.add(cam_bb.ext.scale(0.5));
                o.yMut().* = cam_bb.pos.y();
                var origin = snapV3(o, sel_snap);
                //origin.data = @divFloor(origin.data, @as(@Vector(3, f32), @splat(sel_snap))) * @as(@Vector(3, f32), @splat(sel_snap));
                if (win.mouse.wheel_delta.y > 0)
                    pencil.grid_y += sel_snap;
                if (win.mouse.wheel_delta.y < 0)
                    pencil.grid_y -= sel_snap;
                origin.yMut().* = pencil.grid_y;
                switch (pencil.state) {
                    .init => {
                        pencil.state = .p1;
                        pencil.grid_y = snap1(cam_bb.pos.y(), sel_snap);
                    },
                    .p1 => {
                        if (doesRayIntersectPlane(camera.pos, camera.front, origin, V3f.new(0, 1, 0))) |p| {
                            const pp = snapV3(p.add(V3f.new(sel_snap / 2, 0, sel_snap / 2)), sel_snap);
                            {
                                const num_lines = 30;
                                const half = @divTrunc(num_lines, 2) * sel_snap;
                                for (0..num_lines + 1) |x| {
                                    const xd: f32 = @as(f32, @floatFromInt(x)) * sel_snap;
                                    const start = pp.add(V3f.new(xd - half, 0, -half));
                                    const starty = pp.add(V3f.new(-half, 0, xd - half));
                                    draw.line3D(start, start.add(V3f.new(0, 0, sel_snap * num_lines)), 0x00ff00ff);
                                    draw.line3D(starty, starty.add(V3f.new(sel_snap * num_lines, 0, 0)), 0x00ff00ff);
                                }
                                const p_feet = o;
                                const penc_base = V3f.new(pp.x(), p_feet.y(), pp.z());
                                draw.line3D(p_feet, penc_base, 0x444444ff);
                                draw.line3D(penc_base, pp, 0x888888ff);
                            }
                            draw.point3D(pp, 0xff0000ff);
                            if (win.mouse.left == .rising) {
                                pencil.state = .p2;
                                pencil.p1 = pp;
                            }
                        }
                    },
                    .p2 => {
                        if (doesRayIntersectPlane(camera.pos, camera.front, origin, V3f.new(0, 1, 0))) |p| {
                            const pp = snapV3(p.add(V3f.new(sel_snap / 2, 0, sel_snap / 2)), sel_snap);
                            const cube = ColType.Cube.fromBounds(pp, pencil.p1);
                            //draw.cube(cube.pos, cube.ext, 0xffffffff);
                            {
                                const num_lines = 30;
                                for (0..num_lines + 1) |x| {
                                    const half = @divTrunc(num_lines, 2) * sel_snap;
                                    const xd: f32 = @as(f32, @floatFromInt(x)) * sel_snap;
                                    const start = pp.add(V3f.new(xd - half, 0, -half));
                                    const starty = pp.add(V3f.new(-half, 0, xd - half));
                                    draw.line3D(start, start.add(V3f.new(0, 0, sel_snap * num_lines)), 0x00ff00ff);
                                    draw.line3D(starty, starty.add(V3f.new(sel_snap * num_lines, 0, 0)), 0x00ff00ff);
                                }
                            }
                            draw.point3D(pp, 0xff0000ff);
                            pencil.p2 = pp;
                            if (win.mouse.left == .rising) {
                                pencil.state = .init;
                                if (@reduce(.Mul, cube.ext.data) != 0)
                                    try lumber.append(cube);
                            }
                        }
                    },
                }
            },
        }

        try draw.flush(null, camera);
        graph.c.glClear(graph.c.GL_DEPTH_BUFFER_BIT);
        if (gcfg.draw_gbuffer != .shaded) {
            const rr = graph.Rec(0, 0, win.screen_dimensions.x, win.screen_dimensions.y);
            const tr = graph.Rec(0, 0, win.screen_dimensions.x, -win.screen_dimensions.y);
            draw.rectTex(rr, tr, .{ .id = switch (gcfg.draw_gbuffer) {
                .pos => gbuffer.pos,
                .normal => gbuffer.normal,
                .albedo => gbuffer.albedo,
                .shaded => unreachable,
            }, .w = win.screen_dimensions.x, .h = win.screen_dimensions.y });
        }
        { //draw a gizmo at crosshair
            const p = camera.pos.add(camera.front.scale(1));
            const l = 0.08;
            draw.line3D(p, p.add(V3f.new(l, 0, 0)), 0xff0000ff);
            draw.line3D(p, p.add(V3f.new(0, l, 0)), 0x00ff00ff);
            draw.line3D(p, p.add(V3f.new(0, 0, l)), 0x0000ffff);
        }
        if (sel_index) |si| {
            const verts = &lumber.items[si].getVerts();
            const col1 = 0x701c23ff;
            const sel_col = 0x00ff00ff;
            const bot = verts[0..4];
            const top = verts[4..8];
            for (0..4) |i| {
                var col: u32 = col1;
                var colb: u32 = col1;
                var colt: u32 = col1;
                //if norm vertical, shade all 2 or 3
                //else

                //determine if vert lies on selected face and change color
                //does vert cross bottom_horiz equal sel_norm
                const vert = top[i].sub(bot[i]);
                const horiz = bot[@mod(i + 1, 4)].sub(bot[i]);
                const prev_horiz = bot[if (i == 0) 3 else i - 1].sub(bot[i]);
                const n = vert.cross(horiz).norm();
                const pn = prev_horiz.cross(vert).norm();
                if (sel_norm) |sn| {
                    if (n.eql(sn)) {
                        col = sel_col;
                        colt = col;
                        colb = col;
                    }
                    if (pn.eql(sn))
                        col = sel_col;
                    if (sn.eql(V3f.new(0, 1, 0)))
                        colt = sel_col;
                    if (sn.eql(V3f.new(0, -1, 0)))
                        colb = sel_col;
                }
                draw.line3D(bot[i], top[i], col);
                draw.line3D(bot[i], bot[@mod(i + 1, 4)], colb);
                draw.line3D(top[i], top[@mod(i + 1, 4)], colt);
            }
        }
        const MIN_SELECTION_ANGLE_DEG = 20;
        switch (tool) {
            else => {},
            .erase => {
                do_camera_move = true;
                if (win.keydown(.LSHIFT)) {
                    if (sel_index) |si| {
                        const lum = &lumber.items[si];
                        if (sel_norm != null and win.mouse.left == .high) {
                            const n = sel_norm.?;
                            const fp0 = if (n.dot(V3f.new(0, 1, 0)) == 0) sel_int.? else sel_int.?;
                            const fpn = blk: {
                                if (n.dot(V3f.new(0, 1, 0)) == 0) {
                                    //If the camera's pitch is close to zero, choose a plane perpendicular to the face and up
                                    if (@abs(camera.front.y()) < sin(radians(10))) {
                                        break :blk n.cross(V3f.new(0, 1, 0));
                                    }

                                    break :blk V3f.new(0, 1, 0);
                                }
                                break :blk sel_int.?.sub(camera.pos).mul(V3f.new(1, 0, 1)).norm();
                            };
                            const dp = n.dot(camera.front);
                            if (dp > cos(radians(MIN_SELECTION_ANGLE_DEG)) or dp < -1) {

                                //Don't do anything
                            } else {
                                //Create a plane at the cameras feet
                                //extract non normal
                                const p0 = lum.getPlane0(n);
                                //Determine where the cameras ray intersects this plane
                                if (doesRayIntersectPlane(camera.pos, camera.front, fp0, fpn)) |int| {
                                    draw.line3D(fp0, int, 0xff0000ff);
                                    //resize the cube so that it lies on this point

                                    const normal_dist = snap1(int.sub(p0).dot(n), sel_snap);
                                    lum.* = lum.addInDir(normal_dist, sel_norm.?);
                                }
                            }
                            const p0 = sel_int.?;
                            if (n.dot(V3f.new(0, 1, 0)) == 0 and false) { //Horizontal faces
                                const c0 = camera.pos;
                                const cf = camera.front;
                                //const a = n;
                                //const b = cf.scale(-1);
                                //const c_ = c0.sub(p0);
                                //const od = (c_.x() * b.z() - b.x() * c_.z()) / (a.x() * b.z() - b.x() * a.z());
                                //const pd = (a.x() * c_.z() - c_.x() * a.z()) / (a.x() * b.z() - b.x() * a.z());
                                const sol = cramers3D(
                                    cf.mul(V3f.new(1, 0, 1)).norm(),
                                    n.scale(-1),
                                    V3f.new(1, 1, 1),
                                    p0.sub(c0).mul(V3f.new(1, 0, 1)),
                                    //c_.mul(V3f.new(1, 0, 1)),
                                );
                                //const sol = cramers2D(.{ .x = a.x(), .y = a.z() }, .{ .x = b.x(), .y = b.z() }, .{ .x = c_.x(), .y = c_.z() });
                                const od = sol.y();
                                const pd = sol.x();
                                draw.line3D(p0, p0.add(n.scale(od)), 0xff0000ff);
                                draw.line3D(p0, p0.add(cf.scale(pd)), 0x00ff00ff);
                                const delta = od;
                                const new_int = sel_int.?.add(n.scale(od));
                                //Stop moving if the new position is greater than a max distance
                                //pd must be positive, otherwise the players view is intersecting the plane behind front
                                const max_plane_dist = 10;
                                if (new_int.sub(c0).length() < max_plane_dist and pd > 0) {
                                    lum.* = lum.addInDir(delta, sel_norm.?);
                                    sel_int.? = new_int;
                                }
                                draw.textFmt(.{ .x = 400, .y = 400 }, "pd {d}, od {d}", .{ pd, od }, &font, 12, 0xffffffff);
                            } else { //Vertical faces

                            }
                            //The line intersection will occur behind camera at angles greater than 0
                            //Next, prevent creating negative extents,
                            //Snap

                        } else {
                            if (doesRayIntersectBoundingBox(3, f32, lum.pos.data, lum.pos.add(lum.ext).data, camera.pos.data, camera.front.data)) |int| {
                                const p = V3f.new(int[0], int[1], int[2]);
                                var norm: @Vector(3, f32) = @splat(0);
                                const pa = p.toArray();
                                const ex = lum.ext.toArray();
                                for (lum.pos.toArray(), 0..) |dim, ind| {
                                    if (dim == pa[ind]) {
                                        norm[ind] = -1;
                                        break;
                                    }
                                    if (dim + ex[ind] == pa[ind]) {
                                        norm[ind] = 1;
                                        break;
                                    }
                                }

                                const n = V3f{ .data = norm };
                                sel_norm = n;
                                sel_int = p;
                                //Draw outline of face rather than normal
                            } else { //If we don't intersect the box, which edge are we closest to
                                sel_norm = null;
                                const normals = [6]V3f{
                                    V3f.new(-1, 0, 0), //left
                                    V3f.new(1, 0, 0), //right
                                    V3f.new(0, -1, 0), //down
                                    V3f.new(0, 1, 0), //up
                                    V3f.new(0, 0, -1), //back
                                    V3f.new(0, 0, 1), //forward
                                };
                                for (normals) |n| {
                                    const d = n.dot(camera.front);
                                    if (d >= 0) {
                                        //for each normal, test if camera ray intersects a bounding box pointing out from normal
                                        const positive = n.dot(V3f.new(1, 1, 1)) > 0;
                                        //TODO what should this magic num be?
                                        const min = if (positive) lum.pos else lum.pos.add(n.scale(100));
                                        const max = if (positive) lum.pos.add(lum.ext.add(n.scale(100))) else lum.pos.add(lum.ext);
                                        if (doesRayIntersectBBZ(camera.pos, camera.front, min, max)) |inti| {
                                            sel_norm = n;
                                            sel_int = inti;
                                            break;
                                        }
                                    }
                                }
                            }
                            if (sel_norm) |n| { //Draw the normal we have selected

                                //Prevent selections at min acute angle
                                if (n.dot(camera.front) > cos(radians(MIN_SELECTION_ANGLE_DEG)))
                                    sel_norm = null;
                                const pl = lum.getPlane0(n);
                                draw.line3D(
                                    pl,
                                    pl.add(n),
                                    0x00ffffff,
                                );
                            }
                        }
                    }
                } else {
                    sel_norm = null; //Reset the face selection once we let go of shift
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
                            //mode = .manipulate;
                            sel_index = i;
                            sel_dist = nearest;
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
                    } else {
                        if (win.mouse.left == .high)
                            sel_index = null;
                    }
                }
            },
            .none => {},
        }
        draw.textFmt(.{ .x = 0, .y = 0 }, "pos [{d:.2}, {d:.2}, {d:.2}]\nyaw: {d}\npitch: {d}\ngrounded {any}\ntool: {s}\nsnap: {d}\nPress {s} to show menu\n", .{
            cam_bb.pos.x(),
            cam_bb.pos.y(),
            cam_bb.pos.z(),
            camera.yaw,
            camera.pitch,
            grounded,
            @tagName(tool),
            sel_snap / 2.54 * 100,
            @tagName(keys.show_menu),
        }, &font, 12, 0xffffffff);

        if (show_gui) {
            if (gcfg.draw_wireframe)
                graph.c.glPolygonMode(graph.c.GL_FRONT_AND_BACK, graph.c.GL_FILL);
            const gw = 1000; //Gui units
            const gh = 500;
            const sw: f32 = @floatFromInt(win.screen_dimensions.x);
            const sh: f32 = @floatFromInt(win.screen_dimensions.y);
            const win_rect = blk: {
                while ((gw * os9gui.scale) / sw < 0.7 and (gh * os9gui.scale) / sh < 0.9) {
                    if (os9gui.scale < 1) {
                        os9gui.scale = 1;
                    } else {
                        os9gui.scale += 1;
                    }
                }
                while (gw * os9gui.scale > sw or gh * os9gui.scale > sh) {
                    if (os9gui.scale > 2) {
                        os9gui.scale -= 1;
                    } else {
                        os9gui.scale -= 0.1;
                    }
                }
                const ww = gw * os9gui.scale;
                const wh = gh * os9gui.scale;
                break :blk graph.Rec(
                    (sw - ww) / 2,
                    (sh - wh) / 2,
                    ww,
                    wh,
                );
            };

            //const win_rect = graph.Rec(0, 0, win.screen_dimensions.x, win.screen_dimensions.y).inset(@floatFromInt(@divTrunc(win.screen_dimensions.y, 3)));
            if (try os9gui.beginTlWindow(win_rect)) {
                defer os9gui.endTlWindow();
                {
                    switch (try os9gui.beginTabs(&gcfg.tab)) {
                        .main => {
                            _ = try os9gui.beginV();
                            defer os9gui.endL();
                            if (os9gui.button("quit game"))
                                win.should_exit = true;
                            if (os9gui.button("go home"))
                                camera.pos = camera_spawn;
                            if (os9gui.button("music"))
                                c.alSourcePlay(audio_source);

                            os9gui.sliderEx(&camera.fov, 30, 120, "fov {d:.0}", .{camera.fov});
                            if (os9gui.checkbox("wireframe", &gcfg.draw_wireframe)) {
                                graph.c.glPolygonMode(graph.c.GL_FRONT_AND_BACK, if (gcfg.draw_wireframe) graph.c.GL_LINE else graph.c.GL_FILL);
                                c.alSourcePlay(ls);
                            }
                            if (os9gui.checkbox("thirdperson", &gcfg.draw_thirdperson))
                                c.alSourcePlay(ls);
                            os9gui.hr();

                            try os9gui.enumCombo("current tool", .{}, &tool);
                            {
                                _ = try os9gui.beginH(2);
                                defer os9gui.endL();
                                os9gui.sliderEx(&sun_yaw, 0, 360, "sun yaw :{d:.0}", .{sun_yaw});
                                os9gui.sliderEx(&sun_pitch, 0, 180, "sun pitch :{d:.0}", .{sun_pitch});
                            }
                            try os9gui.colorPicker(&sun_color);
                            os9gui.label("{x}", .{sun_color.toInt()});
                            os9gui.sliderEx(&exposure, 0, 4, "exposure {d:.2}", .{exposure});
                            os9gui.sliderEx(&gamma, 0.1, 4, "gamma {d:.2}", .{gamma});
                        },
                        .graphics => {
                            _ = try os9gui.beginV();
                            defer os9gui.endL();
                            _ = os9gui.checkbox("do lighting", &gcfg.lighting);
                            _ = os9gui.checkbox("draw lighting spheres", &gcfg.draw_lighting_spheres);
                            {
                                _ = try os9gui.beginH(2);
                                //_ = try os9gui.beginL(Gui.HorizLayout{ .count = 2 });
                                defer os9gui.endL();
                                try os9gui.radio(&gcfg.shadow_map_select);
                                os9gui.sliderEx(&gcfg.sun_perspective_index, 0, CASCADE_COUNT - 1, "cascade level: {d}", .{gcfg.sun_perspective_index});
                            }
                            try os9gui.radio(&gcfg.draw_gbuffer);
                            os9gui.hr();
                            if (try os9gui.numberCombo("shadow resolution: {d}", .{sm.res}, &.{ 256, 512, 1024, 2048, 4096 }, &sm.res)) {
                                c.glDeleteFramebuffers(1, &sm.fbo);
                                c.glDeleteTextures(1, &sm.textures);
                                sm = create3DDepthMap(sm.res, CASCADE_COUNT);
                            }
                            {
                                _ = try os9gui.beginL(Gui.HorizLayout{ .count = 2 });
                                defer os9gui.endL();
                                os9gui.label("Shadow camera planes: ", .{});
                                _ = try os9gui.beginL(Gui.HorizLayout{ .count = planes.len });
                                defer os9gui.endL();
                                for (&planes) |*plane| {
                                    try os9gui.textboxNumber(plane);
                                }
                            }
                        },
                        .keyboard => {
                            _ = try os9gui.beginV();
                            defer os9gui.endL();
                            const info = @typeInfo(@TypeOf(keys));
                            inline for (info.Struct.fields) |field| {
                                os9gui.label("{s}: {s}", .{ field.name, @tagName(@field(keys, field.name)) });
                            }
                        },
                        .info => {
                            if (os9gui.gui.getArea()) |area| {
                                os9gui.gui.drawTextFmt("This is the game", .{}, area, 20 * os9gui.scale, graph.CharColor.Black, .{ .justify = .left }, &os9gui.font);
                            }
                        },
                        else => {},
                    }
                    os9gui.endTabs();
                }
            }

            try os9gui.endFrame(&draw);
            if (gcfg.draw_wireframe)
                graph.c.glPolygonMode(graph.c.GL_FRONT_AND_BACK, graph.c.GL_LINE);
        }
        //const rr = graph.Rec(0, 0, win.screen_dimensions.x, win.screen_dimensions.y);
        //const r2 = graph.Rec(0, 0, win.screen_dimensions.x, -win.screen_dimensions.y);
        //draw.rectTex(rr, r2, .{ .w = win.screen_dimensions.x, .h = win.screen_dimensions.y, .id = hdrbuffer.color });
        try draw.end(camera);
        win.swap();
    }
}
