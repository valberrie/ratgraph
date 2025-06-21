const std = @import("std");
pub const graph = @import("../graphics.zig");
const Os9Gui = @import("../gui_app.zig");
pub const Dctx = graph.ImmediateDrawingContext;
pub const GuiConfig = Os9Gui.GuiConfig;
pub const Rect = graph.Rect;
pub const Rec = graph.Rec;
const AL = std.mem.Allocator;

pub const Widget = struct {
    pub usingnamespace @import("widget_textbox.zig");
    pub usingnamespace @import("widget_basic.zig");
};

pub fn getVt(comptime T: type, vt: anytype) *T {
    return @alignCast(@fieldParentPtr("vt", vt));
}
pub const TextCbState = struct {
    gui: *Gui,
    text: []const u8,
};

pub const iArea = struct {
    draw_fn: ?*const fn (*iArea, DrawState) void = null,
    deinit_fn: ?*const fn (*iArea, *Gui, *iWindow) void = null,
    onclick: ?*const fn (*iArea, MouseCbState, *iWindow) void = null,
    onscroll: ?*const fn (*iArea, *Gui, *iWindow, distance: f32) void = null,
    textinput: ?*const fn (*iArea, TextCbState, *iWindow) void = null,

    area: Rect,
    children: std.ArrayList(*iArea),
    is_dirty: bool = false,

    pub fn init(gui: *Gui, area: Rect) iArea {
        return .{
            .area = area,
            .children = std.ArrayList(*iArea).init(gui.alloc),
        };
    }

    pub fn deinit(self: *@This(), gui: *Gui, win: *iWindow) void {
        self.clearChildren(gui, win);
        self.children.deinit();
        if (self.deinit_fn) |dfn|
            dfn(self, gui, win);
    }

    pub fn draw(self: *@This(), dctx: DrawState) void {
        if (self.draw_fn) |drawf|
            drawf(self, dctx);
        for (self.children.items) |child|
            child.draw(dctx);
        //if (gui.needsDraw(self)) {
        //    if (self.draw_fn) |drawf|
        //        drawf(self, dctx);
        //}
        self.is_dirty = false;
    }

    pub fn dirty(self: *@This(), gui: *Gui) void {
        if (!self.is_dirty)
            gui.setDirty(self);
        self.is_dirty = true;
    }

    pub fn addChild(self: *@This(), gui: *Gui, win: *iWindow, vt: *iArea) void {
        if (vt.onclick != null)
            gui.registerOnClick(vt, win) catch return;
        if (vt.onscroll != null)
            gui.regOnScroll(vt, win) catch return;
        self.children.append(vt) catch return;
    }

    pub fn deinitEmpty(vt: *iArea, gui: *Gui, _: *iWindow) void {
        gui.alloc.destroy(vt);
    }

    pub fn addEmpty(self: *@This(), gui: *Gui, win: *iWindow, area: Rect) *iArea {
        const vt = gui.alloc.create(iArea) catch unreachable;
        vt.* = init(gui, area);
        vt.deinit_fn = &deinitEmpty;
        self.addChild(gui, win, vt);
        return vt;
    }

    pub fn clearChildren(self: *@This(), gui: *Gui, window: *iWindow) void {
        for (self.children.items) |child| {
            gui.deregister(child, window);
            child.deinit(gui, window);
        }
        self.children.clearRetainingCapacity();
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
        self.area.draw(dctx);
        //self.area.draw_fn(self.area, dctx);
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
    pub fn deinit(self: *iWindow, gui: *Gui) void {
        //self.layout.vt.deinit_fn(&self.layout.vt, gui, self);
        self.area.deinit(gui, self);
        if (self.click_listeners.items.len != 0)
            std.debug.print("BROKEN\n", .{});
        if (self.scroll_list.items.len != 0)
            std.debug.print("BROKEN\n", .{});
        self.click_listeners.deinit();
        self.scroll_list.deinit();
    }

    /// Returns true if this window contains the mouse
    pub fn dispatchClick(win: *iWindow, cb: MouseCbState) bool {
        if (win.area.area.containsPoint(cb.pos)) {
            for (win.click_listeners.items) |vt| {
                if (vt.area.containsPoint(cb.pos)) {
                    if (vt.onclick) |oc|
                        oc(vt, cb, win);
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

pub const DrawState = struct {
    ctx: *Dctx,
    gui: *Gui,
    font: *graph.FontInterface,
    style: *GuiConfig,
    scale: f32 = 2,
};

pub const MouseCbState = struct {
    pos: Vec2f,
    delta: Vec2f,
    gui: *Gui,
    state: graph.SDL.ButtonState,
};

//Two options for this, we use a button widget which registers itself for onclick
//or we listen for onclick and determine which was clicked

//What happens when area changes?
//rebuild everyone
//start with a window
//call to register window, that window has a "build" vfunc?

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

const Vec2f = graph.Vec2f;

pub const Gui = struct {
    const Self = @This();
    pub const MouseGrabFn = *const fn (*iArea, MouseCbState, *iWindow) void;
    pub const TextinputFn = *const fn (*iArea, TextCbState, *iWindow) void;
    const MouseGrabState = enum { high, falling };

    alloc: std.mem.Allocator,
    windows: std.ArrayList(*iWindow),

    transient_should_close: bool = false,
    transient_window: ?*iWindow = null,

    mouse_grab: ?struct {
        cb: MouseGrabFn,
        vt: *iArea,
        win: *iWindow,
    } = null,

    focused: ?struct {
        vt: *iArea,
        win: *iWindow,
    } = null,

    cached_drawing: bool = false,
    cache_map: std.AutoHashMap(*iArea, void),
    to_draw: std.ArrayList(*iArea),

    text_listeners: std.ArrayList(*iArea),

    style: GuiConfig,

    pub fn init(alloc: AL) !Self {
        return Gui{
            .alloc = alloc,
            .windows = std.ArrayList(*iWindow).init(alloc),
            .cache_map = std.AutoHashMap(*iArea, void).init(alloc),
            .to_draw = std.ArrayList(*iArea).init(alloc),
            .text_listeners = std.ArrayList(*iArea).init(alloc),
            .style = try GuiConfig.init(alloc, std.fs.cwd(), "asset/os9gui", std.fs.cwd()),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.windows.items) |win|
            win.deinit_fn(win, self);

        self.windows.deinit();
        self.text_listeners.deinit();
        self.closeTransientWindow();
        self.to_draw.deinit();
        self.cache_map.deinit();
        self.style.deinit();
    }

    pub fn needsDraw(self: *Self, vt: *iArea) bool {
        if (!self.cached_drawing)
            return true;
        if (!self.cache_map.contains(vt)) {
            self.cache_map.put(vt, {}) catch return true;
            return true;
        }
        return false;
    }

    pub fn registerOnClick(_: *Self, vt: *iArea, window: *iWindow) !void {
        try window.click_listeners.append(vt);
    }

    pub fn registerTextinput(self: *Self, vt: *iArea, window: *iWindow) !void {
        _ = window;

        try self.text_listeners.append(vt);
    }

    pub fn setDirty(self: *Self, vt: *iArea) void {
        if (self.cached_drawing) {
            self.to_draw.append(vt) catch return;
        }
    }

    pub fn update(self: *Self) !void {
        self.to_draw.clearRetainingCapacity();
        self.cache_map.clearRetainingCapacity();
        if (self.transient_should_close) {
            self.transient_should_close = false;
            self.closeTransientWindow();
        }
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
        for (self.to_draw.items, 0..) |item, index| {
            if (item == vt) {
                _ = self.to_draw.swapRemove(index);
                break;
            }
        }
        for (self.text_listeners.items, 0..) |item, index| {
            if (item == vt) {
                _ = self.text_listeners.swapRemove(index);
                break;
            }
        }
        if (self.mouse_grab) |g| {
            if (g.vt == vt) {
                self.mouse_grab = null;
            }
        }
        if (self.focused) |f| {
            if (f.vt == vt)
                self.focused = null;
        }
    }

    pub fn grabFocus(self: *Self, vt: *iArea, win: *iWindow) void {
        self.focused = .{
            .vt = vt,
            .win = win,
        };
    }

    pub fn isFocused(self: *Self, vt: *iArea) bool {
        if (self.focused) |f| {
            return f.vt == vt;
        }
        return false;
    }

    pub fn closeTransientWindow(self: *Self) void {
        if (self.transient_window) |tw| {
            tw.deinit_fn(tw, self);
        }
        self.transient_window = null;
    }

    pub fn dispatchTextinput(self: *Self, cb: TextCbState) void {
        if (self.focused) |f| {
            if (f.vt.textinput) |func| {
                func(f.vt, cb, f.win);
            }
        }
    }

    pub fn dispatchClick(self: *Self, mstate: MouseCbState) void {
        if (self.transient_window) |tw| {
            if (tw.dispatchClick(mstate)) {
                return; //Don't click top level windows
            } else {
                //Close the window, we clicked outside
                self.closeTransientWindow();
            }
        }
        for (self.windows.items) |win| {
            if (win.dispatchClick(mstate))
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
    pub fn grabMouse(self: *Self, cb: MouseGrabFn, vt: *iArea, win: *iWindow) void {
        self.mouse_grab = .{
            .cb = cb,
            .vt = vt,
            .win = win,
        };
    }

    pub fn addWindow(self: *Self, window: *iWindow, area: Rect) !void {
        window.build_fn(window, self, area, &self.style); //Rebuild it
        try self.windows.append(window);
    }

    pub fn draw(self: *Self, dctx: DrawState) void {
        if (self.cached_drawing) {
            for (self.to_draw.items) |draw_area| {
                draw_area.draw(dctx);
            }
        } else {
            for (self.windows.items) |window|
                window.draw(dctx);
            if (self.transient_window) |tw|
                tw.draw(dctx);
        }
    }
};
