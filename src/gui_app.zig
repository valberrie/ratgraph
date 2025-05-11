const std = @import("std");
const graph = @import("graphics.zig");
const Rect = graph.Rect;
const Rec = graph.Rec;
const Pad = graph.Padding;
const OFont = @import("graphics/online_font.zig").OnlineFont;
pub const FileBrowser = @import("guiapp/filebrowser.zig").FileBrowser;

const lua = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});

const ArgUtil = @import("arg_gen.zig");
const Color = graph.Colori;
//const Gui = @import("gui.zig");
const Gui = graph.Gui;
const Vec2f = graph.Vec2f;

const bg1 = (0xff);
const fg = (0xffffffff);
const bg4 = (0xff);
const bg2 = (0xff);
const bg0 = (0xff);

inline fn F(a: anytype) f32 {
    return std.math.lossyCast(f32, a);
}

//A i3_layout is a parent area that is then recursivly split vertically or horizontally.
//Each section can be given a name, not required though

pub const SplitPlan = struct {
    pub const SplitK = enum { v, h };
    pub const split_pos_kind = union(enum) {
        percent: f32,
        left_size: f32,
        right_size: f32,

        pub fn getDim(self: @This(), dim: f32) f32 {
            return switch (self) {
                .percent => |p| dim * p,
                .left_size => |l| if (l < dim) l else dim,
                .right_size => |r| if (r < dim) dim - r else dim,
            };
        }
    };
    pub const split_pos = struct {
        param_name: ?[]const u8 = null,
        pos: split_pos_kind,
    };

    pub const Node = union(enum) {
        split: struct {
            k: SplitK,
            pos: split_pos,
            l: ?*const Node = null,
            r: ?*const Node = null,
        },
        area: struct {
            name: [:0]const u8,
        },

        //pub fn draw(self: Node, ctx: *Gui.Context, area: Rect) void {
        //    switch (self) {
        //        .split => |s| {
        //            const o: graph.Orientation = if (s.k == .v) .vertical else .horizontal;
        //            const d = if (s.k == .v) area.w else area.h;
        //            const sp = area.split(o, d * s.perc);
        //            if (s.l) |l|
        //                l.draw(ctx, sp[0]);
        //            if (s.r) |r|
        //                r.draw(ctx, sp[1]);
        //        },
        //        .area => |a| {
        //            const ar = area.inset(4);
        //            ctx.drawRectFilled(ar, Color.Blue);
        //            ctx.drawTextFmt("{s}", .{a.name}, ar, 50, Color.Black, .{});
        //        },
        //    }
        //}
    };

    pub fn A(name: [:0]const u8) Node {
        return .{ .area = .{ .name = name } };
    }

    pub fn S(k: SplitK, perc: f32, l: ?*const Node, r: ?*const Node) Node {
        return .{ .split = .{ .k = k, .pos = .{ .pos = .{ .percent = perc } }, .l = l, .r = r } };
    }

    pub fn LS(k: SplitK, left_w: f32, l: ?*const Node, r: ?*const Node) Node {
        return .{ .split = .{ .k = k, .pos = .{ .pos = .{ .left_size = left_w } }, .l = l, .r = r } };
    }

    pub fn LSP(k: SplitK, param: []const u8, l: ?*const Node, r: ?*const Node) Node {
        return .{ .split = .{ .k = k, .pos = .{ .pos = .{ .percent = 0.5 }, .param_name = param }, .l = l, .r = r } };
    }

    fn countNames(comptime node: Node, comptime num_names: *usize) void {
        switch (node) {
            .split => |s| {
                if (s.l) |l|
                    countNames(l.*, num_names);
                if (s.r) |r|
                    countNames(r.*, num_names);
            },
            .area => num_names.* += 1,
        }
    }

    fn insertNames(comptime node: Node, comptime index: *usize, comptime fields: []std.builtin.Type.StructField) void {
        switch (node) {
            .split => |s| {
                if (s.l) |l|
                    insertNames(l.*, index, fields);
                if (s.r) |r|
                    insertNames(r.*, index, fields);
            },
            .area => |a| {
                fields[index.*] = .{ .name = a.name, .type = Rect, .default_value = null, .is_comptime = false, .alignment = @alignOf(Rect) };
                index.* += 1;
            },
        }
    }

    pub fn createSplitPlan(comptime plan: Node) type {
        var num_names: usize = 0;
        countNames(plan, &num_names);
        var fields: [num_names]std.builtin.Type.StructField = undefined;
        var index: usize = 0;
        insertNames(plan, &index, &fields);

        return @Type(.{ .Struct = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
    }

    fn calcRecur(comptime node: Node, ret: anytype, area: Rect) void {
        switch (node) {
            .split => |s| {
                const o: graph.Orientation = if (s.k == .v) .vertical else .horizontal;
                const d = if (s.k == .v) area.w else area.h;
                const sp = area.split(o, s.pos.pos.getDim(d));
                if (s.l) |l|
                    calcRecur(l.*, ret, sp[0]);
                if (s.r) |r|
                    calcRecur(r.*, ret, sp[1]);
            },
            .area => |a| {
                @field(ret.*, a.name) = area.inset(4);
            },
        }
    }

    pub fn calculatePlan(comptime plan: Node, area: Rect, params: anytype) createSplitPlan(plan) {
        _ = params;
        var ret: createSplitPlan(plan) = undefined;
        calcRecur(plan, &ret, area);
        return ret;
    }

    area: Rect,
    root: Node,
};

pub const MyStruct = struct {
    my_color: graph.Hsva = .{ .h = 20, .s = 1, .v = 1, .a = 1 },
    my_number: f32 = 11.2,
    my_enum: Gui.ClickState = .click,
    do_stuff: bool = true,
    fuck: std.builtin.CallingConvention = .C,
    str: []const u8 = "hello world",
    a: u8 = 0,
    b: u8 = 10,
    c: i32 = -10,
    v2: graph.Vec2f = .{ .x = 0, .y = 10 },
};

fn nspace(n: u32) []const u8 {
    const buf = "                                   ";
    if (n >= buf.len) unreachable;
    return buf[0..n];
}

pub const Icons = enum(u21) {
    //https://remixicon.com/
    folder = 0xED52,
    file = 0xECEB,
    img_file = 0xF3C5,
    folder_link = 0xED78,
    src_file = 0xECD1,
    txt_file = 0xED0F,
    drop_up = 0xEA56,
    drop_down = 0xEA50,
    drop_right = 0xEA54,

    check = 0xEB7B,
    erasor = 0xEC9F,
    pencil = 0xEFDF,

    pub fn get(icon: Icons) u21 {
        return @intFromEnum(icon);
    }
};

pub const GameMenu = struct {
    view: enum { main, connect, serve } = .main,
    exit_app: bool = false,

    ip_box: std.ArrayList(u8),
    port_box: std.ArrayList(u8),
    username_box: std.ArrayList(u8),

    pub fn update(self: *GameMenu, os9gui: *Os9Gui) !void {
        _ = try os9gui.beginV();
        defer os9gui.endL();
        switch (self.view) {
            .main => {
                if (os9gui.button("Connect to server"))
                    self.view = .connect;
                if (os9gui.button("Host server"))
                    self.view = .serve;
                if (os9gui.button("quit game"))
                    self.exit_app = true;
            },
            .connect => {
                if (os9gui.button("back"))
                    self.view = .main;
                try os9gui.textboxEx(&self.ip_box, .{});
            },
            .serve => {
                if (os9gui.button("back"))
                    self.view = .main;
            },
        }
    }

    pub fn init(alloc: std.mem.Allocator) GameMenu {
        return .{
            .ip_box = std.ArrayList(u8).init(alloc),
            .port_box = std.ArrayList(u8).init(alloc),
            .username_box = std.ArrayList(u8).init(alloc),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.ip_box.deinit();
        self.port_box.deinit();
        self.username_box.deinit();
    }
};

pub const KeyboardDisplay = struct {
    const Self = @This();
    pub const Row = struct {
        pub const Key = struct {
            name: ?[]const u8 = null,
            width: f32 = 1,
            height: f32 = 1,
            ktype: enum { key, spacing } = .key,
        };

        x: f32,
        y: f32,
        keys: []const Key,
    };
    pub const Rows = struct {
        const fkeys = [_]Row.Key{
            .{ .name = "Esc" },
            .{ .ktype = .spacing },
            .{ .name = "F1" },
            .{ .name = "F2" },
            .{ .name = "F3" },
            .{ .name = "F4" },
            .{ .ktype = .spacing, .width = 0.5 },
            .{ .name = "F5" },
            .{ .name = "F6" },
            .{ .name = "F7" },
            .{ .name = "F8" },
            .{ .ktype = .spacing, .width = 0.5 },
            .{ .name = "F9" },
            .{ .name = "F10" },
            .{ .name = "F11" },
            .{ .name = "F12" },
            .{ .ktype = .spacing, .width = 0.25 },
            .{ .name = "PrtSc" },
            .{ .name = "Scroll Lock" },
            .{ .name = "Pause\tBreak" },
        };

        const numkeys = [_]Row.Key{
            .{ .name = "~\t`" },
            .{ .name = "!\t1" },
            .{ .name = "@\t2" },
            .{ .name = "#\t3" },
            .{ .name = "$\t4" },
            .{ .name = "%\t5" },
            .{ .name = "^\t6" },
            .{ .name = "&\t7" },
            .{ .name = "*\t8" },
            .{ .name = "(\t9" },
            .{ .name = ")\t0" },
            .{ .name = "_\t-" },
            .{ .name = "+\t=" },

            .{ .name = "Backspace", .width = 2 },
        };
        const numkeys_ex = [_]Row.Key{
            .{ .ktype = .spacing, .width = 0.25 },
            .{ .name = "Insert" },
            .{ .name = "Home" },
            .{ .name = "PgUp" },
        };

        const tabkeys = [_]Row.Key{
            .{ .name = "Tab", .width = 1.5 },
            .{ .name = "Q" },
            .{ .name = "W" },
            .{ .name = "E" },
            .{ .name = "R" },
            .{ .name = "T" },
            .{ .name = "Y" },
            .{ .name = "U" },
            .{ .name = "I" },
            .{ .name = "O" },
            .{ .name = "P" },
            .{ .name = "{\t[" },
            .{ .name = "}\t]" },
            .{ .name = "|\t\\", .width = 1.5 },
            .{ .ktype = .spacing, .width = 0.25 },
            .{ .name = "Delete" },
            .{ .name = "End" },
            .{ .name = "PgDn" },
        };

        const capskeys = [_]Row.Key{
            .{ .name = "CapsLock", .width = 1.75 },
            .{ .name = "A" },
            .{ .name = "S" },
            .{ .name = "D" },
            .{ .name = "F" },
            .{ .name = "G" },
            .{ .name = "H" },
            .{ .name = "J" },
            .{ .name = "K" },
            .{ .name = "L" },
            .{ .name = ":\t;" },
            .{ .name = "\"\t\'" },
            .{ .name = "Return", .width = 2.25 },
        };

        const shiftkeys = [_]Row.Key{
            .{ .name = "Shift", .width = 2.25 },
            .{ .name = "Z" },
            .{ .name = "X" },
            .{ .name = "C" },
            .{ .name = "V" },
            .{ .name = "B" },
            .{ .name = "N" },
            .{ .name = "M" },
            .{ .name = "<\t," },
            .{ .name = ">\t." },
            .{ .name = "?\t/" },
            .{ .name = "RShift", .width = 2.75 },
            .{ .ktype = .spacing, .width = 1.25 },
            .{ .name = "Up" },
        };

        const ctrlkeys = [_]Row.Key{
            .{ .name = "Control", .width = 1.25 },
            .{ .name = "Meta", .width = 1.25 },
            .{ .name = "Alt", .width = 1.25 },
            .{ .name = "Space", .width = 6.25 },
            .{ .name = "RAlt", .width = 1.25 },
            .{ .name = "RMeta", .width = 1.25 },
            .{ .name = "Menu", .width = 1.25 },
            .{ .name = "RCtrl", .width = 1.25 },
            .{ .ktype = .spacing, .width = 0.25 },
            .{ .name = "Left" },
            .{ .name = "Down" },
            .{ .name = "Right" },
        };

        const numpad1 = [_]Row.Key{
            .{ .name = "NumLock" },
            .{ .name = "NumpadDivide" },
            .{ .name = "NumpadMultiply" },
            .{ .name = "NumpadMinus" },
        };

        const numpad2 = [_]Row.Key{
            .{ .name = "Numpad7" },
            .{ .name = "Numpad8" },
            .{ .name = "Numpad9" },
            .{ .name = "NumpadPlus", .height = -2 },
        };

        const numpad3 = [_]Row.Key{
            .{ .name = "Numpad4" },
            .{ .name = "Numpad5" },
            .{ .name = "Numpad6" },
        };

        const numpad4 = [_]Row.Key{
            .{ .name = "Numpad1" },
            .{ .name = "Numpad2" },
            .{ .name = "Numpad3" },
            .{ .name = "NumpadEnter", .height = -2 },
        };

        const numpad5 = [_]Row.Key{
            .{ .name = "Numpad0", .width = 2 },
            .{ .name = "NumpadPeriod" },
        };
    };

    pub const Ansi104 = [_]Row{
        .{ .x = 0, .y = 0, .keys = &Rows.fkeys },
        .{ .x = 0, .y = 1.5, .keys = &(Rows.numkeys ++ Rows.numkeys_ex) },
        .{ .x = 0, .y = 2.5, .keys = &Rows.tabkeys },
        .{ .x = 0, .y = 3.5, .keys = &Rows.capskeys },
        .{ .x = 0, .y = 4.5, .keys = &Rows.shiftkeys },
        .{ .x = 0, .y = 5.5, .keys = &Rows.ctrlkeys },
        .{ .x = 18.5, .y = 1.5, .keys = &Rows.numpad1 },
        .{ .x = 18.5, .y = 2.5, .keys = &Rows.numpad2 },
        .{ .x = 18.5, .y = 3.5, .keys = &Rows.numpad3 },
        .{ .x = 18.5, .y = 4.5, .keys = &Rows.numpad4 },
        .{ .x = 18.5, .y = 5.5, .keys = &Rows.numpad5 },
    };

    pub const Ansi104_60 = [_]Row{
        .{ .x = 0, .y = 1.5, .keys = &(Rows.numkeys ++ Rows.numkeys_ex) },
        .{ .x = 0, .y = 2.5, .keys = &Rows.tabkeys },
        .{ .x = 0, .y = 3.5, .keys = &Rows.capskeys },
        .{ .x = 0, .y = 4.5, .keys = &Rows.shiftkeys },
        .{ .x = 0, .y = 5.5, .keys = &Rows.ctrlkeys },
    };

    w_perc: f32 = 0.5,

    pub fn init(alloc: std.mem.Allocator) Self {
        _ = alloc;
        return .{};
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn update(self: *Self, wrap: *Os9Gui) !void {
        const gui = &wrap.gui;
        const win_area = gui.getArea() orelse return;
        const border_area = win_area.inset(6 * wrap.scale);
        const area = border_area.inset(6 * wrap.scale);
        const keyboard = Ansi104;

        gui.draw9Slice(win_area, wrap.style.getRect(.window_outer_small), wrap.style.texture, wrap.scale);
        gui.draw9Slice(border_area, wrap.style.getRect(.basic_inset), wrap.style.texture, wrap.scale);

        const keyboard_width = blk: {
            var maxw: f32 = 0;
            for (keyboard) |row| {
                var w: f32 = row.x;
                for (row.keys) |key| {
                    w += key.width;
                }
                maxw = if (w > maxw) w else maxw;
            }
            break :blk maxw;
        };

        {
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = area }, .{});
            defer gui.endLayout();
            const r = gui.getArea() orelse return;
            const kw = r.w / keyboard_width;
            const kh = kw;
            for (keyboard) |row| {
                var x: f32 = row.x * kw;
                const y: f32 = row.y * kh;
                for (row.keys) |key| {
                    const ww = key.width * kw;
                    switch (key.ktype) {
                        .key => {
                            const rr = Rect.new(r.x + x, r.y + y, ww, kh);
                            gui.draw9Slice(rr.inset(3), wrap.style.getRect(.err), wrap.style.texture, wrap.scale);
                            const tr = rr.inset(wrap.style.getRect(.err).w / 3 * wrap.scale + 3);

                            if (key.name) |n| {
                                gui.drawTextFmt("{s}", .{n}, tr, 20 * wrap.scale, Color.Black, .{}, wrap.font);
                            }
                        },
                        .spacing => {},
                    }
                    x += ww;
                }
            }
            //gui.drawRectMultiColor(r, [_]Color{ (0xffffffff), itc(0xff0000ff), itc(0x00ff00ff), itc(0x0000ffff) });
            //gui.drawRectMultiColor(r, [_]Color{ (0x888888ff), itc(0x222222ff), itc(0x222222ff), itc(0x888888ff) });
            var unused: f32 = 0;
            _ = gui.draggable(r, .{ .x = 1 / r.w, .y = 0 }, &(self.w_perc), &unused, .{ .x_min = 0.1, .x_max = 0.9 });
            { //SplitPlan
                const A = SplitPlan.A;
                const S = SplitPlan.S;
                const splits = comptime SplitPlan{
                    .area = Rec(0, 0, 1000, 1000),
                    .root = SplitPlan.LS(
                        .v,
                        1000,
                        &A("left_panel"),
                        &S(
                            .h,
                            0.2,
                            &A("header_bar"),
                            &S(.h, 0.9, &A("Main_area"), &A("bottom_bar")),
                        ),
                    ),
                };
                //const planT = SplitPlan.createSplitPlan(splits.root);
                const sp = SplitPlan.calculatePlan(splits.root, r, .{});
                gui.drawRectFilled(sp.left_panel, Color.Blue);
                gui.drawRectFilled(sp.Main_area, Color.Black);
                gui.drawRectFilled(sp.header_bar, Color.Red);
                gui.drawRectFilled(sp.bottom_bar, Color.Green);
            }
        }
    }
};

pub const GuiConfig = struct {
    const Self = @This();
    pub const ConfigJson = struct {
        //All units are pixels
        default_item_h: f32 = 20,
        default_v_pad: graph.Padding = .{},
        pixel_per_line: f32 = 20,
        color_picker_size: Vec2f = .{ .x = 600, .y = 300 },
        property_table_item_h: f32 = 20,
        textbox_caret_width: f32 = 3,
        textbox_inset: f32 = 3,
        //All units are counts
        enum_combo_item_count_scroll_threshold: u32 = 15,

        colors: struct {
            pub const ColorWrap = struct {
                child: u32,

                pub fn jsonParse(alloc: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
                    const str = try std.json.innerParse([]const u8, alloc, source, options);
                    const int = try std.fmt.parseInt(u32, str, 0);
                    return .{ .child = int };
                }
            };
            button_text: u32 = 0xff,
            button_text_disabled: u32 = 0x222222ff,
            text_highlight: u32 = 0xccccffff,
            textbox_fg: u32 = 0xff,
            textbox_fg_disabled: u32 = 0xff,
            textbox_bg_disabled: u32 = 0xffffff75,
            textbox_invalid: u32 = 0xff0000ff,
            textbox_caret: u32 = 0xff,

            fn createWrapperType() type {
                const ch: @This() = .{};
                const info = @typeInfo(@This());
                var fields: [info.Struct.fields.len]std.builtin.Type.StructField = undefined;
                inline for (info.Struct.fields, 0..) |field, i| {
                    if (field.type != u32)
                        @compileError("color not an int");
                    const default = ColorWrap{ .child = @field(ch, field.name) };
                    fields[i] = .{
                        .name = field.name,
                        .type = ColorWrap,
                        .default_value = &default,
                        .is_comptime = false,
                        .alignment = @alignOf(ColorWrap),
                    };
                }

                return @Type(std.builtin.Type{ .Struct = .{
                    .layout = .auto,
                    .fields = &fields,
                    .decls = &.{},
                    .is_tuple = false,
                } });
            }
            const JT = createWrapperType();

            pub fn jsonParse(alloc: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
                const wrap = try std.json.innerParse(JT, alloc, source, options);
                var ret: @This() = .{};
                inline for (@typeInfo(@This()).Struct.fields) |f| {
                    @field(ret, f.name) = @field(wrap, f.name).child;
                }
                return ret;
            }
        } = .{},
    };

    pub const Style9Slices = enum {
        rat,
        tab_border,
        tab_active,
        tab_inactive,
        tab_header_bg,
        radio,
        radio_active,
        button,
        button_disabled,
        button_clicked,
        down_arrow,
        combo_background,
        combo_button,
        slider_box,
        slider_shuttle,
        window,
        window_outer,
        window_outer_small,
        err,
        basic_inset,
        window_inner,
        checkbox_empty,
        checkbox_checked,
    };

    //Map Style9Slices to rects
    nineSliceLut: std.ArrayList(Rect),
    config: ConfigJson = .{},
    texture: graph.Texture,

    pub fn init(alloc: std.mem.Allocator, dir: std.fs.Dir, path: []const u8, output_path: std.fs.Dir) !Self {
        const BAKE_NAME = "gui_baked";
        //TODO maybe put the baked atlas into a xdg cache dir
        try graph.AssetBake.assetBake(
            alloc,
            dir,
            path,
            output_path,
            BAKE_NAME,
            .{ .pixel_extrude = 1 },
        );

        var manifest = try graph.AssetBake.AssetMap.initFromManifest(alloc, output_path, BAKE_NAME);
        defer manifest.deinit();
        var ret = Self{
            .nineSliceLut = std.ArrayList(Rect).init(alloc),
            .texture = try graph.AssetBake.AssetMap.initTextureFromManifest(alloc, output_path, BAKE_NAME),
        };
        errdefer ret.deinit();
        try ret.nineSliceLut.resize(@typeInfo(Style9Slices).Enum.fields.len);
        var found = std.ArrayList(bool).init(alloc);
        defer found.deinit();
        try found.appendNTimes(false, ret.nineSliceLut.items.len);
        for (manifest.id_name_lut.items, 0..) |l, id| {
            if (l) |name| {
                if (std.mem.startsWith(u8, name, "nineSlice/") and std.mem.endsWith(u8, name, ".png")) {
                    const str = name["nineSlice/".len .. name.len - ".png".len];
                    if (std.meta.stringToEnum(Style9Slices, str)) |enum_v| {
                        ret.nineSliceLut.items[@intFromEnum(enum_v)] = manifest.resource_rect_lut.items[id].?;
                        found.items[@intFromEnum(enum_v)] = true;
                    }
                }
            }
        }
        for (found.items, 0..) |f, i| {
            if (!f) {
                std.debug.print("WARNING key not found: {s}\n", .{@tagName(@as(Style9Slices, @enumFromInt(i)))});
            }
        }

        var user = try manifest.loadUserResources();
        defer user.deinit();
        if (user.name_map.get("gui_config.json")) |conf| {
            const j = std.json.parseFromSlice(ConfigJson, alloc, conf, .{}) catch |err| switch (err) {
                error.UnknownField => {
                    std.debug.print("Encountered unknown field when parsing gui_config.json\n", .{});
                    return err;
                },
                else => return err,
            };
            defer j.deinit();
            ret.config = j.value;
        } else {
            std.debug.print("COULD NOT FIND GUI CONFIG\n", .{});
        }

        return ret;
    }

    pub fn getRect(self: *Self, v: Style9Slices) Rect {
        return self.nineSliceLut.items[@intFromEnum(v)];
    }

    pub fn deinit(self: *Self) void {
        self.nineSliceLut.deinit();
    }
};

// Widgets:
// Button
// Drop down
// Text label
// text box with label
// scrollable list with selection
// checkbox
// header
// table with scroll area
//
// TODO
// tab to next textbox
// better textboxes
pub const Os9Gui = struct {
    const Self = @This();

    pub const DynamicTextbox = struct {
        arraylist: std.ArrayList(u8),

        pub fn init(alloc: std.mem.Allocator) DynamicTextbox {
            return .{ .arraylist = std.ArrayList(u8).init(alloc) };
        }
        pub fn deinit(self: *@This()) void {
            self.arraylist.deinit();
        }

        pub fn getMaxLen(_: *@This()) ?usize {
            return null;
        }
        pub fn getSlice(self: *@This()) []const u8 {
            return self.arraylist.items;
        }
        pub fn setSlice(self: *@This(), slice: []const u8) !usize {
            try self.arraylist.resize(slice.len);

            @memcpy(self.arraylist.items, slice);
            return 0;
        }
    };

    pub const StaticTextbox = struct {
        buf: []u8,
        len: usize,

        pub fn init(buffer: []u8) StaticTextbox {
            return .{
                .buf = buffer,
                .len = 0,
            };
        }

        pub fn getMaxLen(self: *@This()) ?usize {
            return self.buf.len;
        }

        pub fn getSlice(self: *@This()) []const u8 {
            return self.buf[0..self.len];
        }

        // Returns the length of omitted slice
        pub fn setSlice(self: *@This(), slice: []const u8) !usize {
            if (slice.len > self.buf.len) {
                @memcpy(self.buf, slice[0..self.buf.len]);
                self.len = self.buf.len;
                return slice.len - self.len;
            }

            @memcpy(self.buf[0..slice.len], slice);
            self.len = slice.len;
            return 0;
        }
    };

    pub fn numberRangeToEnum(comptime numbers: []const i32) !type {
        var fields: [numbers.len]std.builtin.Type.EnumField = undefined;
        var buf: [10 * numbers.len]u8 = undefined;
        var fbs = std.io.FixedBufferStream([]u8){ .buffer = &buf, .pos = 0 };
        for (numbers, 0..) |num, i| {
            const start = fbs.pos;
            try std.fmt.formatIntValue(num, "d", .{}, fbs.writer());
            try fbs.writer().writeByte(0);
            fields[i] = .{ .name = @ptrCast(fbs.getWritten()[start..]), .value = num };
        }
        return @Type(std.builtin.Type{ .Enum = .{ .tag_type = i32, .fields = &fields, .decls = &.{}, .is_exhaustive = true } });
    }

    const SampleEnum = enum {
        first_one,
        val1,
        val2,
        what,
        tabs,
        lots,
        of,
        values,
        to,
        choose,
        from,
        last_one,
    };

    const SampleStruct = struct {
        icon: Icons = .folder,
        en: SampleEnum = .what,
        float_edit: f32 = 22,
        int_edit: i64 = 21,
        uint_edit: u32 = 0,
        float: f32 = 123,
        flag: bool = false,
        my_int: i32 = 1222,
        my_struct: Rect = Rec(4, 5, 6, 7),
        ar_str: std.ArrayList(u8),
    };

    //TODO remove all of these and use AssetMap instead
    pub const os9line = Rec(0, 18, 6, 6);
    pub const os9slider = Rec(0, 24, 3, 3);
    pub const os9shuttle = Rec(0, 30, 19, 14);

    pub const os9scrollhandle = Rec(9, 44, 14, 15);
    pub const os9scrollw = 16;
    pub const os9hr = Rec(88, 0, 1, 2);

    pub const win_warning = Rec(0, 60, 32, 32);

    //TODO remove lua crap?
    //lua specific state
    vlayout: ?*Gui.VerticalLayout = null,

    style: GuiConfig,
    scale: f32,
    gui: Gui.Context,
    gui_draw_ctx: Gui.GuiDrawContext,
    ofont: *OFont,
    font: *graph.FontUtil.PublicFontInterface,
    icon_ofont: *OFont,
    icon_font: *graph.FontUtil.PublicFontInterface,
    alloc: std.mem.Allocator,

    drop_down: ?Gui.Context.WidgetId = null,
    drop_down_scroll: Vec2f = .{ .x = 0, .y = 0 },

    pub fn init(alloc: std.mem.Allocator, asset_dir: std.fs.Dir, scale: f32, cache_dir: std.fs.Dir) !Self {
        //const icon_list = comptime blk: {
        //    const info = @typeInfo(Icons);
        //    var list: [info.Enum.fields.len]u21 = undefined;

        //    for (info.Enum.fields, 0..) |f, i| {
        //        list[i] = f.value;
        //    }
        //    break :blk list;
        //};
        const ofont_ptr = try alloc.create(OFont);
        const ofont_icon_ptr = try alloc.create(OFont);
        ofont_ptr.* = try OFont.init(alloc, asset_dir, "asset/fonts/noto.ttc", 64, .{});
        ofont_icon_ptr.* = try OFont.init(alloc, asset_dir, "asset/fonts/remix.ttf", 64, .{});
        //ofont_icon_ptr.* = try OFont.initFromBuffer(alloc, @embedFile("font/remix.ttf"), 12, .{});
        return .{
            .gui = try Gui.Context.init(alloc),
            .style = try GuiConfig.init(alloc, asset_dir, "asset/os9gui", cache_dir),
            .gui_draw_ctx = try Gui.GuiDrawContext.init(alloc),
            .scale = scale,
            .alloc = alloc,
            // .texture = try graph.Texture.initFromImgFile(alloc, asset_dir, "next_step.png", .{
            //     .mag_filter = graph.c.GL_NEAREST,
            // }),
            //TODO switch to stb font init
            .ofont = ofont_ptr,
            .font = &ofont_ptr.font,
            //.font = try graph.Font.initFromBuffer(alloc, @embedFile("font/roboto.ttf"), 64, .{}),
            .icon_ofont = ofont_icon_ptr,
            .icon_font = &ofont_icon_ptr.font,
            //.icon_font = &ofont_icon_ptr.font,
            //.icon_ofont = ofont_icon_ptr,
            //.icon_font = try graph.Font.init(
            //    alloc,
            //    asset_dir,
            //    "fonts/remix.ttf",
            //    12,
            //    .{
            //        .codepoints_to_load = &[_]graph.Font.CharMapEntry{.{ .list = &icon_list }},
            //    },
            //),
        };
    }

    pub fn deinit(self: *Self) void {
        self.style.deinit();
        self.gui.deinit();
        self.gui_draw_ctx.deinit();
        self.ofont.deinit();
        self.alloc.destroy(self.ofont);
        //self.font.deinit();
        self.icon_ofont.deinit();
        self.alloc.destroy(self.icon_ofont);
    }

    pub fn beginFrame(self: *Self, input_state: Gui.InputState, win: *graph.SDL.Window) !void {
        switch (self.gui.text_input_state.state) {
            .start => win.startTextInput(self.gui.text_input_state.rect),
            .stop => win.stopTextInput(),
            .cont => self.gui.text_input_state.buffer = win.text_input,
            .disabled => {},
        }
        try self.gui.reset(input_state);
    }

    pub fn endFrame(self: *Self, draw: *graph.ImmediateDrawingContext) !void {
        try self.gui_draw_ctx.drawGui(draw, &self.gui);
        graph.c.glDisable(graph.c.GL_STENCIL_TEST);
    }

    pub fn beginTlWindow(self: *Self, parea: Rect) !bool {
        try self.gui.beginWindow(parea);
        if (self.gui.getArea()) |win_area| {
            const _br = self.style.getRect(.window);
            const border_area = win_area.inset((_br.h / 3) * self.scale);
            //const area = border_area.inset(6 * self.scale);
            self.gui.draw9Slice(win_area, _br, self.style.texture, self.scale);
            //self.gui.draw9Slice(border_area, self.style.getRect(.basic_inset), self.style.texture, self.scale);
            _ = try self.gui.beginLayout(Gui.SubRectLayout, .{ .rect = border_area }, .{});
            return true;
        }
        self.gui.endWindow();
        return false;
    }
    pub fn endTlWindow(self: *Self) void {
        self.gui.endLayout();
        self.gui.endWindow();
    }

    pub fn beginV(self: *Self) !*Gui.VerticalLayout {
        const VLP = Gui.VerticalLayout{ .item_height = self.style.config.default_item_h * self.scale, .padding = self.style.config.default_v_pad.scale(self.scale) };
        return try self.gui.beginLayout(Gui.VerticalLayout, VLP, .{});
    }

    pub fn beginH(self: *Self, count: usize) !*Gui.HorizLayout {
        const HLP = Gui.HorizLayout{ .count = count };
        return try self.gui.beginLayout(Gui.HorizLayout, HLP, .{});
    }

    pub fn endL(self: *Self) void {
        self.gui.endLayout();
    }

    pub fn beginL(self: *Self, layout: anytype) !*@TypeOf(layout) {
        return try self.gui.beginLayout(@TypeOf(layout), layout, .{});
    }

    pub fn beginSubLayout(self: *Self, sub: Rect, comptime Layout_T: type, layout_data: Layout_T) !*Layout_T {
        _ = try self.gui.beginLayout(Gui.SubRectLayout, .{ .rect = sub }, .{});
        return try self.gui.beginLayout(Layout_T, layout_data, .{});
    }

    pub fn endSubLayout(self: *Self) void {
        self.gui.endLayout();
        self.gui.endLayout();
    }

    pub fn beginScroll(self: *Self, scr: *Vec2f, opts: struct { sw: f32 = 10000 }, child_layout: anytype) !?struct { area: Rect, scroll: Gui.Context.ScrollData, child: *@TypeOf(child_layout) } {
        if (try self.gui.beginScroll(scr, .{
            .vertical_scroll = true,
            .bar_w = os9scrollw * self.scale,
            .scroll_area_w = opts.sw,
            .scroll_area_h = 10000,
        })) |scrolld| {
            const lrq = self.gui.layout.last_requested_bounds;
            return .{
                .child = try self.gui.beginLayout(@TypeOf(child_layout), child_layout, .{}),
                .scroll = scrolld,
                .area = lrq orelse graph.Rec(0, 0, 0, 0),
            };
        }
        return null;
    }

    pub fn endScroll(self: *Self, d: anytype, omax: f32) void {
        const max = omax - d.area.h;
        const sd = d.scroll;
        if (max > 0) {
            if (self.gui.getMouseWheelDelta()) |del| {
                //if (self.gui.mouse_grab_id == null and !self.gui.scroll_claimed_mouse and w.scroll_bounds.?.containsPoint(self.gui.input_state.mouse_pos) and self.gui.window_index_grabbed_mouse == self.gui.window_index.?) {
                const pixel_per_line = self.style.config.pixel_per_line * self.scale;
                sd.offset.y = std.math.clamp(sd.offset.y + del * -pixel_per_line * 3, 0, max);
            }
        }
        self.gui.endLayout();
        self.gui.endScroll();
        if (sd.vertical_slider_area) |va| {
            _ = self.gui.beginLayout(Gui.SubRectLayout, .{ .rect = va }, .{}) catch unreachable;
            defer self.gui.endLayout();
            self.scrollBar(&sd.offset.y, 0, if (max < 0) 0 else max, .vertical, .{
                .handle_w = if (max > d.area.h) os9scrollhandle.h * self.scale else d.area.h - max,
            });
        }
    }

    pub fn beginVScroll(self: *Self, scr: *Vec2f, opts: struct { sw: f32 = 10000, sh: f32 = 10000 }) !?Gui.Context.VLayoutScrollData {
        const scale = self.scale;
        if (try self.gui.beginScroll(scr, .{
            .vertical_scroll = true,
            .bar_w = os9scrollw * scale,
            .scroll_area_w = opts.sw,
            .scroll_area_h = opts.sh,
        })) |scroll| {
            const lrq = self.gui.layout.last_requested_bounds;
            return .{
                .layout = try self.beginV(),
                //.layout = try self.gui.beginLayout(Gui.VerticalLayout, .{ .item_height = 20 * scale }, .{}),
                .data = scroll,
                .area = lrq orelse graph.Rec(0, 0, 0, 0),
            };
        }
        return null;
    }

    pub fn endVScroll(self: *Self, scroll_data: Gui.Context.VLayoutScrollData) void {
        const sd = scroll_data.data;
        const max = scroll_data.layout.current_h - scroll_data.area.h;
        if (max > 0) {
            if (self.gui.getMouseWheelDelta()) |del| {
                //if (self.gui.mouse_grab_id == null and !self.gui.scroll_claimed_mouse and w.scroll_bounds.?.containsPoint(self.gui.input_state.mouse_pos)) {
                const pixel_per_line = self.style.config.pixel_per_line * self.scale;
                sd.offset.y = std.math.clamp(sd.offset.y + del * -pixel_per_line * 3, 0, max);
            }
        }
        self.gui.endLayout();
        self.gui.endScroll();
        if (sd.vertical_slider_area) |va| {
            _ = self.gui.beginLayout(Gui.SubRectLayout, .{ .rect = va }, .{}) catch unreachable;
            defer self.gui.endLayout();
            self.scrollBar(&sd.offset.y, 0, if (max < 0) 0 else max, .vertical, .{
                .handle_w = if (max > scroll_data.area.h) os9scrollhandle.h * self.scale else scroll_data.area.h - max,
            });
        }
    }

    pub fn hr(self: *Self) void {
        if (self.gui.getArea()) |area| {
            if (area.h >= os9hr.h * self.scale) {
                self.gui.drawRectTextured(
                    Rec(area.x, area.y + (area.h - os9hr.h * self.scale) / 2, area.w, os9hr.h * self.scale),
                    Color.White,
                    os9hr,
                    self.style.texture,
                );
            }
        }
    }

    pub fn tabsBorderCalc(comptime list_type: type, selected: list_type, w: f32) struct { f32, f32 } {
        const info = @typeInfo(list_type);
        const item_w = w / @as(f32, @floatFromInt(info.Enum.fields.len));
        inline for (info.Enum.fields, 0..) |field, i| {
            const active = @as(info.Enum.tag_type, @intFromEnum(selected)) == field.value;
            const fi: f32 = @floatFromInt(i);
            if (active) {
                return .{ fi * item_w, (fi + 1) * item_w };
            }
        }
        unreachable;
    }

    pub fn beginTabs(self: *Self, selected: anytype) !@typeInfo(@TypeOf(selected)).Pointer.child {
        const ptrinfo = @typeInfo(@TypeOf(selected));
        const childT = ptrinfo.Pointer.child;
        const info = @typeInfo(childT);
        const fields = info.Enum.fields;
        var v = try self.beginL(Gui.VerticalLayout{ .item_height = 20 * self.scale });

        _ = try self.beginH(fields.len);
        const bound = self.gui.getLayoutBounds() orelse return selected.*;
        //const bord = self.style.getRect(.tab_border);
        const bg = self.style.getRect(.tab_header_bg);
        self.gui.draw9Slice(bound, bg, self.style.texture, self.scale);
        //self.gui.drawRectTextured(bound.replace(
        //    null,
        //    bound.y + bound.h - self.scale * bord.h,
        //    null,
        //    self.scale * bord.h,
        //), Color.White, bord, self.style.texture);
        const active = self.style.getRect(.tab_active);
        const inactive = self.style.getRect(.tab_inactive);

        inline for (fields) |f| {
            const d = self.gui.buttonGeneric();
            if (d.state == .click)
                selected.* = @enumFromInt(f.value);
            const _9s = if (f.value == @intFromEnum(selected.*)) active else inactive;
            self.gui.draw9Slice(d.area, _9s, self.style.texture, self.scale);
            const tarea = d.area.inset(self.scale * (_9s.w / 3));
            self.gui.drawTextFmt("{s}", .{f.name}, tarea, tarea.h, Color.Black, .{ .justify = .center }, self.font);
            //self.label("{s}", .{f.name});
        }
        self.endL(); // horiz
        v.pushRemaining();
        const border_r = self.gui.getArea() orelse Rec(0, 0, 0, 0);
        _ = try self.beginL(Gui.SubRectLayout{ .rect = border_r.inset(self.scale * 3) });

        return selected.*;
    }

    pub fn endTabs(self: *Self) void {
        self.endL();
        self.endL();
    }

    pub fn rat(self: *Self) !void {
        if (self.gui.getArea()) |area| {
            const scr = try self.gui.storeLayoutData(struct {
                frame: u32,
                x: f32,
            }, .{ .frame = 0, .x = 0 }, "frame");
            const frame = self.style.getRect(.rat);
            const p = 6;
            const rect = frame.replace(frame.x + @as(f32, @floatFromInt(32 * (scr.frame / p))), null, 32, 24);
            scr.frame = (scr.frame + 1) % (p * 3);
            scr.x += 2 * self.scale;
            if (scr.x > area.w)
                scr.x = 0;
            self.gui.drawRectTextured(area.replace(area.x + scr.x, null, 32 * self.scale, 24 * self.scale), Color.White, rect, self.style.texture);
        }
    }

    pub fn colorPicker(self: *Self, color: *graph.Hsva) !void {
        if (self.gui.getArea()) |area| {
            _ = try self.gui.beginLayout(Gui.SubRectLayout, .{ .rect = area }, .{});
            defer self.gui.endLayout();
            const scr = try self.gui.storeLayoutData(bool, false, "popped_");
            self.gui.drawRectFilled(area, color.toInt());
            const d = self.gui.buttonGeneric();
            if (d.state == .click)
                scr.* = true;
            if (scr.*) {
                const sz = self.style.config.color_picker_size;
                const r = Rec(d.area.x, d.area.y, sz.x * self.scale, sz.y * self.scale);
                if (!(d.state == .click) and self.gui.input_state.mouse.left == .rising and !self.gui.isCursorInRect(r) and self.gui.window_index_grabbed_mouse == self.gui.window_index.?)
                    scr.* = false;
                if (try self.beginTlWindow(r)) {
                    defer self.endTlWindow();
                    _ = try self.beginH(2);
                    defer self.endL();
                    {
                        const ar = self.gui.getArea() orelse return;
                        const pad = self.scale * 5;
                        const slider_w = 40 * self.scale;
                        const sv_area = Rec(ar.x, ar.y, ar.w - (slider_w + pad) * 1, ar.h);
                        const hs = 15;
                        var sv_handle = Rect.new(sv_area.x + color.s * sv_area.w - hs / 2, sv_area.y + (1.0 - color.v) * sv_area.h - hs / 2, hs, hs);
                        const clicked = self.gui.clickWidgetEx(sv_handle, .{ .teleport_area = sv_area }).click;
                        const mpos = self.gui.input_state.mouse.pos;
                        switch (clicked) {
                            .click, .held => {
                                const mdel = self.gui.input_state.mouse.delta;

                                color.s += mdel.x / sv_area.w;
                                color.v += -mdel.y / sv_area.h;

                                color.s = std.math.clamp(color.s, 0, 1);
                                color.v = std.math.clamp(color.v, 0, 1);

                                if (mpos.x > sv_area.x + sv_area.w)
                                    color.s = 1.0;
                                if (mpos.x < sv_area.x)
                                    color.s = 0.0;

                                if (mpos.y > sv_area.y + sv_area.h)
                                    color.v = 0.0;
                                if (mpos.y < sv_area.y)
                                    color.v = 1.0;
                            },
                            .click_teleport => {
                                color.s = (mpos.x - sv_area.x) / sv_area.w;
                                color.v = (1.0 - (mpos.y - sv_area.y) / sv_area.h);
                                color.s = std.math.clamp(color.s, 0, 1);
                                color.v = std.math.clamp(color.v, 0, 1);
                            },

                            else => {},
                        }
                        sv_handle = Rect.new(sv_area.x + color.s * sv_area.w - hs / 2, sv_area.y + (1.0 - color.v) * sv_area.h - hs / 2, hs, hs);
                        const h_area = Rec(sv_area.x + sv_area.w + pad, ar.y, slider_w, ar.h);
                        const hue_handle_height = 15;
                        var hue_handle = Rect.new(h_area.x, h_area.y + h_area.h * color.h / 360.0 - hue_handle_height / 2, h_area.w, hue_handle_height);
                        const hue_clicked = self.gui.clickWidgetEx(hue_handle, .{ .teleport_area = h_area }).click;
                        switch (hue_clicked) {
                            .click, .held => {
                                const mdel = self.gui.input_state.mouse.delta;
                                color.h += 360 * mdel.y / h_area.h;
                                color.h = std.math.clamp(color.h, 0, 360);

                                if (self.gui.input_state.mouse.pos.y > h_area.y + h_area.h)
                                    color.h = 360.0;
                                if (self.gui.input_state.mouse.pos.y < h_area.y)
                                    color.h = 0.0;
                            },
                            .click_teleport => {
                                color.h = (mpos.y - h_area.y) / h_area.h * 360.0;
                            },
                            else => {},
                        }
                        hue_handle = Rect.new(h_area.x, h_area.y + h_area.h * color.h / 360.0 - hue_handle_height / 2, h_area.w, hue_handle_height);
                        //Ported from Nuklear
                        { //Hue slider
                            //const hue_colors: [7]u32 = .{ Col(255, 0, 0, 255), Col(255, 255, 0, 255), Col(0, 255, 0, 255), Col(0, 255, 255, 255), Col(0, 0, 255, 255), Col(255, 0, 255, 255), Col(255, 0, 0, 255) };
                            const hue_colors: [7]u32 = .{ 0xff0000ff, 0xffff00ff, 0x00ff00ff, 0x00ffffff, 0xffff, 0xff00ffff, 0xff0000ff };
                            var i: u32 = 0;
                            while (i < 6) : (i += 1) {
                                const fi = @as(f32, @floatFromInt(i));
                                self.gui.drawRectMultiColor(Rect.new(h_area.x, h_area.y + fi * h_area.h / 6.0, h_area.w, h_area.h / 6.0), .{
                                    hue_colors[i], // 1
                                    hue_colors[i + 1], //3
                                    hue_colors[i + 1], //4
                                    hue_colors[i], //2
                                });
                            }
                        }
                        const temp = (graph.Hsva{ .h = color.h, .s = 1, .v = 1, .a = 1 }).toInt();
                        const black_trans = 0;
                        self.gui.drawRectMultiColor(sv_area, .{ Color.Black, Color.Black, Color.Black, Color.Black });
                        self.gui.drawRectMultiColor(sv_area, .{ Color.White, Color.White, temp, temp });
                        self.gui.drawRectMultiColor(sv_area, .{ black_trans, Color.Black, Color.Black, black_trans });
                        self.gui.drawRectFilled(sv_handle, Color.Black);
                        self.gui.drawRectFilled(hue_handle, Color.Black);
                    }

                    {
                        var vl = try self.beginV();
                        defer self.endL();
                        if (self.button("Done")) {
                            scr.* = false;
                        }

                        {
                            _ = try self.beginH(3);
                            defer self.endL();
                            self.label("Hue", .{});
                            self.slider(&color.h, 0, 360);
                            try self.textboxNumber(&color.h);
                        }
                        {
                            _ = try self.beginH(3);
                            defer self.endL();
                            self.label("Saturation", .{});
                            self.slider(&color.s, 0, 1);
                            try self.textboxNumber(&color.s);
                        }
                        {
                            _ = try self.beginH(3);
                            defer self.endL();
                            self.label("Value", .{});
                            self.slider(&color.v, 0, 1);
                            try self.textboxNumber(&color.v);
                        }
                        {
                            _ = try self.beginH(3);
                            defer self.endL();
                            self.label("Alpha", .{});
                            self.slider(&color.a, 0, 1);
                            try self.textboxNumber(&color.v);
                        }
                        {
                            var buf: [16]u8 = undefined;
                            var sb = StaticTextbox.init(&buf);
                            try self.textbox2(&sb, .{});
                            if (sb.len > 0) {
                                _ = blk: {
                                    const newcolor = graph.Hsva.fromInt((std.fmt.parseInt(u32, buf[0..sb.len], 0) catch |err| switch (err) {
                                        else => break :blk,
                                    } << 8) | 0xff);
                                    color.* = newcolor;
                                };
                            }
                        }
                        vl.pushRemaining();
                        const ar3 = self.gui.getArea() orelse return;
                        self.gui.drawRectFilled(ar3, 0xff);
                        self.gui.drawRectFilled(ar3, color.toInt());
                    }
                }
            }
        }
    }

    pub fn propertyTableHeight(self: *Self, to_edit: anytype) f32 {
        const err_prefix = @typeName(@This()) ++ ".propertyTable: ";
        const invalid = err_prefix ++ "Argument \'to_edit\' expects a mutable pointer to a struct. Recieved: " ++ @typeName(@TypeOf(to_edit));
        const e_info = @typeInfo(@TypeOf(to_edit));
        if (e_info != .Pointer or e_info.Pointer.is_const) @compileError(invalid);
        const ptype = e_info.Pointer.child;
        const info = @typeInfo(ptype);
        if (info != .Struct) @compileError(invalid);
        const num_lines = info.Struct.fields.len;
        const item_height = self.scale * self.style.config.property_table_item_h;
        return num_lines * item_height + (2 * 3 * self.scale) + 100;
    }

    pub fn propertyTable(self: *Self, to_edit: anytype) !void {
        const err_prefix = @typeName(@This()) ++ ".propertyTable: ";
        const invalid = err_prefix ++ "Argument \'to_edit\' expects a mutable pointer to a struct. Recieved: " ++ @typeName(@TypeOf(to_edit));
        const e_info = @typeInfo(@TypeOf(to_edit));
        if (e_info != .Pointer or e_info.Pointer.is_const) @compileError(invalid);
        const ptype = e_info.Pointer.child;
        const info = @typeInfo(ptype);
        if (info != .Struct) @compileError(invalid);
        const num_lines = info.Struct.fields.len;
        const item_height = self.scale * self.style.config.property_table_item_h;
        const ar = self.gui.getArea() orelse return;
        self.gui.draw9Slice(ar, self.style.getRect(.basic_inset), self.style.texture, self.scale);
        const in = ar.inset(3 * self.scale);
        _ = try self.gui.beginLayout(Gui.SubRectLayout, .{ .rect = in }, .{});
        defer self.gui.endLayout();
        const do_scroll = (in.h < item_height * num_lines);
        const scr = try self.gui.storeLayoutData(Vec2f, .{ .x = 0, .y = 0 }, "popped_prop_index");

        const sd = blk: {
            if (do_scroll) {
                break :blk .{ .scroll = try self.gui.beginScroll(scr, .{
                    .vertical_scroll = true,
                    .bar_w = os9scrollw * self.scale,
                    .scroll_area_h = item_height * num_lines,
                    .scroll_area_w = in.w,
                }) orelse unreachable, .area = self.gui.layout.last_requested_bounds orelse graph.Rec(0, 0, 0, 0) };
            }
            break :blk null;
        };
        const max = item_height * num_lines;

        {
            _ = try self.gui.beginLayout(Gui.TableLayout, .{ .columns = 2, .item_height = item_height }, .{});
            //_ = try self.gui.beginLayout(Gui.VerticalLayout, .{ .item_height = 35 }, .{});
            if (self.gui.layout.last_requested_bounds) |lrq| {
                const lx = lrq.w / 2 + lrq.x;
                self.gui.drawLine(.{ .x = lx, .y = lrq.y }, .{ .x = lx, .y = lrq.y + lrq.h }, (0xff));
                inline for (info.Struct.fields) |f| {
                    self.label("{s}, {s}", .{ f.name, @typeName(f.type) });
                    try self.editProperty(f.type, &@field(to_edit, f.name), f.name, 0);
                }
            }
            self.gui.endLayout();
        }
        if (do_scroll) {
            if (self.gui.getMouseWheelDelta()) |del| {
                //if (self.gui.mouse_grab_id == null and !self.gui.scroll_claimed_mouse and w.scroll_bounds.?.containsPoint(self.gui.input_state.mouse_pos)) {
                const pixel_per_line = self.style.config.pixel_per_line * self.scale;
                scr.y = std.math.clamp(scr.y + del * -pixel_per_line * 3, 0, 1000);
            }
            self.gui.endScroll();
            if (sd.?.scroll.vertical_slider_area) |va| {
                _ = self.gui.beginLayout(Gui.SubRectLayout, .{ .rect = va }, .{}) catch unreachable;
                defer self.gui.endLayout();
                self.scrollBar(&scr.y, 0, if (max < 0) 0 else max, .vertical, .{
                    .handle_w = if (max > sd.?.area.h) os9scrollhandle.h * self.scale else sd.?.area.h - max,
                });
            }
        }
    }

    pub fn toggleWindowPop(self: *Self, a: Rect, pop: *bool) void {
        if (self.gui.input_state.mouse.left == .rising and !self.gui.isCursorInRect(a) and self.gui.window_index_grabbed_mouse == self.gui.window_index.?)
            pop.* = false;
    }

    pub fn editProperty(self: *Self, comptime T: type, prop: *T, comptime field_name: []const u8, index: usize) !void {
        switch (@typeInfo(T)) {
            .Struct => {
                switch (T) {
                    Vec2f => {
                        _ = try self.gui.beginLayout(Gui.HorizLayout, .{ .count = 2 }, .{});
                        defer self.gui.endLayout();
                        try self.textboxNumber(&prop.x);
                        try self.textboxNumber(&prop.y);
                    },
                    std.ArrayList(u8) => {
                        try self.textbox(prop);
                    },
                    else => {
                        if (std.meta.hasFn(T, "guiEditProperty")) {
                            try prop.guiEditProperty(self);
                            return;
                        }
                        const scr = try self.gui.storeLayoutData(bool, false, self.gui.scratchPrint("s{s}{d}", .{ field_name, index }));
                        if (self.button("edit"))
                            scr.* = true;
                        if (scr.*) {
                            const pa = self.gui.layout.last_requested_bounds orelse return;
                            const a = graph.Rect.newV(pa.pos(), .{ .x = pa.w, .y = pa.h * 5 });
                            if (self.gui.input_state.mouse.left == .rising and !self.gui.isCursorInRect(a) and self.gui.window_index_grabbed_mouse == self.gui.window_index.?)
                                scr.* = false;
                            try self.gui.beginWindow(a);
                            defer self.gui.endWindow();
                            try self.propertyTable(prop);
                        }
                    },
                }
            },
            .Pointer => |p| {
                if (p.is_const) {
                    self.label("const_ptr", .{});
                    return;
                }
                switch (p.size) {
                    .Slice => {
                        if (p.child == u8) {
                            self.label("{s}", .{prop.*});
                            return;
                        } else {
                            const scr = try self.gui.storeLayoutData(
                                struct { pop: bool, scr: Vec2f },
                                .{ .pop = false, .scr = .{ .x = 0, .y = 0 } },
                                self.gui.scratchPrint("sp{s}{d}", .{ field_name, index }),
                            );
                            if (self.button("view"))
                                scr.pop = true;
                            if (scr.pop) {
                                const pa = self.gui.layout.last_requested_bounds.?;
                                const a = graph.Rect.newV(pa.pos(), .{ .x = pa.w, .y = pa.h * 5 });
                                if (self.gui.input_state.mouse.left == .rising and !self.gui.isCursorInRect(a) and self.gui.window_index_grabbed_mouse == self.gui.window_index.?)
                                    scr.pop = false;
                                try self.gui.beginWindow(a);
                                defer self.gui.endWindow();

                                if (try self.beginVScroll(&scr.scr, .{ .sw = a.w })) |file_scroll| {
                                    defer self.endVScroll(file_scroll);
                                    for (prop.*, 0..) |*item, i| {
                                        try self.editProperty(p.child, item, field_name, i + index);
                                    }
                                }
                            }
                            return;
                        }
                    },
                    .One => {
                        //if (!p.is_const)
                        //try self.editProperty(p.child, prop.*, field_name);
                    },
                    else => {},
                }
                self.gui.skipArea();
            },
            .Optional => |o| {
                if (prop.* != null) {
                    try self.editProperty(o.child, &(prop.*.?), field_name, 0);
                    return;
                }
                self.label("null", .{});
            },
            .Bool => _ = self.checkbox("", prop),
            .Enum => try self.enumCombo("{s}", .{@tagName(prop.*)}, prop),
            .Int, .Float => try self.textboxNumber(prop),
            else => self.gui.skipArea(),
        }
    }

    pub fn labelEx(self: *Self, comptime fmt: []const u8, args: anytype, params: struct { justify: Gui.Justify = .left }) void {
        const area = self.gui.getArea() orelse return;
        self.gui.drawTextFmt(fmt, args, area, area.h, Color.Black, .{ .justify = params.justify }, self.font);
    }

    pub fn label(self: *Self, comptime fmt: []const u8, args: anytype) void {
        self.labelEx(fmt, args, .{});
    }

    pub fn button(self: *Self, label_: []const u8) bool {
        return self.buttonEx("{s}", .{label_}, .{});
    }

    pub fn toggleButton(self: *Self, comptime fmt: []const u8, args: anytype, checked: *bool) bool {
        const gui = &self.gui;
        if (gui.checkboxGeneric(checked)) |d| {
            const color = if (!checked.*) self.style.config.colors.button_text_disabled else (self.style.config.colors.button_text);
            const sl = if (!checked.*) self.style.getRect(.button) else self.style.getRect(.button_clicked);

            gui.draw9Slice(d.area, sl, self.style.texture, self.scale);
            const texta = d.area.inset(3 * self.scale);
            gui.drawTextFmt(fmt, args, texta, texta.h, color, .{ .justify = .center }, self.font);
            return d.changed;
        }
        return false;
    }

    pub fn buttonEx(self: *Self, comptime fmt: []const u8, args: anytype, params: struct {
        disabled: bool = false,
        continuous: bool = false,
    }) bool {
        const gui = &self.gui;
        const d = gui.buttonGeneric();
        const sl = switch (d.state) {
            .none, .hover, .hover_no_focus => self.style.getRect(.button),
            .click, .held => self.style.getRect(.button_clicked),
            else => self.style.getRect(.button),
        };
        const disable = self.style.getRect(.button_disabled);
        const sl1 = if (params.disabled) disable else sl;
        const color = if (params.disabled) self.style.config.colors.button_text_disabled else (self.style.config.colors.button_text);
        gui.draw9Slice(d.area, sl1, self.style.texture, self.scale);
        const texta = d.area.inset(3 * self.scale);
        gui.drawTextFmt(fmt, args, texta, texta.h, color, .{ .justify = .center }, self.font);

        const is_cont = if (params.continuous) d.state == .held else false;
        return (d.state == .click or is_cont) and !params.disabled;
    }

    pub fn scrollBar(self: *Self, pos: *f32, min: f32, max: f32, orientation: Gui.Orientation, params: struct {
        handle_w: f32 = os9scrollhandle.h,
    }) void {
        const gui = &self.gui;
        if (gui.sliderGeneric(pos, min, max, .{
            .handle_offset_y = 0,
            .handle_offset_x = 0,
            .handle_w = params.handle_w,
            .handle_h = os9scrollhandle.w * self.scale,
            .orientation = orientation,
        })) |d| {
            gui.draw9Slice(d.area, self.style.getRect(.slider_box), self.style.texture, self.scale);
            gui.draw9Slice(d.handle, self.style.getRect(.slider_shuttle), self.style.texture, self.scale);
            //gui.drawRectTextured(
            //    d.handle,
            //    Color.White,
            //    self.style.getRect(.slider_shuttle),
            //    self.style.texture,
            //);
        }
    }

    pub fn sliderEx(self: *Self, value: anytype, min: anytype, max: anytype, comptime fmt: []const u8, args: anytype) void {
        _ = self.beginL(Gui.HorizLayout{ .count = 2 }) catch return;
        self.label(fmt, args);
        self.slider(value, min, max);
        self.endL();
    }

    pub fn sliderLog(self: *Self, value: anytype, min: anytype, max: anytype, comptime fmt: []const u8, args: anytype, base: f32) void {
        _ = self.beginL(Gui.HorizLayout{ .count = 2 }) catch return;
        self.label(fmt, args);
        self.sliderParam(value, min, max, base);
        self.endL();
    }

    pub fn slider(self: *Self, value: anytype, min: anytype, max: anytype) void {
        self.sliderParam(value, min, max, 1);
    }

    pub fn sliderParam(self: *Self, value: anytype, min_: anytype, max_: anytype, base: f32) void {
        const min = std.math.lossyCast(f32, min_);
        const max = std.math.lossyCast(f32, max_);
        const gui = &self.gui;
        const box = self.style.getRect(.slider_box);
        const shuttle = self.style.getRect(.slider_shuttle);
        if (gui.sliderGeneric(value, min, max, .{
            .base = base,
            .handle_offset_x = 0,
            .handle_offset_y = 0,
            .handle_w = 16 * self.scale,
            .handle_h = box.h * self.scale,
        })) |d| {
            gui.draw9Slice(d.area, box, self.style.texture, self.scale);
            const textb = d.area.inset(self.scale * box.h / 3);
            const diff: usize = @intFromFloat(max - min);
            if (diff <= 10 and @typeInfo(@typeInfo(@TypeOf(value)).Pointer.child) == .Int) {
                const h = d.area.h - os9slider.h / 3 * 2;
                const dist: usize = @divTrunc(@as(usize, @intFromFloat(d.area.w - os9shuttle.w * self.scale)), diff);
                for (1..diff) |i| {
                    gui.drawRectFilled(Rec(@as(f32, @floatFromInt(dist * i)) + d.area.x + os9shuttle.w * self.scale / 2, d.area.y + os9slider.h / 3, self.scale * 3, h), Color.Black);
                }
            }
            gui.draw9Slice(d.handle, shuttle, self.style.texture, self.scale);
            gui.drawTextFmt("{d:.2}", .{value.*}, textb, textb.h, (0xff), .{ .justify = .center }, self.font);
            //gui.draw9Slice(d.handle, os9shuttle, self.style.texture, self.scale);
        }
    }

    pub fn checkbox(self: *Self, label_: []const u8, checked: *bool) bool {
        const gui = &self.gui;
        if (gui.checkboxGeneric(checked)) |d| {
            const cr = self.style.getRect(if (checked.*) .checkbox_checked else .checkbox_empty);
            const area = d.area;

            const br = Rect.newV(area.pos(), .{ .x = @min(cr.w * self.scale, area.w), .y = @min(cr.h * self.scale, area.h) });
            gui.drawRectTextured(
                br,
                Color.White,
                cr,
                self.style.texture,
            );
            const tarea = Rec(br.farX(), area.y, area.w - br.farX(), area.h);
            gui.drawTextFmt("{s}", .{label_}, tarea, area.h, Color.Black, .{}, self.font);
            return d.changed;
        }
        return false;
    }

    pub fn radio(self: *Self, enum_value: anytype) !void {
        //TODO Move this whole error section into a function
        const err_prefix = @typeName(@This()) ++ ".radio: ";
        const invalid = err_prefix ++ "Argument \'enum_value\' expects a mutable pointer to an enum. Recieved: " ++ @typeName(@TypeOf(enum_value));
        const e_info = @typeInfo(@TypeOf(enum_value));
        if (e_info != .Pointer or e_info.Pointer.is_const) @compileError(invalid);
        const enum_type = e_info.Pointer.child;
        const enum_info = @typeInfo(enum_type);
        if (enum_info != .Enum) @compileError(invalid);

        _ = try self.beginH(enum_info.Enum.fields.len);
        inline for (enum_info.Enum.fields) |f| {
            const d = self.gui.buttonGeneric();
            if (d.state == .click)
                enum_value.* = @enumFromInt(f.value);
            const inactive = self.style.getRect(.radio);
            const tarea = Rec(d.area.x + d.area.h, d.area.y, d.area.w - d.area.h, d.area.h);
            const rr = d.area.replace(null, null, @min(d.area.h, inactive.w * self.scale), @min(d.area.w, inactive.h * self.scale));
            self.gui.drawTextFmt("{s}", .{f.name}, tarea, tarea.h, Color.Black, .{ .justify = .left }, self.font);
            const active = self.style.getRect(.radio_active);
            self.gui.drawRectTextured(rr, Color.White, if (@intFromEnum(enum_value.*) == f.value) active else inactive, self.style.texture);
        }
        self.endL();
    }

    pub fn numberCombo(self: *Self, comptime fmt: []const u8, args: anytype, comptime numbers: []const i32, number: *i32) !bool {
        const EnumType = try numberRangeToEnum(numbers);
        var en: EnumType = @enumFromInt(number.*);
        try self.enumCombo(fmt, args, &en);
        const ret: i32 = @intFromEnum(en);
        if (ret != number.*) {
            number.* = ret;
            return true;
        }
        return false;
    }

    pub fn combo(
        self: *Self,
        comptime fmt: []const u8,
        args: anytype,
        index: *usize,
        count: usize,
        ctx: anytype,
        next: *const fn (@TypeOf(ctx)) ?struct { usize, []const u8 },
    ) !void {
        const id = self.gui.getId();

        {
            const d = self.gui.buttonGeneric();
            const cb = self.style.getRect(.combo_background);
            self.gui.draw9Slice(d.area, cb, self.style.texture, self.scale);
            const texta = d.area.inset(cb.w / 3 * self.scale);
            self.gui.drawTextFmt(fmt, args, texta, texta.h, 0xff, .{ .justify = .center }, self.font);
            const cbb = self.style.getRect(.combo_button);
            const da = self.style.getRect(.down_arrow);
            const cbbr = d.area.replace(d.area.x + d.area.w - cbb.w * self.scale, null, cbb.w * self.scale, null).centerR(da.w * self.scale, da.h * self.scale);
            //const sp = d.area.split(.horizontal, @min(d.area.w, d.area.w - 16 * self.scale));
            //const right = sp[1];
            self.gui.drawRectTextured(cbbr, Color.White, da, self.style.texture);
            //const icon_rect =

            if (d.state == .click) {
                self.drop_down = id;
                self.drop_down_scroll = .{ .x = 0, .y = 0 };
                return;
            }
        }

        if (self.drop_down) |dd| {
            if (dd.eql(id)) {
                const scrth = self.style.config.enum_combo_item_count_scroll_threshold;
                const do_scroll = count > scrth;
                const pa = self.gui.layout.last_requested_bounds.?;
                const dd_area = graph.Rect.newV(pa.pos(), .{
                    .x = pa.w,
                    .y = if (do_scroll) pa.h * @as(f32, @floatFromInt(scrth)) else @as(f32, @floatFromInt(count)) * pa.h,
                });
                if (self.gui.input_state.mouse.left == .rising and !self.gui.isCursorInRect(dd_area)) {
                    self.drop_down = null;
                    return;
                }
                var buf: [256]u8 = undefined;
                var sb = StaticTextbox.init(&buf);
                if (try self.beginTlWindow(dd_area)) {
                    defer self.endTlWindow();

                    const ar = self.gui.getArea().?;
                    //self.gui.drawRectFilled(dd_area, Color.Red);
                    //const ar = dd_area.inset(14 * self.scale);
                    _ = try self.gui.beginLayout(Gui.SubRectLayout, .{ .rect = ar }, .{});
                    defer self.gui.endLayout();
                    const vl = try self.beginV();
                    defer self.endL();
                    const old_len = sb.len;
                    try self.textbox2(&sb, .{});
                    if (old_len != sb.len)
                        self.drop_down_scroll.y = 0;
                    vl.pushRemaining();
                    if (try self.beginScroll(&self.drop_down_scroll, .{ .sw = ar.w }, Gui.VerticalLayout{ .item_height = 20 * self.scale })) |file_scroll| {
                        defer self.endScroll(file_scroll, file_scroll.child.current_h);
                        while (next(ctx)) |fname| {
                            //inline for (enum_info.Enum.fields) |f| {
                            if (std.mem.startsWith(u8, fname[1], sb.getSlice())) {
                                if (self.buttonEx("{s}", .{fname[1]}, .{})) {
                                    index.* = fname[0];
                                    self.drop_down = null;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    pub fn enumCombo(self: *Self, comptime fmt: []const u8, args: anytype, enum_value: anytype) !void {
        const err_prefix = @typeName(@This()) ++ ".enumCombo: ";
        const invalid = err_prefix ++ "Argument \'enum_value\' expects a mutable pointer to an enum. Recieved: " ++ @typeName(@TypeOf(enum_value));
        const e_info = @typeInfo(@TypeOf(enum_value));
        if (e_info != .Pointer or e_info.Pointer.is_const) @compileError(invalid);
        const enum_type = e_info.Pointer.child;
        const enum_info = @typeInfo(enum_type);
        if (enum_info != .Enum) @compileError(invalid);
        const id = self.gui.getId();

        {
            const d = self.gui.buttonGeneric();
            const cb = self.style.getRect(.combo_background);
            self.gui.draw9Slice(d.area, cb, self.style.texture, self.scale);
            const texta = d.area.inset(cb.w / 3 * self.scale);
            self.gui.drawTextFmt(fmt, args, texta, texta.h, 0xff, .{ .justify = .center }, self.font);
            const cbb = self.style.getRect(.combo_button);
            const da = self.style.getRect(.down_arrow);
            const cbbr = d.area.replace(d.area.x + d.area.w - cbb.w * self.scale, null, cbb.w * self.scale, null).centerR(da.w * self.scale, da.h * self.scale);
            //const sp = d.area.split(.horizontal, @min(d.area.w, d.area.w - 16 * self.scale));
            //const right = sp[1];
            self.gui.drawRectTextured(cbbr, Color.White, da, self.style.texture);
            //const icon_rect =

            if (d.state == .click) {
                self.drop_down = id;
                self.drop_down_scroll = .{ .x = 0, .y = 0 };
                return;
            }
        }

        if (self.drop_down) |dd| {
            if (dd.eql(id)) {
                const scrth = self.style.config.enum_combo_item_count_scroll_threshold;
                const do_scroll = enum_info.Enum.fields.len > scrth;
                const pa = self.gui.layout.last_requested_bounds.?;
                const dd_area = graph.Rect.newV(pa.pos(), .{
                    .x = pa.w,
                    .y = if (do_scroll) pa.h * @as(f32, @floatFromInt(scrth)) else enum_info.Enum.fields.len * pa.h,
                });
                if (self.gui.input_state.mouse.left == .rising and !self.gui.isCursorInRect(dd_area)) {
                    self.drop_down = null;
                    return;
                }
                var buf: [256]u8 = undefined;
                var sb = StaticTextbox.init(&buf);
                if (try self.beginTlWindow(dd_area)) {
                    defer self.endTlWindow();

                    const ar = self.gui.getArea().?;
                    //self.gui.drawRectFilled(dd_area, Color.Red);
                    //const ar = dd_area.inset(14 * self.scale);
                    _ = try self.gui.beginLayout(Gui.SubRectLayout, .{ .rect = ar }, .{});
                    defer self.gui.endLayout();
                    const vl = try self.beginV();
                    defer self.endL();
                    const old_len = sb.len;
                    try self.textbox2(&sb, .{});
                    if (old_len != sb.len)
                        self.drop_down_scroll.y = 0;
                    vl.pushRemaining();
                    if (try self.beginScroll(&self.drop_down_scroll, .{ .sw = ar.w }, Gui.VerticalLayout{ .item_height = 20 * self.scale })) |file_scroll| {
                        defer self.endScroll(file_scroll, file_scroll.child.current_h);
                        inline for (enum_info.Enum.fields) |f| {
                            if (std.mem.startsWith(u8, f.name, sb.getSlice())) {
                                if (self.buttonEx("{s}", .{f.name}, .{})) {
                                    enum_value.* = @enumFromInt(f.value);
                                    self.drop_down = null;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    pub fn textboxNumber(self: *Self, number_ptr: anytype) !void {
        const gui = &self.gui;
        const inset = self.style.config.textbox_inset * self.scale;
        if (try gui.textboxNumberGeneric(number_ptr, self.font, .{ .text_inset = inset })) |d| {
            const tr = d.text_area;
            gui.draw9Slice(d.area, self.style.getRect(.basic_inset), self.style.texture, self.scale);
            if (d.is_invalid)
                gui.drawRectFilled(d.text_area, 0xff000086);
            gui.drawTextFmt("{s}", .{d.slice}, d.text_area, d.text_area.h, Color.Black, .{}, self.font);
            gui.drawRectFilled(Rect.new(
                d.selection_pos_min + d.text_area.x,
                d.text_area.y,
                d.selection_pos_max - d.selection_pos_min,
                d.text_area.h,
            ), 0x0000ff55);
            if (d.caret) |of| {
                gui.drawRectFilled(Rect.new(of + tr.x, tr.y + 2, 3, tr.h - 4), Color.Black);
            }
        }
    }

    //TODO
    //Option to treat an integer as decimal fixed point
    //floats in textboxes are messy
    //Support raw slices with alloc?
    //Have support for static buffers
    //
    //Fix the drawing of highlighted. Alpha problems
    //Support for "scrolling" the text if it is wider that the textbox
    //Make this function support numbers instead
    pub fn textbox2(self: *Self, tb: anytype, params: struct {
        disabled: bool = false,
        invalid: bool = false,
        make_active: bool = false,
        make_inactive: bool = false,
    }) !void {
        const gui = &self.gui;
        const inset = self.style.config.textbox_inset * self.scale;
        if (params.disabled) {
            const a = self.gui.getArea() orelse return;
            const tr = a.inset(inset);
            gui.draw9Slice(a, self.style.getRect(.basic_inset), self.style.texture, self.scale);
            gui.drawRectFilled(a, self.style.config.colors.textbox_bg_disabled);
            gui.drawTextFmt("{s}", .{tb.getSlice()}, tr, tr.h, self.style.config.colors.textbox_fg_disabled, .{}, self.font);
            return;
        }
        if (try gui.textboxGeneric2(tb, self.font, .{ .text_inset = inset, .make_active = params.make_active, .make_inactive = params.make_inactive })) |d| {
            const tr = d.text_area;
            gui.draw9Slice(d.area, self.style.getRect(.basic_inset), self.style.texture, self.scale);
            if (params.invalid)
                gui.drawRectFilled(tr, self.style.config.colors.textbox_invalid);
            gui.drawRectFilled(Rect.new(
                d.selection_pos_min + d.text_area.x,
                d.text_area.y,
                d.selection_pos_max - d.selection_pos_min,
                d.text_area.h,
            ), self.style.config.colors.text_highlight);
            if (d.caret) |of| {
                gui.drawRectFilled(
                    Rect.new(of + tr.x, tr.y + 2, self.style.config.textbox_caret_width, tr.h - 4),
                    self.style.config.colors.textbox_caret,
                );
            }
            gui.drawTextFmt("{s}", .{d.slice}, d.text_area, d.text_area.h, Color.Black, .{}, self.font);
        }
    }

    pub fn textView(self: *Self, font_height: f32, color: u32) ?struct {
        area: graph.Rect,
        fh: f32,
        line: f32 = 0,
        num_line: f32,
        color: u32,
        os9gui: *Self,

        pub fn text(tt: *@This(), comptime fmt: []const u8, args: anytype) void {
            tt.os9gui.gui.drawTextFmt(
                fmt,
                args,
                graph.Rec(tt.area.x, tt.area.y + tt.fh * tt.line, tt.area.w, tt.fh),
                tt.fh,
                tt.color,
                .{},
                tt.os9gui.font,
            );
            tt.line += 1;
        }
    } {
        const area = self.gui.getArea() orelse return null;
        self.gui.draw9Slice(area, self.style.getRect(.basic_inset), self.style.texture, self.scale);
        return .{
            .area = area.inset(3 * self.scale),
            .fh = font_height,
            .num_line = @trunc(area.h / font_height),
            .os9gui = self,
            .color = color,
        };
    }

    //TODO delete me and use textbox2
    pub fn textboxEx(self: *Self, contents: *std.ArrayList(u8), params: struct {
        disabled: bool = false,
        invalid: bool = false,
    }) !void {
        const gui = &self.gui;
        if (params.disabled) {
            const a = self.gui.getArea() orelse return;
            const tr = a.inset(3 * self.scale);
            gui.draw9Slice(a, self.style.getRect(.basic_inset), self.style.texture, self.scale);
            gui.drawTextFmt("{s}", .{contents.items}, tr, tr.h, 0x00aa, .{}, self.font);
            gui.drawRectFilled(a, 0xffffff75);
            return;
        }
        if (try gui.textboxGeneric(contents, self.font, .{ .text_inset = 3 * self.scale })) |d| {
            const tr = d.text_area;
            gui.draw9Slice(d.area, self.style.getRect(.basic_inset), self.style.texture, self.scale);
            if (params.invalid)
                gui.drawRectFilled(tr, 0xff0000ff);
            gui.drawRectFilled(Rect.new(
                d.selection_pos_min + d.text_area.x,
                d.text_area.y,
                d.selection_pos_max - d.selection_pos_min,
                d.text_area.h,
            ), 0x0000ff55);
            if (d.caret) |of| {
                gui.drawRectFilled(Rect.new(of + tr.x, tr.y + 2, 3, tr.h - 4), Color.Black);
            }
            gui.drawTextFmt("{s}", .{d.slice}, d.text_area, d.text_area.h, Color.Black, .{}, self.font);
        }
    }

    pub fn textbox(self: *Self, contents: *std.ArrayList(u8)) !void {
        try self.textboxEx(contents, .{});
    }
};

pub const GuiTest = struct {
    const Self = @This();
    const Fullname = struct {
        name: []const u8,
        surname: []const u8,
    };

    arr: std.ArrayList(u8),
    start_date: std.ArrayList(u8),
    end_date: std.ArrayList(u8),

    count: usize = 0,
    temp_f: f32 = 60,
    f_kind: std.fs.File.Kind = .file,

    child_pos: ?Vec2f = null,
    child_pos2: ?Vec2f = null,
    crass: Vec2f = .{ .x = 0, .y = 600 },

    is_popped: bool = false,

    flight_status: enum { one_way, return_flight } = .one_way,

    task: enum { counter, temp, flight, timer, crud } = .crud,
    timer: std.time.Timer,
    max_time: u64 = std.time.ns_per_s * 10,

    scroll: Vec2f = .{ .x = 0, .y = 0 },
    names: std.ArrayList(Fullname),
    name_box: std.ArrayList(u8),
    surname_box: std.ArrayList(u8),
    filter: std.ArrayList(u8),
    selected_index: ?usize = null,

    pub fn init(alloc: std.mem.Allocator) !Self {
        var ret = Self{
            .filter = std.ArrayList(u8).init(alloc),
            .name_box = std.ArrayList(u8).init(alloc),
            .surname_box = std.ArrayList(u8).init(alloc),
            .names = std.ArrayList(Fullname).init(alloc),
            .arr = std.ArrayList(u8).init(alloc),
            .start_date = std.ArrayList(u8).init(alloc),
            .end_date = std.ArrayList(u8).init(alloc),
            .timer = try std.time.Timer.start(),
        };
        const epsec = std.time.epoch.EpochSeconds{ .secs = @intCast(std.time.timestamp()) };
        const epday = epsec.getEpochDay();
        const epyear = epday.calculateYearDay();
        const epmday = epyear.calculateMonthDay();
        try ret.start_date.writer().print("{d:0>2}.{d:0>2}.{d}", .{ epmday.month.numeric(), epmday.day_index + 1, epyear.year });
        try ret.end_date.appendSlice(ret.start_date.items);
        try ret.names.appendSlice(&.{
            .{ .name = try alloc.dupe(u8, "crass"), .surname = try alloc.dupe(u8, "house") },
            .{ .name = try alloc.dupe(u8, "tony"), .surname = try alloc.dupe(u8, "santo") },
            .{ .name = try alloc.dupe(u8, "george"), .surname = try alloc.dupe(u8, "hh") },
        });
        return ret;
    }
    pub fn deinit(self: *Self) void {
        for (self.names.items) |n| {
            self.names.allocator.free(n.name);
            self.names.allocator.free(n.surname);
        }

        self.filter.deinit();
        self.name_box.deinit();
        self.surname_box.deinit();
        self.names.deinit();
        self.start_date.deinit();
        self.end_date.deinit();
        self.arr.deinit();
    }

    pub fn update(self: *Self, wrap: *Os9Gui) !void {
        const gui = &wrap.gui;
        const scale = wrap.scale;
        const area = gui.getArea() orelse return;
        gui.draw9Slice(area, wrap.style.getRect(.window_outer_small), wrap.style.texture, scale);
        const VLP = Gui.VerticalLayout{ .item_height = 20 * scale, .padding = .{ .bottom = 6 * scale } };
        var vl = try wrap.beginSubLayout(area.inset(6 * scale), Gui.VerticalLayout, VLP);
        defer wrap.endSubLayout();
        try wrap.enumCombo("Task: {s}", .{@tagName(self.task)}, &self.task);
        switch (self.task) {
            .counter => {
                _ = try gui.beginLayout(Gui.HorizLayout, .{ .count = 2 }, .{});
                defer gui.endLayout();
                wrap.labelEx("{d}", .{self.count}, .{});
                //try wrap.textbox(&self.arr);
                if (wrap.button("Count")) {
                    self.count += 1;
                }
            },
            .temp => {
                _ = try gui.beginLayout(Gui.HorizLayout, .{ .count = 4 }, .{});
                defer gui.endLayout();
                wrap.labelEx("Farenheit = ", .{}, .{});
                var temp_f = self.temp_f;
                try wrap.textboxNumber(&temp_f);
                if (temp_f != self.temp_f)
                    self.temp_f = temp_f;
                const temp_ci: f32 = (temp_f - 32) * (5.0 / 9.0);
                var temp_c = temp_ci;
                wrap.labelEx("Celsius = ", .{}, .{});
                try wrap.textboxNumber(&temp_c);
                if (temp_c != temp_ci)
                    self.temp_f = temp_c * (9.0 / 5.0) + 32;

                if (self.child_pos == null)
                    self.child_pos = area.pos();
                const c_area = graph.Rect.newV(self.child_pos.?, area.dim().smul(0.3));
                if (gui.isKeyDown(.SPACE) and gui.isCursorInRect(c_area)) {
                    self.child_pos.? = self.child_pos.?.add(gui.input_state.mouse.delta);
                }

                // C = (F - 32) * (5/9)
                //  F = C * (9/5) + 32.
                //try wrap.textbox(&self.arr);
            },
            .flight => {
                try wrap.enumCombo("Status: {s}", .{@tagName(self.flight_status)}, &self.flight_status);
                try wrap.textboxEx(&self.start_date, .{});
                try wrap.textboxEx(&self.end_date, .{ .disabled = self.flight_status == .one_way });
                if (wrap.button("Book")) {}
            },
            .timer => {
                const t = self.timer.read();
                const tt = if (t > self.max_time) self.max_time else t;
                blk: { //Custom widget inline
                    const a = gui.getArea() orelse break :blk;
                    gui.drawRectFilled(
                        graph.Rec(a.x, a.y, a.w * @as(f32, @floatFromInt(tt)) / @as(f32, @floatFromInt(self.max_time)), a.h),
                        0x44ff,
                    );
                }
                wrap.label("time: {d:.1}s", .{@as(f32, @floatFromInt(tt / std.time.ns_per_ms)) / 1000});
                wrap.slider(&self.max_time, 0, std.time.ns_per_s * 20);

                if (wrap.button("Reset")) {
                    self.timer.reset();
                }
            },
            .crud => {
                {
                    try wrap.textbox(&self.filter);
                    _ = try gui.beginLayout(Gui.HorizLayout, .{ .count = 3 }, .{});
                    defer gui.endLayout();
                    if (wrap.buttonEx("create", .{}, .{ .disabled = self.name_box.items.len == 0 or self.surname_box.items.len == 0 })) {
                        try self.names.append(.{
                            .name = try self.names.allocator.dupe(u8, self.name_box.items),
                            .surname = try self.names.allocator.dupe(u8, self.surname_box.items),
                        });
                        try self.name_box.resize(0);
                        try self.surname_box.resize(0);
                    }
                    if (wrap.buttonEx("update", .{}, .{ .disabled = self.selected_index == null })) {
                        const n = &self.names.items[self.selected_index.?];
                        self.names.allocator.free(n.surname);
                        self.names.allocator.free(n.name);
                        n.surname = try self.names.allocator.dupe(u8, self.surname_box.items);
                        n.name = try self.names.allocator.dupe(u8, self.name_box.items);
                    }
                    if (wrap.buttonEx("delete", .{}, .{ .disabled = self.selected_index == null })) {
                        const n = self.names.orderedRemove(self.selected_index.?);
                        self.names.allocator.free(n.surname);
                        self.names.allocator.free(n.name);
                        self.selected_index = if (self.selected_index.? > 0) self.selected_index.? - 1 else null;
                    }
                }
                vl.pushRemaining();
                {
                    _ = try gui.beginLayout(Gui.HorizLayout, .{ .count = 2 }, .{});
                    defer gui.endLayout();
                    if (try wrap.beginVScroll(&self.scroll, .{ .sw = gui.layout.last_requested_bounds.?.w / 2 })) |scroll| {
                        defer wrap.endVScroll(scroll);
                        gui.draw9Slice(scroll.area, wrap.style.getRect(.basic_inset), wrap.style.texture, scale);
                        var num_ommitted: usize = 0;
                        for (self.names.items, 0..) |n, i| {
                            if (std.mem.startsWith(u8, n.surname, self.filter.items)) {
                                wrap.label("{s}, {s}", .{ n.surname, n.name });
                                const lr = gui.layout.last_requested_bounds.?;
                                const click = gui.clickWidget(lr);
                                if (click == .click) {
                                    self.selected_index = i;
                                    self.name_box.clearRetainingCapacity();
                                    self.surname_box.clearRetainingCapacity();
                                    try self.name_box.appendSlice(n.name);
                                    try self.surname_box.appendSlice(n.surname);
                                }
                                if (self.selected_index) |si| {
                                    if (si == i)
                                        gui.drawRectFilled(lr, 0xff22);
                                }
                            } else {
                                num_ommitted += 1;
                            }
                        }
                        wrap.label("Filtered out: {d} results", .{num_ommitted});
                    }
                    {
                        _ = try gui.beginLayout(Gui.TableLayout, .{ .item_height = VLP.item_height, .columns = 2 }, .{});
                        defer gui.endLayout();
                        wrap.label("Name: ", .{});
                        try wrap.textbox(&self.name_box);
                        wrap.label("Surname: ", .{});
                        try wrap.textbox(&self.surname_box);
                    }
                }
            },
        }
    }
};

var os9_ctx: Os9Gui = undefined;

pub const Lua = struct {
    const Ls = ?*lua.lua_State;
    var zstring_buffer: [512]u8 = undefined;

    pub fn checkError(L: Ls, err: c_int) void {
        if (err != 0) {
            var len: usize = 0;
            const str = lua.lua_tolstring(L, 1, &len);
            std.debug.print("{s}\n", .{str[0..len]});
            lua.lua_pop(L, 1);
        }
    }

    pub export fn printStack(L: Ls) c_int {
        std.debug.print("STACK: \n", .{});
        const top = lua.lua_gettop(L);
        var i: i32 = 1;
        while (i <= top) : (i += 1) {
            const t = lua.lua_type(L, i);
            switch (t) {
                lua.LUA_TSTRING => std.debug.print("STRING: {s}\n", .{tostring(L, i)}),
                lua.LUA_TBOOLEAN => std.debug.print("BOOL: {any}\n", .{lua.lua_toboolean(L, i)}),
                lua.LUA_TNUMBER => std.debug.print("{d}\n", .{tonumber(L, i)}),
                else => std.debug.print("{s}\n", .{lua.lua_typename(L, t)}),
            }
        }
        std.debug.print("END STACK\n", .{});
        return 0;
    }

    pub fn tonumber(L: Ls, idx: c_int) lua.lua_Number {
        var is_num: c_int = 0;
        return lua.lua_tonumberx(L, idx, &is_num);
    }

    pub fn tostring(L: Ls, idx: c_int) []const u8 {
        var len: usize = 0;
        const str = lua.lua_tolstring(L, idx, &len);
        return str[0..len];
    }

    pub fn zstring(str: []const u8) [*c]const u8 {
        @memcpy(zstring_buffer[0..str.len], str);
        zstring_buffer[str.len] = 0;
        return &zstring_buffer[0];
    }

    pub fn register(L: Ls) void {
        lua.lua_register(L, "printStack", printStack);
        lua.lua_register(L, "label", Lua.label);
        lua.lua_register(L, "checkbox", Lua.checkbox);
        lua.lua_register(L, "getArea", Lua.getArea);
        lua.lua_register(L, "beginV", Lua.beginVertical);
        lua.lua_register(L, "pushHeight", Lua.pushHeight);
        lua.lua_register(L, "endV", Lua.endVertical);
        lua.lua_register(L, "button", Lua.button);
        lua.lua_register(L, "slider", Lua.slider);
        lua.lua_register(L, "getStruct", getStruct);
        lua.lua_register(L, "giveData", giveData);
    }

    fn getArg(L: Ls, comptime s: type, idx: c_int) s {
        const in = @typeInfo(s);
        return switch (in) {
            .Float => @floatCast(lua.luaL_checknumber(L, idx)),
            .Int => std.math.lossyCast(s, lua.luaL_checkinteger(L, idx)),
            .Enum => blk: {
                var len: usize = 0;
                const str = lua.luaL_checklstring(L, idx, &len);
                const h = std.hash.Wyhash.hash;
                inline for (in.Enum.fields) |f| {
                    if (h(0, f.name) == h(0, str[0..len])) {
                        break :blk @enumFromInt(f.value);
                    }
                }
            },
            .Bool => lua.lua_toboolean(L, idx) == 1,
            .Pointer => |p| {
                if (p.child == u8 and p.size == .Slice) {
                    var len: usize = 0;
                    const str = lua.luaL_checklstring(L, idx, &len);
                    //defer lua.lua_pop(L, 1);
                    return os9_ctx.gui.storeString(str[0..len]);
                } else {
                    @compileError("Can't get slice from lua " ++ p);
                }
            },
            .Struct => {
                var ret: s = undefined;
                inline for (in.Struct.fields) |f| {
                    const lt = lua.lua_getfield(L, idx, zstring(f.name));
                    @field(ret, f.name) = switch (lt) {
                        lua.LUA_TNIL => if (f.default_value) |d| @as(*const f.type, @ptrCast(@alignCast(d))).* else undefined,
                        else => getArg(L, f.type, -1),
                    };
                    lua.lua_pop(L, 1);
                }
                return ret;
            },
            else => @compileError("getV type not supported " ++ @typeName(s)),
        };
    }

    pub fn getGlobal(L: Ls, name: []const u8, comptime s: type) s {
        _ = lua.lua_getglobal(L, zstring(name));
        switch (@typeInfo(s)) {
            .Struct => {
                return getArg(L, s, 1);
            },
            else => @compileError("not supported"),
        }
    }

    fn pushV(L: Ls, s: anytype) void {
        const info = @typeInfo(@TypeOf(s));
        switch (info) {
            .Struct => |st| {
                lua.lua_newtable(L);
                inline for (st.fields) |f| {
                    _ = lua.lua_pushstring(L, zstring(f.name));
                    pushV(L, @field(s, f.name));
                    lua.lua_settable(L, -3);
                }
            },
            .Enum => {
                const str = @tagName(s);
                _ = lua.lua_pushlstring(L, zstring(str), str.len);
            },
            .Float => lua.lua_pushnumber(L, s),
            .Bool => lua.lua_pushboolean(L, if (s) 1 else 0),
            .Int => lua.lua_pushinteger(L, std.math.lossyCast(i64, s)),
            .Pointer => |p| {
                if (p.child == u8 and p.size == .Slice) {
                    _ = lua.lua_pushlstring(L, zstring(s), s.len);
                } else {
                    @compileError("Can't send slice to lua " ++ p);
                }
            },
            else => @compileError("don't work"),
        }
    }

    pub export fn getStruct(L: Ls) c_int {
        pushV(L, MyStruct{});
        return 1;
    }

    pub export fn giveData(L: Ls) c_int {
        lua.lua_settop(L, 2);
        const d2 = getArg(L, f32, 1);
        const d3 = getArg(L, struct { num: f32, name: []const u8 }, 2);
        lua.lua_pop(L, 2);
        std.debug.print("{any} {any}\n", .{ d2, d3 });
        return 0;
    }

    pub export fn checkbox(L: Ls) c_int {
        lua.lua_settop(L, 2);
        const str = getArg(L, []const u8, 1);
        var boolean = getArg(L, bool, 2);
        _ = os9_ctx.checkbox(str, &boolean);
        pushV(L, boolean);
        return 1;
    }

    pub export fn getArea(L: Ls) c_int {
        const area = os9_ctx.gui.getArea();
        if (area) |a| {
            pushV(L, a);
            return 1;
        }
        return 0;
    }

    pub export fn beginVertical(L: Ls) c_int {
        _ = L;
        os9_ctx.vlayout = os9_ctx.gui.beginLayout(Gui.VerticalLayout, .{ .item_height = 20 * os9_ctx.scale, .padding = .{ .bottom = 6 * os9_ctx.scale } }, .{}) catch unreachable;
        return 0;
    }

    pub export fn pushHeight(L: Ls) c_int {
        lua.lua_settop(L, 1);
        const n = getArg(L, f32, 1);
        if (os9_ctx.vlayout) |vl| {
            vl.pushHeight(@floatCast(n));
        }
        return 0;
    }

    pub export fn endVertical(L: Ls) c_int {
        _ = L;
        os9_ctx.gui.endLayout();
        os9_ctx.vlayout = null;
        return 0;
    }

    pub export fn slider(L: Ls) c_int {
        lua.lua_settop(L, 1);
        //lua.lua_checktype(L, 1, lua.LUA_TTABLE);

        _ = lua.lua_getfield(L, 1, "val");
        var val: f64 = lua.luaL_checknumber(L, -1);
        os9_ctx.slider(&val, 0, 100);
        lua.lua_pushnumber(L, val);
        lua.lua_setfield(L, 1, "val");

        return 0;
    }

    pub export fn button(L: Ls) c_int {
        lua.lua_settop(L, 1);
        const str = getArg(L, []const u8, 1);
        pushV(L, os9_ctx.button(str));
        return 1;
    }

    pub export fn label(L: Ls) c_int {
        lua.lua_settop(L, 1);
        const str = getArg(L, []const u8, 1);
        os9_ctx.label("{s}", .{str});
        return 0;
    }
};

pub const TestConfig = struct {
    tab: enum { ptable, other, math } = .ptable,
    my_int: i32 = 0,
    my_color: graph.Hsva = graph.Hsva.fromInt(0xef8825ff),
    my_bool: bool = false,
    item_height: f32 = 30,
    scale: f32 = 0.5,
    win_inset: f32 = 24,
    padding: graph.Padding = graph.Padding.new(12, 0, 12, 12),
    filek: std.fs.File.Kind = .file,
};
//TODO I want to try to ship a working version of Os9gui.
//ImmediateDrawingContext is a required part of the Gui draw process.
//Force Sdl backend? Ideally not.
//Asset loading. Embed a default font and style atlas. The library is already structered in a way that sortof allows for custom styling.
//
//TODO write a gui testbed, should showcase all the features, be easy to copy and paste working examples
//current usage
//ogui = Os9gui.init(alloc);
//
//while window_good
//  ogui.beginFrame(input_state)
//      ogui.beginTlWindow(area);
//          beginlayout
//              widget
//              widget
//              widget
//          endlayout
//      osgui.endTlWindow();
//
//  ogui.endFrame()

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .retain_metadata = true, .never_unmap = false, .verbose_log = false, .stack_trace_frames = 8 }){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    var current_app: enum { keyboard_display, filebrowser, gtest, crass, game_menu } = .crass;
    var arg_it = try std.process.ArgIterator.initWithAllocator(alloc);
    defer arg_it.deinit();
    const Arg = ArgUtil.Arg;
    const cli_opts = try (ArgUtil.parseArgs(&.{
        Arg("scale", .number, "The scale of the gui"),
        Arg("wireframe", .flag, "draw in wireframe"),
        ArgUtil.ArgCustom("app", @TypeOf(current_app), "Which gui app to run"),
    }, &arg_it));

    if (cli_opts.app) |app|
        current_app = app;

    const scale = if (cli_opts.scale) |s| s else 2.0;
    var win = try graph.SDL.Window.createWindow("My window", .{
        .double_buffer = true,
        .window_flags = &.{
            graph.c.SDL_WINDOW_BORDERLESS,
            graph.c.SDL_WINDOW_UTILITY,
        },
        .window_size = .{ .x = 1920, .y = 1080 },
    });
    defer win.destroyWindow();
    var debug_dir = try std.fs.cwd().makeOpenPath("debug", .{});
    defer debug_dir.close();

    //var cwin = try win.createChildWindow("HELLO", 1000, 500);
    //defer cwin.deinit();

    graph.c.glLineWidth(1);

    //const init_size = graph.pxToPt(win.getDpi(), 100);
    // var font = try graph.Font.init(alloc, std.fs.cwd(), "fonts/roboto.ttf", init_size, .{
    //     .debug_dir = debug_dir,
    // });
    // defer font.deinit();
    var my_str = std.ArrayList(u8).init(alloc);
    defer my_str.deinit();

    Gui.hash_timer = try std.time.Timer.start();
    Gui.hash_time = 0;

    var draw = graph.ImmediateDrawingContext.init(alloc);
    defer draw.deinit();

    //var draw_line_debug: bool = false;

    const gui_frac: f32 = 0.3;
    _ = gui_frac * 0.1;
    var gui_timer = try std.time.Timer.start();
    var gui_time: u64 = 0;
    //var dcall_count: usize = 0;

    const conf_dir = blk: {
        //const dir = win.getPrefPath("nik_org", "test_gui");
        //if (dir) |dd| {
        //    break :blk try std.fs.openDirAbsoluteZ(dd, .{});
        //}
        break :blk std.fs.cwd();
    };
    //defer conf_dir.close();

    var staticbuf: [16]u8 = undefined;
    var statictb = Os9Gui.StaticTextbox.init(&staticbuf);
    var dyn_tb = Os9Gui.DynamicTextbox.init(alloc);
    defer dyn_tb.deinit();

    var fb = try FileBrowser.init(alloc, conf_dir);
    defer fb.deinit();

    var kbd = KeyboardDisplay.init(alloc);
    defer kbd.deinit();

    var gt = try GuiTest.init(alloc);
    defer gt.deinit();

    var os9gui = try Os9Gui.init(alloc, std.fs.cwd(), scale);
    defer os9gui.deinit();

    //var os9gui2 = try Os9Gui.init(alloc, std.fs.cwd(), scale);
    //defer os9gui2.deinit();

    var gamemenu = GameMenu.init(alloc);
    defer gamemenu.deinit();

    //NEEDS TO BE SET BEFORE LUA RUNS
    os9_ctx = os9gui;
    //BEGIN LUA
    //const L = lua.luaL_newstate();
    //lua.luaL_openlibs(L);
    //Lua.register(L);
    //const lf = lua.luaL_loadfilex(L, "script.lua", "bt");
    //Lua.checkError(L, lua.lua_pcallk(L, 0, lua.LUA_MULTRET, 0, 0, null));
    //_ = lf;
    //const lparam = Lua.getGlobal(L, "params", struct { window_x: i32, window_y: i32, scale: f32 });
    //win.setWindowSize(lparam.window_x, lparam.window_y);
    win.centerWindow();

    var tc: TestConfig = .{};
    var crass_scroll: graph.Vec2f = .{ .x = 0, .y = 0 };

    //END LUA
    win.pumpEvents(.poll);

    if (cli_opts.wireframe != null)
        graph.c.glPolygonMode(graph.c.GL_FRONT_AND_BACK, graph.c.GL_LINE);
    while (!win.should_exit) {
        try draw.begin(0x2f2f2fff, win.screen_dimensions.toF());
        win.pumpEvents(.wait); //Important that this is called after beginDraw for input lag reasons

        const win_rect = graph.Rect.newV(.{ .x = 0, .y = 0 }, draw.screen_dimensions);
        gui_timer.reset();
        Gui.hash_time = 0;
        const is: Gui.InputState = .{ .mouse = win.mouse, .key_state = &win.key_state, .keys = win.keys.slice(), .mod_state = win.mod };
        const def_is: Gui.InputState = .{};
        try os9gui.beginFrame(if (graph.c.SDL_GetMouseFocus() == win.win) is else def_is, &win);

        gui_time = gui_timer.read();

        //if (win.keydown(.LSHIFT) and win_rect.containsPoint(win.mouse.pos)) {
        //    win_rect.x += win.mouse.delta.x;
        //    win_rect.y += win.mouse.delta.y;
        //}
        //if (win.keydown(.SPACE) and win_rect.containsPoint(win.mouse.pos)) {
        //    win_rect.w += win.mouse.delta.x;
        //    win_rect.h += win.mouse.delta.y;
        //}

        if (try os9gui.beginTlWindow(win_rect)) {
            defer os9gui.endTlWindow();

            switch (try os9gui.beginTabs(&current_app)) {
                .keyboard_display => try kbd.update(&os9gui),
                //.lua_test => try luaTest(alloc: std.mem.Allocator),
                .gtest => {
                    if (os9gui.gui.getArea()) |winar| {
                        os9gui.gui.drawRectTextured(
                            winar,
                            0xffffffff,
                            os9gui.font.texture.rect(),
                            os9gui.font.texture,
                        );
                    }
                    //try gt.update(&os9gui);
                },
                .filebrowser => {
                    try fb.update(&os9gui);
                    switch (fb.flag) {
                        .should_exit => win.should_exit = true,
                        .ok_clicked => {
                            if (fb.file) |f| {
                                std.debug.print("Trying to open file: {s}\n", .{f.file_name});
                                win.should_exit = true;
                            }
                        },
                        else => {},
                    }
                },
                .crass => {
                    const gui = &os9gui.gui;
                    if (gui.getArea()) |win_area| {
                        const area = win_area.inset(6 * os9gui.scale);
                        _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = area }, .{});
                        defer gui.endLayout();
                        if (try os9gui.beginVScroll(&crass_scroll, .{ .sw = area.w })) |scr| {
                            defer os9gui.endVScroll(scr);
                            os9gui.slider(&tc.scale, 0.1, 4);
                            os9gui.slider(&tc.my_int, -10, 10);
                            try os9gui.textboxNumber(&tc.my_int);
                            try os9gui.radio(&tc.tab);
                            try os9gui.colorPicker(&tc.my_color);
                            try os9gui.rat();

                            try os9gui.enumCombo("filek", .{}, &tc.filek);
                            try os9gui.textboxNumber(&tc.scale);
                            _ = os9gui.checkbox("MY CHECK", &tc.my_bool);
                            try os9gui.textboxNumber(&tc.win_inset);
                            try os9gui.textbox(&my_str);
                            try os9gui.textbox2(&statictb, .{});
                            try os9gui.textbox2(&dyn_tb, .{
                                .disabled = os9gui.buttonEx("Disable box", .{}, .{ .continuous = true }),
                            });
                            scr.layout.pushHeight(os9gui.propertyTableHeight(&tc));
                            switch (try os9gui.beginTabs(&tc.tab)) {
                                .ptable => {
                                    try os9gui.propertyTable(&tc);
                                },
                                else => {},
                            }
                            os9gui.endTabs();
                            scr.layout.pushHeight(os9gui.propertyTableHeight(&os9gui.style.config));
                            try os9gui.propertyTable(&os9gui.style.config);
                        }
                    }
                },
                .game_menu => try gamemenu.update(&os9gui),
            }
            os9gui.endTabs();
            //if(false){
            //try gui.beginWindow(graph.Rec(0, 0, 1000, 1000));
            //    defer gui.endWindow();
            //    const a = gui.getArea() orelse unreachable;
            //    const s = tc.scale;
            //    gui.draw9Slice(a, o_win, ass.texture, s);
            //    _ = o_inwin;
            //    gui.draw9Slice(a.inset(tc.win_inset * s), o_bg, ass.texture, s);
            //    _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = a.inset(tc.win_inset * s) }, .{});
            //    defer gui.endLayout();
            //    _ = try gui.beginLayout(Gui.VerticalLayout, .{
            //        .item_height = tc.item_height,
            //        .padding = tc.padding,
            //    }, .{});
            //    defer gui.endLayout();
            //    gui.draw9Slice(gui.getArea().?, o_tb, ass.texture, s);
            //    gui.draw9Slice(gui.getArea().?, o_tb, ass.texture, s);
            //    gui.draw9Slice(gui.getArea().?, o_win, ass.texture, s);
            //}
        }

        //if (false) {
        //    var node = gui.layout_cache.first;
        //    const rr = sp[0];
        //    const ix = rr.x;
        //    var cursor = Rec(ix, rr.y, rr.w / 5, 40);
        //    while (node) |n| : (node = n.next) {
        //        var color: u32 = 0xffffffff;
        //        if (n.data.rec.containsPoint(win.mouse.pos)) {
        //            color = 0xff0000ff;
        //            if (win.keydown(.A)) {
        //                draw.rect(n.data.rec, 0xff55);
        //            }
        //        }

        //        cursor.x = ix + F(n.depth) * 100;
        //        draw.rect(cursor.inset(4), color);
        //        cursor.y += cursor.h;
        //    }
        //}

        try os9gui.endFrame(&draw);
        graph.c.glDisable(graph.c.GL_STENCIL_TEST);

        //draw.rectTex(graph.Rec(0, 0, 400, 400), graph.Rec(0, 0, 4000, 4000), os9gui.ofont.font.texture);
        //draw.rectTex(os9gui.ofont.font.texture.rect(), os9gui.ofont.font.texture.rect(), os9gui.ofont.font.texture);
        try draw.end(null);
        win.swap();

        //if (graph.c.SDL_GetMouseFocus() == cwin.win) {
        //    _ = graph.c.SDL_GL_MakeCurrent(cwin.win, win.ctx);
        //    defer _ = graph.c.SDL_GL_MakeCurrent(win.win, win.ctx);
        //    const rec = graph.Rec(0, 0, 1000, 500);
        //    try draw.begin(0x2f2f2fff, rec.dim());
        //    try os9gui2.beginFrame(if (graph.c.SDL_GetMouseFocus() == cwin.win) is else def_is, &win);
        //    if (try os9gui2.beginTlWindow(rec)) {
        //        defer os9gui2.endTlWindow();
        //        try os9gui2.propertyTable(&os9gui.style.config);
        //    }
        //    try os9gui2.endFrame(&draw);
        //    graph.c.glDisable(graph.c.GL_STENCIL_TEST);
        //    //draw.text(.{.x = 0, .y = 0}, "hello world", &font, 40, (t.color));
        //    try draw.end(null);
        //    graph.c.SDL_GL_SwapWindow(cwin.win);
        //}
    }
}
