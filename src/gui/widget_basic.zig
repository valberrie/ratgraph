const g = @import("vtables.zig");
const iArea = g.iArea;
const std = @import("std");
const Gui = g.Gui;
const Rect = g.Rect;
const iWindow = g.iWindow;
const GuiConfig = g.GuiConfig;
const VerticalLayout = g.VerticalLayout;
const DrawState = g.DrawState;
const MouseCbState = g.MouseCbState;
const Color = graph.Colori;
const Rec = g.Rec;
const graph = g.graph;
const getVt = g.getVt;

pub const VScroll = struct {
    pub const BuildCb = *const fn (*iArea, current_area: *iArea, index: usize, *Gui, *iWindow) void;

    vt: iArea,

    build_cb: BuildCb,
    build_cb_vt: *iArea,
    index: usize = 0,
    count: usize = 10,

    pub fn build(gui: *Gui, area_o: ?Rect, build_cb: BuildCb, build_cb_vt: *iArea, win: *iWindow, count: usize, item_h_hint: f32) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = iArea.init(gui, area),
            .count = count,
            .build_cb = build_cb,
            .build_cb_vt = build_cb_vt,
        };
        self.vt.draw_fn = &draw;
        self.vt.onscroll = &onScroll;
        self.vt.deinit_fn = &deinit;

        const SW = 30;
        const split = self.vt.area.split(.vertical, self.vt.area.w - SW);
        _ = self.vt.addEmpty(gui, win, split[0]);
        self.vt.addChildOpt(gui, win, ScrollBar.build(
            gui,
            split[1],
            &self.index,
            self.count,
            item_h_hint,
            &self.vt,
            &notifyChange,
        ));

        self.rebuild(gui, win);
        return &self.vt;
    }

    pub fn rebuild(self: *@This(), gui: *Gui, win: *iWindow) void {
        if (self.vt.children.items.len != 2)
            return;
        self.vt.dirty(gui);
        const child = self.vt.children.items[0];
        child.clearChildren(gui, win);
        self.build_cb(self.build_cb_vt, child, self.index, gui, win);
    }

    pub fn deinit(vt: *iArea, gui: *Gui, window: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        _ = window;
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, 0xff00ffff);
        _ = self;
    }

    pub fn notifyChange(vt: *iArea, gui: *Gui, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.rebuild(gui, win);
    }

    pub fn onScroll(vt: *iArea, gui: *Gui, win: *iWindow, dist: f32) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        if (self.count == 0) {
            self.index = 0;
            return;
        }

        var fi: f32 = @floatFromInt(self.index);
        fi += dist;
        fi = std.math.clamp(fi, 0, @as(f32, @floatFromInt(self.count - 1)));
        self.index = @intFromFloat(fi);
        self.rebuild(gui, win);
    }
};

pub const Checkbox = struct {
    vt: iArea,

    bool_ptr: *bool,
    name: []const u8,

    pub fn build(gui: *Gui, area_o: ?Rect, bool_ptr: *bool, name: []const u8) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = iArea.init(gui, area),
            .bool_ptr = bool_ptr,
            .name = name,
        };
        self.vt.can_tab_focus = true;
        self.vt.onclick = &onclick;
        self.vt.focusEvent = &fevent;
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        return &self.vt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn fevent(vt: *iArea, ev: g.FocusedEvent) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        switch (ev.event) {
            .focusChanged => vt.dirty(ev.gui),
            .text_input => {},
            .keydown => |kev| {
                for (kev.keys) |k| {
                    switch (@as(graph.SDL.keycodes.Scancode, @enumFromInt(k.key_id))) {
                        else => {},
                        .SPACE => self.toggle(ev.gui, ev.window),
                    }
                }
            },
        }
    }

    fn toggle(self: *@This(), gui: *Gui, _: *iWindow) void {
        self.bool_ptr.* = !self.bool_ptr.*;
        self.vt.dirty(gui);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const cr = d.style.getRect(if (self.bool_ptr.*) .checkbox_checked else .checkbox_empty);
        const is_focused = d.gui.isFocused(vt);

        const bw = 1;
        const area = vt.area;
        const h = @min(cr.h * d.scale, area.h);
        const pad = (area.h - h) / 2;
        const br = Rect.newV(.{ .x = area.x + bw, .y = area.y + pad }, .{ .x = @min(cr.w * d.scale, area.w), .y = h });
        d.ctx.rect(vt.area, d.style.config.colors.background);
        if (is_focused)
            d.ctx.rectBorder(vt.area, bw, d.style.config.colors.selected);
        d.ctx.rectTex(
            br,
            cr,
            d.style.texture,
        );
        const tarea = Rec(br.farX() + pad, area.y + pad, area.w - br.farX(), area.h);
        d.ctx.textClipped(tarea, "{s}{s}", .{ self.name, if (is_focused) " space to toggle" else "" }, d.textP(null), .left);

        //std.debug.print("{s} says: {any}\n", .{ self.name, self.bool_ptr.* });
    }

    //If we click, we need to redraw
    pub fn onclick(vt: *iArea, cb: MouseCbState, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.bool_ptr.* = !self.bool_ptr.*;
        vt.dirty(cb.gui);
    }
};

