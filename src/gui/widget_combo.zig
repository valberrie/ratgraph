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

pub const Combo = struct {
    pub fn build(gui: *Gui, area_o: ?Rect, enum_ptr: anytype) ?*iArea {
        const info = @typeInfo(@TypeOf(enum_ptr));
        if (info != .Pointer) @compileError("expected a pointer to enum");
        if (info.Pointer.is_const or info.Pointer.size != .One) @compileError("invalid pointer");
        const child_info = @typeInfo(info.Pointer.child);
        if (child_info != .Enum) @compileError("Expected an enum");

        const Gen = ComboGeneric(info.Pointer.child);
        const area = area_o orelse return null;
        return Gen.build(gui, area, enum_ptr);
    }
};

pub const ComboVt = struct {
    //build_cb: *const fn (user_vt: *iArea, widget_vt: *iArea, index: usize, *Gui, *iWindow) void,
    name_cb: *const fn (user_vt: *iArea, index: usize, *Gui) []const u8,
    commit_cb: *const fn (user_vt: *iArea, index: usize) void,
    count: usize,
    current: usize,

    user_vt: *iArea,
};

pub const ComboUser = struct {
    const ParentT = @This();
    pub const PoppedWindow = struct {
        vt: iWindow,
        area: iArea,

        parent_vt: *iArea,
        name: []const u8,

        pub fn buildWindow(vt: *iWindow, gui: *Gui, area: Rect) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            self.area.area = area;
            self.area.clearChildren(gui, vt);
            vt.area.dirty(gui);
            const p: *ComboUser = @alignCast(@fieldParentPtr("vt", self.parent_vt));
            self.area.addChildOpt(gui, vt, VScroll.build(gui, area, .{
                .build_cb = &build_scroll_cb,
                .build_vt = &self.area,
                .win = vt,
                .item_h = gui.style.config.default_item_h,
                .count = p.opts.count,
                .index_ptr = &p.index,
            }));
        }

        pub fn build_scroll_cb(vt: *iArea, area: *iArea, index: usize, gui: *Gui, win: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
            var ly = g.VerticalLayout{ .item_height = gui.style.config.default_item_h, .bounds = area.area };
            const p: *ComboUser = @alignCast(@fieldParentPtr("vt", self.parent_vt));
            const count = p.opts.count;
            if (index >= count) return;
            for (index..count) |i| {
                if (i >= index) {
                    area.addChild(gui, win, Widget.Button.build(
                        gui,
                        ly.getArea(),
                        p.opts.name_cb(p.opts.user_vt, i, gui),
                        .{ .cb_vt = self.parent_vt, .cb_fn = &ParentT.buttonCb, .id = i },
                    ) orelse return);
                }
            }
        }

        pub fn deinit(vt: *iWindow, gui: *Gui) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            vt.deinit(gui);
            gui.alloc.destroy(self);
        }

        pub fn draw(vt: *iArea, d: g.DrawState) void {
            const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
            _ = d;
            _ = self;
        }

        pub fn deinit_area(vt: *iArea, _: *Gui, _: *iWindow) void {
            _ = vt;
        }
    };

    vt: iArea,

    opts: ComboVt,
    index: usize = 0,
    current: usize = 0,

    pub fn build(gui: *Gui, area: Rect, opts: ComboVt) *iArea {
        const self = gui.create(@This());
        self.* = .{
            .vt = iArea.init(gui, area),
            .opts = opts,
        };
        self.vt.onclick = &onclick;
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        return &self.vt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, 0x2ffff0ff);

        const cb = d.style.getRect(.combo_background);
        d.ctx.nineSlice(vt.area, cb, d.style.texture, d.scale, d.tint);
        const texta = vt.area.inset(cb.w / 3 * d.scale);
        d.ctx.textClipped(texta, "{s}", .{self.opts.name_cb(self.opts.user_vt, self.opts.current, d.gui)}, d.textP(null), .center);
        //self.gui.drawTextFmt(fmt, args, texta, self.style.config.text_h, 0xff, .{ .justify = .center }, self.font);
        const cbb = d.style.getRect(.combo_button);
        const da = d.style.getRect(.down_arrow);
        const cbbr = vt.area.replace(vt.area.x + vt.area.w - cbb.w * d.scale, null, cbb.w * d.scale, null).centerR(da.w * d.scale, da.h * d.scale);
        d.ctx.rectTex(cbbr, da, d.style.texture);
    }

    pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        _ = win;
        self.makeTransientWindow(cb.gui, Rec(vt.area.x, vt.area.y, vt.area.w, cb.gui.style.config.default_item_h * 4));
    }

    pub fn buttonCb(vt: *iArea, id: usize, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        vt.dirty(gui);
        self.opts.current = id;
        self.opts.commit_cb(self.opts.user_vt, id);
        gui.deferTransientClose();
    }

    pub fn makeTransientWindow(self: *@This(), gui: *Gui, area: Rect) void {
        const popped = gui.create(PoppedWindow);
        popped.* = .{
            .parent_vt = &self.vt,
            .vt = iWindow.init(
                &PoppedWindow.buildWindow,
                gui,
                &PoppedWindow.deinit,
                &popped.area,
            ),
            .area = iArea.init(gui, area),
            .name = "noname",
        };
        popped.area.draw_fn = &PoppedWindow.draw;
        popped.area.deinit_fn = &PoppedWindow.deinit_area;
        gui.setTransientWindow(&popped.vt);
        popped.vt.build_fn(&popped.vt, gui, area);
    }
};

