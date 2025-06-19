const std = @import("std");
const graph = @import("graphics.zig");
const Dctx = graph.ImmediateDrawingContext;
const Os9Gui = @import("gui_app.zig");
const GuiConfig = Os9Gui.GuiConfig;

const Rect = graph.Rect;
const Rec = graph.Rec;
const AL = std.mem.Allocator;

//How to do events?
//don't overthink it, just specify functions for each
//Decide how to do window ordering.
//child (transient) window is special case
//rest idc

//The tree is spatial
//all children exist within parents area

pub fn getVt(comptime T: type, vt: anytype) *T {
    return @alignCast(@fieldParentPtr("vt", vt));
}

pub const DrawState = struct {
    ctx: *Dctx,
    font: *graph.FontInterface,
    style: *GuiConfig,
    scale: f32 = 2,
};

//Two options for this, we use a button widget which registers itself for onclick
//or we listen for onclick and determine which was clicked
pub fn WidgetCombo(comptime enumT: type) type {
    return struct {
        const ParentT = @This();
        pub const PoppedWindow = struct {
            vt: iWindow,
            area: iArea,

            layout: SubLayout,

            parent_vt: *iArea,
            name: []const u8,

            pub fn build(vt: *iWindow, gui: *Gui, area: Rect, _: *GuiConfig) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                self.area.area = area;
                self.layout.reset(gui, vt);
                const info = @typeInfo(enumT);
                self.layout.addChild(gui, WidgetVScroll.build(gui, area, &build_cb, &self.area, vt, info.Enum.fields.len) catch return, vt);
            }

            pub fn build_cb(vt: *iArea, tl: *SubLayout, area: Rect, index: usize, gui: *Gui, win: *iWindow) void {
                const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
                var ly = VerticalLayout{ .item_height = gui.style.config.default_item_h, .bounds = area };
                const info = @typeInfo(enumT);
                inline for (info.Enum.fields, 0..) |field, i| {
                    if (i >= index) {
                        tl.addChild(gui, WidgetButton.build(
                            gui,
                            ly.getArea().?,
                            field.name,
                            self.parent_vt,
                            &ParentT.buttonCb,
                            field.value,
                        ) catch return, win);
                    }
                }
            }

            pub fn deinit(vt: *iWindow, gui: *Gui) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                self.layout.deinit(gui, vt);
                vt.deinit();
                gui.alloc.destroy(self);
            }

            pub fn draw(vt: *iArea, d: DrawState) void {
                const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
                self.layout.draw(d);
            }

            pub fn deinit_area(vt: *iArea, _: *Gui, _: *iWindow) void {
                _ = vt;
            }
        };

        vt: iArea,

        enum_ptr: *enumT,

        pub fn build(gui: *Gui, area: Rect, enum_ptr: *enumT) !*iArea {
            const self = try gui.alloc.create(@This());
            self.* = .{
                .vt = .{
                    .onclick = &@This().onclick,
                    .draw_fn = &@This().draw,
                    .deinit_fn = &@This().deinit,
                    .area = area,
                },
                .enum_ptr = enum_ptr,
            };
            return &self.vt;
        }

        pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            gui.alloc.destroy(self);
        }

        pub fn draw(vt: *iArea, d: DrawState) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            d.ctx.rect(vt.area, 0x2ffff0ff);
            d.ctx.textFmt(vt.area.pos(), "{s}", .{@tagName(self.enum_ptr.*)}, d.font, vt.area.h, 0xff, .{});
            //std.debug.print("{s} says: {any}\n", .{ self.name, self.bool_ptr.* });
        }

        pub fn onclick(vt: *iArea, gui: *Gui) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            self.makeTransientWindow(gui, Rec(0, 0, 600, 600)) catch return;
        }

        pub fn buttonCb(vt: *iArea, id: usize, gui: *Gui) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            self.enum_ptr.* = @enumFromInt(id);
            gui.deferTransientClose();
        }

        pub fn makeTransientWindow(self: *@This(), gui: *Gui, area: Rect) !void {
            const popped = try gui.alloc.create(PoppedWindow);
            popped.* = .{
                .layout = SubLayout.init(gui),
                .parent_vt = &self.vt,
                .vt = iWindow.init(
                    &PoppedWindow.build,
                    gui,
                    &PoppedWindow.deinit,
                    &popped.area,
                ),
                .area = .{
                    .draw_fn = &PoppedWindow.draw,
                    .deinit_fn = &PoppedWindow.deinit_area,
                    .area = area,
                },
                .name = "noname",
            };
            popped.vt.build_fn(&popped.vt, gui, area, &gui.style);
            gui.transient_window = &popped.vt;
        }
    };
}

