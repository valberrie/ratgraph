const std = @import("std");
const graph = @import("graphics.zig");
const Rect = graph.Rect;
const Rec = graph.Rec;
const itc = graph.itc;
const Pad = graph.Padding;

const Color = graph.CharColor;
//const Gui = @import("gui.zig");
const Gui = graph.Gui;
const Vec2f = graph.Vec2f;

const bg1 = itc(0xff);
const fg = itc(0xffffffff);
const bg4 = itc(0xff);
const bg2 = itc(0xff);
const bg0 = itc(0xff);

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

    check = 0xEB7B,
    erasor = 0xEC9F,
    pencil = 0xEFDF,

    pub fn get(icon: Icons) u21 {
        return @intFromEnum(icon);
    }
};

pub const FileBrowser = struct {
    const Self = @This();

    pub const Extensions = enum {
        png,
        bmp,
        json,
        txt,
        zig,
        unknown,
    };

    pub const Bookmark = struct {
        abs_path: []const u8,
        name: []const u8,
    };

    pub const DirEntry = struct {
        pub const CompareContext = struct {
            ascending: bool = true,
            column_kind: ColumnKind,
        };
        name: []const u8,
        size: u64 = 0,
        kind: std.fs.File.Kind,
        mtime: u64 = 0,

        fn compare(ctx: CompareContext, lhs: DirEntry, rhs: DirEntry) bool {
            switch (ctx.column_kind) {
                .name => {
                    if (ctx.ascending) {
                        return std.ascii.lessThanIgnoreCase(lhs.name, rhs.name);
                    } else {
                        return std.ascii.lessThanIgnoreCase(rhs.name, lhs.name);
                    }
                },
                .ftype => {
                    const lt = @intFromEnum(lhs.kind) < @intFromEnum(rhs.kind);
                    return if (ctx.ascending) lt else !lt;
                },
                .size => {
                    const lt = lhs.size < rhs.size;
                    return if (ctx.ascending) lt else !lt;
                },
                .mtime => {
                    const lt = lhs.mtime < rhs.mtime;
                    return if (ctx.ascending) lt else !lt;
                },
            }
            return false;
        }
    };

    pub const ColumnKind = enum { size, name, mtime, ftype };

    pub const FileColumn = struct {
        kind: ColumnKind,
        width: f32,
    };

    pub const PersistSettings = struct {
        column_widths: []f32,
        show_hidden: bool = false,
    };

    alloc: std.mem.Allocator,
    entries: std.ArrayList(DirEntry),
    dir: std.fs.Dir,
    file: ?struct { file_name: []const u8, dir: std.fs.Dir } = null,

    file_scroll: graph.Vec2f = .{ .x = 0, .y = 0 },

    selected_bookmark: ?usize = null,
    selected: ?usize = null,
    show_hidden: bool = true,

    path_str: ?[]const u8 = null,

    bookmarks: []const Bookmark = &.{
        .{ .name = "Home", .abs_path = "/home/tony" },
        .{ .name = "Gui repo", .abs_path = "/home/tony/user-data/develpment/zig-gui" },
        .{ .name = "Mario", .abs_path = "/home/tony/user-data/develpment/zig-game_engine/mario_assets" },
    },

    columns: [4]FileColumn = [_]FileColumn{
        .{ .width = 200, .kind = .name },
        .{ .width = 400, .kind = .mtime },
        .{ .width = 400, .kind = .size },
        .{ .width = 200, .kind = .ftype },
    },

    sorted_column_index: usize = 0,
    sorted_column_ascending: bool = true,

    conf_dir: std.fs.Dir,

    pub fn init(alloc: std.mem.Allocator, settings_dir: std.fs.Dir) !Self {
        const cwd = std.fs.cwd();
        var file: ?std.fs.File = settings_dir.openFile("file_browser_config.json", .{}) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        var ret = Self{ .alloc = alloc, .entries = std.ArrayList(DirEntry).init(alloc), .dir = cwd, .conf_dir = settings_dir };

        if (file) |f| {
            const jslice = try f.readToEndAlloc(alloc, std.math.maxInt(usize));
            defer alloc.free(jslice);
            const json_p = try std.json.parseFromSlice(PersistSettings, alloc, jslice, .{ .allocate = .alloc_always });
            defer json_p.deinit();

            ret.show_hidden = json_p.value.show_hidden;
            for (json_p.value.column_widths, 0..) |cw, i| {
                if (i < ret.columns.len)
                    ret.columns[i].width = cw;
            }
        }

        try ret.popuplate_entries();

        return ret;
    }

    pub fn deinit(self: *Self) void {
        blk: {
            var widths = self.alloc.alloc(f32, self.columns.len) catch break :blk;
            defer self.alloc.free(widths);
            for (self.columns, 0..) |col, i| {
                widths[i] = col.width;
            }
            const persist = PersistSettings{ .column_widths = widths, .show_hidden = self.show_hidden };
            var out_file = self.conf_dir.createFile("file_browser_config.json", .{}) catch break :blk;
            defer out_file.close();
            std.json.stringify(persist, .{}, out_file.writer()) catch break :blk;
        }
        for (self.entries.items) |item| {
            self.alloc.free(item.name);
        }
        self.entries.deinit();
        if (self.path_str) |str|
            self.alloc.free(str);
    }

    pub fn sort_entries(self: *Self, ctx: DirEntry.CompareContext) void {
        std.sort.insertion(DirEntry, self.entries.items, ctx, DirEntry.compare);
    }

    pub fn popuplate_entries(self: *Self) !void {
        self.file_scroll = .{ .x = 0, .y = 0 };
        var it_dir = self.dir.openIterableDir(".", .{}) catch {
            self.dir = try self.dir.openDir("..", .{});
            self.clear_entries();
            try self.popuplate_entries();
            return;
        };
        defer it_dir.close();
        var it = it_dir.iterate();
        var o_item = try it.next();
        while (o_item) |item| : (o_item = try it.next()) {
            if (!self.show_hidden) {
                if (item.name.len > 0 and item.name[0] == '.') {
                    continue;
                }
            }
            const alloc_name = try self.alloc.alloc(u8, item.name.len);
            std.mem.copy(u8, alloc_name, item.name);
            const stat = self.dir.statFile(item.name) catch null;
            if (stat) |s| {
                try self.entries.append(.{ .name = alloc_name, .kind = item.kind, .mtime = @intCast(@divFloor(s.mtime, std.time.ns_per_s)), .size = s.size });
            } else {
                try self.entries.append(.{
                    .name = alloc_name,
                    .kind = item.kind,
                });
            }
        }

        self.sorted_column_index = 0;
        self.sorted_column_ascending = true;
        self.sort_entries(.{ .ascending = true, .column_kind = .name });
        if (self.path_str) |str| {
            self.alloc.free(str);
        }
        self.path_str = try self.dir.realpathAlloc(self.alloc, ".");
    }

    pub fn clear_entries(self: *Self) void {
        for (self.entries.items) |item| {
            self.alloc.free(item.name);
        }
        self.entries.deinit();
        self.entries = std.ArrayList(DirEntry).init(self.alloc);
    }

    fn getExtension(name: []const u8) Extensions {
        if (std.mem.lastIndexOfScalar(u8, name, '.')) |index| {
            const ext = name[index + 1 .. name.len];
            const info = @typeInfo(Extensions);
            inline for (info.Enum.fields, 0..) |field, i| {
                if (std.mem.eql(u8, field.name, ext))
                    return @enumFromInt(i);
            }
        }
        return .unknown;
    }

    fn fileItem(self: *Self, gui: *Gui.Context, entry: DirEntry, index: usize, columns: []const FileColumn) !bool {
        const rec = gui.getArea() orelse return true;
        var cx: f32 = 0;
        if (index == self.selected)
            gui.drawRectFilled(rec, bg1);
        for (columns) |col| {
            const r = graph.Rec(rec.x + cx, rec.y, col.width, rec.h);
            defer cx += col.width; //defer so continue; still applies width
            switch (col.kind) {
                .name => {
                    const ico = graph.Rec(rec.x, rec.y, rec.h, rec.h);
                    gui.drawIcon(Icons.get(switch (entry.kind) {
                        .directory => .folder,
                        .sym_link => .folder_link,
                        .file => switch (getExtension(entry.name)) {
                            .zig, .json => .src_file,
                            .png, .bmp => .img_file,
                            .txt => .txt_file,
                            else => .file,
                        },
                        else => .file,
                    }), .{ .x = ico.x, .y = ico.y + ico.h / 3 }, ico.h * 0.7, fg);
                    const ir = graph.Rec(r.x + ico.w, r.y, r.w - ico.w, r.h);
                    if (gui.font.nearestGlyphX(entry.name, rec.h, .{ .x = col.width - ico.w, .y = rec.h / 2 })) |glyph_index| {
                        if (glyph_index > 2)
                            gui.drawTextFmt("{s}…", .{entry.name[0 .. glyph_index - 2]}, ir, rec.h, fg, .{});
                    } else {
                        gui.drawTextFmt("{s}", .{entry.name}, ir, rec.h, fg, .{});
                    }
                    //const b = gui.font.textBounds(entry.name.len, rec.h);
                    //const trunc = b.y > ;
                    //const str = if (trunc) entry.name[0..max_chars] else entry.name;
                    //gui.drawTextFmt("{s}{u}", .{ str, if (trunc) @as(u21, 0x2026) else ' ' }, graph.Rec(r.x + ico.w, r.y, r.w - ico.w, r.h), rec.h, fg, .{});
                },
                .size => {
                    if (entry.kind != .file)
                        continue;
                    const s = entry.size;
                    //how to fmt?
                    //we have a 64 bit int
                    //10 bits > kilo
                    //20 bits > mega
                    //

                    const val = switch (64 - @clz(s)) {
                        0...10 => .{ s, "b" },
                        11...20 => .{ s >> 10, "K" },
                        21...30 => .{ s >> 20, "M" },
                        31...40 => .{ s >> 30, "G" },
                        41...50 => .{ s >> 40, "T" },
                        51...60 => .{ s >> 50, "P" },
                        61...64 => .{ s >> 60, "E" },
                        else => .{ s, "" },
                    };
                    gui.drawTextFmt("{d: >3}{s}", .{ val[0], val[1] }, r, rec.h, fg, .{});
                },
                .mtime => {
                    const epsec = std.time.epoch.EpochSeconds{ .secs = entry.mtime };
                    const epday = epsec.getEpochDay();
                    const epyear = epday.calculateYearDay();
                    const epmday = epyear.calculateMonthDay();
                    gui.drawTextFmt("{d:0>2}/{d:0>2}/{d}", .{
                        epmday.month.numeric(),
                        @as(u16, epmday.day_index) + 1,
                        epyear.year,
                    }, r, r.h * 0.8, fg, .{});
                },
                .ftype => {
                    gui.drawTextFmt("{s}", .{@tagName(entry.kind)}, r, r.h * 0.8, fg, .{});
                },
            }
        }
        //const time_rec = graph.Rec(rec.x + rec.w / 2, rec.y, rec.w / 4, rec.h);
        //const type_rec = graph.Rec(time_rec.x + time_rec.w, time_rec.y, time_rec.w, rec.h);

        const click = gui.clickWidget(rec, .{});
        if (click == .click) {
            self.selected = index;
        }

        if (click == .double) {
            switch (entry.kind) {
                .directory => {
                    self.file_scroll = .{ .x = 0, .y = 0 };
                    if (self.dir.openDir(entry.name, .{}) catch null) |new_dir| {
                        self.dir = new_dir;
                        self.clear_entries();
                        try self.popuplate_entries();
                        return true;
                    }
                },
                .file => {
                    self.file = .{ .file_name = entry.name, .dir = self.dir };
                },
                else => {},
            }
        }
        return false;
    }

    pub fn update(self: *Self, gui: *Gui.Context) !void {
        const item_height = 35;
        const area = gui.getArea() orelse return;
        const header_bar = graph.Rec(area.x, area.y, area.w, area.h / 5);
        const mid_panel = graph.Rec(area.x, area.y + header_bar.h, area.w, area.h / 5 * 3);
        const left_side = graph.Rec(mid_panel.x, mid_panel.y, mid_panel.w / 5, mid_panel.h);
        //const main_area = graph.Rec(mid_panel.x + left_side.w, mid_panel.y, mid_panel.w - left_side.w, mid_panel.h);
        const prev_w = mid_panel.w / 3;
        const main_area = graph.Rec(mid_panel.x + left_side.w, mid_panel.y, mid_panel.w - left_side.w - prev_w, mid_panel.h);
        const prev_area = graph.Rec(main_area.x + main_area.w, main_area.y, prev_w, main_area.h);
        const bottom_bar = graph.Rec(area.x, mid_panel.y + mid_panel.h, area.w, area.h / 5);
        gui.drawRectFilled(area, bg4);

        {
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = header_bar }, .{});
            //gui.drawRectOutline(header_bar, Color.Black);
            defer gui.endLayout();
            var vlayout = try gui.beginLayout(Gui.VerticalLayout, .{ .item_height = item_height }, .{});
            defer gui.endLayout();
            _ = vlayout;
            try gui.printLabel("File Browser", .{});
            try gui.printLabel("Path: {s}", .{if (self.path_str) |str| str else ""});
        }
        {
            const ls = left_side.inset(5);
            gui.drawRectFilled(ls, bg2);
            gui.drawRectOutline(ls, bg2);
            const ils = ls.inset(1);
            { //header bar
                _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = graph.Rec(ils.x, ils.y, ils.w, item_height) }, .{});
                defer gui.endLayout();
                gui.textLabel("Places");
            }
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = graph.Rec(ils.x, ils.y + item_height, ils.w, ils.h - item_height) }, .{});
            defer gui.endLayout();
            var vlayout = try gui.beginLayout(Gui.VerticalLayout, .{ .item_height = item_height }, .{});
            defer gui.endLayout();
            _ = vlayout;
            for (self.bookmarks, 0..) |bookmark, i| {
                const rec = gui.getArea() orelse break;
                if (self.selected_bookmark) |sb| {
                    if (sb == i)
                        gui.drawRectFilled(rec, bg1);
                }
                const vpad = rec.h * 0.1;
                const tpos = graph.Vec2f.new(rec.x, rec.y + vpad);
                gui.drawText(bookmark.name, tpos, rec.h - vpad * 2, fg);
                const click = gui.clickWidget(rec, .{});
                if (click == .click) {
                    self.selected_bookmark = i;
                    self.dir = try std.fs.openDirAbsolute(bookmark.abs_path, .{});
                    self.clear_entries();
                    try self.popuplate_entries();
                }
            }
        }
        {
            const ma = main_area.inset(5);
            gui.drawRectFilled(ma, bg2);
            gui.drawRectOutline(ma, bg2);
            const ima = ma.inset(3);
            {
                _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = graph.Rec(ima.x, ima.y, ima.w, item_height) }, .{});
                defer gui.endLayout();
                const rec = gui.getArea() orelse return;
                gui.drawRectFilled(rec, bg4);
                var cx: f32 = 0;
                for (&self.columns, 0..) |*cc, i| {
                    if (i == self.columns.len - 1) //We can't adjust the last columns width
                        break;
                    const hw = 8;
                    const old_w = cc.width;
                    var handle = graph.Rec(rec.x + cx + cc.width - hw, rec.y, hw, rec.h);
                    //var evil: f32 = 0;
                    //const d = gui.draggable(handle, .{ .x = 1, .y = 0 }, &cc.width, &evil, .{ .x_min = rec.h * 5, .x_max = rec.w });
                    //if (d == .hover or d == .held or d == .click)
                    //    gui.trySetCursor(.size_WE);

                    handle.x += -old_w + cc.width;
                    gui.drawRectFilled(handle, bg0);
                    cx += cc.width;
                }
                cx = 0;
                for (self.columns, 0..) |cc, i| {
                    gui.drawText(switch (cc.kind) {
                        .name => "Name",
                        .mtime => "Modified",
                        .ftype => "Kind",
                        .size => "Size",
                    }, Vec2f.new(rec.x + cx, rec.y), rec.h, Color.White);
                    if (i == self.sorted_column_index) {
                        gui.drawIcon(Icons.get(
                            if (!self.sorted_column_ascending) .drop_up else .drop_down,
                        ), .{ .x = rec.x + cx + cc.width - rec.h, .y = rec.y }, rec.h, Color.White);
                    }
                    if (gui.clickWidget(graph.Rec(rec.x + cx, rec.y, cc.width, rec.h), .{}) == .click) {
                        if (i == self.sorted_column_index) {
                            self.sorted_column_ascending = !self.sorted_column_ascending;
                        } else {
                            self.sorted_column_index = i;
                            self.sorted_column_ascending = true;
                        }
                        self.sort_entries(.{ .ascending = self.sorted_column_ascending, .column_kind = cc.kind });
                    }
                    cx += cc.width;
                }
            }
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = graph.Rec(ima.x, ima.y + item_height, ima.w, ima.h - item_height) }, .{});
            defer gui.endLayout();
            if (try gui.beginVLayoutScroll(&self.file_scroll, .{ .item_height = item_height })) |file_scroll| {
                _ = try self.fileItem(gui, .{ .name = "..", .kind = .directory }, 0, &self.columns);
                for (self.entries.items, 1..) |entry, i| {
                    if (try self.fileItem(gui, entry, i, &self.columns))
                        break;
                }
                try gui.endVLayoutScroll(file_scroll);
            }
        }
        {
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = prev_area }, .{});
            defer gui.endLayout();
        }
        {
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = bottom_bar }, .{});
            defer gui.endLayout();
            var vlayout = try gui.beginLayout(Gui.VerticalLayout, .{ .item_height = item_height }, .{});
            defer gui.endLayout();
            _ = vlayout;
            if (gui.checkboxNotify("show hidden", &self.show_hidden)) {
                self.clear_entries();
                try self.popuplate_entries();
            }
        }
    }
};

