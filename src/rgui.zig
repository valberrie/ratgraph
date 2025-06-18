const std = @import("std");
const graph = @import("graphics.zig");
const Dctx = graph.ImmediateDrawingContext;

const Rect = graph.Rect;
const Rec = graph.Rec;
const AL = std.mem.Allocator;

//How to do events?
//don't overthink it, just specify functions for each
//
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
};

//Two options for this, we use a button widget which registers itself for onclick
//or we listen for onclick and determine which was clicked
pub fn WidgetCombo(comptime enumT: type) type {
    return struct {
        const ParentT = @This();
        pub const PoppedWindow = struct {
            vt: iWindow,
            parent_vt: *iArea,
            name: []const u8,

            pub fn build(vt: *iWindow, gui: *Gui) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                vt.layout.reset();

                var ly = Vert{ .area = vt.layout.vt.area };
                const tl = &vt.layout;
                tl.addChild(gui, WidgetButton.build(
                    gui,
                    ly.getArea().?,
                    "item 1",
                    self.parent_vt,
                    &ParentT.buttonCb,
                    0,
                ) catch return, vt);
                tl.addChild(gui, WidgetButton.build(
                    gui,
                    ly.getArea().?,
                    "item 2",
                    self.parent_vt,
                    &ParentT.buttonCb,
                    1,
                ) catch return, vt);
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
                    .area = area,
                },
                .enum_ptr = enum_ptr,
            };
            return &self.vt;
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

        pub fn buttonCb(vt: *iArea, id: usize) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            self.enum_ptr.* = @enumFromInt(id);
        }

        pub fn makeTransientWindow(self: *@This(), gui: *Gui, area: Rect) !void {
            const popped = try gui.alloc.create(PoppedWindow);
            popped.* = .{
                .parent_vt = &self.vt,
                .vt = try iWindow.init(gui.alloc, &PoppedWindow.build, gui),
                .name = "noname",
            };
            popped.vt.layout.vt.area = area;
            popped.vt.build_fn(&popped.vt, gui);
            gui.transient_window = &popped.vt;
        }
    };
}

pub const WidgetVScroll = struct {
    vt: iArea,

    index: usize = 0,
    count: usize = 10,

    pub fn build(gui: *Gui, area: Rect) !*iArea {
        const self = try gui.alloc.create(@This());
        self.* = .{
            .vt = .{
                .draw_fn = &@This().draw,
                .onscroll = &@This().onScroll,
                .area = area,
            },
        };
        return &self.vt;
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, 0xff00ffff);
        var ly = Vert{ .area = vt.area };

        for (self.index..self.count) |i| {
            const area = ly.getArea() orelse break;
            d.ctx.textFmt(area.pos(), "index {d}", .{i}, d.font, area.h, 0xff, .{});
        }
        //while()
    }

    pub fn onScroll(vt: *iArea, _: *Gui, dist: f32) void {
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
                .area = area,
            },
            .bool_ptr = bool_ptr,
            .name = name,
        };
        return &self.vt;
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
    pub const ButtonCallbackT = *const fn (*iArea, usize) void;
    vt: iArea,

    callback_vt: ?*iArea = null,
    callback_fn: ?ButtonCallbackT,
    user_id: usize = 0,
    text: []const u8,

    pub fn build(gui: *Gui, area: Rect, name: []const u8, cb_vt: ?*iArea, cb_fn: ?ButtonCallbackT, id: usize) !*iArea {
        const self = try gui.alloc.create(@This());
        self.* = .{
            .vt = .{
                .draw_fn = &@This().draw,
                .onclick = &@This().onclick,
                .area = area,
            },
            .text = name,
            .callback_vt = cb_vt,
            .callback_fn = cb_fn,
            .user_id = id,
        };
        return &self.vt;
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, 0x5ffff0ff);
        d.ctx.textFmt(vt.area.pos(), "Btn {s}", .{self.text}, d.font, vt.area.h, 0xff, .{});
    }

    pub fn onclick(vt: *iArea, _: *Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        if (self.callback_fn) |cbfn|
            cbfn(self.callback_vt.?, self.user_id);
    }
};

