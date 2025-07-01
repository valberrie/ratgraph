const g = @import("vtables.zig");
const iArea = g.iArea;
const graph = g.graph;
const std = @import("std");
const Gui = g.Gui;
const Rect = g.Rect;
const Rec = g.Rec;
const iWindow = g.iWindow;
const Color = graph.Colori;
const VScroll = g.Widget.VScroll;
const Widget = g.Widget;

pub const TextView = struct {
    pub const INSET_AMOUNT = 5;
    pub fn heightForN(gui: *const Gui, count: anytype) f32 {
        const inset_amount = 2 * INSET_AMOUNT * gui.scale;
        const item_h = gui.style.config.default_item_h;
        return item_h * std.math.lossyCast(f32, count) + inset_amount;
    }

    pub const Opts = struct {
        mode: enum { simple, split_on_space },
    };
    vt: iArea,

    cat_string: []const u8, //Alloced by gui
    lines: std.ArrayList([]const u8), //slices into cat_string

    pub fn build(gui: *Gui, area_o: ?Rect, text: []const []const u8, win: *iWindow, opts: Opts) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());

        self.* = .{
            .cat_string = catStrings(gui.alloc, text) catch return null,
            .vt = iArea.init(gui, area),
            .lines = std.ArrayList([]const u8).init(gui.alloc),
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;

        const inset = area.inset(INSET_AMOUNT * gui.scale);

        //First, walk through string with xWalker and stick in a buffer of lines
        const extra_margin = gui.style.config.text_h / 3;
        const tw = Widget.VScroll.getAreaW(inset.w - extra_margin);
        switch (opts.mode) {
            .split_on_space => self.buildLinesSpaceSplit(gui.font, tw, gui.style.config.text_h) catch return null,
            .simple => self.buildLines(gui.font, tw, gui.style.config.text_h) catch return null,
        }
        const vscr = Widget.VScroll.build(gui, inset, .{
            .build_vt = &self.vt,
            .build_cb = &buildScroll,
            .win = win,
            .item_h = gui.style.config.default_item_h,
            .count = self.lines.items.len,
            .index_ptr = null,
        }) orelse return null;
        self.vt.addChild(gui, win, vscr);

        return &self.vt;
    }

    pub fn buildScroll(user: *iArea, layout: *iArea, index: usize, gui: *Gui, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", user));
        var ly = g.VerticalLayout{ .item_height = gui.style.config.default_item_h, .bounds = layout.area };
        if (index >= self.lines.items.len) return;
        for (self.lines.items[index..], index..) |line, i| {
            _ = i;
            const color = 0xffff_ffff;
            //const color: u32 = if (i % 2 == 0) 0xffff_ffff else 0xff_0000_ff;
            layout.addChildOpt(gui, win, Widget.Text.buildStatic(gui, ly.getArea(), line, color));
        }
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.free(self.cat_string);
        self.lines.deinit();
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: g.DrawState) void {
        d.ctx.nineSlice(vt.area, d.style.getRect(.basic_inset), d.style.texture, d.scale, d.tint);
        //d.ctx.rect(vt.area, 0xff); //Black rect
    }

    // populate self.lines with cat_string
    fn buildLines(self: *@This(), font: *graph.FontInterface, area_w: f32, font_h: f32) !void {
        const max_line_w = area_w;
        var xwalker = font.xWalker(self.cat_string, font_h);
        var current_line_w: f32 = 0;
        var start_index: usize = 0;
        while (xwalker.next()) |n| {
            const w = n[0];
            current_line_w += w;
            if (current_line_w > max_line_w or n[1] == '\n') {
                const end = xwalker.index();
                try self.lines.append(self.cat_string[start_index..end]);
                start_index = end;
                current_line_w = 0;
            }
        }
        try self.lines.append(self.cat_string[start_index..]);
    }

    fn buildLinesSpaceSplit(self: *@This(), font: *graph.FontInterface, area_w: f32, font_h: f32) !void {
        const max_line_w = area_w;
        var xwalker = font.xWalker(self.cat_string, font_h);
        var current_line_w: f32 = 0;
        var start_index: usize = 0;
        var last_space: ?usize = null;
        var width_at_last_space: f32 = 0;
        while (xwalker.next()) |n| {
            const w = n[0];
            current_line_w += w;
            if (n[1] == ' ') {
                //TODO split on any unicode ws
                last_space = xwalker.index();
                width_at_last_space = current_line_w;
            }
            const past = current_line_w > max_line_w;
            if (past or n[1] == '\n') {
                const end = xwalker.index();
                if (past and last_space != null) {
                    const ls = last_space.?;
                    if (start_index > ls) return;
                    try self.lines.append(self.cat_string[start_index..ls]);
                    current_line_w = current_line_w - width_at_last_space;
                    start_index = ls;
                } else {
                    if (start_index > end) return;
                    try self.lines.append(self.cat_string[start_index..end]);
                    start_index = end;
                    current_line_w = 0;
                }
            }
        }
        try self.lines.append(self.cat_string[start_index..]);
    }

    fn catStrings(alloc: std.mem.Allocator, text: []const []const u8) ![]const u8 {
        var strlen: usize = 0;
        for (text) |str|
            strlen += str.len;
        const slice = try alloc.alloc(u8, strlen);
        strlen = 0;
        for (text) |str| {
            @memcpy(slice[strlen .. strlen + str.len], str);
            strlen += str.len;
        }
        return slice;
    }
};