pub const MapEditor = struct {
    const Self = @This();

    pub fn floorPos(v: graph.Vec2f, ts: f32) graph.Vec2f {
        return .{ .x = @floor(v.x / ts) * ts, .y = @floor(v.y / ts) * ts };
    }

    pub const AreaIt = struct {
        w: usize,
        h: usize,
        bounds: graph.Rect,

        index: usize = 0,
        ts: f32,

        pub fn init(a: graph.Vec2f, b: graph.Vec2f, ts: anytype) AreaIt {
            const fts = std.math.lossyCast(f32, ts);
            const at = floorPos(a, fts);
            const bt = floorPos(b, fts);
            const w = at.x - bt.x;
            const h = at.y - bt.y;
            const bounds = graph.Rec(if (w > 0) bt.x else at.x, if (h > 0) bt.y else at.y, @fabs(w) + ts, @fabs(h) + ts);
            const wp: usize = @intFromFloat(@floor(@fabs(w) / fts) + 1);
            const hp: usize = @intFromFloat(@floor(@fabs(h) / fts) + 1);

            return .{ .bounds = bounds, .w = wp, .h = hp, .ts = fts };
        }

        pub fn next(self: *@This()) ?graph.Rect {
            defer self.index += 1;
            if (self.index >= self.w * self.h) return null;

            const fy: f32 = @floatFromInt(@divFloor(self.index, self.w));
            const fx: f32 = @floatFromInt(@mod(self.index, self.w));

            return graph.Rec(self.bounds.x + fx * self.ts, self.bounds.y + fy * self.ts, self.ts, self.ts);
        }
    };

    pub const Tool = enum {
        pencil,
        erasor,
    };

    alloc: std.mem.Allocator,
    loaded_map: ?*graph.MarioData.Map = null,
    atlas: ?graph.BakedAtlas = null,
    layer_index: usize = 0,
    canvas_cam: ?graph.Camera2D = null,
    inspector_scroll: graph.Vec2f = .{ .x = 0, .y = 0 },

    draw_ref_img: bool = true,

    tool: Tool = .pencil,

    tile_index: usize = 0,
    set_index: usize = 0,

    last_placed_pos: ?graph.Vec2f = null,

    pub fn init(alloc: std.mem.Allocator) Self {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn update(self: *Self, gui: *Gui.Context) !void {
        const inspector_item_height = 30;
        const area = gui.getArea() orelse return;
        _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = area }, .{});
        defer gui.endLayout();
        const inspector_rec = graph.Rec(area.x, area.y, area.w / 3, area.h);
        const canvas = graph.Rec(area.x + inspector_rec.w, area.y, area.w - inspector_rec.w, area.h);
        { //Inspector
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = inspector_rec }, .{});
            defer gui.endLayout();
            if (try gui.beginVLayoutScroll(&self.inspector_scroll, .{ .item_height = inspector_item_height })) |inspector_scroll| {
                {
                    const items = [_]struct { tool: Tool, icon: Icons }{.{ .tool = .pencil, .icon = .erasor }};
                    _ = try gui.beginLayout(Gui.HorizLayout, .{ .count = items.len }, .{});
                    defer gui.endLayout();
                    const pp = gui.getArea() orelse return;
                    gui.drawIcon(Icons.get(.erasor), pp.pos(), pp.h, Color.White);
                }
                _ = try gui.tabs(Tool, &self.tool);
                if (self.loaded_map) |map| {
                    const atlas = self.atlas orelse return;
                    if (gui.button("New Layer")) {
                        try map.appendLayer();
                    }

                    for (map.layers.items, 0..) |_, li| {
                        if (gui.button("l")) {
                            self.layer_index = li;
                        }
                    }

                    inspector_scroll.layout.pushHeight(inspector_item_height * 40);
                    const tile_area = gui.getArea() orelse return;
                    gui.drawRectTextured(tile_area, Color.White, atlas.texture.rect(), atlas.texture);
                    var cam = graph.Camera2D{ .cam_area = atlas.texture.rect(), .screen_area = tile_area };
                    for (atlas.tilesets.items, 0..) |ts, ts_i| {
                        for (0..ts.count) |i| {
                            const r = atlas.getTexRec(ts_i, i);
                            const wr = cam.toWorld(r);
                            if ((gui.clickWidget(wr, .{})) == .click) {
                                self.set_index = ts_i;
                                self.tile_index = i;
                            }
                        }
                    }
                    gui.drawRectOutline(cam.toWorld(atlas.getTexRec(self.set_index, self.tile_index)), Color.White);
                    inspector_scroll.layout.pushHeight(gui.propertyTableHeight(graph.Rect));
                    try gui.propertyTable(graph.Rect, &map.ref_img_pos);
                    gui.checkbox("Draw ref img", &self.draw_ref_img);
                }
                if (gui.button("next tile")) {
                    self.tile_index += 1;
                }
                gui.textLabel("Ref img path");
                //try gui.text

                try gui.endVLayoutScroll(inspector_scroll);
            }
        }
        {
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = canvas }, .{});
            if (self.loaded_map) |map| {
                const atlas = self.atlas orelse return;
                var cam = blk: {
                    if (self.canvas_cam) |*cam| {
                        break :blk cam;
                    } else {
                        self.canvas_cam = .{ .cam_area = graph.Rec(0, 0, 400, 400), .screen_area = canvas };
                        break :blk &self.canvas_cam.?;
                    }
                };
                if (gui.mouse_grabbed_by_hash == null and graph.rectContainsPoint(canvas, gui.input_state.mouse_pos)) {
                    {
                        const zf = 0.1;
                        const md = gui.input_state.mouse_wheel_delta;
                        cam.zoom(zf * md, gui.input_state.mouse_pos);

                        if (gui.input_state.mouse_wheel_down) {
                            cam.pan(gui.input_state.mouse_delta);
                        }
                    }
                }
                {
                    gui.scissor(canvas);
                    gui.drawRectFilled(canvas, itc(0xffffffff));
                    gui.drawSetCamera(.{ .set_camera = .{ .win_area = canvas } });
                    cam.screen_area = canvas;
                    {
                        gui.drawLine(.{ .x = 0, .y = std.math.maxInt(i32) }, .{ .x = 0, .y = -std.math.maxInt(i32) }, Color.Black);
                        gui.drawLine(.{ .y = 0, .x = std.math.maxInt(i32) }, .{ .y = 0, .x = -std.math.maxInt(i32) }, Color.Black);
                        if (map.ref_img_texture != null and self.draw_ref_img) {
                            gui.drawRectTextured(map.ref_img_pos, Color.White, map.ref_img_texture.?.rect(), map.ref_img_texture.?);
                        }
                        for (map.layers.items) |*layer| {
                            for (layer.tiles.items) |tile| {
                                gui.drawRectTextured(graph.Rec(tile.x, tile.y, tile.w, tile.h), Color.White, atlas.getTexRec(tile.ts_name_index, tile.index), atlas.texture);
                            }
                        }
                        const tile = atlas.getTexRec(self.set_index, self.tile_index);
                        const pos = self.canvas_cam.?.toCamV(gui.input_state.mouse_pos);
                        switch (self.tool) {
                            .pencil => {
                                const tt = gui.clickWidget(graph.Rec(0, 0, 0, 0), .{ .teleport_area = canvas });

                                if (gui.isKeyDown(.LSHIFT) and self.last_placed_pos != null) {
                                    var a_it = AreaIt.init(pos, self.last_placed_pos.?, 16);
                                    while (a_it.next()) |n| {
                                        gui.drawRectTextured(n, Color.White, tile, atlas.texture);
                                    }
                                } else {
                                    gui.drawRectTextured(graph.Rec(@floor(pos.x / 16) * 16, @floor(pos.y / 16) * 16, tile.w, tile.h), Color.White, tile, atlas.texture);
                                }
                                if (tt == .click_teleport) {
                                    if (gui.isKeyDown(.LSHIFT) and self.last_placed_pos != null) {
                                        var a_it = AreaIt.init(pos, self.last_placed_pos.?, 16);
                                        while (a_it.next()) |n| {
                                            try map.placeTile(self.layer_index, self.set_index, self.tile_index, n);
                                        }
                                    } else {
                                        try map.placeTile(self.layer_index, self.set_index, self.tile_index, graph.Rect.newV(
                                            floorPos(pos, 16),
                                            .{ .x = tile.w, .y = tile.h },
                                        ));
                                    }
                                    self.last_placed_pos = pos;
                                }
                            },
                            .erasor => {
                                const tt = gui.clickWidget(graph.Rec(0, 0, 0, 0), .{ .teleport_area = canvas });
                                const fp = floorPos(pos, 16);
                                if (gui.isKeyDown(.LSHIFT) and self.last_placed_pos != null) {
                                    var a_it = AreaIt.init(pos, self.last_placed_pos.?, 16);
                                    gui.drawRectOutline(a_it.bounds, Color.White);
                                } else {
                                    gui.drawRectOutline(graph.Rec(fp.x, fp.y, 16, 16), Color.White);
                                }
                                if (tt == .click_teleport) {
                                    if (gui.isKeyDown(.LSHIFT) and self.last_placed_pos != null) {
                                        var a_it = AreaIt.init(pos, self.last_placed_pos.?, 16);
                                        while (a_it.next()) |n| {
                                            map.removeTile(self.layer_index, n.pos());
                                        }
                                    } else {
                                        map.removeTile(self.layer_index, fp);
                                    }
                                    self.last_placed_pos = pos;
                                } else if (tt == .held and !gui.isKeyDown(.LSHIFT)) {
                                    map.removeTile(self.layer_index, fp);
                                }
                            },
                        }
                    }

                    gui.drawSetCamera(.{ .set_camera = .{ .cam_area = cam.cam_area } });

                    gui.scissor(null);
                }
            } else {}
            gui.endLayout();
        }
    }
};