pub const WidgetText = struct {
    vt: iArea,

    text: []const u8,

    pub fn build(gui: *Gui, area: Rect, name: []const u8) !*iArea {
        const self = try gui.alloc.create(@This());
        self.* = .{
            .vt = .{
                .draw_fn = &@This().draw,
                .area = area,
            },
            .text = name,
        };
        return &self.vt;
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, 0x5ffff0ff);
        d.ctx.textFmt(vt.area.pos(), "{s}", .{self.text}, d.font, vt.area.h, 0xff, .{});
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
                .area = area,
            },
            .num = num,
            .min = min,
            .max = max,
        };
        return &self.vt;
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self = getVt(@This(), vt);
        d.ctx.rect(vt.area, 0x00ffffff);
        d.ctx.textFmt(vt.area.pos(), "{d:.2}", .{self.num}, d.font, vt.area.h, 0xff, .{});
    }

    pub fn mouseGrabbed(vt: *iArea, gui: *Gui, pos: Vec2f, del: Vec2f) void {
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

    pub fn scroll(vt: *iArea, _: *Gui, dist: f32) void {
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

pub const Layout = struct {
    vt: iArea,
    children: std.ArrayList(*iArea),

    pub fn build(gui: *Gui, area: Rect) !*iArea {
        const self = try gui.alloc.create(@This());
        self.* = .{
            .vt = .{
                .draw_fn = &@This().draw,
                .area = area,
            },
            .children = std.ArrayList(*iArea).init(gui.alloc),
        };
        return &self.vt;
    }

    pub fn addChild(self: *@This(), gui: *Gui, vt: *iArea, window: *iWindow) void {
        if (vt.onclick != null)
            gui.registerOnClick(vt, window) catch return;
        if (vt.onscroll != null)
            gui.regOnScroll(vt, window) catch return;
        self.children.append(vt) catch return;
    }

    pub fn draw(vt: *iArea, dctx: DrawState) void {
        const self = getVt(@This(), vt);
        //vt.draw_fn(vt, dctx);
        for (self.children.items) |child|
            child.draw_fn(child, dctx);
    }

    pub fn generic_draw(self: *iArea, d: DrawState) void {
        d.ctx.rect(self.area, 0x2222_22ff);
    }

    pub fn reset(self: *@This()) void {
        self.children.clearRetainingCapacity();
        //TODO  in the future, kill all the children
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
    };

    vt: iWindow,
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
            .vt = try iWindow.init(gui.alloc, &@This().build, gui),
        };
        return &self.vt;
    }

    pub fn build(vt: *iWindow, gui: *Gui) void {
        const self = getVt(@This(), vt);
        vt.layout.reset();
        //start a vlayout
        //var ly = Vert{ .area = vt.area };
        var ly = VerticalLayout{
            .item_height = 100,
            .bounds = vt.layout.vt.area,
        };
        const tl = &vt.layout;

        tl.addChild(gui, WidgetCheckbox.build(gui, ly.getArea().?, &self.bool1, "first button") catch return, vt);
        tl.addChild(gui, WidgetCheckbox.build(gui, ly.getArea().?, &self.bool2, "secnd button") catch return, vt);
        tl.addChild(gui, WidgetSlider.build(gui, ly.getArea().?, 4, 0, 10) catch return, vt);
        tl.addChild(gui, WidgetCombo(MyEnum).build(gui, ly.getArea().?, &self.my_enum) catch return, vt);

        tl.addChild(gui, WidgetButton.build(gui, ly.getArea().?, "My button", &self.vt.layout.vt, @This().btnCb, 48) catch return, vt);

        ly.pushRemaining();
        tl.addChild(gui, WidgetVScroll.build(gui, ly.getArea().?) catch return, vt);
    }

    pub fn btnCb(_: *iArea, id: usize) void {
        std.debug.print("BUTTON CLICKED {d}\n", .{id});
    }
};

pub const Vert = struct {
    area: Rect,
    index: usize = 0,
    item_h: f32 = 100,

    next_h: ?f32 = null,

    pub fn getArea(self: *@This()) ?Rect {
        defer self.index += 1;
        const a = self.area;
        const dy = @as(f32, @floatFromInt(self.index)) * self.item_h;
        if (dy > a.h)
            return null;
        return .{ .x = a.x, .y = a.y + dy, .w = a.w, .h = self.item_h };
    }
};

