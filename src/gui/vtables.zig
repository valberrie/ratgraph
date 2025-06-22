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
    pub usingnamespace @import("widget_combo.zig");
};

pub fn getVt(comptime T: type, vt: anytype) *T {
    return @alignCast(@fieldParentPtr("vt", vt));
}
pub const TextCbState = struct {
    gui: *Gui,
    text: []const u8,

    //TODO, move this to some other event
    keys: []const graph.SDL.KeyState = &.{}, // Populated with keys just pressed, keydown events
    mod_state: graph.SDL.keycodes.KeymodMask = 0,
};

pub const iArea = struct {
    draw_fn: ?*const fn (*iArea, DrawState) void = null,
    deinit_fn: ?*const fn (*iArea, *Gui, *iWindow) void = null,
    onclick: ?*const fn (*iArea, MouseCbState, *iWindow) void = null,
    onscroll: ?*const fn (*iArea, *Gui, *iWindow, distance: f32) void = null,
    focusEvent: ?*const fn (*iArea, FocusedEvent) void = null,

    can_tab_focus: bool = false,

    parent: ?*iArea = null,
    index: usize = 0,
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

    pub fn draw(self: *@This(), dctx: DrawState, window: *iWindow) void {
        if (dctx.gui.needsDraw(self, window)) {
            if (self.draw_fn) |drawf|
                drawf(self, dctx);
            for (self.children.items) |child|
                child.draw(dctx, window);
        }
        self.is_dirty = false;
    }

    pub fn dirty(self: *@This(), gui: *Gui) void {
        if (!self.is_dirty) {
            if (gui.getWindow(self)) |win|
                gui.setDirty(self, win);
        }
        self.is_dirty = true;
    }

    pub fn addChild(self: *@This(), gui: *Gui, win: *iWindow, vt: *iArea) void {
        gui.register(vt, win);
        if (vt.onclick != null)
            gui.registerOnClick(vt, win) catch return;
        if (vt.onscroll != null)
            gui.regOnScroll(vt, win) catch return;
        vt.parent = self;
        vt.index = self.children.items.len;
        self.children.append(vt) catch return;
        gui.setDirty(vt, win);
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

    pub fn genericSetDirtyOnFocusChange(self: *iArea, gui: *Gui, is_focused: bool) void {
        _ = is_focused;
        self.dirty(gui);
    }
};

pub const iWindow = struct {
    const BuildfnT = *const fn (*iWindow, *Gui, Rect) void;

    build_fn: BuildfnT,
    deinit_fn: *const fn (*iWindow, *Gui) void,

    area: *iArea,

    click_listeners: std.ArrayList(*iArea),
    scroll_list: std.ArrayList(*iArea),

    cache_map: std.AutoHashMap(*iArea, void),
    to_draw: std.ArrayList(*iArea),

    pub fn draw(self: *iWindow, dctx: DrawState) void {
        self.area.draw(dctx, self);
        //self.area.draw_fn(self.area, dctx);
    }

    pub fn init(build_fn: BuildfnT, gui: *Gui, deinit_fn: *const fn (*iWindow, *Gui) void, area: *iArea) iWindow {
        return .{
            .deinit_fn = deinit_fn,
            .build_fn = build_fn,
            .click_listeners = std.ArrayList(*iArea).init(gui.alloc),
            .scroll_list = std.ArrayList(*iArea).init(gui.alloc),
            .cache_map = std.AutoHashMap(*iArea, void).init(gui.alloc),
            .to_draw = std.ArrayList(*iArea).init(gui.alloc),
            .area = area,
        };
    }

    // the implementers deinit fn should call this first
    pub fn deinit(self: *iWindow, gui: *Gui) void {
        //self.layout.vt.deinit_fn(&self.layout.vt, gui, self);
        gui.deregister(self.area, self);
        self.area.deinit(gui, self);
        if (self.click_listeners.items.len != 0)
            std.debug.print("BROKEN\n", .{});
        if (self.scroll_list.items.len != 0)
            std.debug.print("BROKEN\n", .{});
        self.click_listeners.deinit();
        self.scroll_list.deinit();
        self.to_draw.deinit();
        self.cache_map.deinit();
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
    tint: u32 = 0xffff_ffff, //Tint for textures
};

pub const MouseCbState = struct {
    pos: Vec2f,
    delta: Vec2f,
    gui: *Gui,
    state: graph.SDL.ButtonState,
};

pub const KeydownState = struct {
    keys: []const graph.SDL.KeyState,
    mod_state: graph.SDL.keycodes.KeymodMask = 0,
};

pub const FocusedEvent = struct {
    pub const Event = union(enum) {
        focusChanged: bool,
        text_input: TextCbState,
        keydown: KeydownState,
    };
    gui: *Gui,
    window: *iWindow,

    event: Event,
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

    fbos: std.AutoHashMap(*iWindow, graph.RenderTexture),
    transient_fbo: graph.RenderTexture,

    area_window_map: std.AutoHashMap(*iArea, *iWindow),

    draws_since_cached: i32 = 0,
    max_cached_before_full_flush: i32 = 60 * 10, //Ten seconds
    cached_drawing: bool = true,

    text_input_enabled: bool = false,
    sdl_win: *graph.SDL.Window,

    style: GuiConfig,
    scale: f32 = 2,

    pub fn init(alloc: AL, win: *graph.SDL.Window) !Self {
        return Gui{
            .alloc = alloc,
            .area_window_map = std.AutoHashMap(*iArea, *iWindow).init(alloc),
            .windows = std.ArrayList(*iWindow).init(alloc),
            .transient_fbo = try graph.RenderTexture.init(100, 100),
            .fbos = std.AutoHashMap(*iWindow, graph.RenderTexture).init(alloc),
            .sdl_win = win,
            .style = try GuiConfig.init(alloc, std.fs.cwd(), "asset/os9gui", std.fs.cwd()),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.windows.items) |win|
            win.deinit_fn(win, self);

        {
            var it = self.fbos.valueIterator();
            while (it.next()) |item|
                item.deinit();
        }
        self.transient_fbo.deinit();
        self.fbos.deinit();
        self.windows.deinit();
        self.closeTransientWindow();
        self.area_window_map.deinit();
        self.style.deinit();
    }

    pub fn needsDraw(self: *Self, vt: *iArea, window: *iWindow) bool {
        if (!self.cached_drawing)
            return true;
        if (!window.cache_map.contains(vt)) {
            window.cache_map.put(vt, {}) catch return true;
            return true;
        }
        return false;
    }

    //Traversal of the tree for tab.
    //Starting at the currently focused,
    //get parent, iterate children until we find ourself.
    //iterate through rest of children,if child has child, recur. if can_tab_focus, return that node
    //get parents parent, do the same, finding ourself.
    //sounds complicated?

    pub fn tabFocus(self: *Self, fwd: bool) void {
        if (self.focused) |f| {
            if (fwd) {
                if (findNextFocusTarget(f.vt)) |next| {
                    self.grabFocus(next, f.win);
                } else if (findFocusTargetNoBacktrack(f.win.area)) |next| { //Start from the root of the window
                    self.grabFocus(next, f.win);
                }
            } else {
                if (findPrevFocusTarget(f.vt)) |prev| {
                    self.grabFocus(prev, f.win);
                }
            }
        }
    }

    fn findNextFocusTarget(vt: *iArea) ?*iArea {
        const parent = vt.parent orelse return null;
        if (vt.index >= parent.children.items.len) return null;
        for (parent.children.items[vt.index + 1 ..]) |next| {
            return findFocusTargetNoBacktrack(next) orelse continue;
        }
        // None found in children,
        return findNextFocusTarget(parent);
    }

    fn findFocusTargetNoBacktrack(vt: *iArea) ?*iArea {
        if (vt.can_tab_focus)
            return vt;
        for (vt.children.items) |child| {
            return findFocusTargetNoBacktrack(child) orelse continue;
        }
        return null;
    }

    fn findPrevFocusTarget(vt: *iArea) ?*iArea {
        const parent = vt.parent orelse return null;
        if (vt.index >= parent.children.items.len) return null;

        var index = vt.index;
        while (index > 0) : (index -= 1) {
            const nvt = parent.children.items[index - 1];
            return findPrevFocusNoBacktrack(nvt) orelse continue;
        }
        return null;
    }

    fn findPrevFocusNoBacktrack(vt: *iArea) ?*iArea {
        var index = vt.children.items.len;
        while (index > 0) : (index -= 1) {
            return findPrevFocusNoBacktrack(vt.children.items[index - 1]) orelse continue;
        }
        if (vt.can_tab_focus)
            return vt;
        return null;
    }

    pub fn registerOnClick(_: *Self, vt: *iArea, window: *iWindow) !void {
        try window.click_listeners.append(vt);
    }

    pub fn setDirty(self: *Self, vt: *iArea, win: *iWindow) void {
        if (self.cached_drawing) {
            win.to_draw.append(vt) catch return;
        }
    }

    pub fn update(self: *Self) !void {
        for (self.windows.items) |win| {
            win.to_draw.clearRetainingCapacity();
            win.cache_map.clearRetainingCapacity();
        }
        if (self.transient_window) |tw| {
            tw.to_draw.clearRetainingCapacity();
            tw.cache_map.clearRetainingCapacity();
        }
        if (self.transient_should_close) {
            self.transient_should_close = false;
            self.closeTransientWindow();
        }
        try self.handleSdlEvents();
    }

    /// If transient windows destroy themselves, the program will crash as used memory is freed.
    /// Defer the close till next update
    pub fn deferTransientClose(self: *Self) void {
        self.transient_should_close = true;
    }

    pub fn regOnScroll(_: *Self, vt: *iArea, window: *iWindow) !void {
        try window.scroll_list.append(vt);
    }

    pub fn register(self: *Self, vt: *iArea, window: *iWindow) void {
        self.area_window_map.put(vt, window) catch return;
    }

    pub fn getWindow(self: *Self, vt: *iArea) ?*iWindow {
        return self.area_window_map.get(vt);
    }

    pub fn deregister(self: *Self, vt: *iArea, window: *iWindow) void {
        _ = self.area_window_map.remove(vt);
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
        for (window.to_draw.items, 0..) |item, index| {
            if (item == vt) {
                _ = window.to_draw.swapRemove(index);
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
        if (self.focused) |f| {
            if (f.vt != vt and f.vt.focusEvent != null)
                f.vt.focusEvent.?(f.vt, .{ .gui = self, .window = win, .event = .{ .focusChanged = false } });
        }
        self.focused = .{
            .vt = vt,
            .win = win,
        };
        if (vt.focusEvent) |fc|
            fc(vt, .{ .gui = self, .window = win, .event = .{ .focusChanged = true } });
    }

    pub fn isFocused(self: *Self, vt: *iArea) bool {
        if (self.focused) |f| {
            return f.vt == vt;
        }
        return false;
    }

    pub fn setTransientWindow(self: *Self, win: *iWindow) void {
        self.closeTransientWindow();
        self.transient_window = win;
        self.register(win.area, win);
        _ = self.transient_fbo.setSize(win.area.area.w, win.area.area.h) catch return;
    }

    pub fn closeTransientWindow(self: *Self) void {
        if (self.transient_window) |tw| {
            tw.deinit_fn(tw, self);
        }
        self.transient_window = null;
    }

    pub fn dispatchTextinput(self: *Self, cb: TextCbState) void {
        if (self.focused) |f| {
            if (f.vt.focusEvent) |func| {
                func(f.vt, .{ .gui = self, .window = f.win, .event = .{
                    .text_input = cb,
                } });
            }
        }
    }

    pub fn dispatchKeydown(self: *Self, state: KeydownState) void {
        self.dispatchFocusedEvent(.{ .keydown = state });
    }

    pub fn dispatchFocusedEvent(self: *Self, event: FocusedEvent.Event) void {
        if (self.focused) |f| {
            if (f.vt.focusEvent) |func|
                func(f.vt, .{ .gui = self, .window = f.win, .event = event });
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

    pub fn startTextinput(self: *Self, rect: Rect) void {
        self.text_input_enabled = true;
        self.sdl_win.startTextInput(rect);
    }

    pub fn stopTextInput(self: *Self) void {
        self.text_input_enabled = false;
        self.sdl_win.stopTextInput();
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
        window.build_fn(window, self, area); //Rebuild it
        try self.fbos.put(window, try graph.RenderTexture.init(area.w, area.h));
        self.register(window.area, window);
        try self.windows.append(window);
    }

    pub fn drawFbos(self: *Self, ctx: *Dctx) void {
        for (self.windows.items) |w| {
            const fbo = self.fbos.getPtr(w) orelse continue;
            drawFbo(w.area.area, fbo, ctx);
        }

        if (self.transient_window) |tw| {
            drawFbo(tw.area.area, &self.transient_fbo, ctx);
        }
    }

    pub fn draw(self: *Self, dctx: DrawState, force_redraw: bool) !void {
        defer {
            graph.c.glBindFramebuffer(graph.c.GL_FRAMEBUFFER, 0);
            graph.c.glViewport(0, 0, @intFromFloat(dctx.ctx.screen_dimensions.x), @intFromFloat(dctx.ctx.screen_dimensions.y));
        }
        if (self.cached_drawing and !force_redraw) {
            defer self.draws_since_cached += 1;
            if (self.draws_since_cached < 1 or self.draws_since_cached > self.max_cached_before_full_flush)
                return self.draw_all(dctx);
            //Otherwise we do the cached
            for (self.windows.items) |win| {
                const fbo = self.fbos.getPtr(win) orelse continue;
                fbo.bind(false);
                for (win.to_draw.items) |draw_area| {
                    draw_area.draw(dctx, win);
                }
                try dctx.ctx.flush(win.area.area, null);
            }
            if (self.transient_window) |tw| {
                self.transient_fbo.bind(false);
                for (tw.to_draw.items) |td| {
                    td.draw(dctx, tw);
                }
                try dctx.ctx.flush(tw.area.area, null);
            }
        } else {
            try self.draw_all(dctx);
        }
    }

    pub fn draw_all(self: *Self, dctx: DrawState) !void {
        self.draws_since_cached = 1;
        for (self.windows.items) |window| {
            const fbo = self.fbos.getPtr(window) orelse continue;
            fbo.bind(true);
            window.draw(dctx);
            try dctx.ctx.flush(window.area.area, null);
        }
        if (self.transient_window) |tw| {
            self.transient_fbo.bind(true);
            tw.draw(dctx);
            try dctx.ctx.flush(tw.area.area, null);
        }
    }

    pub fn drawFbo(area: Rect, fbo: *graph.RenderTexture, dctx: *Dctx) void {
        dctx.rectTex(
            area,
            graph.Rec(0, 0, area.w, -area.h),
            fbo.texture,
        );
    }

    pub fn handleSdlEvents(self: *Self) !void {
        const win = self.sdl_win;
        const mstate = MouseCbState{
            .gui = self,
            .pos = win.mouse.pos,
            .delta = win.mouse.delta,
            .state = win.mouse.left,
        };
        if (win.keyRising(.TAB))
            self.tabFocus(!win.keyHigh(.LSHIFT));
        switch (win.mouse.left) {
            .rising => self.dispatchClick(mstate),
            .low => {
                self.mouse_grab = null;
            },
            .falling => {
                if (self.mouse_grab) |g|
                    g.cb(
                        g.vt,
                        mstate,
                        g.win,
                    );
            },
            .high => {
                if (self.mouse_grab) |g| {
                    g.cb(g.vt, mstate, g.win);
                }
            },
        }
        {
            const keys = win.keys.slice();
            if (keys.len > 0) {
                self.dispatchKeydown(.{ .keys = keys, .mod_state = win.mod });
            }
        }
        if (self.text_input_enabled and win.text_input.len > 0) {
            self.dispatchTextinput(.{
                .gui = self,
                .text = win.text_input,
                .mod_state = win.mod,
                .keys = win.keys.slice(),
            });
        }
        if (win.mouse.wheel_delta.y != 0)
            self.dispatchScroll(win.mouse.pos, win.mouse.wheel_delta.y);
    }
};
