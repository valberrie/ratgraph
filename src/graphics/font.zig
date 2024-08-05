const std = @import("std");
const c = @import("c.zig");
const Alloc = std.mem.Allocator;
const Dir = std.fs.Dir;
const SparseSet = @import("sparse_set.zig").SparseSet;
const ptypes = @import("types.zig");
const SDL = @import("SDL.zig");
const Rect = ptypes.Rect;
const Vec2f = ptypes.Vec2f;
const Vec2i = ptypes.Vec2i;
const lcast = std.math.lossyCast;
const intToColor = ptypes.intToColor;
const glID = SDL.glID;
const Rec = Rect.NewAny;

pub const OptionalFileWriter = struct {
    writer: ?std.fs.File.Writer = null,

    pub fn print(self: *OptionalFileWriter, comptime fmt: []const u8, args: anytype) !void {
        if (self.writer) |wr| {
            try wr.print(fmt, args);
        }
    }
};

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

        pub const EssentialUnicode = [_]CharMapEntry{ .{ .unicode = std.unicode.replacement_character }, .{ .unicode = 0x2026 } };

        pub const AsciiBasic = AsciiUpperAlpha ++ AsciiLowerAlpha ++ AsciiNumeric ++ AsciiPunctiation;
        pub const Default = AsciiBasic ++ EssentialUnicode;

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
    pub const padding: i32 = 2;

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

    //TODO write a init function for stb_truetype
    // pub fn initFromBuffer(alloc: std.mem.Allocator, buffer:[]const u8)!void{
    // }

    pub fn init(alloc: Alloc, dir: Dir, filename: []const u8, point_size: f32, dpi: f32, options: struct {
        codepoints_to_load: []const CharMapEntry = &(CharMaps.Default),
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
            ddir.makeDir("bitmaps") catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
            const font_log = try ddir.createFile("fontgen.log", .{ .truncate = true });
            log.writer = font_log.writer();
            //defer font_log.close();
            try log.print("zig: Init font with arguments:\nfilename: \"{s}\"\npoint_size: {d}\ndpi: {d}\n", .{
                filename,
                point_size,
                dpi,
            });
            try log.print("px_size: {d}\n", .{point_size * (dpi / 72)});
        }
        var result = Font{
            .height = 0,
            .dpi = dpi,
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
                @intFromFloat(dpi),
                @intFromFloat(dpi),
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
            const glyph = Glyph{
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
            var out = std.ArrayList(u8).init(alloc);
            defer out.deinit();
            try out.writer().print("freetype_{s}.png", .{filename});
            std.mem.replaceScalar(u8, out.items, '/', '.');
            std.debug.print("{s}\n", .{out.items});
            try texture_bitmap.writeToPngFile(ddir, out.items);
        }

        result.texture = Texture.initFromBitmap(texture_bitmap, .{
            .pixel_store_alignment = 1,
            .internal_format = c.GL_RED,
            .pixel_format = c.GL_RED,
            .min_filter = c.GL_LINEAR,
            .mag_filter = c.GL_LINEAR,
        });

        return result;
    }

    pub fn nearestGlyphX(self: *Self, string: []const u8, size_px: f32, rel_coord: Vec2f) ?usize {
        const scale = (size_px / self.dpi * 72) / self.font_size;
        //const scale = size_px / @as(f32, @floatFromInt(self.height));

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
        const scale = (lcast(f32, size_px) / self.dpi * 72) / self.font_size;
        //const scale = size_px / @as(f32, @floatFromInt(self.height));
        //const scale = size_px / self.font_size;

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

///Rectangle packing
///Usage:
///init()
///appendRect()s
///pack();
///rects.items now contains the arranged rectangles.
///deinit()
pub const RectPack = struct {
    const Self = @This();
    pub const RectType = c.stbrp_rect;
    const RectDimType = c_int;
    const NodeType = c.stbrp_node;
    const ExtraNodeCount = 200;
    const InitRectPos = 50;

    rects: std.ArrayList(RectType),
    nodes: std.ArrayList(NodeType),

    running_size: usize = 0,

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
        self.running_size += std.math.lossyCast(usize, w * h);
    }

    pub fn packOptimalSize(self: *Self) !Vec2i {
        var safety_factor: f32 = 1.1;
        const safety_factor_inc = 0.3;
        const max_fails = 3;
        for (0..max_fails) |_| {
            const fsize: f32 = @floatFromInt(self.running_size);
            const w: u32 = @intFromFloat(@ceil(@sqrt(fsize)) * safety_factor);
            self.pack(w, w) catch |err| {
                switch (err) {
                    error.rectPackFailed => {
                        std.debug.print("Rect pack failed, trying again\n", .{});
                        safety_factor += safety_factor_inc;
                        continue;
                    },
                    else => return err,
                }
            };
            return Vec2i{ .x = @intCast(w), .y = @intCast(w) };
        }
        return error.rectPackFailed;
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

pub const Bitmap = struct {
    const Self = @This();
    pub const ImageFormat = enum(usize) {
        rgba_8 = c.SPNG_FMT_RGBA8,
        rgb_8 = c.SPNG_FMT_RGB8,
        g_8 = c.SPNG_FMT_G8, //grayscale, 8 bit
        ga_8 = c.SPNG_FMT_GA8,
    };

    format: ImageFormat = .rgba_8,
    data: std.ArrayList(u8),
    w: u32,
    h: u32,

    pub fn rect(self: Self) Rect {
        return Rec(0, 0, self.w, self.h);
    }

    pub fn initBlank(alloc: Alloc, width: anytype, height: anytype, format: ImageFormat) !Self {
        const h = lcast(u32, height);
        const w = lcast(u32, width);
        var ret = Self{ .format = format, .data = std.ArrayList(u8).init(alloc), .w = lcast(u32, width), .h = lcast(u32, height) };
        const num_comp: u32 = switch (format) {
            .rgba_8 => 4,
            .g_8 => 1,
            .rgb_8 => 3,
            .ga_8 => 2,
        };
        try ret.data.appendNTimes(0, num_comp * w * h);
        return ret;
    }

    pub fn initFromBuffer(alloc: Alloc, buffer: []const u8, width: anytype, height: anytype, format: ImageFormat) !Bitmap {
        const copy = try alloc.dupe(u8, buffer);
        return Bitmap{ .data = std.ArrayList(u8).fromOwnedSlice(alloc, copy), .w = lcast(u32, width), .h = lcast(u32, height), .format = format };
    }

    pub fn initFromPngBuffer(alloc: Alloc, buffer: []const u8) !Bitmap {
        const pngctx = c.spng_ctx_new(0);
        defer c.spng_ctx_free(pngctx);
        _ = c.spng_set_png_buffer(pngctx, &buffer[0], buffer.len);

        var ihdr: c.spng_ihdr = undefined;
        _ = c.spng_get_ihdr(pngctx, &ihdr);
        //ihdr.bit_depth;
        //ihdr.color_type;
        const fmt: ImageFormat = switch (ihdr.color_type) {
            c.SPNG_COLOR_TYPE_GRAYSCALE => .rgba_8,
            c.SPNG_COLOR_TYPE_GRAYSCALE_ALPHA => .rgba_8,
            c.SPNG_COLOR_TYPE_TRUECOLOR => .rgba_8,
            c.SPNG_COLOR_TYPE_TRUECOLOR_ALPHA => .rgba_8,
            c.SPNG_COLOR_TYPE_INDEXED => .rgba_8,
            else => return error.unsupportedColorFormat,
        };

        var out_size: usize = 0;
        _ = c.spng_decoded_image_size(pngctx, @intCast(@intFromEnum(fmt)), &out_size);

        const decoded_data = try alloc.alloc(u8, out_size);

        _ = c.spng_decode_image(pngctx, &decoded_data[0], out_size, @intCast(@intFromEnum(fmt)), 0);

        return Bitmap{ .format = fmt, .w = ihdr.width, .h = ihdr.height, .data = std.ArrayList(u8).fromOwnedSlice(alloc, decoded_data) };
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
        @memcpy(decoded, img_buf[0..len]);

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
        const pngctx = c.spng_ctx_new(c.SPNG_CTX_ENCODER);
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
                .ga_8 => c.SPNG_COLOR_TYPE_GRAYSCALE_ALPHA,
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