pub const VerticalLayout = struct {
    const Self = @This();
    padding: graph.Padding = .{ .top = 0, .bottom = 0, .left = 0, .right = 0 },
    item_height: f32,
    current_h: f32 = 0,
    hidden: bool = false,
    next_height: ?f32 = null,
    give_remaining: bool = false,

    bounds: Rect,

    pub fn getArea(self: *Self) ?Rect {
        const bounds = self.bounds;
        const h = if (self.next_height) |nh| nh else self.item_height;
        self.next_height = null;

        if (self.current_h + self.padding.top > bounds.h or self.hidden) //We don't add h yet because the last element can be partially displayed. (if clipped)
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

    //TODO this doesn't really "push" a height. misleading as one might push push push then expecting subsequent widgets to pop pop pop
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

    onclick: ?*const fn (*iArea, *Gui) void = null,
    onscroll: ?*const fn (*iArea, *Gui, distance: f32) void = null,
    area: Rect,
    is_dirty: bool = false,

    pub fn dirty(self: *@This()) void {
        self.is_dirty = true;
    }
};

pub const iWindow = struct {
    const BuildfnT = *const fn (*iWindow, *Gui) void;

    build_fn: BuildfnT,

    layout: Layout,

    click_listeners: std.ArrayList(*iArea),
    scroll_list: std.ArrayList(*iArea),

    pub fn draw(self: *iWindow, dctx: DrawState) void {
        self.layout.vt.draw_fn(&self.layout.vt, dctx);
    }

    pub fn init(alloc: std.mem.Allocator, build_fn: BuildfnT, gui: *Gui) !iWindow {
        return .{
            .build_fn = build_fn,
            .click_listeners = std.ArrayList(*iArea).init(alloc),
            .scroll_list = std.ArrayList(*iArea).init(alloc),
            .layout = getVt(Layout, try Layout.build(gui, .{ .x = 0, .y = 0, .w = 0, .h = 0 })).*,
        };
    }

    /// Returns true if this window contains the mouse
    pub fn dispatchClick(win: *iWindow, coord: Vec2f, gui: *Gui) bool {
        if (win.layout.vt.area.containsPoint(coord)) {
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
};
const Vec2f = graph.Vec2f;

pub const Gui = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    windows: std.ArrayList(*iWindow),

    transient_window: ?*iWindow = null,

    mouse_grab: ?*const fn (*iArea, *Gui, Vec2f, Vec2f) void = null,
    mouse_grab_vt: ?*iArea = null,

    pub fn init(alloc: AL) Self {
        return Gui{
            .alloc = alloc,
            .windows = std.ArrayList(*iWindow).init(alloc),
        };
    }

    pub fn registerOnClick(_: *Self, vt: *iArea, window: *iWindow) !void {
        try window.click_listeners.append(vt);
    }

    pub fn regOnScroll(_: *Self, vt: *iArea, window: *iWindow) !void {
        try window.scroll_list.append(vt);
    }

    pub fn dispatchClick(self: *Self, coord: Vec2f) void {
        if (self.transient_window) |tw| {
            if (tw.dispatchClick(coord, self)) {
                return; //Don't click top level windows
            } else {
                //Close the window, we clicked outside
                self.transient_window = null;
            }
        }
        for (self.windows.items) |win| {
            if (win.dispatchClick(coord, self))
                break;
        }
    }

    pub fn dispatchScroll(self: *Self, pos: Vec2f, dist: f32) void {
        for (self.windows.items) |win| {
            if (win.layout.vt.area.containsPoint(pos)) {
                for (win.scroll_list.items) |vt| {
                    if (vt.area.containsPoint(pos)) {
                        if (vt.onscroll) |oc|
                            oc(vt, self, dist);
                    }
                }
                break; //Windows cannot overlap so we can break
            }
        }
    }

    pub fn grabMouse(self: *Self, ptr: anytype, vt: *iArea) void {
        self.mouse_grab = ptr;
        self.mouse_grab_vt = vt;
    }

    pub fn addWindow(self: *Self, window: *iWindow, area: Rect) !void {
        window.layout.vt.area = area;
        window.build_fn(window, self); //Rebuild it
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
    const alloc = gpa.allocator();

    var win = try graph.SDL.Window.createWindow("My window", .{
        // Optional, see Window.createWindow definition for full list of options
        .window_size = .{ .x = 800, .y = 600 },
    });
    defer win.destroyWindow();

    var draw = graph.ImmediateDrawingContext.init(alloc);
    defer draw.deinit();

    var font = try graph.Font.init(alloc, std.fs.cwd(), "asset/fonts/roboto.ttf", 40, .{});
    defer font.deinit();
    const v1 = Vec2f.new(0, 0);
    const v2 = Vec2f.new(3, 3);
    const v3 = Vec2f.new(30, 30);

    var gui = Gui.init(alloc);

    const window_area = .{ .x = 0, .y = 0, .w = 1000, .h = 1000 };

    try gui.addWindow(try MyInspector.create(&gui), window_area);

    std.debug.print("STARTING\n", .{});

    while (!win.should_exit) {
        try draw.begin(0x2f2f2fff, win.screen_dimensions.toF());
        win.pumpEvents(.poll); //Important that this is called after draw.begin for input lag reasons
        if (win.keyRising(.ESCAPE))
            win.should_exit = true;

        draw.triangle(v1, v2, v3, 0xfffffff0);
        switch (win.mouse.left) {
            .rising => gui.dispatchClick(win.mouse.pos),
            .falling, .low => {
                gui.mouse_grab_vt = null;
                gui.mouse_grab = null;
            },
            .high => {
                if (gui.mouse_grab) |func| {
                    func(gui.mouse_grab_vt.?, &gui, win.mouse.pos, win.mouse.delta);
                }
            },
        }
        if (win.mouse.wheel_delta.y != 0)
            gui.dispatchScroll(win.mouse.pos, win.mouse.wheel_delta.y);
        gui.draw(.{ .ctx = &draw, .font = &font.font });

        try draw.flush(null, null); //Flush any draw commands

        try draw.end(null);
        win.swap();
    }
}
