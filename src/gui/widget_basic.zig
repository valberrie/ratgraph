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

// Write a widget that is a static text box.
// Works like a tabs or whatever which holds all the alloc for string, so scrolling doesn't realloc

pub const VScroll = struct {
    pub const BuildCb = *const fn (*iArea, current_area: *iArea, index: usize, *Gui, *iWindow) void;
    pub const Opts = struct {
        build_cb: BuildCb,
        build_vt: *iArea,
        win: *iWindow,
        count: usize,
        item_h: f32,

        index_ptr: ?*usize = null,
        force_scroll: bool = false,
    };

    vt: iArea,

    __index: usize = 0,
    index_ptr: *usize,
    opts: Opts,
    has_scroll: bool = false,

    pub fn build(gui: *Gui, area_o: ?Rect, opts: Opts) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = iArea.init(gui, area),
            .opts = opts,
            .index_ptr = opts.index_ptr orelse &self.__index,
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;

        const needs_scroll = opts.force_scroll or opts.item_h * @as(f32, @floatFromInt(opts.count)) > area.h;

        const split = self.vt.area.split(.vertical, if (needs_scroll) getAreaW(self.vt.area.w, gui.scale) else self.vt.area.w);
        _ = self.vt.addEmpty(gui, opts.win, split[0]);
        if (needs_scroll) {
            self.has_scroll = true;
            self.vt.onscroll = &onScroll;
            self.vt.addChildOpt(gui, opts.win, ScrollBar.build(
                gui,
                split[1],
                self.index_ptr,
                opts.count,
                opts.item_h,
                &self.vt,
                &notifyChange,
            ));
        } else {
            _ = self.vt.addEmpty(gui, opts.win, split[1]);
        }

        self.rebuild(gui, opts.win);
        return &self.vt;
    }

    pub fn getAreaW(parent_w: f32, scale: f32) f32 {
        const SW = 15 * scale;
        return parent_w - SW;
    }

    pub fn getCount(self: *@This()) usize {
        return self.opts.count;
    }

    pub fn updateCount(self: *@This(), new_count: usize) void {
        if (self.vt.children.items.len != 2) return;
        const scr: *ScrollBar = @alignCast(@fieldParentPtr("vt", self.vt.children.items[1]));
        scr.updateCount(new_count);
        self.opts.count = new_count;
    }

    pub fn rebuild(self: *@This(), gui: *Gui, win: *iWindow) void {
        if (self.vt.children.items.len != 2)
            return;
        //TODO check if it needs the vscroll and add it

        self.vt.dirty(gui);
        const child = self.vt.children.items[0];
        child.clearChildren(gui, win);

        self.opts.build_cb(self.opts.build_vt, child, self.index_ptr.*, gui, win);
    }

    pub fn deinit(vt: *iArea, gui: *Gui, window: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        _ = window;
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, d.style.config.colors.background);
        _ = self;
    }

    pub fn notifyChange(vt: *iArea, gui: *Gui, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.rebuild(gui, win);
    }

    pub fn onScroll(vt: *iArea, gui: *Gui, win: *iWindow, dist: f32) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        if (self.opts.count == 0) {
            self.index_ptr.* = 0;
            return;
        }

        var fi: f32 = @floatFromInt(self.index_ptr.*);
        fi += dist * 4;
        fi = std.math.clamp(fi, 0, @as(f32, @floatFromInt(self.opts.count - 1)));
        self.index_ptr.* = @intFromFloat(fi);
        self.rebuild(gui, win);
    }
};

pub const Checkbox = struct {
    pub const CommitCb = *const fn (*iArea, *Gui, bool, user_id: usize) void;
    pub const Opts = struct {
        bool_ptr: ?*bool = null,
        cb_fn: ?CommitCb = null,
        cb_vt: ?*iArea = null,
        user_id: usize = 0,
    };
    vt: iArea,

    __bool: bool = false,
    bool_ptr: *bool,
    opts: Opts,
    name: []const u8,

    pub fn build(gui: *Gui, area_o: ?Rect, name: []const u8, opts: Opts, set: ?bool) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = iArea.init(gui, area),
            .opts = opts,
            .bool_ptr = opts.bool_ptr orelse &self.__bool,
            .name = name,
        };
        self.__bool = set orelse self.__bool;
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
        if (self.opts.cb_fn) |cbfn| {
            cbfn(self.opts.cb_vt orelse return, gui, self.bool_ptr.*, self.opts.user_id);
        }
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
        d.ctx.textClipped(tarea, "{s}{s}", .{ self.name, if (is_focused) " [space to toggle]" else "" }, d.textP(null), .left);

        //std.debug.print("{s} says: {any}\n", .{ self.name, self.bool_ptr.* });
    }

    //If we click, we need to redraw
    pub fn onclick(vt: *iArea, cb: MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.toggle(cb.gui, win);
    }
};