pub const AtlasEditor = struct {
    const Self = @This();

    const Mode = enum {
        edit,
        copy_range,
        add_image,
    };

    alloc: std.mem.Allocator,

    copy_range_offset_x: i32 = 0,
    copy_range_offset_y: i32 = 0,
    copy_range_desc_prefix: []u8 = "",
    copy_range_range_start: u32 = 0,
    copy_range_range_end: u32 = 0,

    add_image_filename: []u8 = "",

    mode: Mode = .edit,

    new_ts_default: graph.SubTileset = .{ .tw = 16, .th = 16, .pad = .{ .x = 1, .y = 1 }, .num = .{ .x = 4, .y = 4 }, .count = 16, .start = .{ .x = 0, .y = 0 } },

    loaded_atlas: ?graph.Atlas = null,
    inspector_scroll: graph.Vec2f = .{ .x = 0, .y = 0 },
    set_scroll: graph.Vec2f = .{ .x = 0, .y = 0 },

    draw_unfocused_overlay: bool = false,

    file_browser: ?FileBrowser = null,
    canvas_cam: ?graph.Camera2D = null,
    marquee: Rect = graph.Rec(0, 0, 0, 0),

    atlas_index: usize = 0,
    set_index: usize = 0,

    pub fn init(alloc: std.mem.Allocator) Self {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Self) void {
        if (self.file_browser) |*b| {
            b.deinit();
        }
        if (self.loaded_atlas) |*b| {
            b.deinit();
        }
        if (self.copy_range_desc_prefix.len > 0)
            self.alloc.free(self.copy_range_desc_prefix);
        if (self.add_image_filename.len > 0)
            self.alloc.free(self.add_image_filename);
    }

    pub fn update(self: *Self, gui: *Gui.Context) !void {
        const inspector_item_height = 50;
        const area = gui.getArea() orelse return;
        _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = area }, .{});
        defer gui.endLayout();
        const inspector_rec = graph.Rec(area.x, area.y, area.w / 3, area.h);
        const canvas = graph.Rec(area.x + inspector_rec.w, area.y, area.w - inspector_rec.w, area.h);
        { //Inspector
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = inspector_rec }, .{});
            defer gui.endLayout();
            if (try gui.beginVLayoutScroll(&self.inspector_scroll, .{ .item_height = inspector_item_height })) |inspector_scroll| {
                if (self.loaded_atlas) |*atlas| {
                    inspector_scroll.layout.pushHeight(inspector_item_height * 40);
                    //if (try gui.beginVLayoutScroll(&self.set_scroll, .{ .item_height = inspector_item_height })) |set_scroll| {
                    for (atlas.atlas_data.sets, 0..) |*set, si| {
                        inspector_scroll.layout.pushHeight(inspector_item_height * 3);
                        {
                            _ = try gui.beginLayout(Gui.VerticalLayout, .{ .item_height = inspector_item_height }, .{});
                            defer gui.endLayout();
                            if (gui.button(set.filename)) {
                                try gui.console.print("Setting new index {d} {d}", .{ 0, si });
                                gui.text_input_hash = null;
                                self.canvas_cam = null;
                                self.set_index = 0;
                                self.atlas_index = si;
                            }
                            if (gui.button("new set")) {
                                std.debug.print("Sett {d}\n", .{set.tilesets.len});
                                const index = set.tilesets.len;
                                set.tilesets = try atlas.alloc.realloc(set.tilesets, set.tilesets.len + 1);
                                set.tilesets[set.tilesets.len - 1] = self.new_ts_default;
                                self.set_index = index;
                            }
                        }
                        for (set.tilesets, 0..) |ts, tsi| {
                            const rec = gui.getArea() orelse break;
                            var col = Color.White;
                            if (self.mode == .copy_range) {
                                if (self.atlas_index == si and tsi < self.copy_range_range_end and tsi >= self.copy_range_range_start) {
                                    col = Color.Green;
                                }
                            }
                            gui.drawText(if (ts.description.len > 0) ts.description else "{blank}", rec.pos(), rec.h, col);
                            const click = gui.clickWidget(rec, .{});
                            if (click == .click) {
                                if (self.atlas_index != si) {
                                    self.copy_range_range_start = 0;
                                    self.copy_range_range_end = 0;
                                }
                                try gui.console.print("Setting new index {d} {d}", .{ tsi, si });
                                gui.text_input_hash = null;
                                self.canvas_cam = null;
                                self.set_index = tsi;
                                self.atlas_index = si;
                            }
                        }
                    }
                    //try gui.endVLayoutScroll(set_scroll);
                    //}
                    if (atlas.atlas_data.sets[self.atlas_index].tilesets.len > 0) {
                        try gui.textbox(&atlas.atlas_data.sets[self.atlas_index].tilesets[self.set_index].description, self.alloc);

                        const sts = &atlas.atlas_data.sets[self.atlas_index].tilesets[self.set_index];

                        //try gui.printLabel("Tile count: {d}", .{sts.count});
                        try gui.sliderOpts(&sts.count, 1, 1000, .{ .handle_w = 40, .label_text = "Count: " });
                        try gui.sliderOpts(&sts.num.x, 1, 1000, .{ .handle_w = 40, .label_text = "Num x: " });
                        try gui.sliderOpts(&sts.num.y, 1, 1000, .{ .handle_w = 40, .label_text = "Num y: " });
                        try gui.sliderOpts(&sts.tw, 1, 1000, .{ .handle_w = 40, .label_text = "tw: " });
                        try gui.sliderOpts(&sts.th, 1, 1000, .{ .handle_w = 40, .label_text = "th: " });
                    }

                    gui.checkbox("overlay unfocused", &self.draw_unfocused_overlay);
                    if (gui.button("Save file")) {
                        const f = self.file_browser.?.file.?;
                        const fname = "testoutput.json";
                        var out_file = try f.dir.createFile(fname, .{});
                        defer out_file.close();
                        try std.json.stringify(atlas.atlas_data, .{}, out_file.writer());
                        try gui.console.print("Saving to file: {s}", .{fname});
                    }
                    if (gui.button("set current as default")) {
                        self.new_ts_default = atlas.atlas_data.sets[self.atlas_index].tilesets[self.set_index];
                        self.new_ts_default.description = "";
                    }
                    try gui.enumDropDown(Mode, &self.mode);
                    switch (self.mode) {
                        .copy_range => {
                            const max_index: f32 = @floatFromInt(atlas.atlas_data.sets[self.atlas_index].tilesets.len);

                            try gui.sliderOpts(&self.copy_range_offset_x, -1000, 1000, .{ .handle_w = 40, .label_text = "cpy offset x: " });
                            try gui.sliderOpts(&self.copy_range_offset_y, -1000, 1000, .{ .handle_w = 40, .label_text = "cpy offset y: " });
                            try gui.sliderOpts(&self.copy_range_range_start, 0, max_index, .{ .handle_w = 40, .label_text = "cpy start i: " });
                            try gui.sliderOpts(&self.copy_range_range_end, 0, max_index, .{ .handle_w = 40, .label_text = "cpy end i: " });
                            try gui.textbox(&self.copy_range_desc_prefix, self.alloc);
                            _ = blk: {
                                if (gui.button("Push copy")) {
                                    if (self.copy_range_desc_prefix.len == 0) {
                                        try gui.console.print("error: Unable to copy tileset range without a description prefix", .{});
                                        break :blk;
                                    }
                                    const current_sets = &atlas.atlas_data.sets[self.atlas_index].tilesets;
                                    if (self.copy_range_range_end > current_sets.len) {
                                        try gui.console.print("error: copy end range larger than current selected set", .{});
                                        break :blk;
                                    }
                                    const copy_len = self.copy_range_range_end - self.copy_range_range_start;
                                    if (copy_len == 0) {
                                        try gui.console.print("error: Unable to copy zero length range", .{});
                                        break :blk;
                                    }

                                    var new_sets: []graph.SubTileset = try self.alloc.alloc(graph.SubTileset, copy_len);
                                    defer self.alloc.free(new_sets);
                                    for (current_sets.*[self.copy_range_range_start..self.copy_range_range_end], 0..) |set, new_i| {
                                        const st = set.start;
                                        new_sets[new_i] = set;
                                        new_sets[new_i].start = .{ .x = st.x + self.copy_range_offset_x, .y = st.y + self.copy_range_offset_y };
                                        var new_name = std.ArrayList(u8).init(self.alloc);
                                        try new_name.appendSlice(self.copy_range_desc_prefix);
                                        try new_name.appendSlice(set.description);

                                        new_sets[new_i].description = try new_name.toOwnedSlice();

                                        try gui.console.print("copying \"{s}{s}\"", .{ self.copy_range_desc_prefix, set.description });
                                    }

                                    const cpy_start_i = current_sets.len;
                                    current_sets.* = try self.alloc.realloc(current_sets.*, cpy_start_i + new_sets.len);
                                    @memcpy(current_sets.*[cpy_start_i .. new_sets.len + cpy_start_i], new_sets);

                                    try gui.console.print("success: Copied {d} tilesets", .{copy_len});
                                }
                            };
                        },
                        .add_image => {
                            try gui.textbox(&self.add_image_filename, self.alloc);

                            if (gui.button("add set")) {
                                atlas.addSet(self.add_image_filename) catch |err| switch (err) {
                                    error.FileNotFound => try gui.console.print("error: Unable to add set. Image file not found: {s}", .{self.add_image_filename}),
                                    else => return err,
                                };
                            }
                        },
                        else => {},
                    }
                }
                inspector_scroll.layout.pushHeight(inspector_item_height * 50);
                gui.drawConsole(gui.console, inspector_item_height);
                try gui.endVLayoutScroll(inspector_scroll);
            }
        }
        _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = canvas }, .{});
        if (self.loaded_atlas) |atlas| {
            const tex = atlas.textures.items[self.atlas_index];
            var sts = &atlas.atlas_data.sets[self.atlas_index].tilesets[self.set_index];
            var cam = blk: {
                if (self.canvas_cam) |*cam| {
                    break :blk cam;
                } else {
                    self.canvas_cam = .{ .cam_area = tex.rect(), .screen_area = canvas };
                    break :blk &self.canvas_cam.?;
                }
            };
            if (gui.mouse_grabbed_by_hash == null and graph.rectContainsPoint(canvas, gui.input_state.mouse_pos)) {
                {
                    const zf = 0.1;
                    const md = gui.input_state.mouse_wheel_delta;
                    cam.zoom(zf * md, gui.input_state.mouse_pos);

                    if (gui.input_state.mouse_wheel_down) {
                        cam.pan(gui.input_state.mouse_delta);
                    }
                }
            }
            {
                gui.scissor(canvas);
                gui.drawRectFilled(canvas, itc(0xffffffff));
                gui.drawSetCamera(.{ .set_camera = .{ .win_area = canvas } });
                cam.screen_area = canvas;
                {
                    gui.drawRectTextured(tex.rect(), itc(0xffffffff), tex.rect(), tex);

                    for (atlas.atlas_data.sets[self.atlas_index].tilesets, 0..) |tset, set_i| {
                        //gui.drawRectFilled(tset.getBounds(), itc(0xffffff11));
                        const color = if (set_i == self.set_index) Color.Gold else Color.Green;
                        if (set_i != self.set_index and self.draw_unfocused_overlay) {
                            gui.drawRectFilled(tset.getBounds(), itc(0xffffffff));
                        } else {
                            for (0..tset.count) |i| {
                                if (i >= tset.num.x * tset.num.y)
                                    break;
                                const r = tset.getTexRec(i);
                                gui.drawRectOutline(r, color);
                            }
                        }
                    }
                    switch (self.mode) {
                        .copy_range => {
                            for (atlas.atlas_data.sets[self.atlas_index].tilesets[self.copy_range_range_start..self.copy_range_range_end]) |tset| {
                                const b = tset.getBounds().addV(self.copy_range_offset_x, self.copy_range_offset_y);

                                gui.drawRectFilled(b, Color.Green);
                            }
                        },
                        else => {},
                    }
                    //gui.drawSetCamera(.{ .set_camera = .{ .cam_area = st.cam_area.toAbsoluteRect(), .offset = st.offset } });
                }

                gui.drawSetCamera(.{ .set_camera = .{ .cam_area = cam.cam_area } });

                const first_tile = cam.toWorld(sts.getTexRec(0));
                const scd = cam.toWorld(sts.getTexRec(@intCast(sts.num.x + 1)));
                const ft = first_tile;
                const pos_handle = graph.Rec(ft.x, ft.y, ft.w / 2, ft.h / 2);
                gui.drawRectFilled(pos_handle, Color.Black);
                const f = cam.factor();
                _ = gui.draggable(pos_handle, f, &sts.start.x, &sts.start.y, .{ .x_min = 0, .y_min = 0 });

                const pad_handle = graph.Rec(scd.x, scd.y, scd.w / 2, scd.h / 2);
                gui.drawRectFilled(pad_handle, Color.Black);
                _ = gui.draggable(pad_handle, f, &sts.pad.x, &sts.pad.y, .{ .x_min = 0, .y_min = 0 });

                const tw_handle = graph.Rec(ft.x + ft.w / 2, ft.y + ft.h / 2, ft.w / 2, ft.h / 2);
                gui.drawRectFilled(tw_handle, Color.Black);
                _ = gui.draggable(tw_handle, f, &sts.tw, &sts.th, .{ .x_min = 1, .y_min = 1 });

                const marquee = gui.clickWidget(graph.Rec(0, 0, 0, 0), .{ .teleport_area = canvas });
                if (marquee == .click_teleport) {
                    self.marquee = graph.Rec(0, 0, 0, 0);
                    self.marquee.x = gui.input_state.mouse_pos.x;
                    self.marquee.y = gui.input_state.mouse_pos.y;
                }
                if (marquee == .held) {
                    self.marquee.w = (gui.input_state.mouse_pos.x) - self.marquee.x;
                    self.marquee.h = (gui.input_state.mouse_pos.y) - self.marquee.y;
                }

                if (marquee != .none) {
                    gui.drawRectOutline(self.marquee, Color.White);
                }

                if (marquee == .click_release) {
                    cam.cam_area = cam.toCam(self.marquee);
                    if (self.marquee.w < 1 or self.marquee.h < 1) {
                        cam.cam_area = tex.rect();
                    }
                }

                gui.scissor(null);
            }
        } else {
            if (self.file_browser == null)
                self.file_browser = try FileBrowser.init(self.alloc, std.fs.cwd());
            try self.file_browser.?.update(gui);
            if (self.file_browser.?.file) |file| {
                self.loaded_atlas = graph.Atlas.initFromJsonFile(file.dir, file.file_name, self.alloc) catch blk: {
                    try gui.console.print("Unable to load \"{s}\" as an atlas manifest", .{file.file_name});
                    self.file_browser.?.file = null;
                    break :blk null;
                };
            }
        }
        gui.endLayout();
    }
};

