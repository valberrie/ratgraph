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

pub fn WidgetCombo(comptime enumT: type) type {
    return struct {
        pub const PoppedWindow = struct {
            vt: iWindow,
            name: []const u8,

            pub fn build(vt: *iWindow, gui: *Gui) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                _ = self;
                vt.children.clearRetainingCapacity();

                var ly = Vert{ .area = vt.area };
                vt.children.append(WidgetText.build(gui, ly.getArea(), "item 1") catch return) catch return;
                vt.children.append(WidgetText.build(gui, ly.getArea(), "item 2") catch return) catch return;
            }
        };

        vt: iLayout,

        enum_ptr: *enumT,

        pub fn build(gui: *Gui, area: Rect, enum_ptr: *enumT) !*iLayout {
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

        pub fn draw(vt: *iLayout, d: DrawState) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            d.ctx.rect(vt.area, 0x2ffff0ff);
            d.ctx.textFmt(vt.area.pos(), "{s}", .{@tagName(self.enum_ptr.*)}, d.font, vt.area.h, 0xff, .{});
            //std.debug.print("{s} says: {any}\n", .{ self.name, self.bool_ptr.* });
        }

        pub fn onclick(vt: *iLayout, gui: *Gui) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            self.makeTransientWindow(gui, Rec(0, 0, 600, 600)) catch return;
        }

        pub fn makeTransientWindow(self: *@This(), gui: *Gui, area: Rect) !void {
            _ = self;
            const popped = try gui.alloc.create(PoppedWindow);
            popped.* = .{
                .vt = .{
                    .build_fn = &PoppedWindow.build,
                    .children = std.ArrayList(*iLayout).init(gui.alloc),
                },
                .name = "noname",
            };
            popped.vt.area = area;
            popped.vt.build_fn(&popped.vt, gui);
            gui.transient_window = &popped.vt;
        }
    };
}

pub const WidgetCheckbox = struct {
    vt: iLayout,

    bool_ptr: *bool,
    name: []const u8,

    pub fn build(gui: *Gui, area: Rect, bool_ptr: *bool, name: []const u8) !*iLayout {
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

    pub fn draw(vt: *iLayout, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, 0xffff00ff);
        d.ctx.textFmt(vt.area.pos(), "{s}: {any}", .{ self.name, self.bool_ptr.* }, d.font, vt.area.h, 0xff, .{});
        //std.debug.print("{s} says: {any}\n", .{ self.name, self.bool_ptr.* });
    }

    //If we click, we need to redraw
    pub fn onclick(vt: *iLayout, _: *Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.bool_ptr.* = !self.bool_ptr.*;
        vt.dirty();
    }
};

pub const WidgetText = struct {
    vt: iLayout,

    text: []const u8,

    pub fn build(gui: *Gui, area: Rect, name: []const u8) !*iLayout {
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

    pub fn draw(vt: *iLayout, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, 0x5ffff0ff);
        d.ctx.textFmt(vt.area.pos(), "{s}", .{self.text}, d.font, vt.area.h, 0xff, .{});
    }
};

