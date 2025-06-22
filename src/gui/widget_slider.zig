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

pub fn Slider(comptime number_T: type) type {
    const info = @typeInfo(number_T);
    switch (info) {
        .Int, .Float => {},
        else => @compileError("invalid type for slider widget: " ++ @typeName(number_T)),
    }

    return struct {
        vt: iArea,

        shuttle_rect: Rect,
        ptr: *number_T,
        min: number_T,
        max: number_T,

        pub fn build(gui: *Gui, area_o: ?Rect, ptr: *number_T, min: anytype, max: anytype) ?*iArea {
            const area = area_o orelse return null;
            if (min >= max) return null;
            const self = gui.create(@This());

            self.* = .{
                .vt = iArea.init(gui, area),
                .ptr = ptr,
                .shuttle_rect = Rec(0, 0, 16 * gui.scale, area.h),
                .min = std.math.lossyCast(number_T, min),
                .max = std.math.lossyCast(number_T, max),
            };
            self.shuttle_rect.x = self.valueToShuttlePos();
            self.vt.draw_fn = &draw;
            self.vt.deinit_fn = &deinit; //we must free our memory !
            self.vt.onclick = &onclick;
            return &self.vt;
        }

        fn shuttlePosToValue(self: *const @This()) number_T {
            const ss_per_val = self.ss_per_v();
            if (ss_per_val == 0)
                return self.ptr.*;
            return std.math.lossyCast(number_T, self.shuttle_rect.x / ss_per_val);
        }

        fn ss_per_v(self: *const @This()) f32 {
            const vdist = std.math.lossyCast(f32, self.max - self.min);
            const ss_dist = self.vt.area.w - self.shuttle_rect.w;
            if (ss_dist < 0)
                return 0;

            return ss_dist / vdist;
        }

        fn valueToShuttlePos(self: *const @This()) f32 {
            const ss_per_value = self.ss_per_v();
            if (ss_per_value == 0)
                return 0;

            const pos = std.math.lossyCast(f32, self.ptr.*) * ss_per_value;
            return std.math.clamp(pos, 0, self.vt.area.w - self.shuttle_rect.w);
        }

        pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            gui.alloc.destroy(self);
        }

        fn shuttleSS(self: *@This()) Rect {
            const sr = self.shuttle_rect;
            const ar = self.vt.area;
            return Rec(sr.x + ar.x, sr.y + ar.y, sr.w, sr.h);
        }

        pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            if (self.shuttleSS().containsPoint(cb.pos)) {
                vt.dirty(cb.gui);
                cb.gui.grabMouse(&mouseGrabbed, vt, win);
            }
        }

        pub fn mouseGrabbed(vt: *iArea, cb: g.MouseCbState, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            if (self.shuttle_rect.w >= vt.area.w) return; //Just give up
            const old = self.shuttle_rect.x;
            self.shuttle_rect.x += cb.delta.x;
            self.shuttle_rect.x = std.math.clamp(self.shuttle_rect.x, 0, vt.area.w - self.shuttle_rect.w);
            if (cb.pos.x >= vt.area.x + vt.area.w)
                self.shuttle_rect.x = vt.area.w - self.shuttle_rect.w;
            if (cb.pos.x <= vt.area.x)
                self.shuttle_rect.x = 0;
            if (old != self.shuttle_rect.x) {
                vt.dirty(cb.gui);
                self.ptr.* = self.shuttlePosToValue();
            }
        }

        pub fn draw(vt: *iArea, d: g.DrawState) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            const box = d.style.getRect(.slider_box);
            d.ctx.nineSlice(vt.area, box, d.style.texture, d.scale, d.tint);

            const textb = vt.area.inset(d.scale * box.h / 3);
            const shuttle = d.style.getRect(.slider_shuttle);

            const MAX_DIV = 50;
            if (info == .Int and self.max - self.min < MAX_DIV) {
                const count = self.max - self.min;
                if (count > 0) {
                    const icount: usize = @intCast(count);
                    const diff = vt.area.w / std.math.lossyCast(f32, icount);
                    for (1..icount) |i| { //Skip the first, it overlaps bounds of box
                        const fi: f32 = @floatFromInt(i);
                        const x = fi * diff + 1;
                        const start = graph.Vec2f.new(vt.area.x + x, vt.area.y);
                        const end = start.add(.{ .x = 0, .y = vt.area.h / 3 });
                        d.ctx.line(start, end, 0x222222ff);
                    }
                }
            }

            //const hr = Rec(vt.area.w / 3, 0, 16 * d.scale, vt.area.h);
            d.ctx.nineSlice(
                self.shuttleSS(),
                shuttle,
                d.style.texture,
                d.scale,
                d.tint,
            );

            //d.ctx.("{d:.2}", .{value.*}, textb, self.style.config.text_h, (0xff), .{ .justify = .center }, self.font);
            d.ctx.textFmt(textb.pos(), "{d:.2}", .{self.ptr.*}, d.font, d.style.config.text_h, 0xff, .{});
        }
    };
}
