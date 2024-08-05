const std = @import("std");
pub const c = @import("graphics/c.zig");
pub const za = @import("zalgebra");
pub const ArgGen = @import("arg_gen.zig");

pub const Tiled = @import("tiled.zig");

const Alloc = std.mem.Allocator;
const Dir = std.fs.Dir;

const lcast = std.math.lossyCast;
pub const Gui = @import("gui.zig");
pub const SparseSet = @import("graphics/sparse_set.zig").SparseSet;
pub const MarioData = @import("data_mario.zig");
pub const Collision = @import("col.zig");
pub const SpatialGrid = @import("spatial_grid.zig");
pub const Ecs = @import("registry.zig");
pub const Lua = @import("lua.zig");
pub const V3 = za.Vec3;
pub const AssetBake = @import("assetbake.zig");

pub const ptypes = @import("graphics/types.zig");
pub const Rect = ptypes.Rect;
pub const Rec = Rect.NewAny;
pub const Vec2f = ptypes.Vec2f;
pub const Vec2i = ptypes.Vec2i;
pub const Vec3f = ptypes.Vec3f;
pub const Orientation = ptypes.Orientation;
pub const Camera2D = ptypes.Camera2D;
pub const Camera3D = ptypes.Camera3D;
pub const FontUtil = @import("graphics/font.zig");
pub const Font = FontUtil.Font;
pub const Texture = FontUtil.Texture;
pub const Bitmap = FontUtil.Bitmap;
pub const RectPack = FontUtil.RectPack;
pub const CharColor = ptypes.CharColor;
pub const Hsva = ptypes.Hsva;
pub const Colori = ptypes.Colori;
pub const itc = ptypes.itc;
pub const Shader = GL.Shader;
pub const gui_app = @import("gui_app.zig");
pub const Os9Gui = gui_app.Os9Gui;

pub const GL = @import("graphics/gl.zig");
pub const glID = GL.glID;

pub const SDL = @import("graphics/SDL.zig");
pub const Bind = SDL.Bind;

pub inline fn ptToPx(dpi: f32, pt: f32) f32 {
    return pt / 72 * dpi;
}

pub inline fn pxToPt(dpi: f32, px: f32) f32 {
    return px * 72 / dpi;
}