/// Attempting to make a nextStep style gui
///
/// For now, reimplement all the elments in gui within this
///
/// Elements we need
/// inset rect
/// title bar
/// Partition lines
///
/// Widgets:
/// Button
/// Drop down
/// Text label
/// text box with label
/// scrollable list with selection
/// checkbox
/// header
/// table with scroll area
pub const TestWindow = struct {
    const Self = @This();

    const SampleEnum = enum { val1, val2, what, tabs };

    const SampleStruct = struct {
        en: SampleEnum = .what,
        float: f32 = 123,
        flag: bool = false,
        my_int: i32 = 1222,
        my_struct: Rect = Rec(4, 5, 6, 7),
    };

    const border = itc(0xff);
    const wbg = itc(0xaaaaaaff);
    const shadow = itc(0x555555ff);
    const light = itc(0xffffffff);

    //Define the different 9slices in "texture"
    const inset9 = Rec(0, 0, 6, 6);
    const outset9 = Rec(0, 6, 6, 6);
    const window9 = Rec(6, 6, 6, 6);
    const title9 = Rec(6, 0, 6, 6);
    const divider = Rec(12, 0, 1, 2);

    const os9win = Rec(0, 12, 6, 6);
    const os9in = Rec(6, 12, 6, 6);
    const os9line = Rec(0, 18, 6, 6);
    const os9drop = Rec(6, 18, 6, 6);
    const os9btn = Rec(12, 0, 12, 12);
    const os9nurl = Rec(24, 0, 6, 12);
    const os9dropbtn = Rec(31, 0, 20, 16);
    const os9slider = Rec(0, 24, 3, 3);
    const os9shuttle = Rec(0, 30, 19, 14);
    const os9checkbox = Rec(12, 12, 12, 12);
    const os9check = Rec(24, 24, 12, 12);

    const os9tabstart = Rec(55, 0, 11, 21);
    const os9tabend = Rec(72, 0, 11, 21);
    const os9tabmid = Rec(66, 0, 6, 21);

    const os9tabstart_active = Rec(55, 24, 11, 21);
    const os9tabend_active = Rec(72, 24, 11, 21);
    const os9tabmid_active = Rec(66, 24, 6, 21);

    const os9tabborder = Rec(42, 24, 9, 9);

    ref_img: graph.Texture,
    texture: graph.Texture,
    scale: f32,
    sample_data: SampleStruct = .{},

    pub fn init(alloc: std.mem.Allocator, scale: f32) !Self {
        const dir = std.fs.cwd();
        return .{
            .scale = scale,
            .texture = try graph.Texture.initFromImgFile(alloc, dir, "next_step.png", .{ .mag_filter = graph.c.GL_NEAREST }),
            .ref_img = try graph.Texture.initFromImgFile(alloc, dir, "nextgui.png", .{ .mag_filter = graph.c.GL_NEAREST }),
        };
    }
    pub fn deinit(self: *Self) void {
        _ = self;
        //self.ref_img.deinit();
    }

    //TODO remove scale variable and scale using GuiDrawContext
    pub fn update(self: *Self, gui: *Gui.Context) !void {
        const scale = self.scale;
        const area = gui.getArea() orelse return;
        gui.draw9Slice(area, os9win, self.texture, scale);
        //const title = "Keyboard";
        const title_h = 20 * scale;
        const s4 = scale * 4;
        const inside = Rect.new(area.x + s4, area.y + title_h, area.w - s4 * 2, area.h - title_h - s4);
        gui.draw9Slice(inside, os9in, self.texture, scale);

        _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = inside.inset(4 * scale) }, .{});
        defer gui.endLayout();
        {
            const nh = 20 * scale;
            var vl = try gui.beginLayout(Gui.VerticalLayout, .{ .item_height = nh, .padding = .{ .bottom = 6 * scale } }, .{});
            defer gui.endLayout();
            self.hLabelTextbox(gui, "Local_Name:", "New_Printer", scale);
            self.hLabelTextbox(gui, "Remote:", "", scale);
            self.hLabelTextbox(gui, "Note:", "This is a new printer", scale);
            vl.current_h += vl.padding.bottom;
            _ = self.button(gui, "Click me", scale);
            vl.pushHeight(vl.item_height * 4);
            _ = try gui.beginLayout(Gui.HorizLayout, .{ .count = 2 }, .{});
            const buttons = [_][]const u8{ "Opt 1", "two", "Just save", "Load It" };
            for (0..2) |_| {
                _ = try gui.beginLayout(Gui.VerticalLayout, .{ .item_height = nh }, .{});
                for (buttons) |btn| {
                    _ = self.button(gui, btn, scale);
                }
                gui.endLayout();
            }

            gui.endLayout();

            const a = gui.getArea() orelse return;
            const mt = "My Area";
            const ts = 12 * scale;
            const bounds = gui.font.textBounds(mt, ts);
            const bx = bounds.x * 1.2;
            gui.draw9Border(a, os9line, self.texture, scale, a.w / 2 - bx / 2, a.w / 2 + bx / 2);
            gui.drawText(mt, Vec2f.new(a.x + a.w / 2 - bounds.x / 2, a.y - ts / 2), ts, Color.Black);
            //gui.spinner(&val);
            self.checkbox(gui, "Checkbox", &self.sample_data.flag);
            vl.pushHeight(os9tabstart.h * scale);
            _ = try self.tabs(gui, SampleEnum, &self.sample_data.en);
            vl.current_h -= (vl.padding.top + vl.padding.bottom + scale * 1);
            vl.pushHeight(vl.item_height * 5);
            const taba = gui.getArea() orelse return;
            const tabb = tabsBorderCalc(SampleEnum, self.sample_data.en, taba.w);
            gui.drawRectFilled(taba, itc(0xeeeeeeff));
            gui.draw9Border(
                taba,
                os9tabborder,
                self.texture,
                scale,
                tabb[0] - 2 * scale,
                tabb[1] - 4 * scale,
            );
            _ = self.button(gui, "hello", scale);
            _ = self.button(gui, "hello", scale);

            try self.enumDropDown(gui, SampleEnum, &self.sample_data.en);
            try self.sliderOpts(gui, &self.sample_data.float, -10, 200);
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

    pub fn tabs(win: *Self, self: *Gui.Context, comptime list_type: type, selected: *list_type) !list_type {
        const info = @typeInfo(list_type);
        const fields = info.Enum.fields;
        _ = try self.beginLayout(Gui.HorizLayout, .{ .count = fields.len, .paddingh = 0 }, .{});
        defer self.endLayout();
        inline for (fields) |field| {
            const active = @as(info.Enum.tag_type, @intFromEnum(selected.*)) == field.value;
            const area = self.getArea() orelse return selected.*;
            const click = self.clickWidget(area, .{});
            if (click == .click)
                selected.* = @as(list_type, @enumFromInt(field.value));
            const sta = if (active) os9tabstart_active else os9tabstart;
            const end = if (active) os9tabend_active else os9tabend;
            const mid = if (active) os9tabmid_active else os9tabmid;
            self.drawRectTextured(
                Rec(area.x, area.y, sta.w * win.scale, area.h),
                Color.White,
                sta,
                win.texture,
            );
            self.drawRectTextured(
                Rec(area.x + area.w - end.w * win.scale, area.y, end.w * win.scale, area.h),
                Color.White,
                end,
                win.texture,
            );
            const mida = Rec(area.x + sta.w * win.scale, area.y, area.w - (end.w + sta.w) * win.scale, area.h);
            self.drawRectTextured(
                mida,
                Color.White,
                mid,
                win.texture,
            );
            //const tbounds = self.font.textBounds(field.name);
            self.drawText(field.name, mida.pos().add(.{ .x = 0, .y = 4 * win.scale }), mida.h - 4 * win.scale, Color.Black);

            //if (self.buttonEx(.{
            //    .name = field.name,
            //})) {
            //    selected.* = @as(list_type, @enumFromInt(field.value));
            //}
        }

        return selected.*;
    }

    pub fn button(self: *Self, gui: *Gui.Context, label: []const u8, scale: f32) bool {
        const area = gui.getArea() orelse return false;
        const click = gui.clickWidget(area, .{});
        const sl = switch (click) {
            .none, .hover => os9btn,
            .click, .held => inset9,
            else => os9btn,
        };
        gui.draw9Slice(area, sl, self.texture, scale);
        const texta = area.inset(3 * scale);
        const bounds = gui.font.textBounds(label, texta.h);
        gui.drawText(label, texta.pos().add(.{ .x = (texta.w - bounds.x) / 2, .y = 0 }), texta.h, Color.Black);

        return click == .click;
    }

    pub fn sliderOpts(win: *Self, self: *Gui.Context, value: anytype, min: anytype, max: anytype) !void {
        const lmin = std.math.lossyCast(f32, min);
        const lmax = std.math.lossyCast(f32, max);
        //const lval = std.math.lossyCast(f32, value.*);
        const ptrinfo = @typeInfo(@TypeOf(value));
        const child_type = ptrinfo.Pointer.child;
        if (ptrinfo != .Pointer) @compileError("slider requires a pointer for value");
        const info = @typeInfo(child_type);

        const rec = self.getArea() orelse return;

        const handle_w = os9shuttle.w * win.scale;
        const mdel = self.input_state.mouse_delta.x;
        const mpos = self.input_state.mouse_pos.x;
        const scale = (rec.w - handle_w) / (lmax - lmin);

        var val: f32 = switch (info) {
            .Float => @as(f32, @floatCast(value.*)),
            .Int => @as(f32, @floatFromInt(value.*)),
            else => @compileError("invalid type"),
        };

        var handle = Rect{
            .x = rec.x + (val - min) * scale,
            .y = rec.y + (os9slider.h / 3) * win.scale,
            .w = handle_w,
            .h = rec.h - (os9slider.h / 3) * 2 * win.scale,
        };
        const clicked = self.clickWidget(handle, .{});

        if (clicked == .click) {
            self.focused_slider_state = 0;
        }

        // Only moving the slider until after our initial .click state prevents the slider from teleporting when used with a touch screen or other input method that teleports the cursor like a drawing tablet.
        if (clicked == .held) {
            val += self.focused_slider_state;
            val += mdel / scale;
            val = std.math.clamp(val, lmin, lmax);

            //Prevents slider moving oddly when mouse has been moved far outside of slider bounds
            if (mpos > rec.x + rec.w)
                val = max;
            if (mpos < rec.x)
                val = min;

            if (info == .Int)
                self.focused_slider_state = (val - @trunc(val));
            handle.x = rec.x + (val - lmin) * scale;
        }

        if (self.mouse_grabbed_by_hash == null and !self.scroll_claimed_mouse and graph.rectContainsPoint(rec, self.input_state.mouse_pos)) {
            self.scroll_claimed_mouse = true;
            switch (info) {
                .Float => {},
                .Int => {
                    val += self.input_state.mouse_wheel_delta.y;
                    val = std.math.clamp(val, lmin, lmax);
                },
                else => {},
            }
            //scroll_data.offset.y = std.math.clamp(scroll_data.offset.y + self.input_state.mouse_wheel_delta * -40, vbounds.x, vbounds.y);
        }

        switch (info) {
            .Float => {
                value.* = val;
            },
            .Int => {
                value.* = @as(ptrinfo.Pointer.child, @intFromFloat(@trunc(val)));
                handle.x = rec.x + (@trunc(val) - min) * scale;
            },
            else => @compileError("invalid type"),
        }

        self.draw9Slice(rec, os9slider, win.texture, win.scale);
        self.draw9Slice(handle, os9shuttle, win.texture, win.scale);
        //if (!opts.draw_text) return;
        //const tt = if (opts.label_text) |t| t else "";
        //if (info == .Float) {
        //    self.drawTextFmt("{s}{d:.2}", .{ tt, val }, rec, rec.h, Color.White, .{ .justify = .center });
        //} else {
        //    self.drawTextFmt("{s}{d:.0}", .{ tt, @trunc(val) }, arec, arec.h, Color.White, .{ .justify = .center });
        //}
    }

    pub fn checkbox(self: *Self, gui: *Gui.Context, label: []const u8, checked: *bool) void {
        const area = gui.getArea() orelse return;
        const click = gui.clickWidget(area, .{});
        if (click == .click or click == .double) {
            checked.* = !checked.*;
        }
        const br = Rect.newV(area.pos(), .{ .x = 12 * self.scale, .y = 12 * self.scale });
        gui.drawRectTextured(
            br,
            Color.White,
            os9checkbox,
            self.texture,
        );
        gui.drawText(label, area.pos().add(.{ .x = area.h * 1.5, .y = 0 }), area.h, Color.Black);
        if (checked.*)
            gui.drawRectTextured(br.addV(2 * self.scale, 0), Color.White, os9check, self.texture);
    }

    pub fn enumDropDown(win: *Self, self: *Gui.Context, comptime enumT: type, enum_val: *enumT) !void {
        const rec = self.getArea() orelse return;
        const ld = self.current_layout_cache_data.?;
        const index = self.getTransientIndex();
        const h = rec.h;

        const click = self.clickWidget(rec, .{});
        const wstate = self.getWidgetState(.{ .c = click, .r = rec, .v = enum_val.* });

        if (self.popup_index) |ind| {
            if (self.popup_hash) |hash| {
                if (hash == ld.hash and ind == index) {
                    var done = false;
                    const info = @typeInfo(enumT);
                    const lrq = self.layout.last_requested_bounds orelse graph.Rec(0, 0, 0, 0);
                    const popup_rec = graph.Rec(lrq.x, lrq.y, lrq.w, h * 5);
                    try self.beginPopup(popup_rec);
                    if (try self.beginVLayoutScroll(&self.enum_drop_down_scroll, .{ .item_height = h })) |scroll| {
                        inline for (info.Enum.fields) |field| {
                            if (self.button(field.name)) {
                                if (!done) {
                                    enum_val.* = @as(enumT, @enumFromInt(field.value));
                                    self.popup_index = null;
                                    self.popup_hash = null;
                                    done = true;
                                }
                            }
                        }
                        try self.endVLayoutScroll(scroll);
                    }
                    self.endPopup();
                }
            }
        } else {
            if (click == .click) {
                self.enum_drop_down_scroll = .{ .x = 0, .y = 0 };
                self.popup_index = index;
                self.popup_hash = ld.hash;
                self.last_frame_had_popup = true;
                //try self.enumDropDown(enumT, enum_val);
            }
        }

        if (wstate != .no_change) {
            self.draw9Slice(rec, os9drop, win.texture, win.scale);
            const text = rec.inset(3 * win.scale);
            self.drawText(@tagName(enum_val.*), text.pos(), text.h, Color.Black);
            const ow = win.scale * os9drop.w / 3;
            const oh = win.scale * os9drop.h / 3;
            const btn_rec = Rec(rec.x + rec.w - ow - os9dropbtn.w * win.scale, rec.y + oh, os9dropbtn.w * win.scale, os9dropbtn.h * win.scale);
            self.drawRectTextured(btn_rec, Color.White, os9dropbtn, win.texture);
        }
    }

    pub fn hLabelTextbox(self: *Self, gui: *Gui.Context, label: []const u8, disp: []const u8, scale: f32) void {
        {
            const bw = scale * 184;
            const tba = gui.getArea() orelse return;
            const texta = Rec(tba.x, tba.y, tba.w - bw, tba.h);
            const ba = Rect.new(tba.x + texta.w, tba.y, bw, tba.h);
            gui.draw9Slice(ba, inset9, self.texture, scale);
            //const bounds =
            const ts = 3;
            const trect = texta.inset(ts * scale);
            const bounds = gui.font.textBounds(label, trect.h);
            gui.drawText(label, trect.pos().add(.{ .x = trect.w - bounds.x, .y = 0 }), trect.h, Color.Black);
            const dispa = ba.inset(ts * scale);
            gui.drawText(disp, dispa.pos(), dispa.h, Color.Black);
        }
    }
};