pub const WidgetSlider = struct {
    vt: iLayout,

    num: f32,
    min: f32,
    max: f32,

    pub fn build(gui: *Gui, area: Rect, num: f32, min: f32, max: f32) !*iLayout {
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

    pub fn draw(vt: *iLayout, d: DrawState) void {
        const self = getVt(@This(), vt);
        d.ctx.rect(vt.area, 0x00ffffff);
        d.ctx.textFmt(vt.area.pos(), "{d:.2}", .{self.num}, d.font, vt.area.h, 0xff, .{});
    }

    pub fn mouseGrabbed(vt: *iLayout, gui: *Gui, pos: Vec2f, del: Vec2f) void {
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

    pub fn scroll(vt: *iLayout, _: *Gui, dist: f32) void {
        const self = getVt(@This(), vt);
        const old_num = self.num;
        self.num += dist;
        self.num = std.math.clamp(self.num, self.min, self.max);
        if (old_num != self.num)
            vt.dirty();
    }

    pub fn onclick(vt: *iLayout, gui: *Gui) void {
        const self = getVt(@This(), vt);
        gui.grabMouse(&@This().mouseGrabbed, vt);
        _ = self;
        //Need some way to grab the mouse until it lets go
    }
};

pub const iLayout = struct {
    draw_fn: *const fn (*iLayout, DrawState) void,

    onclick: ?*const fn (*iLayout, *Gui) void = null,
    onscroll: ?*const fn (*iLayout, *Gui, distance: f32) void = null,
    area: Rect,
    is_dirty: bool = false,

    pub fn dirty(self: *@This()) void {
        self.is_dirty = true;
    }
};

pub const Layout = struct {
    vt: iLayout,
    children: std.ArrayList(*iLayout),

    pub fn build(gui: *Gui, area: Rect) !*iLayout {
        const self = try gui.alloc.create(@This());
        self.* = .{
            .vt = .{
                .draw_fn = &@This().draw,
                .area = area,
            },
            .children = std.ArrayList(*iLayout).init(gui.alloc),
        };
        return &self.vt;
    }

    pub fn addChild(self: *@This(), gui: *Gui, vt: *iLayout) void {
        if (vt.onclick != null)
            gui.registerOnClick(vt) catch return;
        if (vt.onscroll != null)
            gui.regOnScroll(vt) catch return;
        self.children.append(vt) catch return;
    }

    pub fn draw(vt: *iLayout, dctx: DrawState) void {
        const self = getVt(@This(), vt);
        for (self.children.items) |child|
            child.draw_fn(child, dctx);
    }

    pub fn reset(self: *@This(), area: Rect) void {
        self.vt.area = area;
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
    list: Layout,
    bool1: bool = false,
    bool2: bool = false,
    my_enum: MyEnum = .hello,
    //This subscribes to onScroll
    //has two child layouts,
    //the act of splitting is not the Layouts job

    pub fn create(gui: *Gui) !*iWindow {
        const self = try gui.alloc.create(@This());
        self.* = .{
            .vt = .{
                .build_fn = &@This().build,
                .children = std.ArrayList(*iLayout).init(gui.alloc),
            },
            .list = getVt(Layout, try Layout.build(gui, .{ .x = 0, .y = 0, .w = 0, .h = 0 })).*,
        };
        return &self.vt;
    }

    pub fn build(vt: *iWindow, gui: *Gui) void {
        const self = getVt(@This(), vt);
        self.list.reset(vt.area);
        vt.children.clearRetainingCapacity();
        //start a vlayout
        var ly = Vert{ .area = vt.area };

        self.list.addChild(gui, WidgetCheckbox.build(gui, ly.getArea(), &self.bool1, "first button") catch return);
        self.list.addChild(gui, WidgetCheckbox.build(gui, ly.getArea(), &self.bool2, "secnd button") catch return);
        self.list.addChild(gui, WidgetSlider.build(gui, ly.getArea(), 4, 0, 10) catch return);
        self.list.addChild(gui, WidgetCombo(MyEnum).build(gui, ly.getArea(), &self.my_enum) catch return);

        vt.children.append(&self.list.vt) catch return;
    }
};

pub const Vert = struct {
    area: Rect,
    index: usize = 0,
    item_h: f32 = 100,

    pub fn getArea(self: *@This()) Rect {
        defer self.index += 1;
        const a = self.area;
        const dy = @as(f32, @floatFromInt(self.index)) * self.item_h;
        return .{ .x = a.x, .y = a.y + dy, .w = a.h, .h = self.item_h };
    }
};

//some function, register top Level, explicitly provide an area

pub const iWindow = struct {
    area: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    build_fn: *const fn (*iWindow, *Gui) void,
    children: std.ArrayList(*iLayout),

    pub fn draw(self: *iWindow, dctx: DrawState) void {
        for (self.children.items) |child|
            child.draw_fn(child, dctx);
    }
};
const Vec2f = graph.Vec2f;

pub const Gui = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    click_listeners: std.ArrayList(*iLayout),
    scroll_list: std.ArrayList(*iLayout),
    windows: std.ArrayList(*iWindow),

    transient_window: ?*iWindow = null,

    mouse_grab: ?*const fn (*iLayout, *Gui, Vec2f, Vec2f) void = null,
    mouse_grab_vt: ?*iLayout = null,

    pub fn registerOnClick(self: *Self, vt: *iLayout) !void {
        try self.click_listeners.append(vt);
    }

    pub fn regOnScroll(self: *Self, vt: *iLayout) !void {
        try self.scroll_list.append(vt);
    }

    pub fn dispatchClick(self: *Self, coord: Vec2f) void {
        if (self.transient_window) |tw| {
            if (!tw.area.containsPoint(coord))
                self.transient_window = null;
        }
        for (self.click_listeners.items) |vt| {
            if (vt.area.containsPoint(coord)) {
                if (vt.onclick) |oc|
                    oc(vt, self);
            }
        }
    }

    pub fn dispatchScroll(self: *Self, pos: Vec2f, dist: f32) void {
        for (self.scroll_list.items) |vt| {
            if (vt.area.containsPoint(pos)) {
                if (vt.onscroll) |oc|
                    oc(vt, self, dist);
            }
        }
    }

    pub fn grabMouse(self: *Self, ptr: anytype, vt: *iLayout) void {
        self.mouse_grab = ptr;
        self.mouse_grab_vt = vt;
    }

    pub fn addWindow(self: *Self, window: *iWindow, area: Rect) !void {
        window.area = area;
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

    var gui = Gui{
        .alloc = alloc,
        .click_listeners = std.ArrayList(*iLayout).init(alloc),
        .windows = std.ArrayList(*iWindow).init(alloc),
        .scroll_list = std.ArrayList(*iLayout).init(alloc),
    };

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