pub const Button = struct {
    pub const ButtonCallbackT = *const fn (*iArea, usize, *Gui, *iWindow) void;
    vt: iArea,

    callback_vt: ?*iArea = null,
    callback_fn: ?ButtonCallbackT,
    user_id: usize = 0,
    text: []const u8,
    is_down: bool = false,

    pub fn build(gui: *Gui, area_o: ?Rect, name: []const u8, cb_vt: ?*iArea, cb_fn: ?ButtonCallbackT, id: usize) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = iArea.init(gui, area),
            .text = name,
            .callback_vt = cb_vt,
            .callback_fn = cb_fn,
            .user_id = id,
        };
        self.vt.draw_fn = &draw;
        self.vt.onclick = &onclick;
        self.vt.deinit_fn = &deinit;
        return &self.vt;
    }
    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn mouseGrabbed(vt: *iArea, cb: MouseCbState, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const old = self.is_down;
        self.is_down = switch (cb.state) {
            .high, .rising => true,
            .falling, .low => false,
        };
        if (self.is_down != old)
            vt.dirty(cb.gui);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        //d.ctx.rect(vt.area, 0x5ffff0ff);
        const sl = if (self.is_down) d.style.getRect(.button_clicked) else d.style.getRect(.button);
        const color = d.style.config.colors.button_text;
        d.ctx.nineSlice(vt.area, sl, d.style.texture, d.scale, d.tint);
        const ta = vt.area.inset(3 * d.scale);
        d.ctx.textClipped(ta, "{s}", .{self.text}, d.textP(color), .center);
    }

    pub fn onclick(vt: *iArea, cb: MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        vt.dirty(cb.gui);
        self.is_down = true;
        if (self.callback_fn) |cbfn|
            cbfn(self.callback_vt.?, self.user_id, cb.gui, win);
        cb.gui.grabMouse(&@This().mouseGrabbed, vt, win);
    }
};

pub const ScrollBar = struct {
    const NotifyFn = *const fn (*iArea, *Gui, *iWindow) void;
    vt: iArea,

    parent_vt: *iArea,
    notify_fn: NotifyFn,

    count: usize,
    index_ptr: *usize,
    shuttle_h: f32 = 0,
    shuttle_pos: f32 = 0,

    pub fn build(gui: *Gui, area_o: ?Rect, index_ptr: *usize, count: usize, item_h: f32, parent_vt: *iArea, notify_fn: NotifyFn) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());

        const shuttle_min_w = 50;
        self.* = .{
            .parent_vt = parent_vt,
            .notify_fn = notify_fn,
            .vt = iArea.init(gui, area),
            .index_ptr = index_ptr,
            .count = count,
            .shuttle_h = calculateShuttleW(count, item_h, area.h, shuttle_min_w),
            .shuttle_pos = calculateShuttlePos(index_ptr.*, count, area.h, shuttle_min_w),
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        self.vt.onclick = &onclick;
        return &self.vt;
    }

    fn calculateShuttleW(count: usize, item_h: f32, area_w: f32, min_w: f32) f32 {
        const area_used = @as(f32, @floatFromInt(count)) * item_h;
        const overflow_amount = area_used - area_w;
        if (overflow_amount <= 0) // all items fit in area, no scrolling required
            return area_w;

        const useable = area_w - min_w;
        if (overflow_amount < useable) // We can have a 1:1 mapping of scrollbar movement
            return overflow_amount;

        return min_w;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    fn calculateShuttlePos(index: usize, count: usize, width: f32, shuttle_w: f32) f32 {
        if (count < 2) //Pos is undefined
            return 0;
        const usable_width = width - shuttle_w;
        const indexf: f32 = @floatFromInt(index);
        const countf: f32 = @floatFromInt(count - 1);

        const perc_pos = indexf / countf;
        return usable_width * perc_pos;
    }

    fn shuttleRect(area: Rect, pos: f32, h: f32) Rect {
        return graph.Rec(area.x, pos + area.y, area.w, h);
    }

    pub fn onclick(vt: *iArea, cb: MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        const actual_pos = calculateShuttlePos(self.index_ptr.*, self.count, vt.area.h, self.shuttle_h);
        const handle = shuttleRect(vt.area, actual_pos, self.shuttle_h);
        if (handle.containsPoint(cb.pos)) {
            self.shuttle_pos = actual_pos;
            cb.gui.grabMouse(&mouseGrabbed, vt, win);
        }
    }

    pub fn mouseGrabbed(vt: *iArea, cb: MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        if (self.count < 2)
            return;
        const usable_width = vt.area.h - self.shuttle_h;
        if (usable_width <= 0)
            return;
        const countf: f32 = @floatFromInt(self.count - 1);
        const screen_space_per_value_space = usable_width / countf;
        self.shuttle_pos += cb.delta.y;

        self.shuttle_pos = std.math.clamp(self.shuttle_pos, 0, usable_width);

        var indexf = self.shuttle_pos / screen_space_per_value_space;

        if (cb.pos.y >= vt.area.y + vt.area.h)
            indexf = countf;
        if (cb.pos.y < vt.area.y)
            indexf = 0;

        if (indexf < 0)
            return;
        self.index_ptr.* = std.math.clamp(@as(usize, @intFromFloat(indexf)), 0, self.count);
        self.notify_fn(self.parent_vt, cb.gui, win);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const sp = calculateShuttlePos(self.index_ptr.*, self.count, vt.area.h, self.shuttle_h);
        //d.ctx.rect(vt.area, 0x5ffff0ff);
        //d.ctx.nineSlice(vt.area, sl, d.style.texture, d.scale, 0xffffffff);
        d.ctx.nineSlice(vt.area, d.style.getRect(.slider_box), d.style.texture, d.scale, d.tint);
        const handle = shuttleRect(vt.area, sp, self.shuttle_h);

        d.ctx.nineSlice(handle, d.style.getRect(.slider_shuttle), d.style.texture, d.scale, d.tint);
    }
};