pub fn basicGraphUsage() !void {
    const graph = @This();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    var binds = graph.Bind(&.{
        .{ "my_bind", "a" },
        .{ "other_bind", "c" },
    }).init();

    var win = try graph.SDL.Window.createWindow("My window", .{
        // Optional, see Window.createWindow definition for full list of options
        .window_size = .{ .x = 800, .y = 600 },
    });
    defer win.destroyWindow();

    var draw = graph.ImmediateDrawingContext.init(alloc, win.getDpi());
    defer draw.deinit();

    var font = try graph.Font.init(alloc, std.fs.cwd(), "fonts/roboto.ttf", 14, win.getDpi(), .{});
    defer font.deinit();

    while (!win.should_exit) {
        try draw.begin(0x2f2f2fff, win.screen_dimensions.toF());
        win.pumpEvents(); //Important that this is called after draw.begin for input lag reasons
        for (win.keys.slice()) |key| {
            switch (binds.get(key.scancode)) {
                .my_bind => std.debug.print("bind pressed\n", .{}),
                else => {},
            }
        }

        var kit = binds.heldIterator(&win);
        while (kit.next()) |m| {
            switch (m) {
                .my_bind => std.debug.print("My bind held\n", .{}),
                .other_bind => std.debug.print("other\n", .{}),
                else => {},
            }
        }

        draw.text(.{ .x = 50, .y = 300 }, "Hello", &font, 16, 0xffffffff);
        try draw.end();
        win.swap();
    }
}

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
        const bit = try Bitmap.initBlank(alloc, atlas_size, atlas_size, .rgba_8);

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

    pub fn getT(self: *Self, name: []const u8, ti: usize) Rect {
        return self.getTexRec(self.getSi(name), ti);
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

            var ret_j: AtlasJson = AtlasJson{ .img_dir_path = try alloc.dupe(u8, json.img_dir_path), .sets = try alloc.alloc(AtlasJson.SetJson, json.sets.len) };

            if (sets_to_load.len == 0) return error.noSets;

            for (sets_to_load, 0..) |item, i| {
                ret_j.sets[i] = .{ .filename = try alloc.dupe(u8, item.filename), .tilesets = try alloc.alloc(SubTileset, item.tilesets.len) };
                for (item.tilesets, 0..) |ts, j| {
                    ret_j.sets[i].tilesets[j] = ts;
                    ret_j.sets[i].tilesets[j].description = try alloc.dupe(u8, ts.description);
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

        var ret_j: AtlasJson = AtlasJson{
            .img_dir_path = try alloc.dupe(u8, json.img_dir_path),
            .sets = try alloc.alloc(AtlasJson.SetJson, json.sets.len),
        };

        if (sets_to_load.len == 0) return error.noSets;

        const img_dir = try dir.openDir(json.img_dir_path, .{});
        //defer img_dir.close();

        var textures = std.ArrayList(Texture).init(alloc);

        for (sets_to_load, 0..) |item, i| {
            try textures.append(try Texture.initFromImgFile(alloc, img_dir, item.filename, .{ .mag_filter = c.GL_NEAREST, .min_filter = c.GL_NEAREST }));

            ret_j.sets[i] = .{ .filename = try alloc.dupe(u8, item.filename), .tilesets = try alloc.alloc(SubTileset, item.tilesets.len) };
            for (item.tilesets, 0..) |ts, j| {
                ret_j.sets[i].tilesets[j] = ts;
                ret_j.sets[i].tilesets[j].description = try alloc.dupe(u8, ts.description);
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

/// A structure that maps indices to a rectangle within a larger rectangle based on various parameters.
/// Useful for tilemaps that include padding
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

//TODO load a font and have a draw.textFmt convenience function with args:(pos, fmt, fmt_args, size);
pub const ImmediateDrawingContext = struct {
    const Self = @This();
    const log = std.log.scoped(.ImmediateDrawingContext);

    pub const VtxFmt = struct {
        pub const Color_2D = packed struct { pos: Vec2f, z: u16, color: u32 };
        pub const Color_Texture_2D = packed struct { pos: Vec2f, uv: Vec2f, z: u16, color: u32 }; // 22 bytes
        pub const Color_3D = packed struct { pos: Vec3f, color: u32 };
        pub const Textured_3D = packed struct { pos: Vec3f, uv: Vec2f, color: u32 };

        //idea for a small vertex, xy are 14.2 or 13.3 fixed point. 2^13 allows for up to 8k with 8 subpixel positions
        //uv are also some fixed point maybe 13.3. These would not be normalized?
        pub const SmallTex = packed struct { x: u16, y: u16, u: u16, v: u16, z: u16 };
        //Total size: 10bytes

        pub fn textured3D(x: f32, y: f32, z: f32, u: f32, v: f32, color: u32) Textured_3D {
            return .{
                .pos = Vec3f.new(x, y, z),
                .uv = Vec2f.new(u, v),
                .color = color,
            };
        }

        pub fn color3D(x: f32, y: f32, z: f32, color: u32) Color_3D {
            return .{
                .pos = Vec3f.new(x, y, z),
                .color = color,
            };
        }
    };

    pub const Batches = union(enum) {
        color_tri: NewBatch(VtxFmt.Color_2D, .{ .index_buffer = true, .primitive_mode = .triangles }),
        color_tri_tex: NewBatch(VtxFmt.Color_Texture_2D, .{ .index_buffer = true, .primitive_mode = .triangles }),
        color_line: NewBatch(VtxFmt.Color_2D, .{ .index_buffer = false, .primitive_mode = .lines }),
        color_line3D: NewBatch(VtxFmt.Color_3D, .{ .index_buffer = false, .primitive_mode = .lines }),
        color_point3D: NewBatch(VtxFmt.Color_3D, .{ .index_buffer = false, .primitive_mode = .points }),
        color_cube: NewBatch(VtxFmt.Color_3D, .{ .index_buffer = true, .primitive_mode = .triangles }),
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
    colored_point3d_shader: c_uint,
    textured_tri_shader: c_uint,
    textured_tri_3d_shader: c_uint,
    textured_tri_3d_shader_new: c_uint,
    dpi: f32,

    alloc: Alloc,

    //TODO actually check this and log or panic
    draw_fn_error: enum {
        no,
        yes,
    } = .no,

    screen_dimensions: Vec2f = .{ .x = 0, .y = 0 },

    pub fn init(alloc: Alloc, dpi: f32) Self {
        const SD = "graphics/shader/";
        return Self{
            .alloc = alloc,
            .batches = MapT.init(alloc),
            .dpi = dpi,

            .textured_tri_3d_shader = Shader.simpleShader(@embedFile(SD ++ "alpha_texturequad.vert"), @embedFile(SD ++ "texturequad.frag")),

            .colored_tri_shader = Shader.simpleShader(@embedFile(SD ++ "newtri.vert"), @embedFile(SD ++ "colorquad.frag")),
            .colored_line3d_shader = Shader.simpleShader(@embedFile(SD ++ "line3d.vert"), @embedFile(SD ++ "colorquad.frag")),
            .colored_point3d_shader = Shader.simpleShader(@embedFile(SD ++ "line3d.vert"), @embedFile(SD ++ "point.fsh")),
            .textured_tri_shader = Shader.simpleShader(@embedFile(SD ++ "tex_tri2d.vert"), @embedFile(SD ++ "tex_tri2d.frag")),
            .textured_tri_3d_shader_new = Shader.simpleShader(@embedFile(SD ++ "tex_tri3d.vsh"), @embedFile(SD ++ "tex_tri3d.fsh")),

            .font_shader = Shader.simpleShader(@embedFile(SD ++ "tex_tri2d.vert"), @embedFile(SD ++ "tex_tri2d_alpha.frag")),
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

    fn setErr(self: *Self, e: anyerror) void {
        std.debug.print("ImmediateDrawingContext: {any}\n", .{e});
        self.draw_fn_error = .yes;
    }

    fn drawErr(e: anyerror!void) void {
        e catch |err| {
            log.err("draw function: {any}", .{err});
        };
    }

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
        //stupid, don't enable
        //std.time.sleep(16 * std.time.ns_per_ms);

        const color = ptypes.intToColorF(bg_color);
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
        drawErr(e: {
            const r = rpt;
            const b = &(self.getBatch(.{ .batch_kind = .color_tri, .params = .{ .shader = self.colored_tri_shader } }) catch |err| break :e err).color_tri;
            const z = self.zindex;
            self.zindex += 1;
            b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len)))) catch |err| break :e err;
            b.vertices.appendSlice(&.{
                .{ .z = z, .color = color, .pos = .{ .x = r.x + r.w, .y = r.y + r.h } },
                .{ .z = z, .color = color, .pos = .{ .x = r.x + r.w, .y = r.y } },
                .{ .z = z, .color = color, .pos = .{ .x = r.x, .y = r.y } },
                .{ .z = z, .color = color, .pos = .{ .x = r.x, .y = r.y + r.h } },
            }) catch |err| break :e err;
        });
    }

    /// The colors are wound ccw starting at top left corner
    pub fn rectVertexColors(self: *Self, r: Rect, vert_colors: []const u32) void {
        drawErr(e: {
            const b = &(self.getBatch(.{ .batch_kind = .color_tri, .params = .{
                .shader = self.colored_tri_shader,
                .draw_priority = 0xff,
            } }) catch |err| break :e err).color_tri;
            const z = self.zindex;
            self.zindex += 1;
            b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len)))) catch |err| break :e err;
            b.vertices.appendSlice(&.{
                .{ .z = z, .color = vert_colors[2], .pos = .{ .x = r.x + r.w, .y = r.y + r.h } },
                .{ .z = z, .color = vert_colors[3], .pos = .{ .x = r.x + r.w, .y = r.y } },
                .{ .z = z, .color = vert_colors[0], .pos = .{ .x = r.x, .y = r.y } },
                .{ .z = z, .color = vert_colors[1], .pos = .{ .x = r.x, .y = r.y + r.h } },
            }) catch |err| break :e err;
        });
    }

    pub fn nineSlice(self: *Self, r: Rect, tr: Rect, texture: Texture, scale: f32) void {
        const un = GL.normalizeTexRect(tr, texture.w, texture.h);
        const tbw = un.w / 3;
        const tbh = un.h / 3;
        const bw = tr.w / 3 * scale;
        const bh = tr.h / 3 * scale;
        const Uv = [_]Vec2f{
            //row 1
            .{ .y = un.y, .x = un.x + 0 },
            .{ .y = un.y, .x = un.x + tbw },
            .{ .y = un.y, .x = un.x + un.w - tbw },
            .{ .y = un.y, .x = un.x + un.w },
            //row 2
            .{ .y = un.y + tbh, .x = un.x + 0 },
            .{ .y = un.y + tbh, .x = un.x + tbw },
            .{ .y = un.y + tbh, .x = un.x + un.w - tbw },
            .{ .y = un.y + tbh, .x = un.x + un.w },
            //row 3
            .{ .y = un.y + un.h - tbh, .x = un.x + 0 },
            .{ .y = un.y + un.h - tbh, .x = un.x + tbw },
            .{ .y = un.y + un.h - tbh, .x = un.x + un.w - tbw },
            .{ .y = un.y + un.h - tbh, .x = un.x + un.w },
            //row 4
            .{ .y = un.y + un.h, .x = un.x + 0 },
            .{ .y = un.y + un.h, .x = un.x + tbw },
            .{ .y = un.y + un.h, .x = un.x + un.w - tbw },
            .{ .y = un.y + un.h, .x = un.x + un.w },
        };
        const b = &(self.getBatch(.{ .batch_kind = .color_tri_tex, .params = .{ .shader = self.textured_tri_shader, .texture = texture.id } }) catch return).color_tri_tex;
        const z = self.zindex;
        self.zindex += 1;
        //br, tr, tl, bl
        const i: u32 = @intCast(b.vertices.items.len);
        b.indicies.appendSlice(&.{
            //tl
            i + 0,  i + 4,  i + 1,  i + 4,  i + 5,  i + 1,
            //tm
            i + 1,  i + 5,  i + 2,  i + 5,  i + 6,  i + 2,
            //tr
            i + 2,  i + 6,  i + 3,  i + 6,  i + 7,  i + 3,
            //ml
            i + 4,  i + 8,  i + 5,  i + 8,  i + 9,  i + 5,
            //mm
            i + 5,  i + 9,  i + 6,  i + 9,  i + 10, i + 6,
            //mr
            i + 6,  i + 10, i + 7,  i + 10, i + 11, i + 7,
            //bl
            i + 8,  i + 12, i + 9,  i + 12, i + 13, i + 9,
            //bm
            i + 13, i + 10, i + 9,  i + 13, i + 14, i + 10,
            //br
            i + 10, i + 14, i + 11, i + 14, i + 15, i + 11,
        }) catch |e| {
            self.setErr(e);
            return;
        };

        b.vertices.appendSlice(&.{}) catch |e| {
            self.setErr(e);
            return;
        };

        b.vertices.appendSlice(&.{
            //Row 1
            .{ .z = z, .color = 0xffffffff, .uv = Uv[0], .pos = .{ .y = r.y, .x = r.x } },
            .{ .z = z, .color = 0xffffffff, .uv = Uv[1], .pos = .{ .y = r.y, .x = r.x + bw } },
            .{ .z = z, .color = 0xffffffff, .uv = Uv[2], .pos = .{ .y = r.y, .x = r.x + r.w - bw } },
            .{ .z = z, .color = 0xffffffff, .uv = Uv[3], .pos = .{ .y = r.y, .x = r.x + r.w } },
            //Row 2
            .{ .z = z, .color = 0xffffffff, .uv = Uv[4], .pos = .{ .y = r.y + bh, .x = r.x } },
            .{ .z = z, .color = 0xffffffff, .uv = Uv[5], .pos = .{ .y = r.y + bh, .x = r.x + bw } },
            .{ .z = z, .color = 0xffffffff, .uv = Uv[6], .pos = .{ .y = r.y + bh, .x = r.x + r.w - bw } },
            .{ .z = z, .color = 0xffffffff, .uv = Uv[7], .pos = .{ .y = r.y + bh, .x = r.x + r.w } },
            //Row 3
            .{ .z = z, .color = 0xffffffff, .uv = Uv[8], .pos = .{ .y = r.y + r.h - bh, .x = r.x } },
            .{ .z = z, .color = 0xffffffff, .uv = Uv[9], .pos = .{ .y = r.y + r.h - bh, .x = r.x + bw } },
            .{ .z = z, .color = 0xffffffff, .uv = Uv[10], .pos = .{ .y = r.y + r.h - bh, .x = r.x + r.w - bw } },
            .{ .z = z, .color = 0xffffffff, .uv = Uv[11], .pos = .{ .y = r.y + r.h - bh, .x = r.x + r.w } },
            ////Row 4
            .{ .z = z, .color = 0xffffffff, .uv = Uv[12], .pos = .{ .y = r.y + r.h, .x = r.x } },
            .{ .z = z, .color = 0xffffffff, .uv = Uv[13], .pos = .{ .y = r.y + r.h, .x = r.x + bw } },
            .{ .z = z, .color = 0xffffffff, .uv = Uv[14], .pos = .{ .y = r.y + r.h, .x = r.x + r.w - bw } },
            .{ .z = z, .color = 0xffffffff, .uv = Uv[15], .pos = .{ .y = r.y + r.h, .x = r.x + r.w } },
        }) catch |e| {
            self.setErr(e);
            return;
        };
    }

    pub fn rectTex(self: *Self, r: Rect, tr: Rect, texture: Texture) void {
        self.rectTexTint(r, tr, 0xffffffff, texture);
    }

    pub fn rectTexTint(self: *Self, r: Rect, tr: Rect, col: u32, texture: Texture) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_tri_tex, .params = .{ .shader = self.textured_tri_shader, .texture = texture.id } }) catch return).color_tri_tex;
        const z = self.zindex;
        self.zindex += 1;
        const un = GL.normalizeTexRect(tr, texture.w, texture.h);

        b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len)))) catch return;
        b.vertices.appendSlice(&.{
            .{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y + un.h }, .color = col }, //0
            .{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y }, .color = col }, //1
            .{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .uv = .{ .x = un.x, .y = un.y }, .color = col }, //2
            .{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x, .y = un.y + un.h }, .color = col }, //3
        }) catch return;
    }

    pub fn textPx(self: *Self, pos: Vec2f, str: []const u8, font: *Font, px_size: f32, col: u32) void {
        self.text(pos, str, font, pxToPt(self.dpi, px_size), col);
    }

    pub fn text(self: *Self, pos: Vec2f, str: []const u8, font: *Font, pt_size: f32, col: u32) void {
        const SF = (pt_size / font.font_size);
        //const SF = (pxToPt(self.dpi, pt_size)) / font.font_size;
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
            const un = GL.normalizeTexRect(g.tr, font.texture.w, font.texture.h);
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

    pub fn point3D(self: *Self, point: za.Vec3, color: u32) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_point3D, .params = .{ .shader = self.colored_point3d_shader, .camera = ._3d } }) catch unreachable).color_point3D;
        b.vertices.append(.{ .pos = .{ .x = point.x(), .y = point.y(), .z = point.z() }, .color = color }) catch return;
    }

    pub fn line3D(self: *Self, start_point: za.Vec3, end_point: za.Vec3, color: u32) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_line3D, .params = .{ .shader = self.colored_line3d_shader, .camera = ._3d } }) catch unreachable).color_line3D;
        b.vertices.append(.{ .pos = .{ .x = start_point.x(), .y = start_point.y(), .z = start_point.z() }, .color = color }) catch return;
        b.vertices.append(.{ .pos = .{ .x = end_point.x(), .y = end_point.y(), .z = end_point.z() }, .color = color }) catch return;
    }

    pub fn cube(self: *Self, pos: za.Vec3, ext: za.Vec3, color: u32) void {
        const px = pos.x();
        const py = pos.y();
        const pz = pos.z();
        const sx = ext.x();
        const sy = ext.y();
        const sz = ext.z();
        const b = &(self.getBatch(.{ .batch_kind = .color_cube, .params = .{
            .shader = self.colored_line3d_shader,
            .camera = ._3d,
        } }) catch unreachable).color_cube;
        b.indicies.appendSlice(&GL.genCubeIndicies(@as(u32, @intCast(b.vertices.items.len)))) catch return;
        // zig fmt: off
        b.vertices.appendSlice(&.{
        // front
        VtxFmt.color3D(px + sx, py + sy, pz, color), //0
        VtxFmt.color3D(px + sx, py     , pz, color), //1
        VtxFmt.color3D(px     , py     , pz, color), //2
        VtxFmt.color3D(px     , py + sy, pz, color), //3

        // backcolor
        VtxFmt.color3D(px     , py + sy, pz + sz, color), //3
        VtxFmt.color3D(px     , py     , pz + sz, color), //2
        VtxFmt.color3D(px + sx, py     , pz + sz, color), //1
        VtxFmt.color3D(px + sx, py + sy, pz + sz, color), //0


        VtxFmt.color3D(px + sx, py, pz,      color),
        VtxFmt.color3D(px + sx, py, pz + sz, color),
        VtxFmt.color3D(px     , py, pz + sz, color),
        VtxFmt.color3D(px     , py, pz     , color),

        VtxFmt.color3D(px     , py + sy, pz     ,  color),
        VtxFmt.color3D(px     , py + sy, pz + sz,  color),
        VtxFmt.color3D(px + sx, py + sy, pz + sz,  color),
        VtxFmt.color3D(px + sx, py + sy, pz,       color),

        VtxFmt.color3D(px, py + sy, pz,       color),
        VtxFmt.color3D(px, py , pz,           color),
        VtxFmt.color3D(px, py , pz + sz,      color),
        VtxFmt.color3D(px, py + sy , pz + sz, color),

        VtxFmt.color3D(px + sx, py + sy , pz + sz, color),
        VtxFmt.color3D(px + sx, py , pz + sz,      color),
        VtxFmt.color3D(px + sx, py , pz,           color),
        VtxFmt.color3D(px + sx, py + sy, pz,       color),


    }) catch return;
    // zig fmt: on
    }

    // Winding order should be CCW
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

    pub fn bitmapText(self: *Self, x: f32, y: f32, h: f32, str: []const u8, font: FixedBitmapFont, col: u32) void {
        const b = &(self.getBatch(.{
            .batch_kind = .color_tri_tex,
            //Text should always be drawn last for best transparency
            .params = .{ .shader = self.textured_tri_shader, .texture = font.texture.id, .draw_priority = 0xff },
        }) catch unreachable).color_tri_tex;
        const z = self.zindex;
        self.zindex += 1;

        var i: u32 = 0;
        for (str) |char| {
            if (char == ' ' or char == '_') {
                i += 1;
                continue;
            }

            const ind = font.translation_table[std.ascii.toUpper(char)];
            const fi = @as(f32, @floatFromInt(i));
            const tr = font.sts.getTexRec(if (ind == 127) continue else ind);
            const un = GL.normalizeTexRect(tr, font.texture.w, font.texture.h);
            const r = Rec(x + fi * h, y, h, h);

            b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len)))) catch unreachable;
            b.vertices.appendSlice(&.{
                .{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y + un.h }, .color = col }, //0
                .{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y }, .color = col }, //1
                .{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .uv = .{ .x = un.x, .y = un.y }, .color = col }, //2
                .{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x, .y = un.y + un.h }, .color = col }, //3
            }) catch return;

            i += 1;
        }
    }

    pub fn line(self: *Self, start_p: Vec2f, end_p: Vec2f, color: u32) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_line, .params = .{ .shader = self.colored_tri_shader } }) catch unreachable).color_line;
        const z = self.zindex;
        self.zindex += 1;
        b.vertices.appendSlice(&.{
            .{ .pos = start_p, .z = z, .color = color },
            .{ .pos = end_p, .z = z, .color = color },
        }) catch return;
    }

    pub fn setViewport(self: *Self, vo: ?Rect) void {
        const sb = self.screen_dimensions;
        if (vo) |v| {
            c.glViewport(
                @as(i32, @intFromFloat(v.x)),
                @as(i32, @intFromFloat(sb.y - (v.y + v.h))),
                @as(i32, @intFromFloat(v.w)),
                @as(i32, @intFromFloat(v.h)),
            );
        } else {
            self.setViewport(Rec(0, 0, sb.x, sb.y));
        }
    }

    pub fn flush(self: *Self, custom_camera: ?Rect, camera_3d: ?Camera3D) !void {
        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        c.glBlendEquation(c.GL_FUNC_ADD);
        defer c.glDisable(c.GL_BLEND);
        const cb = if (custom_camera) |cc| cc else Rec(0, 0, self.screen_dimensions.x, self.screen_dimensions.y);
        const view = za.orthographic(cb.x, cb.x + cb.w, cb.y + cb.h, cb.y, -100000, 1);
        const view_3d = if (camera_3d) |c3| c3.getMatrix(self.screen_dimensions.x / self.screen_dimensions.y, 0.1, 100000) else view;
        const model = za.Mat4.identity();

        const sortctx = MapKeySortCtx{ .items = self.batches.keys() }; // Sort the batches by params.draw_priority
        self.batches.sort(sortctx);
        var b_it = self.batches.iterator();
        //c.glEnable(c.GL_BLEND);
        while (b_it.next()) |b| {
            inline for (@typeInfo(Batches).Union.fields, 0..) |ufield, i| {
                if (i == @intFromEnum(b.value_ptr.*)) {
                    @field(b.value_ptr.*, ufield.name).pushVertexData();
                    @field(b.value_ptr.*, ufield.name).draw(b.key_ptr.params, switch (b.key_ptr.params.camera) {
                        ._2d => view,
                        ._3d => view_3d,
                    }, model);
                }
            }
        }
        try self.clearBuffers();
    }

    pub fn end(self: *Self, camera_3d: ?Camera3D) !void {
        try self.flush(null, camera_3d);
    }
};