pub const WidgetVScroll = struct {
    pub const BuildCb = *const fn (*iArea, layout: *SubLayout, area: Rect, index: usize, *Gui, *iWindow) void;

    vt: iArea,

    layout: SubLayout,

    build_cb: BuildCb,
    build_cb_vt: *iArea,
    index: usize = 0,
    count: usize = 10,

    pub fn build(gui: *Gui, area: Rect, build_cb: BuildCb, build_cb_vt: *iArea, win: *iWindow, count: usize) !*iArea {
        const self = try gui.alloc.create(@This());
        self.* = .{
            .vt = .{
                .draw_fn = &@This().draw,
                .onscroll = &@This().onScroll,
                .deinit_fn = &@This().deinit,
                .area = area,
            },
            .count = count,
            .layout = SubLayout.init(gui),
            .build_cb = build_cb,
            .build_cb_vt = build_cb_vt,
        };
        self.build_cb(self.build_cb_vt, &self.layout, area, self.index, gui, win);
        return &self.vt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, window: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.layout.deinit(gui, window);
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, 0xff00ffff);
        self.layout.draw(d);
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
        vt.dirty();
        self.layout.reset(gui, win);
        self.build_cb(self.build_cb_vt, &self.layout, self.vt.area, self.index, gui, win);
    }
};

pub const WidgetCheckbox = struct {
    vt: iArea,

    bool_ptr: *bool,
    name: []const u8,

    pub fn build(gui: *Gui, area: Rect, bool_ptr: *bool, name: []const u8) !*iArea {
        const self = try gui.alloc.create(@This());
        self.* = .{
            .vt = .{
                .onclick = &@This().onclick,
                .draw_fn = &@This().draw,
                .deinit_fn = &@This().deinit,
                .area = area,
            },
            .bool_ptr = bool_ptr,
            .name = name,
        };
        return &self.vt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, 0xffff00ff);
        d.ctx.textFmt(vt.area.pos(), "{s}: {any}", .{ self.name, self.bool_ptr.* }, d.font, vt.area.h, 0xff, .{});
        //std.debug.print("{s} says: {any}\n", .{ self.name, self.bool_ptr.* });
    }

    //If we click, we need to redraw
    pub fn onclick(vt: *iArea, _: *Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.bool_ptr.* = !self.bool_ptr.*;
        vt.dirty();
    }
};

pub const WidgetButton = struct {
    pub const ButtonCallbackT = *const fn (*iArea, usize, *Gui) void;
    vt: iArea,

    callback_vt: ?*iArea = null,
    callback_fn: ?ButtonCallbackT,
    user_id: usize = 0,
    text: []const u8,
    is_down: bool = false,

    pub fn build(gui: *Gui, area: Rect, name: []const u8, cb_vt: ?*iArea, cb_fn: ?ButtonCallbackT, id: usize) !*iArea {
        const self = try gui.alloc.create(@This());
        self.* = .{
            .vt = .{
                .draw_fn = &@This().draw,
                .onclick = &@This().onclick,
                .deinit_fn = &@This().deinit,
                .area = area,
            },
            .text = name,
            .callback_vt = cb_vt,
            .callback_fn = cb_fn,
            .user_id = id,
        };
        return &self.vt;
    }
    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn mouseGrabbed(vt: *iArea, _: *Gui, _: Vec2f, _: Vec2f, state: Gui.MouseGrabState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const old = self.is_down;
        self.is_down = switch (state) {
            .high => true,
            .falling => false,
        };
        if (self.is_down != old)
            vt.dirty();
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        //d.ctx.rect(vt.area, 0x5ffff0ff);
        const sl = if (self.is_down) d.style.getRect(.button_clicked) else d.style.getRect(.button);
        const color = d.style.config.colors.button_text;
        d.ctx.nineSlice(vt.area, sl, d.style.texture, d.scale, 0xffffffff);
        const ta = vt.area.inset(3 * d.scale);
        d.ctx.textFmt(ta.pos(), "{s}", .{self.text}, d.font, d.style.config.text_h, color, .{});
    }

    pub fn onclick(vt: *iArea, gui: *Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        if (self.callback_fn) |cbfn|
            cbfn(self.callback_vt.?, self.user_id, gui);
        gui.grabMouse(&@This().mouseGrabbed, vt);
    }
};

