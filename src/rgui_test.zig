const std = @import("std");
const graph = @import("graphics.zig");
const Dctx = graph.ImmediateDrawingContext;
const Os9Gui = @import("gui_app.zig");
const GuiConfig = Os9Gui.GuiConfig;

const Rect = graph.Rect;
const Rec = graph.Rec;
const AL = std.mem.Allocator;

const guis = @import("gui/vtables.zig");
const iWindow = guis.iWindow;
const iArea = guis.iArea;
const DrawState = guis.DrawState;

const Gui = guis.Gui;
const Wg = guis.Widget;

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
            .area = iArea.init(gui, Rec(0, 0, 0, 0)),
            .vt = iWindow.init(&@This().build, gui, &@This().deinit, &self.area),
        };
        self.area.draw_fn = &draw;
        self.area.deinit_fn = &area_deinit;

        return &self.vt;
    }

    pub fn deinit(vt: *iWindow, gui: *Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        //self.layout.deinit(gui, vt);
        vt.deinit(gui);
        gui.alloc.destroy(self); //second
    }

    pub fn area_deinit(_: *iArea, _: *Gui, _: *iWindow) void {}

    pub fn draw(vt: *iArea, d: DrawState) void {
        _ = vt;
        _ = d;
        //const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
        //self.layout.draw(d);
    }

    pub fn build(vt: *iWindow, gui: *Gui, area: Rect, style: *GuiConfig) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.area.area = area;
        self.area.clearChildren(gui, vt);
        //self.layout.reset(gui, vt);
        //start a vlayout
        //var ly = Vert{ .area = vt.area };
        var ly = guis.VerticalLayout{
            .item_height = style.config.default_item_h,
            .bounds = area,
        };

        self.area.addChild(gui, vt, Wg.Checkbox.build(gui, ly.getArea().?, &self.bool1, "first button") catch return);
        self.area.addChild(gui, vt, Wg.Checkbox.build(gui, ly.getArea().?, &self.bool2, "secnd button") catch return);
        self.area.addChild(gui, vt, Wg.Slider.build(gui, ly.getArea().?, 4, 0, 10) catch return);
        self.area.addChild(gui, vt, Wg.Combo(MyEnum).build(gui, ly.getArea().?, &self.my_enum) catch return);

        self.area.addChild(gui, vt, Wg.Button.build(gui, ly.getArea().?, "My button", &self.area, @This().btnCb, 48) catch return);
        self.area.addChild(gui, vt, Wg.Button.build(gui, ly.getArea().?, "My button 2", null, null, 48) catch return);
        self.area.addChild(gui, vt, Wg.Button.build(gui, ly.getArea().?, "My button 3", null, null, 48) catch return);

        self.area.addChild(gui, vt, Wg.Textbox.build(gui, ly.getArea().?) catch return);
        self.area.addChild(gui, vt, Wg.Textbox.build(gui, ly.getArea().?) catch return);

        ly.pushRemaining();
        self.area.addChild(gui, vt, Wg.VScroll.build(
            gui,
            ly.getArea().?,
            &buildScrollItems,
            &self.area,
            vt,
            10,
            style.config.default_item_h,
        ) catch return);
    }

    pub fn buildScrollItems(window_area: *iArea, vt: *iArea, index: usize, gui: *Gui, window: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("area", window_area));
        var ly = guis.VerticalLayout{ .item_height = gui.style.config.default_item_h, .bounds = vt.area };
        for (index..10) |i| {
            vt.addChild(gui, window, Wg.Text.build(gui, ly.getArea() orelse return, "item {d}", .{i}) catch return);
        }
        _ = self;
    }

    pub fn btnCb(_: *iArea, id: usize, _: *Gui) void {
        std.debug.print("BUTTON CLICKED {d}\n", .{id});
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

    var fbo = try graph.RenderTexture.init(800, 600);
    win.startTextInput(null);

    while (!win.should_exit) {
        try fbo.setSize(win.screen_dimensions.x, win.screen_dimensions.y);
        try draw.begin(0xff, win.screen_dimensions.toF());
        win.pumpEvents(.poll); //Important that this is called after draw.begin for input lag reasons
        if (win.keyRising(.ESCAPE))
            win.should_exit = true;

        try gui.update();
        const mstate = guis.MouseCbState{
            .gui = &gui,
            .pos = win.mouse.pos,
            .delta = win.mouse.delta,
            .state = win.mouse.left,
        };
        switch (win.mouse.left) {
            .rising => gui.dispatchClick(mstate),
            .low => {
                gui.mouse_grab = null;
            },
            .falling => {
                if (gui.mouse_grab) |g|
                    g.cb(
                        g.vt,
                        mstate,
                        g.win,
                    );
            },
            .high => {
                if (gui.mouse_grab) |g| {
                    g.cb(g.vt, mstate, g.win);
                }
            },
        }
        gui.dispatchTextinput(.{ .gui = &gui, .text = win.text_input });
        if (win.mouse.wheel_delta.y != 0)
            gui.dispatchScroll(win.mouse.pos, win.mouse.wheel_delta.y);

        fbo.bind(!gui.cached_drawing);
        gui.draw(.{ .ctx = &draw, .font = &font.font, .style = &gui.style, .gui = &gui });
        try draw.flush(null, null);

        graph.c.glBindFramebuffer(graph.c.GL_FRAMEBUFFER, 0);
        graph.c.glViewport(0, 0, @intFromFloat(draw.screen_dimensions.x), @intFromFloat(draw.screen_dimensions.y));
        const tr = fbo.texture.rect();
        draw.rectTex(
            graph.Rec(0, 0, win.screen_dimensions.x, win.screen_dimensions.y),
            graph.Rec(0, 0, tr.w, -tr.h),
            fbo.texture,
        );

        try draw.flush(null, null); //Flush any draw commands

        try draw.end(null);
        win.swap();
    }
}