pub fn main() anyerror!void {
    //_ = graph.MarioData.dd;
    var gpa = std.heap.GeneralPurposeAllocator(.{ .retain_metadata = true, .never_unmap = true, .verbose_log = false }){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    const scale = 2.0;
    var win = try graph.SDL.Window.createWindow("My window", .{
        .window_flags = &.{
            graph.c.SDL_WINDOW_BORDERLESS,
            //graph.c.SDL_WINDOW_UTILITY,
        },
        .window_size = .{ .x = @intFromFloat(273 * scale), .y = @intFromFloat(430 * scale) },
    });
    defer win.destroyWindow();

    var ctx = try graph.GraphicsContext.init(
        alloc,
        163,
    );
    defer ctx.deinit();
    graph.c.glLineWidth(1);

    //TODO
    //load multiple 9 slices into a single texture
    //An easy way to manage it would be, a directory called "gui_asset", all pngs in this dir will be loaded and packed into a single texture.
    //Can be referenced by name in program
    //
    //const fna = "h9.png";
    //var t9 = try graph.Texture.initFromImgFile(alloc, std.fs.cwd(), fna, .{ .mag_filter = graph.c.GL_NEAREST });

    var dpix: u32 = @as(u32, @intFromFloat(win.getDpi()));
    //const init_size = graph.pxToPt(win.getDpi(), 100);
    const init_size = 8;
    var font = try graph.Font.init(alloc, std.fs.cwd(), "fonts/roboto.ttf", init_size, dpix, .{
        .debug_dir = std.fs.cwd(),
    });
    defer font.deinit();
    const icon_list = comptime blk: {
        const info = @typeInfo(Icons);
        var list: [info.Enum.fields.len]u21 = undefined;

        for (info.Enum.fields, 0..) |f, i| {
            list[i] = f.value;
        }
        break :blk list;
    };
    var icons = try graph.Font.init(
        alloc,
        std.fs.cwd(),
        "fonts/remix.ttf",
        init_size,
        dpix,
        .{
            .codepoints_to_load = &[_]graph.Font.CharMapEntry{.{ .list = &icon_list }},
        },
    );
    defer icons.deinit();

    var stack_buffer: [300000]u8 = undefined;
    var stack_alloc = std.heap.FixedBufferAllocator.init(&stack_buffer);
    var gui = try Gui.Context.init(alloc, &stack_alloc, .{ .x = 0, .y = 0, .w = 3840, .h = 2160 }, &font, &icons);
    defer gui.deinit();

    Gui.hash_timer = try std.time.Timer.start();
    Gui.hash_time = 0;

    var gui_draw_context = try Gui.GuiDrawContext.init();
    defer gui_draw_context.deinit();

    var nctx = graph.NewCtx.init(alloc, win.getDpi());
    defer nctx.deinit();

    var parent_area = graph.Rec(0, 0, 0, 0);

    var percent_usage: f32 = 0;

    var draw_line_debug: bool = false;

    const gui_frac: f32 = 0.3;
    _ = gui_frac * 0.1;
    var gui_timer = try std.time.Timer.start();
    var gui_time: u64 = 0;
    var rbuf = graph.RingBuffer(3, u64, 0){};
    var dcall_count: usize = 0;

    //_ = graph.MarioData.jj;
    const type_name = @typeName(std.ArrayList(void));
    std.debug.print("{s}\n", .{type_name});

    //var scr1: graph.Vec2f = .{ .x = 0, .y = 0 };

    //var atlas = try graph.Atlas.initFromJsonFile("../zig-game_engine/mario_assets", "tileset_manifest.json", alloc);
    //defer atlas.deinit();

    var atlas_editor = AtlasEditor.init(alloc);
    defer atlas_editor.deinit();

    var test_win = try TestWindow.init(alloc, scale);
    defer test_win.deinit();

    //var file_browser = try FileBrowser.init(alloc);
    //defer file_browser.deinit();

    //var ts_tex = try graph.Texture.fromImage("../zig-game_engine/mario_assets/img/mario-tileset.png", alloc, .{ .mag_filter = graph.c.GL_NEAREST, .min_filter = graph.c.GL_NEAREST });
    //var clear_screen = true;

    //var out_dir = try std.fs.cwd().openDir("test_out", .{});
    //defer out_dir.close();
    //try graph.Atlas.writeToTiled(asset_dir, "fuck.json", out_dir, alloc);
    //if (true) {
    //    return;
    //}

    //var atlasjson = try graph.Atlas.AtlasJson.initFromJsonFile(asset_dir, "fuck.json", alloc);
    //var baked_atlas = try graph.BakedAtlas.fromAtlas(asset_dir, atlasjson, alloc);
    //defer baked_atlas.deinit();
    //atlasjson.deinit(alloc);
    //try baked_atlas.bitmap.writeToPngFile(std.fs.cwd(), "test.png");

    //var mario_map = try graph.MarioData.Map.initFromJsonFile(alloc, std.fs.cwd(), "test_map_thir.json");
    //defer mario_map.deinit();
    ////try mario_map.updateAtlas(baked_atlas);
    //var map_editor = MapEditor.init(alloc);
    //defer map_editor.deinit();
    //map_editor.loaded_map = &mario_map;
    //map_editor.atlas = baked_atlas;

    //defer mario_map.writeToJsonFile(alloc, std.fs.cwd(), "test_map_thir.json") catch unreachable;

    const conf_dir = blk: {
        //const dir = win.getPrefPath("nik_org", "test_gui");
        //if (dir) |dd| {
        //    break :blk try std.fs.openDirAbsoluteZ(dd, .{});
        //}
        break :blk std.fs.cwd();
    };
    //defer conf_dir.close();

    var fb = try FileBrowser.init(alloc, conf_dir);
    defer fb.deinit();

    while (!win.should_exit) {
        try ctx.beginDraw(win.screen_width, win.screen_height, itc(0x2f2f2fff), true);
        defer dcall_count = ctx.call_count;
        win.pumpEvents(); //Important that this is called after beginDraw for input lag reasons

        switch (gui.text_input_state) {
            .start => win.startTextInput(),
            .stop => win.stopTextInput(),
            ._continue => gui.text_input = win.text_input,
            .disabled => {},
        }

        gui_timer.reset();
        Gui.hash_time = 0;
        try gui.reset(.{
            .mouse_pos = win.mouse.pos,
            .mouse_delta = win.mouse.delta,
            .mouse_left_held = win.mouse.left == .high,
            .mouse_left_clicked = win.mouse.left == .rising,
            .mouse_wheel_delta = win.mouse.wheel_delta.y,
            .mouse_wheel_down = win.mouse.middle == .high,
            .keyboard_state = &win.keyboard_state,
            .keys = win.keys.slice(),
        });
        defer percent_usage = @as(f32, @floatFromInt(stack_alloc.end_index)) / 1000;

        gui_time = gui_timer.read();
        rbuf.put(gui_time);

        {
            const r = graph.Rec(0, 0, win.screen_width, win.screen_height);
            parent_area = r;
            //parent_area = graph.Rec(r.x + r.w / 4, r.y + r.h / 4, r.w / 2, r.h / 2);
            //_ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = parent_area }, .{});
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = parent_area }, .{});
            defer gui.endLayout();
            try test_win.update(&gui);
            //try fb.update(&gui);
        }

        try gui_draw_context.draw(&ctx, &font, parent_area, &gui, win.screen_width, win.screen_height);
        const fs = 40;
        var cy = struct {
            val: f32 = 300,
            fn get(self: *@This()) f32 {
                self.val += fs;
                return self.val;
            }
        }{};

        //ctx.drawRect(graph.Rec(0, 0, 1000, 1000), Color.Green);
        //ctx.drawTextFmt(0, cy.get(), "Popped: {any}", .{gui.last_frame_had_popup}, &font, fs, Color.White);
        //ctx.drawTextFmt(0, cy.get(), "Time : {d:.2}ms", .{@intToFloat(f32, rbuf.avg()) / std.time.ns_per_ms}, &font, fs, Color.White);
        //ctx.drawTextFmt(0, cy.get(), "Cache: {d:.2}ms", .{@intToFloat(f32, gui.layout_cache.last_time) / std.time.ns_per_ms}, &font, fs, Color.White);
        //ctx.drawTextFmt(0, cy.get(), "Hash: {d:.2}ms", .{@intToFloat(f32, Gui.hash_time) / std.time.ns_per_ms}, &font, fs, Color.White);
        //ctx.drawTextFmt(0, cy.get(), "Calls {d}", .{dcall_count}, &font, fs, Color.White);
        //ctx.drawTextFmt(0, cy.get(), "Cmds  {d}", .{gui.command_list.items.len}, &font, fs, Color.White);
        //ctx.drawTextFmt(0, cy.get(), "size: {d} {d}", .{ parent_area.w, parent_area.h }, &font, fs, Color.White);
        //ctx.drawTextFmt(0, cy.get(), "Str space: {d}%", .{@intToFloat(f32, gui.str_index) / @intToFloat(f32, gui.strings.len) * 100}, &font, fs, Color.White);
        //ctx.drawTextFmt(0, cy.get(), "{u}", .{0xEB7B}, &icons, fs, Color.White);

        graph.c.glDisable(graph.c.GL_STENCIL_TEST);
        //try ctx.drawRectTex(graph.Rec(0, 0, 1000, 1000), ts_tex.rect(), itc(0xffffffff), ts_tex);
        if (draw_line_debug) {
            var y: f32 = cy.get();
            var it = gui.layout_cache.first;
            while (it != null) : (it = it.?.next) {
                const color = if (gui.mouse_grabbed_by_hash) |h| if (h == it.?.data.hash) Color.Blue else Color.White else Color.White;
                if (it.?.data.was_init) {
                    ctx.drawRect(graph.Rec(0, y, fs, fs), Color.Red);
                }
                ctx.drawTextFmt(0, y, "{s}{d}", .{ nspace(it.?.depth * 2), it.?.data.hash & 0xfff }, &font, fs, color);
                y = cy.get();
                const dd = it.?.data.rec;
                const xx = dd.x - 400 + @as(f32, @floatFromInt(it.?.depth)) * 40;
                const h = dd.h;
                const of = h * 0.2;
                try ctx.drawLine(.{ .x = @as(f32, @floatFromInt(it.?.depth)) * fs + 30, .y = y - fs / 2 }, .{ .x = xx, .y = dd.y + dd.h / 2 }, Color.Red);
                try ctx.drawLine(.{ .x = xx, .y = dd.y + of }, .{ .x = xx, .y = dd.y + dd.h - 2 * of }, Color.Blue);
                try ctx.drawLine(.{ .x = xx, .y = dd.y + of }, .{ .x = dd.x, .y = dd.y }, Color.Blue);
                try ctx.drawLine(.{ .x = xx, .y = dd.y + dd.h - 2 * of }, .{ .x = dd.x, .y = dd.y + dd.h }, Color.Blue);
            }
        }

        ctx.endDraw(null);
        win.swap();
    }
}