pub const WidgetText = struct {
    vt: iArea,

    text: std.ArrayList(u8),

    pub fn build(gui: *Gui, area: Rect, comptime fmt: []const u8, args: anytype) !*iArea {
        const self = try gui.alloc.create(@This());
        var vec = std.ArrayList(u8).init(gui.alloc);
        try vec.writer().print(fmt, args);

        self.* = .{
            .vt = .{
                .draw_fn = &@This().draw,
                .deinit_fn = &@This().deinit,
                .area = area,
            },
            .text = vec,
        };
        return &self.vt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.text.deinit();
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, 0x5ffff0ff);
        d.ctx.textFmt(vt.area.pos(), "{s}", .{self.text.items}, d.font, vt.area.h, 0xff, .{});
    }
};

pub const WidgetSlider = struct {
    vt: iArea,

    num: f32,
    min: f32,
    max: f32,

    pub fn build(gui: *Gui, area: Rect, num: f32, min: f32, max: f32) !*iArea {
        const self = try gui.alloc.create(@This());
        self.* = .{
            .vt = .{
                .onclick = &@This().onclick,
                .draw_fn = &@This().draw,
                .onscroll = &@This().scroll,
                .deinit_fn = &@This().deinit,
                .area = area,
            },
            .num = num,
            .min = min,
            .max = max,
        };
        return &self.vt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self = getVt(@This(), vt);
        d.ctx.rect(vt.area, 0x00ffffff);
        d.ctx.textFmt(vt.area.pos(), "{d:.2}", .{self.num}, d.font, vt.area.h, 0xff, .{});
    }

    pub fn mouseGrabbed(vt: *iArea, gui: *Gui, pos: Vec2f, del: Vec2f, _: Gui.MouseGrabState) void {
        const self = getVt(@This(), vt);
        const dist = self.max - self.min;
        const width = vt.area.w;
        const factor = dist / width;

        const old_num = self.num;
        self.num += del.x * factor;
        self.num = std.math.clamp(self.num, self.min, self.max);
        if (old_num != self.num)
            vt.dirty();
        _ = pos;
        _ = gui;
    }

    pub fn scroll(vt: *iArea, _: *Gui, _: *iWindow, dist: f32) void {
        const self = getVt(@This(), vt);
        const old_num = self.num;
        self.num += dist;
        self.num = std.math.clamp(self.num, self.min, self.max);
        if (old_num != self.num)
            vt.dirty();
    }

    pub fn onclick(vt: *iArea, gui: *Gui) void {
        const self = getVt(@This(), vt);
        gui.grabMouse(&@This().mouseGrabbed, vt);
        _ = self;
        //Need some way to grab the mouse until it lets go
    }
};

pub const SubLayout = struct {
    children: std.ArrayList(*iArea),

    pub fn init(gui: *Gui) SubLayout {
        return .{
            .children = std.ArrayList(*iArea).init(gui.alloc),
        };
    }

    pub fn addChild(self: *@This(), gui: *Gui, vt: *iArea, window: *iWindow) void {
        if (vt.onclick != null)
            gui.registerOnClick(vt, window) catch return;
        if (vt.onscroll != null)
            gui.regOnScroll(vt, window) catch return;
        self.children.append(vt) catch return;
    }

    pub fn draw(self: *@This(), dctx: DrawState) void {
        for (self.children.items) |child|
            child.draw_fn(child, dctx);
    }

    pub fn reset(self: *@This(), gui: *Gui, window: *iWindow) void {
        for (self.children.items) |child| {
            gui.deregister(child, window);
            child.deinit_fn(child, gui, window);
        }
        self.children.clearRetainingCapacity();
    }

    pub fn deinit(self: *@This(), gui: *Gui, window: *iWindow) void {
        self.reset(gui, window);
        self.children.deinit();
    }
};

//What happens when area changes?
//rebuild everyone
//start with a window
//call to register window, that window has a "build" vfunc?

