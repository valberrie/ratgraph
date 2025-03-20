const std = @import("std");
const font = @import("font.zig");
const c = @import("c.zig");
const Glyph = font.Glyph;

//TODO how should font interface work?
//We can use comptime duck typing
//Or we can use a "Font" type with a function ptr to parent fonts getGlyph function

pub const OnlineFont = struct {
    const Self = @This();

    font: font.PublicFontInterface,
    glyphs: std.AutoHashMap(u21, Glyph),
    cell_width: i32,
    cell_height: i32,
    cx: i32 = 10,
    cy: i32 = 10,
    cindex: i32 = 0,
    scratch_bmp: font.Bitmap,
    bitmap: font.Bitmap,

    finfo: c.stbtt_fontinfo,
    SF: f32 = 0,

    pub fn deinit(self: *Self) void {
        self.glyphs.deinit();
        self.scratch_bmp.deinit();
        self.bitmap.deinit();
        self.font.texture.deinit();
    }

    pub fn initFromBuffer(
        alloc: std.mem.Allocator,
        buf: []const u8,
        pixel_size: f32,
        params: struct { char_count: usize = 4096 },
    ) !Self {
        _ = params;
        var finfo: c.stbtt_fontinfo = undefined;
        _ = c.stbtt_InitFont(&finfo, @as([*c]const u8, @ptrCast(buf)), c.stbtt_GetFontOffsetForIndex(&buf[0], 0));

        const SF = c.stbtt_ScaleForPixelHeight(&finfo, pixel_size);
        var result = OnlineFont{
            .font = .{
                .getGlyphfn = &OnlineFont.getGlyph,
                .height = 0,
                .font_size = pixel_size,
                .texture = .{ .id = 0, .w = 0, .h = 0 },
                .ascent = 0,
                .descent = 0,
                .line_gap = 0,
            },
            .glyphs = std.AutoHashMap(u21, Glyph).init(alloc),
            .cell_width = 0,
            .cell_height = 0,
            .SF = SF,
            .finfo = finfo,
            .scratch_bmp = try font.Bitmap.initBlank(alloc, 10, 10, .g_8),
            .bitmap = undefined,
        };

        {
            var x0: c_int = 0;
            var y0: c_int = 0;
            var x1: c_int = 0;
            var y1: c_int = 0;
            c.stbtt_GetFontBoundingBox(&finfo, &x0, &y0, &x1, &y1);

            result.cell_width = @intFromFloat(@abs(@ceil(@as(f32, @floatFromInt(x1)) * SF) - @ceil(@as(f32, @floatFromInt(x0)) * SF)));
            result.cell_height = @intFromFloat(@abs(@ceil(@as(f32, @floatFromInt(y1)) * SF) - @ceil(@as(f32, @floatFromInt(y0)) * SF)));
        }
        const ww = 20;
        result.font.texture = font.Texture.initFromBuffer(null, result.cell_width * ww, result.cell_height * ww, .{
            .pixel_store_alignment = 1,
            .internal_format = c.GL_RED,
            .pixel_format = c.GL_RED,
            .min_filter = c.GL_LINEAR,
            .mag_filter = c.GL_NEAREST_MIPMAP_NEAREST,
        });
        result.bitmap = try font.Bitmap.initBlank(alloc, result.cell_width * ww, result.cell_height * ww, .g_8);

        {
            var ascent: c_int = 0;
            var descent: c_int = 0;
            var line_gap: c_int = 0;
            c.stbtt_GetFontVMetrics(&finfo, &ascent, &descent, &line_gap);

            result.font.ascent = @as(f32, @floatFromInt(ascent)) * SF;
            result.font.descent = @as(f32, @floatFromInt(descent)) * SF;
            result.font.height = result.font.ascent - result.font.descent;
            result.font.line_gap = result.font.height + @as(f32, @floatFromInt(line_gap)) * SF;
        }
        //_ = result.font.getGlyph(std.unicode.replacement_character);

        return result;
    }

    pub fn getGlyph(font_i: *font.PublicFontInterface, codepoint: u21) font.Glyph {
        const self: *@This() = @fieldParentPtr("font", font_i);
        const glyph = self.glyphs.get(codepoint) orelse {
            const cpo = codepoint;
            const SF = self.SF;
            if (c.stbtt_FindGlyphIndex(&self.finfo, codepoint) == 0) {}
            var x: c_int = 0;
            var y: c_int = 0;
            var xf: c_int = 0;
            var yf: c_int = 0;
            c.stbtt_GetCodepointBitmapBox(&self.finfo, cpo, SF, SF, &x, &y, &xf, &yf);
            const w: f32 = @floatFromInt(xf - x);
            const h: f32 = @floatFromInt(yf - y);
            if (xf - x > 0 and yf - y > 0) {
                //var bmp = try Bitmap.initBlank(alloc, xf - x, yf - y, .g_8);
                self.scratch_bmp.resize(xf - x, yf - y) catch unreachable;
                var bmp = &self.scratch_bmp;
                c.stbtt_MakeCodepointBitmap(
                    &self.finfo,
                    &bmp.data.items[0],
                    xf - x,
                    yf - y,
                    xf - x,
                    SF,
                    SF,
                    cpo,
                );
            }
            std.debug.print("Building {u} {d} {d}\n", .{ codepoint, w, h });

            var adv_w: c_int = 0;
            var left_side_bearing: c_int = 0;
            c.stbtt_GetCodepointHMetrics(&self.finfo, cpo, &adv_w, &left_side_bearing);
            var glyph = Glyph{
                .tr = .{ .x = -1, .y = -1, .w = w, .h = h },
                .offset_x = @as(f32, @floatFromInt(left_side_bearing)) * SF,
                .offset_y = -@as(f32, @floatFromInt(y)),
                .advance_x = @as(f32, @floatFromInt(adv_w)) * SF,
                .width = w,
                .height = h,
            };
            {
                const atlas_cx = @mod(self.cindex, self.cx);
                const atlas_cy = @divTrunc(self.cindex, self.cy);
                c.glTextureSubImage2D(
                    font_i.texture.id,
                    0, //Level
                    //x,y,w,h,
                    @intCast(atlas_cx * self.cell_width),
                    @intCast(atlas_cy * self.cell_height),
                    @intCast(self.scratch_bmp.w),
                    @intCast(self.scratch_bmp.h),
                    //format,
                    c.GL_RED,
                    //type,
                    c.GL_UNSIGNED_BYTE,
                    //pixel_data
                    &self.scratch_bmp.data.items[0],
                );
                font.Bitmap.copySubR(
                    1,
                    &self.bitmap,
                    @intCast(atlas_cx * self.cell_width),
                    @intCast(atlas_cy * self.cell_height),
                    &self.scratch_bmp,
                    0,
                    0,
                    self.scratch_bmp.w,
                    self.scratch_bmp.h,
                );

                glyph.tr.x = @floatFromInt(atlas_cx * self.cell_width);
                glyph.tr.y = @floatFromInt(atlas_cy * self.cell_height);
                self.cindex += 1;
            }
            self.glyphs.put(cpo, glyph) catch unreachable;
            return glyph;
            //bake the glyph
        };
        return glyph;
    }
};
