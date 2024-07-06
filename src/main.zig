const std = @import("std");
const graph = @import("graphics.zig");
const gui = @import("gui.zig");
const Gui = graph.Gui;
const V2f = graph.Vec2f;
const V3f = graph.za.Vec3;
const Mat4 = graph.za.Mat4;
const Rec = graph.Rec;
const Col3d = @import("col3d.zig");

const pow = std.math.pow;
const sqrt = std.math.sqrt;
const cos = std.math.cos;
const sin = std.math.sin;
const radians = std.math.degreesToRadians;

const gui_app = @import("gui_app.zig");
const Os9Gui = gui_app.Os9Gui;
const itm = 0.0254;
const c = graph.c;
//TODO
//load shaders at runtime rather than embedding at compile time. Allows for faster shader prototyping

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

pub fn main() !void {
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
    const ColType = Col3d.CollisionType(graph.Rect, graph.za.Vec3);

    const Arg = graph.ArgGen.Arg;
    const args = try graph.ArgGen.parseArgs(&.{
        Arg("model", .string, "model to load"),
        Arg("texture", .string, "texture to load"),
        Arg("scale", .number, "scale the model"),
    }, &arg_it);

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

    var footstep_timer = try std.time.Timer.start();
    //checkAl();
    const ls = try loadOgg(lifetime_alloc, "stop.ogg", V3f.zero());
    checkAl();
    //c.alSourcePlay(audio_source);

    const init_size = 72;
    var font = try graph.Font.init(alloc, std.fs.cwd(), "fonts/roboto.ttf", init_size, win.getDpi(), .{});
    defer font.deinit();

    var draw = graph.ImmediateDrawingContext.init(alloc, win.getDpi());
    defer draw.deinit();

    var os9gui = try Os9Gui.init(alloc, std.fs.cwd(), 2);
    defer os9gui.deinit();
    var show_gui = false;
    var tab: enum { main, graphics, keyboard, info, sound } = .main;
    var draw_wireframe = false;
    var draw_thirdperson = false;
    var shadow_map_select: enum { camera, sun, depth } = .camera;
    var sun_perspective_index: usize = 0;

    var camera = graph.Camera3D{};
    const camera_spawn = V3f.new(1, 3, 1);
    camera.pos = camera_spawn;
    const tex = try graph.Texture.initFromImgFile(alloc, std.fs.cwd(), args.texture orelse "two4.png", .{});
    const ggrid = try graph.Texture.initFromImgFile(alloc, std.fs.cwd(), args.texture orelse "graygrid.png", .{});
    const sky_tex = try graph.Texture.initFromImgFile(alloc, std.fs.cwd(), args.texture orelse "sky06.png", .{
        .mag_filter = graph.c.GL_NEAREST,
    });
    const light_shader = try graph.Shader.loadFromFilesystem(alloc, std.fs.cwd(), &.{
        .{ .path = "src/graphics/shader/light.vert", .t = .vert },
        .{ .path = "src/graphics/shader/light.frag", .t = .frag },
    });
    const shadow_shader = try graph.Shader.loadFromFilesystem(alloc, std.fs.cwd(), &.{
        .{ .path = "src/graphics/shader/shadow_map.vert", .t = .vert },
        .{ .path = "src/graphics/shader/shadow_map.frag", .t = .frag },
        .{ .path = "src/graphics/shader/shadow_map.geom", .t = .geom },
    });

    var planes = [_]f32{ 3, 8, 25 };

    var sm = create3DDepthMap(2048, CASCADE_COUNT);
    var sun_yaw: f32 = 225;
    var sun_pitch: f32 = 61;
    var light_dir = V3f.new(-20, 50, -20).norm();
    var sun_color = graph.Hsva.fromInt(graph.ptypes.charColorToInt(graph.CharColor.new(240, 187, 117, 255)));

    var light_mat_ubo: c_uint = 0;
    {
        c.glGenBuffers(1, &light_mat_ubo);
        c.glBindBuffer(c.GL_UNIFORM_BUFFER, light_mat_ubo);
        c.glBufferData(c.GL_UNIFORM_BUFFER, @sizeOf([4][4]f32) * 16, null, c.GL_STATIC_DRAW);
        c.glBindBufferBase(c.GL_UNIFORM_BUFFER, 0, light_mat_ubo);
        c.glBindBuffer(c.GL_UNIFORM_BUFFER, 0);

        const li = c.glGetUniformBlockIndex(light_shader, "LightSpaceMatrices");
        c.glUniformBlockBinding(light_shader, li, 0);
    }

    graph.c.glEnable(graph.c.GL_CULL_FACE);
    graph.c.glCullFace(graph.c.GL_BACK);

    var cubes_grnd = graph.Cubes.init(alloc, ggrid, draw.textured_tri_3d_shader);
    defer cubes_grnd.deinit();
    cubes_grnd.setData();

    var cubes = graph.Cubes.init(alloc, tex, light_shader);
    defer cubes.deinit();

    var lumber = std.ArrayList(ColType.Cube).init(alloc);
    {
        if (std.fs.cwd().openFile("lumber.json", .{}) catch null) |infile| {
            const sl = try infile.reader().readAllAlloc(alloc, std.math.maxInt(usize));
            defer alloc.free(sl);
            const j = try std.json.parseFromSlice([]const ColType.Cube, alloc, sl, .{});
            defer j.deinit();
            try lumber.appendSlice(j.value);
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
        const outfile = std.fs.cwd().createFile("lumber.json", .{}) catch unreachable;
        std.json.stringify(lumber.items, .{}, outfile.writer()) catch unreachable;
        outfile.close();
    }

    var cubes_st = try loadObj(alloc, std.fs.cwd(), "sky.obj", 0.3, sky_tex, draw.textured_tri_3d_shader);
    defer cubes_st.deinit();

    const couch_tex = try graph.Texture.initFromImgFile(alloc, std.fs.cwd(), "drum.png", .{});
    const couch_m = graph.za.Mat4.identity().translate(V3f.new(3, 0, 4));
    var couch = try loadObj(alloc, std.fs.cwd(), "barrel.obj", 0.03, couch_tex, draw.textured_tri_3d_shader);
    defer couch.deinit();

    cubes_st.setData();
    win.grabMouse(true);

    var tool: enum {
        none,
        pencil,
    } = .none;

    var pencil: struct {
        state: enum { init, p1, p2 } = .init,
        grid_y: f32 = 0,
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
    var sel_snap: f32 = 12 * itm;

    var p_velocity = V3f.new(0, 0, 0);
    var grounded = false;

    while (!win.should_exit) {
        const dt = 1.0 / 60.0;
        _ = arena_alloc.reset(.retain_capacity);
        try draw.begin(0x3fbaeaff, win.screen_dimensions.toF());
        cubes.clear();
        for (lumber.items) |l| {
            try cubes.cube(l.pos.x(), l.pos.y(), l.pos.z(), l.ext.x(), l.ext.y(), l.ext.z(), tex.rect(), null);
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

                if (!show_gui)
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

        if (win.keyPressed(.TAB)) {
            show_gui = !show_gui;
            win.grabMouse(!show_gui);
        }

        if (win.keyPressed(._1))
            tool = .none;
        if (win.keyPressed(._2)) {
            tool = .pencil;
            pencil = .{};
        }

        if (win.keyPressed(.R))
            sel_snap *= 2;
        if (win.keyPressed(.F))
            sel_snap /= 2;

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
        if (draw_thirdperson)
            third_cam.pos = third_cam.pos.sub(third_cam.front.scale(3));
        const screen_aspect = draw.screen_dimensions.x / draw.screen_dimensions.y;
        const cam_near = 0.1;
        const cam_far = 1000;
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
                    }
                },
                .manipulate => {
                    if (win.mouse.left != .high)
                        mode = .look;
                    const lum = &lumber.items[sel_index];
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

        const cam_matrix = switch (shadow_map_select) {
            .camera => cmatrix,
            else => mats[sun_perspective_index],
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

            c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
            c.glViewport(0, 0, win.screen_dimensions.x, win.screen_dimensions.y);
            c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

            {
                c.glUseProgram(light_shader);
                const diffuse_loc = c.glGetUniformLocation(light_shader, "diffuse_texture");

                c.glUniform1i(diffuse_loc, 0);
                c.glBindTextureUnit(0, cubes.texture.id);

                const shadow_map_loc = c.glGetUniformLocation(light_shader, "shadow_map");
                c.glUniform1i(shadow_map_loc, 1);
                c.glBindTextureUnit(1, sm.textures);

                c.glBindBufferBase(c.GL_UNIFORM_BUFFER, 0, light_mat_ubo);

                graph.GL.passUniform(light_shader, "cascadePlaneDistances[0]", @as(f32, planes[0]));
                graph.GL.passUniform(light_shader, "cascadePlaneDistances[1]", @as(f32, planes[1]));
                graph.GL.passUniform(light_shader, "cascadePlaneDistances[2]", @as(f32, planes[2]));
                graph.GL.passUniform(light_shader, "cascadePlaneDistances[3]", @as(f32, 400));

                graph.GL.passUniform(light_shader, "view", cam_matrix);
                graph.GL.passUniform(light_shader, "model", mod);
                graph.GL.passUniform(light_shader, "view_pos", third_cam.pos);
                graph.GL.passUniform(light_shader, "light_dir", light_dir);
                graph.GL.passUniform(light_shader, "light_color", sun_color.toCharColor().toFloat());

                c.glBindVertexArray(cubes.vao);
                c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(cubes.indicies.items.len)), c.GL_UNSIGNED_INT, null);

                c.glBindVertexArray(couch.vao);
                c.glUniform1i(diffuse_loc, 0);
                c.glActiveTexture(c.GL_TEXTURE0 + 0);
                graph.GL.passUniform(light_shader, "model", couch_m);
                c.glBindTexture(c.GL_TEXTURE_2D, couch.texture.id);
                c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(couch.indicies.items.len)), c.GL_UNSIGNED_INT, null);
            }
        }

        cubes_st.draw(cam_matrix, graph.za.Mat4.identity().scale(graph.za.Vec3.new(1000, 1000, 1000)));
        cubes_grnd.draw(cam_matrix, graph.za.Mat4.identity().scale(graph.za.Vec3.new(1, 1, 1)));
        switch (tool) {
            .none => {},
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
                                    const start = origin.add(V3f.new(xd - half, 0, -half));
                                    const starty = origin.add(V3f.new(-half, 0, xd - half));
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
                            draw.cube(cube.pos, cube.ext, 0xffffffff);
                            {
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
                            draw.point3D(pp, 0xff0000ff);
                            if (win.mouse.left == .rising) {
                                pencil.state = .init;
                                pencil.p2 = pp;
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
        { //draw a gizmo at crosshair
            const p = camera.pos.add(camera.front.scale(1));
            const l = 0.08;
            draw.line3D(p, p.add(V3f.new(l, 0, 0)), 0xff0000ff);
            draw.line3D(p, p.add(V3f.new(0, l, 0)), 0x0000ffff);
            draw.line3D(p, p.add(V3f.new(0, 0, l)), 0x00ff00ff);
        }
        draw.textFmt(.{ .x = 0, .y = 0 }, "pos [{d:.2}, {d:.2}, {d:.2}]\nyaw: {d}\npitch: {d}\ngrounded {any}\ntool: {s}", .{
            cam_bb.pos.x(),
            cam_bb.pos.y(),
            cam_bb.pos.z(),
            camera.yaw,
            camera.pitch,
            grounded,
            @tagName(tool),
        }, &font, 12, 0xffffffff);

        if (show_gui) {
            if (draw_wireframe)
                graph.c.glPolygonMode(graph.c.GL_FRONT_AND_BACK, graph.c.GL_FILL);
            const win_rect = graph.Rec(0, 0, win.screen_dimensions.x, win.screen_dimensions.y).inset(@floatFromInt(@divTrunc(win.screen_dimensions.y, 3)));
            if (try os9gui.beginTlWindow(win_rect)) {
                defer os9gui.endTlWindow();
                {
                    switch (try os9gui.beginTabs(&tab)) {
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
                            if (os9gui.checkbox("wireframe", &draw_wireframe)) {
                                graph.c.glPolygonMode(graph.c.GL_FRONT_AND_BACK, if (draw_wireframe) graph.c.GL_LINE else graph.c.GL_FILL);
                                c.alSourcePlay(ls);
                            }
                            if (os9gui.checkbox("thirdperson", &draw_thirdperson))
                                c.alSourcePlay(ls);
                            os9gui.hr();

                            try os9gui.enumCombo("current tool", .{}, &tool);
                            {
                                _ = try os9gui.beginH(2);
                                defer os9gui.endL();
                                os9gui.sliderEx(&sun_yaw, 0, 360, "sun yaw :{d:.0}", .{sun_yaw});
                                os9gui.sliderEx(&sun_pitch, 0, 180, "sun pitch :{d:.0}", .{sun_pitch});
                                const cc = cos(radians(sun_pitch));
                                light_dir = V3f.new(cos(radians(sun_yaw)) * cc, sin(radians(sun_pitch)), sin(radians(sun_yaw)) * cc).norm();
                            }
                            try os9gui.colorPicker(&sun_color);
                        },
                        .graphics => {
                            _ = try os9gui.beginV();
                            defer os9gui.endL();
                            {
                                _ = try os9gui.beginH(2);
                                //_ = try os9gui.beginL(Gui.HorizLayout{ .count = 2 });
                                defer os9gui.endL();
                                try os9gui.radio(&shadow_map_select);
                                os9gui.sliderEx(&sun_perspective_index, 0, CASCADE_COUNT - 1, "cascade level: {d}", .{sun_perspective_index});
                            }
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
            if (draw_wireframe)
                graph.c.glPolygonMode(graph.c.GL_FRONT_AND_BACK, graph.c.GL_LINE);
        }
        try draw.end(camera);
        win.swap();
    }
}