pub const BatchOptions = struct {
    index_buffer: bool,
    primitive_mode: GL.PrimitiveMode,
};
pub const DrawParams = struct {
    texture: ?c_uint = null,
    camera: enum { _3d, _2d } = ._2d,
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

        pub fn dirty(self: *Self) bool {
            return self.vertices.items.len != 0;
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
            if (self.vertices.items.len == 0)
                return;
            c.glUseProgram(params.shader);
            c.glBindVertexArray(self.vao);
            if (params.texture) |texture| {
                c.glBindTextureUnit(0, texture);
            }
            GL.passUniform(params.shader, "view", view);
            GL.passUniform(params.shader, "model", model);

            const prim: u32 = @intFromEnum(self.primitive_mode);
            if (batch_options.index_buffer) {
                c.glDrawElements(prim, @as(c_int, @intCast(self.indicies.items.len)), c.GL_UNSIGNED_INT, null);
            } else {
                c.glLineWidth(3.0);
                c.glPointSize(16.0);
                c.glDrawArrays(prim, 0, @as(c_int, @intCast(self.vertices.items.len)));
            }
        }
    };
}

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

pub const RenderTexture = struct {
    const Self = @This();
    fb: c_uint,
    depth_rb: c_uint,
    stencil_rb: c_uint,
    texture: Texture,
    w: i32,
    h: i32,

    pub fn init(wa: anytype, ha: anytype) !Self {
        const w = lcast(i32, wa);
        const h = lcast(i32, ha);
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
        c.glFramebufferRenderbuffer(c.GL_FRAMEBUFFER, c.GL_DEPTH_STENCIL_ATTACHMENT, c.GL_RENDERBUFFER, ret.stencil_rb);

        c.glFramebufferTexture(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, ret.texture.id, 0);
        const draw_buffers = [_]c.GLenum{c.GL_COLOR_ATTACHMENT0};
        c.glDrawBuffers(draw_buffers.len, &draw_buffers[0]);

        if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) return error.framebufferCreateFailed;

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        c.glBindRenderbuffer(c.GL_RENDERBUFFER, 0);

        return ret;
    }

    pub fn setSize(self: *Self, w: anytype, h: anytype) !void {
        const wi = lcast(i32, w);
        const hi = lcast(i32, h);
        if (wi != self.w or hi != self.h) {
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

pub const CubeVert = packed struct {
    x: f32,
    y: f32,
    z: f32,

    u: f32,
    v: f32,

    nx: f32,
    ny: f32,
    nz: f32,

    color: u32,

    tx: f32 = 0,
    ty: f32 = 0,
    tz: f32 = 0,
    ti: u16,
};

pub fn cubeVert(x: f32, y: f32, z: f32, u: f32, v: f32, nx: f32, ny: f32, nz: f32, color: u32, tx: f32, ty: f32, tz: f32, ti: u16) CubeVert {
    return .{
        .x = x,
        .y = y,
        .z = z,

        .u = u,
        .v = v,

        .nx = nx,
        .ny = ny,
        .nz = nz,

        .color = color,
        .tx = tx,
        .ty = ty,
        .tz = tz,
        .ti = ti,
    };
}

pub const Cubes = struct {
    const Self = @This();
    vertices: std.ArrayList(CubeVert),
    indicies: std.ArrayList(u32),

    shader: glID,
    texture: Texture,
    vao: c_uint = undefined,
    vbo: c_uint = undefined,
    ebo: c_uint = undefined,

    pub fn setData(self: *Self) void {
        c.glBindVertexArray(self.vao);
        GL.bufferData(c.GL_ARRAY_BUFFER, self.vbo, CubeVert, self.vertices.items);
        GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, self.ebo, u32, self.indicies.items);
    }

    pub fn drawSimple(b: *Self, view: za.Mat4, model: za.Mat4, shader: glID) void {
        c.glUseProgram(shader);
        GL.passUniform(b.shader, "view", view);
        GL.passUniform(b.shader, "model", model);

        c.glBindVertexArray(b.vao);
        c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(b.indicies.items.len)), c.GL_UNSIGNED_INT, null);
    }

    pub fn draw(b: *Self, view: za.Mat4, model: za.Mat4) void {
        c.glUseProgram(b.shader);
        const diffuse_loc = c.glGetUniformLocation(b.shader, "diffuse_texture");

        c.glUniform1i(diffuse_loc, 0);
        c.glActiveTexture(c.GL_TEXTURE0 + 0);
        c.glBindTexture(c.GL_TEXTURE_2D, b.texture.id);

        GL.passUniform(b.shader, "view", view);
        GL.passUniform(b.shader, "model", model);

        c.glBindVertexArray(b.vao);
        c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(b.indicies.items.len)), c.GL_UNSIGNED_INT, null);
        c.glActiveTexture(c.GL_TEXTURE0);
    }

    pub fn init(alloc: Alloc, texture: Texture, shader: glID) @This() {
        var ret = Self{
            .vertices = std.ArrayList(CubeVert).init(alloc),
            .indicies = std.ArrayList(u32).init(alloc),
            .texture = texture,
            .shader = shader,
        };

        c.glGenVertexArrays(1, &ret.vao);
        c.glGenBuffers(1, &ret.vbo);
        c.glGenBuffers(1, &ret.ebo);

        GL.floatVertexAttrib(ret.vao, ret.vbo, 0, 3, CubeVert, "x"); //XYZ
        GL.floatVertexAttrib(ret.vao, ret.vbo, 1, 2, CubeVert, "u"); //RGBA
        GL.floatVertexAttrib(ret.vao, ret.vbo, 2, 3, CubeVert, "nx"); //RGBA
        GL.intVertexAttrib(ret.vao, ret.vbo, 3, 1, CubeVert, "color", c.GL_UNSIGNED_INT);
        GL.floatVertexAttrib(ret.vao, ret.vbo, 4, 3, CubeVert, "tx");
        GL.intVertexAttrib(ret.vao, ret.vbo, 5, 1, CubeVert, "ti", c.GL_UNSIGNED_SHORT);

        c.glBindVertexArray(ret.vao);
        GL.bufferData(c.GL_ARRAY_BUFFER, ret.vbo, CubeVert, ret.vertices.items);
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
    pub fn cubeVec(self: *Self, pos: anytype, scale: anytype, tr: Rect) !void {
        try self.cube(
            lcast(f32, pos.x),
            lcast(f32, pos.y),
            lcast(f32, pos.z),
            lcast(f32, scale.x),
            lcast(f32, scale.y),
            lcast(f32, scale.z),
            tr,
            null,
        );
    }

    pub fn cube(self: *Self, px: f32, py: f32, pz: f32, sx: f32, sy: f32, sz: f32, tr: Rect, ti: u16) !void {
        const tx_w = self.texture.w;
        const tx_h = self.texture.h;
        const color = 0xffffffff;
        const un = GL.normalizeTexRect(tr, @as(i32, @intCast(tx_w)), @as(i32, @intCast(tx_h)));
        try self.indicies.appendSlice(&GL.genCubeIndicies(@as(u32, @intCast(self.vertices.items.len))));
        const nx = sx / tr.w * 512;
        const ny = sy / tr.h * 512;
        const nz = sz / tr.w * 512;

        const uxx = (un.x + un.w) * nx;
        const uyy = (un.y + un.h) * ny;
        const uzz = (un.x + un.w) * nz;
        // zig fmt: off
    try self.vertices.appendSlice(&.{
        // front
        cubeVert(px + sx, py + sy, pz, uxx, uyy, 0,0,-1, color, 1,0,0,ti), //0
        cubeVert(px + sx, py     , pz, uxx, un.y       , 0,0,-1, color, 1,0,0,ti), //1
        cubeVert(px     , py     , pz, un.x       , un.y       , 0,0,-1, color, 1,0,0,ti), //2
        cubeVert(px     , py + sy, pz, un.x       , uyy, 0,0,-1, color, 1,0,0,ti), //3

        // back
        cubeVert(px     , py + sy, pz + sz, un.x       , (un.y + un.h) * ny, 0,0,1, color, 1,0,0,ti), //3
        cubeVert(px     , py     , pz + sz, un.x       , un.y       , 0,0,1, color, 1,0,0,ti), //2
        cubeVert(px + sx, py     , pz + sz, (un.x + un.w) * nx, un.y       , 0,0,1, color, 1,0,0,ti), //1
        cubeVert(px + sx, py + sy, pz + sz, (un.x + un.w) * nx, (un.y + un.h) * ny, 0,0,1, color, 1,0,0,ti), //0


        cubeVert(px + sx, py, pz,      uxx,un.x, 0,-1,0,      color, 1,0,0,ti),
        cubeVert(px + sx, py, pz + sz, uxx,uzz,        0,-1,0,      color, 1,0,0,ti),
        cubeVert(px     , py, pz + sz, un.x,uzz,             0,-1,0,      color, 1,0,0,ti),
        cubeVert(px     , py, pz     , un.x,un.y + un.h,      0,-1,0,      color, 1,0,0,ti),

        cubeVert(px     , py + sy, pz     , un.x,un.y ,        0,1,0,   color, 1,0,0,ti),
        cubeVert(px     , py + sy, pz + sz, un.x,(un.y + un.w) * nz,               0,1,0,   color, 1,0,0,ti),
        cubeVert(px + sx, py + sy, pz + sz, (un.x + un.w) * nx,(un.y + un.w) * nz,        0,1,0,   color, 1,0,0,ti),
        cubeVert(px + sx, py + sy, pz, (un.x + un.w) * nx,   un.y  ,  0,1,0,   color, 1,0,0,ti),

        cubeVert(px, py + sy, pz, un.x + un.w,un.y + un.h,   -1,0,0,   color, 0,1,0,ti),
        cubeVert(px, py , pz, un.x + un.w,un.y,              -1,0,0,   color, 0,1,0,ti),
        cubeVert(px, py , pz + sz, un.x,un.y,                -1,0,0,   color, 0,1,0,ti),
        cubeVert(px, py + sy , pz + sz, un.x,un.y + un.h,    -1,0,0,   color, 0,1,0,ti),

        cubeVert(px + sx, py + sy , pz + sz , un.x       ,  un.y + un.h,     1,0,0, color, 0,-1,0,ti),
        cubeVert(px + sx, py      , pz + sz , un.x       ,  un.y,            1,0,0, color, 0,-1,0,ti),
        cubeVert(px + sx, py      , pz      , un.x + un.w,  un.y,            1,0,0, color, 0,-1,0,ti),
        cubeVert(px + sx, py + sy , pz      , un.x + un.w,  un.y + un.h,     1,0,0, color, 0,-1,0,ti),


    });
    // zig fmt: on

    }

    pub fn clear(self: *Self) void {
        self.vertices.clearRetainingCapacity();
        self.indicies.clearRetainingCapacity();
    }

    pub fn deinit(self: *Self) void {
        self.vertices.deinit();
        self.indicies.deinit();
    }
};
