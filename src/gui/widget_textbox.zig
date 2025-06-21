const g = @import("vtables.zig");
const iArea = g.iArea;
const std = @import("std");
const Gui = g.Gui;
const Rect = g.Rect;
const iWindow = g.iWindow;

pub const Textbox = struct {
    vt: iArea,

    text: std.ArrayList(u8),

    pub fn build(gui: *Gui, area: Rect) !*iArea {
        const self = try gui.alloc.create(@This());
        self.* = .{
            .vt = iArea.init(gui, area),
            .text = std.ArrayList(u8).init(gui.alloc),
        };
        self.vt.deinit_fn = &deinit;
        self.vt.draw_fn = &draw;
        self.vt.onclick = &onclick;
        self.vt.textinput = &textinput;
        return &self.vt;
    }

    pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        _ = self;
        cb.gui.grabFocus(vt, win);
    }

    pub fn textinput(vt: *iArea, cb: g.TextCbState, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.text.appendSlice(cb.text) catch return;
    }

    pub fn draw(vt: *iArea, d: g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, if (d.gui.isFocused(vt)) 0xff00ffff else 0x222222ff);
        d.ctx.textFmt(vt.area.pos(), "{s}", .{self.text.items}, d.font, vt.area.h, 0xff, .{});
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.text.deinit();
        gui.alloc.destroy(self);
    }
};