pub const MyInspector = struct {
    const MyEnum = enum {
        hello,
        world,
        this,
        is,
        a,
        enum_,
        that,
        has,
        fields,
    };

    vt: iWindow,
    area: iArea,
    layout: SubLayout,

    inspector_state: u32 = 0,
    bool1: bool = false,
    bool2: bool = false,
    my_enum: MyEnum = .hello,
    //This subscribes to onScroll
    //has two child layouts,
    //the act of splitting is not the Layouts job

    pub fn create(gui: *Gui) !*iWindow {
        const self = try gui.alloc.create(@This());
        self.* = .{
            .area = .{
                .draw_fn = &@This().draw,
                .deinit_fn = &@This().area_deinit,
                .area = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            },
            .vt = iWindow.init(&@This().build, gui, &@This().deinit, &self.area),
            .layout = SubLayout.init(gui),
        };
        return &self.vt;
    }

    pub fn deinit(vt: *iWindow, gui: *Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.layout.deinit(gui, vt);
        vt.deinit();
        gui.alloc.destroy(self); //second
    }

    pub fn area_deinit(_: *iArea, _: *Gui, _: *iWindow) void {}

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
        self.layout.draw(d);
    }

    pub fn build(vt: *iWindow, gui: *Gui, area: Rect, style: *GuiConfig) void {
        const self = getVt(@This(), vt);
        self.area.area = area;
        self.layout.reset(gui, vt);
        //start a vlayout
        //var ly = Vert{ .area = vt.area };
        var ly = VerticalLayout{
            .item_height = style.config.default_item_h,
            .bounds = area,
        };
        const tl = &self.layout;

        tl.addChild(gui, WidgetCheckbox.build(gui, ly.getArea().?, &self.bool1, "first button") catch return, vt);
        tl.addChild(gui, WidgetCheckbox.build(gui, ly.getArea().?, &self.bool2, "secnd button") catch return, vt);
        tl.addChild(gui, WidgetSlider.build(gui, ly.getArea().?, 4, 0, 10) catch return, vt);
        tl.addChild(gui, WidgetCombo(MyEnum).build(gui, ly.getArea().?, &self.my_enum) catch return, vt);

        tl.addChild(gui, WidgetButton.build(gui, ly.getArea().?, "My button", &self.area, @This().btnCb, 48) catch return, vt);

        ly.pushRemaining();
        tl.addChild(gui, WidgetVScroll.build(gui, ly.getArea().?, &buildScrollItems, &self.area, vt, 10) catch return, vt);
    }

    pub fn buildScrollItems(window_area: *iArea, sl: *SubLayout, area: Rect, index: usize, gui: *Gui, window: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("area", window_area));
        var ly = VerticalLayout{ .item_height = gui.style.config.default_item_h, .bounds = area };
        for (index..10) |i| {
            sl.addChild(gui, WidgetText.build(gui, ly.getArea() orelse return, "item {d}", .{i}) catch return, window);
        }
        _ = self;
    }

    pub fn btnCb(_: *iArea, id: usize, _: *Gui) void {
        std.debug.print("BUTTON CLICKED {d}\n", .{id});
    }
};

pub const VerticalLayout = struct {
    const Self = @This();
    padding: graph.Padding = .{ .top = 0, .bottom = 0, .left = 0, .right = 0 },
    item_height: f32,
    current_h: f32 = 0,
    next_height: ?f32 = null,
    give_remaining: bool = false,

    bounds: Rect,

    pub fn getArea(self: *Self) ?Rect {
        const bounds = self.bounds;
        const h = if (self.next_height) |nh| nh else self.item_height;
        self.next_height = null;

        if (self.current_h + self.padding.top > bounds.h) //We don't add h yet because the last element can be partially displayed. (if clipped)
            return null;

        if (self.give_remaining) {
            defer self.current_h = bounds.h;
            return .{
                .x = bounds.x + self.padding.left,
                .y = bounds.y + self.current_h + self.padding.top,
                .w = bounds.w - self.padding.horizontal(),
                .h = bounds.h - (self.current_h + self.padding.top) - self.padding.bottom,
            };
        }

        defer self.current_h += h + self.padding.vertical();
        return .{
            .x = bounds.x + self.padding.left,
            .y = bounds.y + self.current_h + self.padding.top,
            .w = bounds.w - self.padding.horizontal(),
            .h = h,
        };
    }

    pub fn pushHeight(self: *Self, h: f32) void {
        self.next_height = h;
    }

    /// The next requested area will be the rest of the available space
    pub fn pushRemaining(self: *Self) void {
        self.give_remaining = true;
    }
};