pub const Text = struct {
    vt: iArea,

    text: std.ArrayList(u8),

    pub fn build(gui: *Gui, area_o: ?Rect, comptime fmt: []const u8, args: anytype) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        var vec = std.ArrayList(u8).init(gui.alloc);
        vec.writer().print(fmt, args) catch {
            vec.deinit();
            gui.alloc.destroy(self);
            return null;
        };

        self.* = .{
            .vt = iArea.init(gui, area),
            .text = vec,
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        return &self.vt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.text.deinit();
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        //d.ctx.rect(vt.area, 0x5ffff0ff);
        d.ctx.textClipped(vt.area, "{s}", .{self.text.items}, d.textP(null), .left);
    }
};

/// A box that when clicked allows allows manipulation of a value by moving mouse in +- x
pub const StaticSlider = struct {
    vt: iArea,

    num: f32,
    min: f32,
    max: f32,

    pub fn build(gui: *Gui, area_o: ?Rect, num: f32, min: f32, max: f32) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = iArea.init(gui, area),
            .num = num,
            .min = min,
            .max = max,
        };
        self.vt.onclick = &onclick;
        self.vt.draw_fn = &draw;
        self.vt.onscroll = &scroll;
        self.vt.deinit_fn = &deinit;
        return &self.vt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self = getVt(@This(), vt);
        d.ctx.rect(vt.area, 0x00ffffff);
        d.ctx.textClipped(vt.area, "{d:.2}", .{self.num}, d.textP(null), .center);
    }

    pub fn mouseGrabbed(vt: *iArea, cb: MouseCbState, _: *iWindow) void {
        const self = getVt(@This(), vt);
        const dist = self.max - self.min;
        const width = vt.area.w;
        const factor = dist / width;

        const old_num = self.num;
        self.num += cb.delta.x * factor;
        self.num = std.math.clamp(self.num, self.min, self.max);
        if (old_num != self.num)
            vt.dirty(cb.gui);
    }

    pub fn scroll(vt: *iArea, gui: *Gui, _: *iWindow, dist: f32) void {
        const self = getVt(@This(), vt);
        const old_num = self.num;
        self.num += dist;
        self.num = std.math.clamp(self.num, self.min, self.max);
        if (old_num != self.num)
            vt.dirty(gui);
    }

    pub fn onclick(vt: *iArea, cb: MouseCbState, win: *iWindow) void {
        const self = getVt(@This(), vt);
        cb.gui.grabMouse(&@This().mouseGrabbed, vt, win);
        _ = self;
        //Need some way to grab the mouse until it lets go
    }
};