pub const Button = struct {
    pub const ButtonCallbackT = *const fn (*iArea, usize, *Gui, *iWindow) void;
    pub const Opts = struct {
        cb_vt: ?*iArea = null,
        cb_fn: ?ButtonCallbackT = null,
        id: usize = 0,
        custom_draw: ?*const fn (*iArea, DrawState) void = null,
        user_1: u32 = 0,
    };
    vt: iArea,

    text: []const u8,
    is_down: bool = false,
    opts: Opts,

    pub fn build(gui: *Gui, area_o: ?Rect, name: []const u8, opts: Opts) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = iArea.init(gui, area),
            .text = gui.alloc.dupe(u8, name) catch return null,
            .opts = opts,
        };
        self.vt.draw_fn = &draw;
        if (opts.custom_draw) |dr|
            self.vt.draw_fn = dr;
        self.vt.onclick = &onclick;
        self.vt.deinit_fn = &deinit;
        return &self.vt;
    }
    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.free(self.text);
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
        cb.gui.grabMouse(&@This().mouseGrabbed, vt, win);
        if (self.opts.cb_fn) |cbfn| {
            cbfn(self.opts.cb_vt orelse return, self.opts.id, cb.gui, win);
        }
    }

    pub fn customButtonDraw_listitem(vt: *iArea, d: DrawState) void {
        const self: *Button = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, 0xffff_ffff);
        if (self.opts.user_1 == 1) {
            const SELECTED_FIELD_COLOR = 0x6097dbff;
            d.ctx.rect(vt.area, SELECTED_FIELD_COLOR);
        }
        const ta = vt.area.inset(3 * d.scale);
        d.ctx.textClipped(ta, "{s}", .{self.text}, d.textP(0xff), .center);
    }
};

pub const ScrollBar = struct {
    const NotifyFn = *const fn (*iArea, *Gui, *iWindow) void;
    const shuttle_min_w = 50;
    vt: iArea,

    parent_vt: *iArea,
    notify_fn: NotifyFn,

    count: usize,
    index_ptr: *usize,
    shuttle_h: f32 = 0,
    shuttle_pos: f32 = 0,
    item_h: f32,

    pub fn build(gui: *Gui, area_o: ?Rect, index_ptr: *usize, count: usize, item_h: f32, parent_vt: *iArea, notify_fn: NotifyFn) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());

        self.* = .{
            .parent_vt = parent_vt,
            .notify_fn = notify_fn,
            .vt = iArea.init(gui, area),
            .index_ptr = index_ptr,
            .count = count,
            .item_h = item_h,
            .shuttle_h = calculateShuttleW(count, item_h, area.h, shuttle_min_w),
            .shuttle_pos = calculateShuttlePos(index_ptr.*, count, area.h, shuttle_min_w),
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        self.vt.onclick = &onclick;
        return &self.vt;
    }

    pub fn updateCount(self: *@This(), new_count: usize) void {
        const area = self.vt.area;
        self.count = new_count;
        self.shuttle_h = calculateShuttleW(new_count, self.item_h, area.h, shuttle_min_w);
        self.shuttle_pos = calculateShuttlePos(self.index_ptr.*, new_count, area.h, shuttle_min_w);
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

    is_alloced: bool,
    text: []const u8,
    bg_col: u32,

    /// The passed in string is not copied or freed.
    pub fn buildStatic(gui: *Gui, area_o: ?Rect, owned_string: []const u8, bg_col: ?u32) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = iArea.init(gui, area),
            .is_alloced = false,
            .bg_col = bg_col orelse gui.style.config.colors.background,
            .text = owned_string,
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        return &self.vt;
    }

    pub fn build(gui: *Gui, area_o: ?Rect, comptime fmt: []const u8, args: anytype) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        var vec = std.ArrayList(u8).initCapacity(gui.alloc, 30) catch return null;
        vec.writer().print(fmt, args) catch {
            vec.deinit();
            gui.alloc.destroy(self);
            return null;
        };

        self.* = .{
            .vt = iArea.init(gui, area),
            .bg_col = gui.style.config.colors.background,
            .is_alloced = true,
            .text = vec.toOwnedSlice() catch return null,
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        return &self.vt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        if (self.is_alloced)
            gui.alloc.free(self.text);
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        //d.ctx.rect(vt.area, 0x5ffff0ff);
        d.ctx.rect(vt.area, self.bg_col);
        const texta = vt.area.inset(d.style.config.default_item_h / 10);
        d.ctx.textClipped(texta, "{s}", .{self.text}, d.textP(null), .left);
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