pub const iArea = struct {
    draw_fn: *const fn (*iArea, DrawState) void,
    deinit_fn: *const fn (*iArea, *Gui, *iWindow) void,

    onclick: ?*const fn (*iArea, *Gui) void = null,
    onscroll: ?*const fn (*iArea, *Gui, *iWindow, distance: f32) void = null,
    area: Rect,
    is_dirty: bool = false,

    pub fn dirty(self: *@This()) void {
        self.is_dirty = true;
    }
};

pub const iWindow = struct {
    const BuildfnT = *const fn (*iWindow, *Gui, Rect, *GuiConfig) void;

    build_fn: BuildfnT,
    deinit_fn: *const fn (*iWindow, *Gui) void,

    area: *iArea,

    click_listeners: std.ArrayList(*iArea),
    scroll_list: std.ArrayList(*iArea),

    pub fn draw(self: *iWindow, dctx: DrawState) void {
        self.area.draw_fn(self.area, dctx);
    }

    pub fn init(build_fn: BuildfnT, gui: *Gui, deinit_fn: *const fn (*iWindow, *Gui) void, area: *iArea) iWindow {
        return .{
            .deinit_fn = deinit_fn,
            .build_fn = build_fn,
            .click_listeners = std.ArrayList(*iArea).init(gui.alloc),
            .scroll_list = std.ArrayList(*iArea).init(gui.alloc),
            .area = area,
        };
    }

    // the implementers deinit fn should call this first
    pub fn deinit(self: *iWindow) void {
        //self.layout.vt.deinit_fn(&self.layout.vt, gui, self);
        if (self.click_listeners.items.len != 0)
            std.debug.print("BROKEN\n", .{});
        if (self.scroll_list.items.len != 0)
            std.debug.print("BROKEN\n", .{});
        self.click_listeners.deinit();
        self.scroll_list.deinit();
    }

    /// Returns true if this window contains the mouse
    pub fn dispatchClick(win: *iWindow, coord: Vec2f, gui: *Gui) bool {
        if (win.area.area.containsPoint(coord)) {
            for (win.click_listeners.items) |vt| {
                if (vt.area.containsPoint(coord)) {
                    if (vt.onclick) |oc|
                        oc(vt, gui);
                }
            }
            return true;
        }
        return false;
    }

    pub fn dispatchScroll(win: *iWindow, coord: Vec2f, gui: *Gui, dist: f32) bool {
        if (win.area.area.containsPoint(coord)) {
            for (win.scroll_list.items) |vt| {
                if (vt.area.containsPoint(coord)) {
                    if (vt.onscroll) |oc|
                        oc(vt, gui, win, dist);
                }
            }
            return true;
        }
        return false;
    }
};
const Vec2f = graph.Vec2f;