pub fn ComboGeneric(comptime enumT: type) type {
    return struct {
        const ParentT = @This();
        pub const PoppedWindow = struct {
            vt: iWindow,
            area: iArea,

            parent_vt: *iArea,
            name: []const u8,

            pub fn build(vt: *iWindow, gui: *Gui, area: Rect) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                self.area.area = area;
                self.area.clearChildren(gui, vt);
                const info = @typeInfo(enumT);
                vt.area.dirty(gui);
                self.area.addChildOpt(gui, vt, VScroll.build(gui, area, .{
                    .build_cb = &build_cb,
                    .build_vt = &self.area,
                    .win = vt,
                    .count = info.Enum.fields.len,
                    .item_h = gui.style.config.default_item_h,
                }));
            }

            pub fn build_cb(vt: *iArea, area: *iArea, index: usize, gui: *Gui, win: *iWindow) void {
                const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
                var ly = g.VerticalLayout{ .item_height = gui.style.config.default_item_h, .bounds = area.area };
                const info = @typeInfo(enumT);
                inline for (info.Enum.fields, 0..) |field, i| {
                    if (i >= index) {
                        area.addChild(gui, win, Widget.Button.build(
                            gui,
                            ly.getArea(),
                            field.name,
                            .{ .cb_vt = self.parent_vt, .cb_fn = &ParentT.buttonCb, .id = field.value },
                        ) orelse return);
                    }
                }
            }

            pub fn deinit(vt: *iWindow, gui: *Gui) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                vt.deinit(gui);
                gui.alloc.destroy(self);
            }

            pub fn draw(vt: *iArea, d: g.DrawState) void {
                const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
                _ = d;
                _ = self;
            }

            pub fn deinit_area(vt: *iArea, _: *Gui, _: *iWindow) void {
                _ = vt;
            }
        };

        vt: iArea,

        enum_ptr: *enumT,

        pub fn build(gui: *Gui, area: Rect, enum_ptr: *enumT) *iArea {
            const self = gui.create(@This());
            self.* = .{
                .vt = iArea.init(gui, area),
                .enum_ptr = enum_ptr,
            };
            self.vt.onclick = &onclick;
            self.vt.draw_fn = &draw;
            self.vt.deinit_fn = &deinit;
            return &self.vt;
        }

        pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            gui.alloc.destroy(self);
        }

        pub fn draw(vt: *iArea, d: g.DrawState) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            d.ctx.rect(vt.area, 0x2ffff0ff);

            const cb = d.style.getRect(.combo_background);
            d.ctx.nineSlice(vt.area, cb, d.style.texture, d.scale, d.tint);
            const texta = vt.area.inset(cb.w / 3 * d.scale);
            d.ctx.textClipped(texta, "{s}", .{@tagName(self.enum_ptr.*)}, d.textP(null), .center);
            //self.gui.drawTextFmt(fmt, args, texta, self.style.config.text_h, 0xff, .{ .justify = .center }, self.font);
            const cbb = d.style.getRect(.combo_button);
            const da = d.style.getRect(.down_arrow);
            const cbbr = vt.area.replace(vt.area.x + vt.area.w - cbb.w * d.scale, null, cbb.w * d.scale, null).centerR(da.w * d.scale, da.h * d.scale);
            d.ctx.rectTex(cbbr, da, d.style.texture);
        }

        pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            _ = win;
            self.makeTransientWindow(cb.gui, Rec(vt.area.x, vt.area.y, vt.area.w, cb.gui.style.config.default_item_h * 4));
        }

        pub fn buttonCb(vt: *iArea, id: usize, gui: *Gui, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            vt.dirty(gui);
            self.enum_ptr.* = @enumFromInt(id);
            gui.deferTransientClose();
        }

        pub fn makeTransientWindow(self: *@This(), gui: *Gui, area: Rect) void {
            const popped = gui.create(PoppedWindow);
            popped.* = .{
                .parent_vt = &self.vt,
                .vt = iWindow.init(
                    &PoppedWindow.build,
                    gui,
                    &PoppedWindow.deinit,
                    &popped.area,
                ),
                .area = iArea.init(gui, area),
                .name = "noname",
            };
            popped.area.draw_fn = &PoppedWindow.draw;
            popped.area.deinit_fn = &PoppedWindow.deinit_area;
            gui.setTransientWindow(&popped.vt);
            popped.vt.build_fn(&popped.vt, gui, area);
        }
    };
}
