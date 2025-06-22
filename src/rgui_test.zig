const std = @import("std");
const graph = @import("graphics.zig");
const Dctx = graph.ImmediateDrawingContext;
const Os9Gui = @import("gui_app.zig");
const GuiConfig = Os9Gui.GuiConfig;
const GuiHelp = guis.GuiHelp;

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
    i32_n: i32 = 3,
    number: f32 = 488.8,
    my_enum: MyEnum = .hello,
    fenum: std.fs.File.Kind = .file,
    color: u32 = 0xff_ff,
    //This subscribes to onScroll
    //has two child layouts,
    //the act of splitting is not the Layouts job

    pub fn create(gui: *Gui) *iWindow {
        const self = gui.create(@This());
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
        GuiHelp.drawWindowFrame(d, vt.area);
    }

    pub fn build(vt: *iWindow, gui: *Gui, area: Rect) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.area.area = area;
        self.area.clearChildren(gui, vt);
        //self.layout.reset(gui, vt);
        //start a vlayout
        //var ly = Vert{ .area = vt.area };
        var ly = guis.VerticalLayout{
            .padding = .{},
            .item_height = gui.style.config.default_item_h,
            .bounds = GuiHelp.insetAreaForWindowFrame(gui, vt.area.area),
        };
        ly.padding.left = 10;
        ly.padding.right = 10;
        ly.padding.top = 10;
        const a = &self.area;

        a.addChildOpt(gui, vt, Wg.Checkbox.build(gui, ly.getArea(), &self.bool1, "first button"));
        a.addChildOpt(gui, vt, Wg.Checkbox.build(gui, ly.getArea(), &self.bool2, "secnd button"));
        a.addChildOpt(gui, vt, Wg.StaticSlider.build(gui, ly.getArea(), 4, 0, 10));
        a.addChild(gui, vt, Wg.Combo(MyEnum).build(gui, ly.getArea() orelse return, &self.my_enum));
        a.addChild(gui, vt, Wg.Combo(std.fs.File.Kind).build(gui, ly.getArea() orelse return, &self.fenum));

        a.addChildOpt(gui, vt, Wg.Button.build(gui, ly.getArea(), "My button", &self.area, @This().btnCb, 48));
        a.addChildOpt(gui, vt, Wg.Button.build(gui, ly.getArea(), "My button 2", null, null, 48));
        a.addChildOpt(gui, vt, Wg.Button.build(gui, ly.getArea(), "My button 3", null, null, 48));
        a.addChild(gui, vt, Wg.Colorpicker.build(gui, ly.getArea() orelse return, &self.color));

        a.addChildOpt(gui, vt, Wg.Textbox.build(gui, ly.getArea()));
        a.addChildOpt(gui, vt, Wg.Textbox.build(gui, ly.getArea()));
        a.addChildOpt(gui, vt, Wg.TextboxNumber.build(gui, ly.getArea(), &self.number, vt));
        a.addChildOpt(gui, vt, Wg.Slider(f32).build(gui, ly.getArea(), &self.number, -10, 10));
        a.addChildOpt(gui, vt, Wg.Slider(i32).build(gui, ly.getArea(), &self.i32_n, -10, 10));

        ly.pushRemaining();
        a.addChildOpt(gui, vt, Wg.VScroll.build(
            gui,
            ly.getArea(),
            &buildScrollItems,
            &self.area,
            vt,
            10,
            gui.style.config.default_item_h,
        ));
    }

    pub fn buildScrollItems(window_area: *iArea, vt: *iArea, index: usize, gui: *Gui, window: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("area", window_area));
        var ly = guis.VerticalLayout{ .item_height = gui.style.config.default_item_h, .bounds = vt.area };
        for (index..10) |i| {
            vt.addChildOpt(gui, window, Wg.Text.build(gui, ly.getArea(), "item {d}", .{i}));
        }
        _ = self;
    }

    pub fn btnCb(_: *iArea, id: usize, _: *Gui, _: *iWindow) void {
        std.debug.print("BUTTON CLICKED {d}\n", .{id});
    }
};

pub fn main() !void {
    std.debug.print("The size is :  {d}\n", .{@sizeOf(guis.iArea)});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    var win = try graph.SDL.Window.createWindow("My window", .{
        // Optional, see Window.createWindow definition for full list of options
        .window_size = .{ .x = 1000, .y = 1000 },
    });
    defer win.destroyWindow();

    var draw = graph.ImmediateDrawingContext.init(alloc);
    defer draw.deinit();

    var gui = try Gui.init(alloc, &win);
    defer gui.deinit();
    const do_test_builder = true;
    if (do_test_builder)
        try gui.openTestBuilder(std.fs.cwd(), "testdum.txt");

    defer {
        if (do_test_builder)
            gui.closeTestBuilder();
    }
    var demo = if (!do_test_builder) try guis.Demo.init(alloc, std.fs.cwd(), "testdum.txt") else {};
    defer {
        if (!do_test_builder)
            demo.deinit();
    }
    gui.style.config.default_item_h = @trunc(25 * 1.6);
    gui.style.config.text_h = @trunc(20 * 1.6);
    var font = try graph.Font.initFromBuffer(alloc, @embedFile("font/roboto.ttf"), gui.style.config.text_h, .{});
    defer font.deinit();

    const window_area = .{ .x = 0, .y = 0, .w = 1000, .h = 1000 };

    const dstate = guis.DrawState{ .ctx = &draw, .font = &font.font, .style = &gui.style, .gui = &gui };
    try gui.addWindow(MyInspector.create(&gui), window_area);

    while (!win.should_exit) {
        try draw.begin(0xff, win.screen_dimensions.toF());
        win.pumpEvents(if (do_test_builder) .wait else .poll);
        if (win.keyRising(.ESCAPE))
            win.should_exit = true;

        try gui.update();
        if (do_test_builder) {
            try gui.handleSdlEvents();
        } else {
            if (demo.next()) |up|
                try gui.handleEvent(up);
        }
        try gui.draw(dstate, false);

        gui.drawFbos(&draw);

        try draw.flush(null, null); //Flush any draw commands

        try draw.end(null);
        win.swap();
    }
}