pub const Gui = struct {
    const Self = @This();
    const MouseGrabState = enum { high, falling };

    alloc: std.mem.Allocator,
    windows: std.ArrayList(*iWindow),

    transient_should_close: bool = false,
    transient_window: ?*iWindow = null,

    mouse_grab: ?*const fn (*iArea, *Gui, Vec2f, Vec2f, MouseGrabState) void = null,
    mouse_grab_vt: ?*iArea = null,

    style: GuiConfig,

    pub fn init(alloc: AL) !Self {
        return Gui{
            .alloc = alloc,
            .windows = std.ArrayList(*iWindow).init(alloc),
            .style = try GuiConfig.init(alloc, std.fs.cwd(), "asset/os9gui", std.fs.cwd()),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.windows.items) |win|
            win.deinit_fn(win, self);

        self.windows.deinit();
        self.closeTransientWindow();
        self.style.deinit();
    }

    pub fn registerOnClick(_: *Self, vt: *iArea, window: *iWindow) !void {
        try window.click_listeners.append(vt);
    }

    /// If transient windows destroy themselves, the program will crash as used memory is freed.
    /// Defer the close till next update
    pub fn deferTransientClose(self: *Self) void {
        self.transient_should_close = true;
    }

    pub fn regOnScroll(_: *Self, vt: *iArea, window: *iWindow) !void {
        try window.scroll_list.append(vt);
    }

    pub fn deregister(self: *Self, vt: *iArea, window: *iWindow) void {
        for (window.scroll_list.items, 0..) |item, index| {
            if (item == vt) {
                _ = window.scroll_list.swapRemove(index);
                break;
            }
        }
        for (window.click_listeners.items, 0..) |item, index| {
            if (item == vt) {
                _ = window.click_listeners.swapRemove(index);
                break;
            }
        }
        if (self.mouse_grab_vt) |mvt| {
            if (mvt == vt) {
                self.mouse_grab_vt = null;
                self.mouse_grab = null;
            }
        }
    }

    pub fn closeTransientWindow(self: *Self) void {
        if (self.transient_window) |tw| {
            tw.deinit_fn(tw, self);
        }
        self.transient_window = null;
    }

    pub fn dispatchClick(self: *Self, coord: Vec2f) void {
        if (self.transient_window) |tw| {
            if (tw.dispatchClick(coord, self)) {
                return; //Don't click top level windows
            } else {
                //Close the window, we clicked outside
                self.closeTransientWindow();
            }
        }
        for (self.windows.items) |win| {
            if (win.dispatchClick(coord, self))
                break;
        }
    }

    pub fn dispatchScroll(self: *Self, pos: Vec2f, dist: f32) void {
        if (self.transient_window) |tw| {
            if (tw.dispatchScroll(pos, self, dist)) {
                return; //Don't click top level windows
            } else {
                //Close the window, we clicked outside
                self.closeTransientWindow();
            }
        }
        for (self.windows.items) |win| {
            if (win.dispatchScroll(pos, self, dist))
                break;
        }
    }

    ///TODO be carefull with this ptr,
    ///if the widget who gave this ptr is destroyed while mouse is grabbed we crash.
    ///how to solve?
    ///name vtables with ids
    ///on vt destroy, check and unset
    pub fn grabMouse(self: *Self, ptr: anytype, vt: *iArea) void {
        self.mouse_grab = ptr;
        self.mouse_grab_vt = vt;
    }

    pub fn addWindow(self: *Self, window: *iWindow, area: Rect) !void {
        window.build_fn(window, self, area, &self.style); //Rebuild it
        try self.windows.append(window);
    }

    pub fn draw(self: *Self, dctx: DrawState) void {
        for (self.windows.items) |window|
            window.draw(dctx);
        if (self.transient_window) |tw|
            tw.draw(dctx);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    var win = try graph.SDL.Window.createWindow("My window", .{
        // Optional, see Window.createWindow definition for full list of options
        .window_size = .{ .x = 800, .y = 600 },
    });
    defer win.destroyWindow();

    var draw = graph.ImmediateDrawingContext.init(alloc);
    defer draw.deinit();

    var gui = try Gui.init(alloc);
    defer gui.deinit();
    gui.style.config.default_item_h = @trunc(25 * 1.6);
    gui.style.config.text_h = @trunc(20 * 1.6);
    var font = try graph.Font.initFromBuffer(alloc, @embedFile("font/roboto.ttf"), gui.style.config.text_h, .{});
    defer font.deinit();

    const window_area = .{ .x = 0, .y = 0, .w = 1000, .h = 1000 };

    try gui.addWindow(try MyInspector.create(&gui), window_area);

    while (!win.should_exit) {
        try draw.begin(0x2f2f2fff, win.screen_dimensions.toF());
        win.pumpEvents(.poll); //Important that this is called after draw.begin for input lag reasons
        if (win.keyRising(.ESCAPE))
            win.should_exit = true;

        if (gui.transient_should_close) {
            gui.transient_should_close = false;
            gui.closeTransientWindow();
        }
        switch (win.mouse.left) {
            .rising => gui.dispatchClick(win.mouse.pos),
            .low => {
                gui.mouse_grab_vt = null;
                gui.mouse_grab = null;
            },
            .falling => {
                if (gui.mouse_grab) |func|
                    func(gui.mouse_grab_vt.?, &gui, win.mouse.pos, win.mouse.delta, .falling);
            },
            .high => {
                if (gui.mouse_grab) |func| {
                    func(gui.mouse_grab_vt.?, &gui, win.mouse.pos, win.mouse.delta, .high);
                }
            },
        }
        if (win.mouse.wheel_delta.y != 0)
            gui.dispatchScroll(win.mouse.pos, win.mouse.wheel_delta.y);
        gui.draw(.{ .ctx = &draw, .font = &font.font, .style = &gui.style });

        try draw.flush(null, null); //Flush any draw commands

        try draw.end(null);
        win.swap();
    }
}
