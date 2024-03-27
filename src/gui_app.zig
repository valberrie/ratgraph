const std = @import("std");
const graph = @import("graphics.zig");
const Rect = graph.Rect;
const Rec = graph.Rec;
const itc = graph.itc;
const Pad = graph.Padding;
//TODO it would be usefull to have types with owners?
//we get a string from lua

const lua = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});

const ArgUtil = @import("arg_gen.zig");
const Color = graph.CharColor;
//const Gui = @import("gui.zig");
const Gui = graph.Gui;
const Vec2f = graph.Vec2f;

const bg1 = itc(0xff);
const fg = itc(0xffffffff);
const bg4 = itc(0xff);
const bg2 = itc(0xff);
const bg0 = itc(0xff);

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
            name: []const u8,
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

    pub fn A(name: []const u8) Node {
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

        return @Type(.{ .Struct = .{ .layout = .Auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
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

pub const FileBrowser = struct {
    //TODO
    //Fix the layouting issues.
    //Fix the color issues
    //Fix the scrollbar disappearing
    //add mouse scrolling
    //right click menu?
    //  Add directory to bookmarks
    //Prevent crashes when file can't be accsesd
    const Self = @This();

    pub const Extensions = enum {
        png,
        bmp,
        jpg,
        jpeg,
        tga,
        json,
        txt,
        zig,
        unknown,

        pub fn isImage(self: Extensions) bool {
            return switch (self) {
                .png, .bmp, .jpg, .jpeg => true,
                else => false,
            };
        }
    };

    pub const Bookmark = struct {
        /// These two fields are allocated
        abs_path: []const u8,
        name: []const u8,
        /// This field is never allocated
        err_msg: ?[]const u8 = null,
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
    pub const DefaultBookmarks: []const Bookmark = &.{
        .{ .name = "crash lol", .abs_path = "/usr/bin" },
        .{ .name = "crash lol", .abs_path = "/root" },
        .{ .name = "Home", .abs_path = "/home/tony" },
        .{ .name = "Gui repo", .abs_path = "/home/tony/user-data/develpment/zig-gui" },
        .{ .name = "Mario", .abs_path = "/home/tony/user-data/develpment/zig_rat_game/asset" },
    };

    pub const FilePreview = struct {
        texture: graph.Texture,

        pub fn deinit(self: *FilePreview) void {
            self.texture.deinit();
        }
    };

    pub const DialogState = enum {
        none,
        add_bookmark,
    };

    pub const ParentFlag = enum {
        normal,
        should_exit,
        ok_clicked,
    };

    file_preview: ?FilePreview = null,
    scratch_vec: std.ArrayList(u8),
    dialog_state: DialogState = .none,
    flag: ParentFlag = .normal,

    alloc: std.mem.Allocator,
    entries: std.ArrayList(DirEntry),
    dir: std.fs.Dir,
    file: ?struct { file_name: []const u8, dir: std.fs.Dir } = null,

    file_scroll: graph.Vec2f = .{ .x = 0, .y = 0 },

    selected_name: std.ArrayList(u8),
    selected_bookmark: ?usize = null,
    selected: ?usize = null,
    show_hidden: bool = true,
    bar_pos: ?f32 = null,

    path_str: ?[]const u8 = null,

    bookmarks: std.ArrayList(Bookmark),
    console: Gui.Console,

    columns: [4]FileColumn = [_]FileColumn{
        .{ .width = 300, .kind = .name },
        .{ .width = 200, .kind = .mtime },
        .{ .width = 100, .kind = .size },
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
        var ret = Self{
            .alloc = alloc,
            .entries = std.ArrayList(DirEntry).init(alloc),
            .dir = cwd,
            .conf_dir = settings_dir,
            .selected_name = std.ArrayList(u8).init(alloc),
            .bookmarks = std.ArrayList(Bookmark).init(alloc),
            .console = Gui.Console.init(alloc),
            .scratch_vec = std.ArrayList(u8).init(alloc),
        };

        for (DefaultBookmarks) |db| {
            try ret.bookmarks.append(.{
                .name = try alloc.dupe(u8, db.name),
                .abs_path = try alloc.dupe(u8, db.abs_path),
                .err_msg = db.err_msg,
            });
        }

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

        //TODO what if this fails?
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
        self.selected_name.deinit();
        for (self.bookmarks.items) |b| {
            self.alloc.free(b.name);
            self.alloc.free(b.abs_path);
        }
        self.bookmarks.deinit();
        self.console.deinit();
        self.scratch_vec.deinit();
    }

    pub fn sort_entries(self: *Self, ctx: DirEntry.CompareContext) void {
        std.sort.heap(DirEntry, self.entries.items, ctx, DirEntry.compare);
    }

    pub fn popuplate_entries(self: *Self) !void {
        self.file_scroll = .{ .x = 0, .y = 0 };
        var it_dir = self.dir.openIterableDir(".", .{}) catch {
            self.dir = try self.dir.openDir("..", .{});
            self.clear_entries();
            self.popuplate_entries() catch |err| {
                std.debug.print("This is really bad\n", .{});
                return err;
            };
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

    fn filepreview(self: *Self, wrap: *Os9Gui) !void {
        const gui = wrap.gui;
        const area = gui.getArea() orelse return;
        gui.draw9Slice(area, Os9Gui.inset9, wrap.texture, wrap.scale);
        const na = area.inset(Os9Gui.inset9.w / 3);
        if (self.file_preview) |fp| {
            gui.drawRectTextured(na, Color.White, fp.texture.rect(), fp.texture);
        }
    }

    fn fileItem(self: *Self, gui: *Gui.Context, entry: DirEntry, index: usize, columns: []const FileColumn, bg: ?Color) !bool {
        const rec = gui.getArea() orelse return false;
        const pada = 4;
        if (bg) |bb| {
            gui.drawRectFilled(rec, bb);
        }
        var cx: f32 = 0;
        if (index == self.selected)
            gui.drawRectFilled(rec, Os9Gui.blue);
        for (columns) |col| {
            const r = graph.Rec(pada + rec.x + cx, rec.y, col.width - pada, rec.h);
            defer cx += col.width; //defer so continue; still applies width
            switch (col.kind) {
                .name => {
                    const ico = graph.Rec(rec.x, rec.y, rec.h, rec.h);
                    gui.drawIcon(Icons.get(switch (entry.kind) {
                        .directory => .folder,
                        .sym_link => .folder_link,
                        .file => switch (getExtension(entry.name)) {
                            .zig, .json => .src_file,
                            .png => .img_file,
                            .txt => .txt_file,
                            else => .file,
                        },
                        else => .file,
                    }), .{ .x = ico.x, .y = ico.y + ico.h / 3 }, ico.h * 0.7, Color.Black);
                    const ir = graph.Rec(r.x + ico.w, r.y, r.w - ico.w, r.h);
                    if (gui.font.nearestGlyphX(entry.name, rec.h, .{ .x = col.width - ico.w, .y = rec.h / 2 })) |glyph_index| {
                        if (glyph_index > 2)
                            gui.drawTextFmt("{s}…", .{entry.name[0..glyph_index]}, ir, rec.h, Color.Black, .{});
                    } else {
                        gui.drawTextFmt("{s}", .{entry.name}, ir, rec.h, Color.Black, .{});
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
                    gui.drawTextFmt("{d: >3}{s}", .{ val[0], val[1] }, r, rec.h, Color.Black, .{});
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
                    }, r, r.h * 0.8, Color.Black, .{});
                },
                .ftype => {
                    gui.drawTextFmt("{s}", .{@tagName(entry.kind)}, r, r.h * 0.8, Color.Black, .{});
                },
            }
        }
        //const time_rec = graph.Rec(rec.x + rec.w / 2, rec.y, rec.w / 4, rec.h);
        //const type_rec = graph.Rec(time_rec.x + time_rec.w, time_rec.y, time_rec.w, rec.h);

        const click = gui.clickWidget(rec);
        if (click == .click) {
            self.selected = index;

            try self.selected_name.resize(0);
            try self.selected_name.writer().print("{s}", .{entry.name});
        }

        if (click == .double) {
            self.selected_bookmark = null;
            switch (entry.kind) {
                .directory => {
                    self.file_scroll = .{ .x = 0, .y = 0 };
                    if (try self.cd(entry.name))
                        return true;
                },
                .file => {
                    self.file = .{ .file_name = entry.name, .dir = self.dir };
                },
                else => {},
            }
        }
        return false;
    }

    pub fn cd(self: *Self, path: []const u8) !bool {
        if (self.dir.openDir(path, .{}) catch null) |new_dir| {
            if (try self.setDir(new_dir, path))
                return true;
        }
        std.debug.print("Can't open directory {s}\n", .{path});
        return false;
    }

    pub fn setDir(self: *Self, dir: std.fs.Dir, name_for_debug: []const u8) !bool {
        //This stat is needed as openDir can return an unreadable directory.
        if (dir.statFile(".") catch null) |stat| {
            _ = stat;
            self.dir = dir;
            self.clear_entries();
            try self.popuplate_entries();
            try self.selected_name.resize(0);
            self.selected = null;
            self.selected_bookmark = null;
            return true;
        } else {
            std.debug.print("Can open directory but can't read {s}\n", .{name_for_debug});
        }
        return false;
    }

    pub fn update(self: *Self, wrap: *Os9Gui) !void {
        const gui = wrap.gui;
        const item_height = 35;
        const win_area = gui.getArea() orelse return;
        const border_area = win_area.inset(6 * wrap.scale);
        const area = border_area.inset(6 * wrap.scale);
        const w_id = gui.getId();

        const popup_area = area.inset(area.w / 5);
        if (gui.isActivePopup(w_id)) {
            try gui.beginPopup(popup_area);
            defer gui.endPopup();
            gui.draw9Slice(popup_area, Os9Gui.os9win, wrap.texture, wrap.scale);
            gui.draw9Slice(popup_area.inset(6 * wrap.scale), Os9Gui.os9in, wrap.texture, wrap.scale);
            switch (self.dialog_state) {
                .none => {},
                .add_bookmark => {
                    //TODO subrectlayout should have a function that scales it so we can avoid so many nested subrect layouts
                    _ = try wrap.beginSubLayout(popup_area.inset(12 * wrap.scale), Gui.VerticalLayout, .{ .item_height = item_height });
                    defer wrap.endSubLayout();
                    wrap.label("Add new bookmark", .{});
                    wrap.label("Path: {s}", .{self.path_str.?});
                    {
                        _ = try gui.beginLayout(Gui.HorizLayout, .{ .count = 2 }, .{});
                        defer gui.endLayout();
                        wrap.labelEx("Name: ", .{}, .{ .justify = .right });
                        try wrap.textbox(&self.scratch_vec);
                    }
                    if (wrap.buttonEx("Add", .{ .disabled = self.scratch_vec.items.len == 0 })) {
                        try self.bookmarks.append(.{
                            .name = try self.alloc.dupe(u8, self.scratch_vec.items),
                            .abs_path = try self.alloc.dupe(u8, self.path_str.?),
                        });
                        gui.popup_id = null;
                    }
                    if (wrap.button("Cancel")) {
                        gui.popup_id = null;
                    }
                },
            }
        }

        {
            if (self.bar_pos == null)
                self.bar_pos = area.w / 4;
        }

        const root = area.split(.vertical, self.bar_pos.?);
        const left_side_outer = root[0];
        const main_t = root[1];
        const first_child = main_t.split(.horizontal, item_height + 6 * wrap.scale);

        const header_bar = first_child[0].insetV(6 * wrap.scale, 1 * wrap.scale);
        const second_child = first_child[1].split(.horizontal, first_child[1].h - item_height * 2);
        const main_area = second_child[0].inset(6 * wrap.scale);
        const bottom_bar = second_child[1].insetV(6 * wrap.scale, 1 * wrap.scale);

        const left_side = left_side_outer.inset(6 * wrap.scale);
        const sep_bar = Rect.new(left_side.x + left_side.w, left_side.y, main_area.x - (left_side.x + left_side.w), left_side.h);
        gui.draw9Slice(win_area, Os9Gui.os9win, wrap.texture, wrap.scale);
        gui.draw9Slice(border_area, Os9Gui.os9in, wrap.texture, wrap.scale);
        gui.draw9Border(left_side_outer, Os9Gui.os9line, wrap.texture, wrap.scale, 0, 0);

        var unused: f32 = 0;
        _ = gui.draggable(sep_bar, .{ .x = 1, .y = 0 }, &(self.bar_pos.?), &unused, .{ .x_min = area.w / 8, .x_max = area.w - area.w / 8 });

        {
            _ = try wrap.beginSubLayout(header_bar, Gui.HorizLayout, .{ .count = 3 });
            defer wrap.endSubLayout();
            if (wrap.checkbox("Show hidden", &self.show_hidden)) {
                _ = try self.setDir(self.dir, ".");
            }
            if (wrap.button("Up")) {
                _ = try self.cd("..");
            }
            wrap.label("Path: {s}", .{if (self.path_str) |str| str else ""});
        }
        const ils = left_side.inset(6);
        const sp = ils.split(.horizontal, ils.h / 2);
        {
            _ = try wrap.beginSubLayout(sp[0], Gui.VerticalLayout, .{ .item_height = item_height });
            defer wrap.endSubLayout();
            wrap.label("Places", .{});
            for (self.bookmarks.items, 0..) |*bookmark, i| {
                const rec = gui.getArea() orelse break;
                if (self.selected_bookmark) |sb| {
                    if (sb == i)
                        gui.drawRectFilled(rec, Os9Gui.blue);
                }
                //const vpad = rec.h * 0.1;
                //const tpos = graph.Vec2f.new(rec.x, rec.y + vpad);
                const color = if (bookmark.err_msg != null) Color.Red else Color.Black;
                const tr = blk: {
                    if (bookmark.err_msg != null) {
                        const d = rec.split(.vertical, rec.h);
                        gui.drawRectTextured(d[0], Color.White, Os9Gui.win_warning, wrap.texture);
                        break :blk d[1];
                    } else {
                        break :blk rec;
                    }
                };
                gui.drawTextFmt("{s}", .{bookmark.name}, tr, tr.h, color, .{});
                gui.tooltip(bookmark.abs_path, rec.h);
                const click = gui.clickWidget(rec);
                if (click == .click) {
                    if (try self.cd(bookmark.abs_path)) {
                        bookmark.err_msg = null;
                    } else {
                        bookmark.err_msg = "Can't open bookmark";
                    }
                    self.selected_bookmark = i;
                }
            }
        }
        {
            var vl = try wrap.beginSubLayout(sp[1], Gui.VerticalLayout, .{ .item_height = item_height });
            defer wrap.endSubLayout();

            if (wrap.button("Add current Folder as bookmark")) {
                gui.popup_id = w_id;
                gui.last_frame_had_popup = true;
                try self.scratch_vec.resize(0);
                self.dialog_state = .add_bookmark;
            }
            if (wrap.buttonEx("Remove selected bookmark", .{ .disabled = self.selected_bookmark == null })) {
                if (self.selected_bookmark) |sb| {
                    if (sb < self.bookmarks.items.len) {
                        const b = self.bookmarks.items[sb];
                        std.debug.print("Removing bookmark Path: {s} Name: {s}\n", .{ b.abs_path, b.name });
                        self.alloc.free(b.abs_path);
                        self.alloc.free(b.name);
                        _ = self.bookmarks.orderedRemove(sb);
                    }
                    if (self.selected_bookmark.? >= self.bookmarks.items.len) {
                        // By only setting this to null here we allow the user to delete multiple bookmarks in a row
                        self.selected_bookmark = null;
                    }
                }
            }
            {
                vl.pushRemaining();
                try self.filepreview(wrap);
            }
        }
        {
            gui.draw9Slice(main_area, Os9Gui.inset9, wrap.texture, wrap.scale);
            const ima = main_area.inset(wrap.scale * Os9Gui.inset9.w / 3);
            const root1 = ima.split(.horizontal, item_height);
            {
                const fheader = root1[0];
                gui.draw9Slice(fheader, Os9Gui.window9, wrap.texture, wrap.scale);
                _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = fheader }, .{});
                defer gui.endLayout();
                const rec = gui.getArea() orelse return;
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
                    //gui.drawRectFilled(handle, bg0);
                    cx += cc.width;
                }
                cx = 0;
                for (self.columns, 0..) |cc, i| {
                    gui.drawText(switch (cc.kind) {
                        .name => " Name",
                        .mtime => "Modified",
                        .ftype => "Kind",
                        .size => "Size",
                    }, Vec2f.new(rec.x + cx, rec.y), rec.h, Color.Black);
                    if (i == self.sorted_column_index) {
                        gui.drawIcon(Icons.get(
                            if (!self.sorted_column_ascending) .drop_up else .drop_down,
                        ), .{ .x = rec.x + cx + cc.width - rec.h, .y = rec.y }, rec.h, Color.Black);
                    }
                    if (gui.clickWidget(graph.Rec(rec.x + cx, rec.y, cc.width, rec.h)) == .click) {
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
            const sa = root1[1];
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = sa }, .{});
            defer gui.endLayout();
            if (try wrap.beginVScroll(&self.file_scroll)) |file_scroll| {
                defer wrap.endVScroll(file_scroll);
                for (self.entries.items, 0..) |entry, i| {
                    const bgfile_color = itc(0xeeeeeeff);
                    if (try self.fileItem(gui, entry, i, &self.columns, if (i % 2 != 0) bgfile_color else null))
                        break;
                }
            }
            var cx: f32 = 0;
            for (self.columns) |cc| {
                cx += cc.width;
                gui.drawLine(Vec2f.new(sa.x + cx, sa.y), Vec2f.new(sa.x + cx, sa.y + sa.h), Color.Black);
            }
        }
        {
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = bottom_bar }, .{});
            defer gui.endLayout();
            var hl = try gui.beginLayout(Gui.HorizLayout, .{ .count = 4 }, .{});
            defer gui.endLayout();
            hl.pushCount(2);
            try wrap.textbox(&self.selected_name);
            if (wrap.button("Cancel")) {
                self.flag = .should_exit;
            }
            if (wrap.buttonEx("Ok", .{ .disabled = !(if (self.selected) |si| self.entries.items[si].kind == .file else false) })) {
                self.file = .{ .file_name = self.entries.items[self.selected.?].name, .dir = self.dir };
                self.flag = .ok_clicked;
            }
        }
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
        const gui = wrap.gui;
        const win_area = gui.getArea() orelse return;
        const border_area = win_area.inset(6 * wrap.scale);
        const area = border_area.inset(6 * wrap.scale);
        const keyboard = Ansi104;

        gui.draw9Slice(win_area, Os9Gui.os9win, wrap.texture, wrap.scale);
        gui.draw9Slice(border_area, Os9Gui.os9in, wrap.texture, wrap.scale);

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
                var y: f32 = row.y * kh;
                for (row.keys) |key| {
                    const ww = key.width * kw;
                    switch (key.ktype) {
                        .key => {
                            const rr = Rect.new(r.x + x, r.y + y, ww, kh);
                            gui.draw9Slice(rr.inset(3), Os9Gui.outset9, wrap.texture, wrap.scale);
                            const tr = rr.inset(Os9Gui.outset9.w / 3 * wrap.scale + 3);

                            if (key.name) |n| {
                                gui.drawTextFmt("{s}", .{n}, tr, 20 * wrap.scale, Color.Black, .{});
                            }
                        },
                        .spacing => {},
                    }
                    x += ww;
                }
            }
            //gui.drawRectMultiColor(r, [_]Color{ itc(0xffffffff), itc(0xff0000ff), itc(0x00ff00ff), itc(0x0000ffff) });
            //gui.drawRectMultiColor(r, [_]Color{ itc(0x888888ff), itc(0x222222ff), itc(0x222222ff), itc(0x888888ff) });
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
                if (gui.mouse_grabbed_by_hash == null and canvas.containsPoint(gui.input_state.mouse_pos)) {
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

    pub fn update(self: *Self, wrap: *Os9Gui) !void {
        const gui = wrap.gui;
        const win_area = gui.getArea() orelse return;
        const border_area = win_area.inset(6 * wrap.scale);
        const area = border_area.inset(6 * wrap.scale);
        const w_id = gui.getId();
        _ = w_id;
        gui.draw9Slice(win_area, Os9Gui.os9win, wrap.texture, wrap.scale);
        gui.draw9Slice(border_area, Os9Gui.os9in, wrap.texture, wrap.scale);

        const root = area.split(.vertical, area.w / 3);
        const inspector_rec = root[0];
        const canvas_outer = root[1];
        const canvas_b = canvas_outer.inset(6 * wrap.scale);
        gui.draw9Slice(canvas_b, Os9Gui.inset9, wrap.texture, wrap.scale);
        const canvas = canvas_b.inset(wrap.scale * Os9Gui.inset9.w / 3);

        const inspector_item_height = 20;
        _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = canvas }, .{});
        defer gui.endLayout();
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
            if (gui.mouse_grab_id == null and canvas.containsPoint(gui.input_state.mouse_pos)) {
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

                const marquee = gui.clickWidgetEx(graph.Rec(0, 0, 0, 0), .{ .teleport_area = canvas });
                switch (marquee.click) {
                    else => {},
                    .click_teleport => {
                        self.marquee = graph.Rec(0, 0, 0, 0);
                        self.marquee.x = gui.input_state.mouse_pos.x;
                        self.marquee.y = gui.input_state.mouse_pos.y;
                    },
                    .held => {
                        self.marquee.w = (gui.input_state.mouse_pos.x) - self.marquee.x;
                        self.marquee.h = (gui.input_state.mouse_pos.y) - self.marquee.y;
                    },
                    .none => {},
                    .click_release => {
                        cam.cam_area = cam.toCam(self.marquee);
                        if (self.marquee.w < 1 or self.marquee.h < 1) {
                            cam.cam_area = tex.rect();
                        }
                        self.marquee = graph.Rec(0, 0, 0, 0);
                    },
                }
                gui.drawRectOutline(self.marquee, Color.White);

                gui.scissor(null);
            }
        } else {
            if (self.file_browser == null)
                self.file_browser = try FileBrowser.init(self.alloc, std.fs.cwd());

            try self.file_browser.?.update(wrap);
            if (self.file_browser.?.file) |file| {
                self.loaded_atlas = graph.Atlas.initFromJsonFile(file.dir, file.file_name, self.alloc) catch blk: {
                    try gui.console.print("Unable to load \"{s}\" as an atlas manifest", .{file.file_name});
                    self.file_browser.?.file = null;
                    break :blk null;
                };
            }
        }
        { //Inspector
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = inspector_rec }, .{});
            defer gui.endLayout();
            if (try wrap.beginVScroll(&self.inspector_scroll)) |inspector_scroll| {
                defer wrap.endVScroll(inspector_scroll);
                if (self.loaded_atlas) |*atlas| {
                    //if (try gui.beginVLayoutScroll(&self.set_scroll, .{ .item_height = inspector_item_height })) |set_scroll| {
                    for (atlas.atlas_data.sets, 0..) |*set, si| {
                        inspector_scroll.layout.pushHeight(inspector_item_height * 3);
                        {
                            _ = try gui.beginLayout(Gui.VerticalLayout, .{ .item_height = inspector_item_height }, .{});
                            defer gui.endLayout();
                            if (wrap.button(set.filename)) {
                                try gui.console.print("Setting new index {d} {d}", .{ 0, si });
                                gui.text_input_state.active_id = null;
                                gui.text_input_state.state = .stop;
                                self.canvas_cam = null;
                                self.set_index = 0;
                                self.atlas_index = si;
                            }
                            if (wrap.button("new set")) {
                                std.debug.print("Sett {d}\n", .{set.tilesets.len});
                                const index = set.tilesets.len;
                                set.tilesets = try atlas.alloc.realloc(set.tilesets, set.tilesets.len + 1);
                                set.tilesets[set.tilesets.len - 1] = self.new_ts_default;
                                self.set_index = index;
                            }
                        }
                        for (set.tilesets, 0..) |ts, tsi| {
                            const rec = gui.getArea() orelse continue;
                            var col = Color.White;
                            if (self.mode == .copy_range) {
                                if (self.atlas_index == si and tsi < self.copy_range_range_end and tsi >= self.copy_range_range_start) {
                                    col = Color.Green;
                                }
                            }
                            gui.drawText(if (ts.description.len > 0) ts.description else "{blank}", rec.pos(), rec.h, col);
                            const click = gui.clickWidget(rec);
                            if (click == .click) {
                                if (self.atlas_index != si) {
                                    self.copy_range_range_start = 0;
                                    self.copy_range_range_end = 0;
                                }
                                try gui.console.print("Setting new index {d} {d}", .{ tsi, si });
                                gui.text_input_state.active_id = null;
                                gui.text_input_state.state = .stop;
                                self.canvas_cam = null;
                                self.set_index = tsi;
                                self.atlas_index = si;
                            }
                        }
                    }
                    //try gui.endVLayoutScroll(set_scroll);
                    //}
                    if (atlas.atlas_data.sets[self.atlas_index].tilesets.len > 0) {
                        //try wrap.textbox(&atlas.atlas_data.sets[self.atlas_index].tilesets[self.set_index].description);

                        const sts = &atlas.atlas_data.sets[self.atlas_index].tilesets[self.set_index];

                        //try gui.printLabel("Tile count: {d}", .{sts.count});
                        wrap.slider(&sts.count, 1, 1000); //Count
                        wrap.slider(&sts.num.x, 1, 1000); //Num x
                        wrap.slider(&sts.num.y, 1, 1000); //num y
                        wrap.slider(&sts.tw, 1, 1000); //twe
                        wrap.slider(&sts.th, 1, 1000); //th
                    }

                    _ = wrap.checkbox("overlay unfocused", &self.draw_unfocused_overlay);
                    if (wrap.button("Save file")) {
                        const f = self.file_browser.?.file.?;
                        const fname = "testoutput.json";
                        var out_file = try f.dir.createFile(fname, .{});
                        defer out_file.close();
                        try std.json.stringify(atlas.atlas_data, .{}, out_file.writer());
                        try gui.console.print("Saving to file: {s}", .{fname});
                    }
                    if (wrap.button("set current as default")) {
                        self.new_ts_default = atlas.atlas_data.sets[self.atlas_index].tilesets[self.set_index];
                        self.new_ts_default.description = "";
                    }
                    try wrap.enumDropdown(Mode, &self.mode);
                    switch (self.mode) {
                        .copy_range => {
                            const max_index: f32 = @floatFromInt(atlas.atlas_data.sets[self.atlas_index].tilesets.len);

                            wrap.slider(&self.copy_range_offset_x, -1000, 1000);
                            wrap.slider(&self.copy_range_offset_y, -1000, 1000);
                            wrap.slider(&self.copy_range_range_start, 0, max_index);
                            wrap.slider(&self.copy_range_range_end, 0, max_index);
                            //wrap.textbox(&self.copy_range_desc_prefix, self.alloc);
                            _ = blk: {
                                if (wrap.button("Push copy")) {
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
                            // try gui.textbox(&self.add_image_filename, self.alloc);

                            if (wrap.button("add set")) {
                                atlas.addSet(self.add_image_filename) catch |err| switch (err) {
                                    error.FileNotFound => try gui.console.print("error: Unable to add set. Image file not found: {s}", .{self.add_image_filename}),
                                    else => return err,
                                };
                            }
                        },
                        else => {},
                    }
                }
                //inspector_scroll.layout.pushHeight(inspector_item_height * 50);
                //gui.drawConsole(gui.console, inspector_item_height);
            }
        }
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
pub const Os9Gui = struct {
    const Self = @This();

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

    const border = itc(0xff);
    const wbg = itc(0xaaaaaaff);
    const shadow = itc(0x555555ff);
    const light = itc(0xffffffff);
    const blue = itc(0xccccffff);

    //Define the different 9slices in "texture"
    const inset9 = Rec(0, 0, 6, 6);
    const outset9 = Rec(0, 6, 6, 6);
    const window9 = Rec(6, 6, 6, 6);
    const title9 = Rec(6, 0, 6, 6);
    const divider = Rec(12, 0, 1, 2);

    const text_disabled = itc(0x222222ff);

    const os9win = Rec(0, 12, 6, 6);
    const os9in = Rec(6, 12, 6, 6);
    const os9line = Rec(0, 18, 6, 6);
    const os9drop = Rec(6, 18, 6, 6);
    const os9btn = Rec(12, 0, 12, 12);
    const os9btn_disable = Rec(26, 37, 12, 12);
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
    const os9scrollinner = Rec(0, 44, 8, 8);
    const os9scrollhandle = Rec(9, 44, 14, 15);
    const os9scrollw = 16;
    const os9handleoffset = 1;

    const win_warning = Rec(0, 60, 32, 32);

    //lua specific state
    vlayout: ?*Gui.VerticalLayout = null,

    texture: graph.Texture,
    scale: f32,
    gui: *Gui.Context,

    pub fn init(alloc: std.mem.Allocator, scale: f32, gui: *Gui.Context) !Self {
        const dir = std.fs.cwd();
        return .{
            .gui = gui,
            .scale = scale,
            .texture = try graph.Texture.initFromImgFile(alloc, dir, "next_step.png", .{ .mag_filter = graph.c.GL_NEAREST }),
        };
    }
    pub fn deinit(self: *Self) void {
        self.texture.deinit();
    }

    //TODO remove scale variable and scale using GuiDrawContext
    pub fn update(self: *Self) !void {
        const gui = self.gui;
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
            vl.current_h += vl.padding.bottom;
            _ = self.button("Click me");
            vl.pushHeight(vl.item_height * 4);
            _ = try gui.beginLayout(Gui.HorizLayout, .{ .count = 2 }, .{});
            const buttons = [_][]const u8{ "Opt 1", "two", "Just save", "Load It" };
            for (0..2) |_| {
                _ = try gui.beginLayout(Gui.VerticalLayout, .{ .item_height = nh }, .{});
                for (buttons) |btn| {
                    _ = self.button(btn);
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
            self.checkbox("Checkbox", &self.sample_data.flag);
            gui.tooltip("This checkbox sucks", ts);
            vl.pushHeight(os9tabstart.h * scale);
            _ = try self.tabs(SampleEnum, &self.sample_data.en);
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
            _ = self.button("hello");
            _ = self.button("hello");
            gui.tooltip("Pressing this button causes great pain", ts);

            try self.enumDropdown(SampleEnum, &self.sample_data.en);
            try self.enumDropdown(Icons, &self.sample_data.icon);
            self.sliderOpts(&self.sample_data.float, -10, 200);
            //self.scrollBar(&self.sample_data.float, -100, 200, .horizontal);
            try self.textbox(&self.sample_data.ar_str);
            try self.textbox(&self.sample_data.ar_str);
            try self.textboxNumber(&self.sample_data.int_edit);
            try self.textboxNumber(&self.sample_data.float);
            gui.tooltip("This number represents my death", ts);
            try self.textboxNumber(&self.sample_data.uint_edit);
            {
                _ = try gui.beginLayout(Gui.HorizLayout, .{ .count = 2 }, .{});
                defer gui.endLayout();
                const aa = (gui.getArea() orelse return).inset(3 * self.scale);
                gui.drawTextFmt("My float", .{}, aa, aa.h, Color.Black, .{});
                try self.textboxNumber(&self.sample_data.float_edit);
            }
            vl.pushHeight(100 * scale);
            const hhh = 100 * scale;
            if (try gui.beginScroll(&self.scroll_offset, .{ .bar_w = 14 * scale, .scroll_area_w = 100 * scale, .scroll_area_h = hhh })) |scroll| {
                {
                    gui.drawRectFilled(gui.scroll_bounds.?, Color.Gray);
                    defer gui.endScroll();
                    _ = try gui.beginLayout(Gui.VerticalLayout, .{ .item_height = 20 * scale }, .{});
                    defer gui.endLayout();
                    if (self.button("hello button")) {
                        try gui.console.print("pushed the button lol\n", .{});
                    }
                }
                {
                    const sd = scroll;
                    if (sd.vertical_slider_area) |va| {
                        _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = va }, .{});
                        defer gui.endLayout();
                        const smax = hhh;
                        self.scrollBar(&sd.offset.y, 0, smax, .vertical);
                    }
                    if (sd.horiz_slider_area) |ha| {
                        _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = ha }, .{});
                        defer gui.endLayout();
                        const smax = hhh;
                        self.scrollBar(&sd.offset.x, 0, smax, .horizontal);
                    }
                }
            }
            vl.pushHeight(100 * scale);
            gui.drawConsole(gui.console, ts);
        }
    }

    pub fn beginSubLayout(self: *Self, sub: Rect, comptime Layout_T: type, layout_data: Layout_T) !*Layout_T {
        _ = try self.gui.beginLayout(Gui.SubRectLayout, .{ .rect = sub }, .{});
        return try self.gui.beginLayout(Layout_T, layout_data, .{});
    }

    pub fn endSubLayout(self: *Self) void {
        self.gui.endLayout();
        self.gui.endLayout();
    }

    pub fn beginVScroll(self: *Self, scr: *Vec2f) !?Gui.Context.VLayoutScrollData {
        const scale = self.scale;
        if (try self.gui.beginScroll(scr, .{
            .vertical_scroll = true,
            .bar_w = os9scrollw * scale,
            .scroll_area_w = 10000 * scale,
            .scroll_area_h = 100000,
        })) |scroll| {
            const lrq = self.gui.layout.last_requested_bounds;
            return .{ .layout = try self.gui.beginLayout(Gui.VerticalLayout, .{ .item_height = 20 * scale }, .{}), .data = scroll, .area = lrq orelse graph.Rec(0, 0, 0, 0) };
        }
        return null;
    }

    pub fn endVScroll(self: *Self, scroll_data: Gui.Context.VLayoutScrollData) void {
        const sd = scroll_data.data;
        const max = scroll_data.layout.current_h - scroll_data.area.h;
        if (max > 0) {
            if (self.gui.mouse_grab_id == null and !self.gui.scroll_claimed_mouse and self.gui.scroll_bounds.?.containsPoint(self.gui.input_state.mouse_pos)) {
                self.gui.scroll_claimed_mouse = true;
                const pixel_per_line = 20 * self.scale;
                sd.offset.y = std.math.clamp(sd.offset.y + self.gui.input_state.mouse_wheel_delta * -pixel_per_line * 3, 0, max);
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

    pub fn tabs(self: *Self, comptime list_type: type, selected: *list_type) !list_type {
        const gui = self.gui;
        const info = @typeInfo(list_type);
        const fields = info.Enum.fields;
        _ = try gui.beginLayout(Gui.HorizLayout, .{ .count = fields.len, .paddingh = 0 }, .{});
        defer gui.endLayout();
        inline for (fields) |field| {
            const active = @as(info.Enum.tag_type, @intFromEnum(selected.*)) == field.value;
            const area = gui.getArea() orelse return selected.*;
            const click = gui.clickWidget(area);
            if (click == .click)
                selected.* = @as(list_type, @enumFromInt(field.value));
            const sta = if (active) os9tabstart_active else os9tabstart;
            const end = if (active) os9tabend_active else os9tabend;
            const mid = if (active) os9tabmid_active else os9tabmid;
            gui.drawRectTextured(
                Rec(area.x, area.y, sta.w * self.scale, area.h),
                Color.White,
                sta,
                self.texture,
            );
            gui.drawRectTextured(
                Rec(area.x + area.w - end.w * self.scale, area.y, end.w * self.scale, area.h),
                Color.White,
                end,
                self.texture,
            );
            const mida = Rec(area.x + sta.w * self.scale, area.y, area.w - (end.w + sta.w) * self.scale, area.h);
            gui.drawRectTextured(
                mida,
                Color.White,
                mid,
                self.texture,
            );
            //const tbounds = self.font.textBounds(field.name);
            gui.drawText(field.name, mida.pos().add(.{ .x = 0, .y = 4 * self.scale }), mida.h - 4 * self.scale, Color.Black);

            //if (self.buttonEx(.{
            //    .name = field.name,
            //})) {
            //    selected.* = @as(list_type, @enumFromInt(field.value));
            //}
        }

        return selected.*;
    }

    pub fn labelEx(self: *Self, comptime fmt: []const u8, args: anytype, params: struct { justify: Gui.Justify = .left }) void {
        const area = self.gui.getArea() orelse return;
        self.gui.drawTextFmt(fmt, args, area, area.h, Color.Black, .{ .justify = params.justify });
    }

    pub fn label(self: *Self, comptime fmt: []const u8, args: anytype) void {
        self.labelEx(fmt, args, .{});
    }

    pub fn button(self: *Self, label_: []const u8) bool {
        return self.buttonEx(label_, .{});
    }

    pub fn buttonEx(self: *Self, label_: []const u8, params: struct { disabled: bool = false }) bool {
        const gui = self.gui;
        const d = gui.buttonGeneric();
        const sl = switch (d.state) {
            .none, .hover => os9btn,
            .click, .held => inset9,
            else => os9btn,
        };
        const sl1 = if (params.disabled) os9btn_disable else sl;
        const color = if (params.disabled) text_disabled else Color.Black;
        gui.draw9Slice(d.area, sl1, self.texture, self.scale);
        const texta = d.area.inset(3 * self.scale);
        gui.drawTextFmt("{s}", .{label_}, texta, texta.h, color, .{ .justify = .center });

        return (d.state == .click) and !params.disabled;
    }

    pub fn scrollBar(self: *Self, pos: *f32, min: f32, max: f32, orientation: Gui.Orientation, params: struct {
        handle_w: f32 = os9scrollhandle.h,
    }) void {
        const gui = self.gui;
        if (gui.sliderGeneric(pos, min, max, .{
            .handle_offset_y = os9handleoffset * self.scale,
            .handle_offset_x = os9handleoffset * self.scale,
            .handle_w = params.handle_w,
            .handle_h = os9scrollhandle.w * self.scale,
            .orientation = orientation,
        })) |d| {
            gui.draw9Slice(d.area, os9scrollinner, self.texture, self.scale);
            gui.drawRectTextured(
                d.handle,
                Color.White,
                os9scrollhandle,
                self.texture,
            );
        }
    }

    pub fn slider(self: *Self, value: anytype, min: anytype, max: anytype) void {
        const gui = self.gui;
        if (gui.sliderGeneric(value, min, max, .{
            .handle_w = os9shuttle.w * self.scale,
            .handle_h = os9shuttle.h * self.scale,
        })) |d| {
            gui.draw9Slice(d.area, os9slider, self.texture, self.scale);
            gui.draw9Slice(d.handle, os9shuttle, self.texture, self.scale);
        }
    }

    pub fn checkbox(self: *Self, label_: []const u8, checked: *bool) bool {
        const gui = self.gui;
        if (gui.checkboxGeneric(checked)) |d| {
            const area = d.area;

            const br = Rect.newV(area.pos(), .{ .x = 12 * self.scale, .y = 12 * self.scale });
            gui.drawRectTextured(
                br,
                Color.White,
                os9checkbox,
                self.texture,
            );
            gui.drawTextFmt("{s}", .{label_}, area, area.h, Color.Black, .{});
            if (checked.*)
                gui.drawRectTextured(br.addV(2 * self.scale, 0), Color.White, os9check, self.texture);
            return d.changed;
        }
        return false;
    }

    pub fn enumDropdown(self: *Self, comptime enumT: type, enum_val: *enumT) !void {
        const gui = self.gui;
        if (try gui.enumDropdownGeneric(enumT, enum_val, .{
            .max_items = 4,
            .scroll_bar_w = os9scrollw * self.scale,
            //.inset_scroll = 4 * self.scale,
        })) |d| {
            var dd = d;
            if (d.popup_active) {
                gui.drawRectFilled(d.area, Color.Black);
                while (dd.next(enumT)) |field| {
                    if (self.button(@tagName(field))) {
                        dd.set(gui, enum_val, field);
                    }
                }
                try d.endFieldList(gui);
                self.scrollBar(dd.slider_ptr.?, d.slider_range.x, d.slider_range.y, .vertical, .{});
            } else {
                gui.draw9Slice(d.area, os9drop, self.texture, self.scale);
                const text = d.area.inset(3 * self.scale);
                gui.drawTextFmt("{s}", .{@tagName(enum_val.*)}, text, text.h, Color.Black, .{});
                const ow = self.scale * os9drop.w / 3;
                const oh = self.scale * os9drop.h / 3;
                const btn_rec = Rec(d.area.x + d.area.w - ow - os9dropbtn.w * self.scale, d.area.y + oh, os9dropbtn.w * self.scale, os9dropbtn.h * self.scale);
                gui.drawRectTextured(btn_rec, Color.White, os9dropbtn, self.texture);
            }
            d.end(gui);
        }
    }

    pub fn textboxNumber(self: *Self, number_ptr: anytype) !void {
        const gui = self.gui;
        if (try gui.textboxNumberGeneric(number_ptr, .{ .text_inset = self.scale * 3 })) |d| {
            const tr = d.text_area;
            gui.draw9Slice(d.area, inset9, self.texture, self.scale);
            if (d.is_invalid)
                gui.drawRectFilled(d.text_area, itc(0xff000086));
            gui.drawTextFmt("{s}", .{d.slice}, d.text_area, d.text_area.h, Color.Black, .{});
            if (d.caret) |of| {
                gui.drawRectFilled(Rect.new(of + tr.x, tr.y + 2, 3, tr.h - 4), Color.Black);
            }
        }
    }

    //TODO better way to display error
    //option to treat an integer as decimal fixed point

    pub fn textbox(self: *Self, contents: *std.ArrayList(u8)) !void {
        const gui = self.gui;
        if (try gui.textboxGeneric(contents, .{ .text_inset = 3 * self.scale })) |d| {
            const tr = d.text_area;
            gui.draw9Slice(d.area, inset9, self.texture, self.scale);
            gui.drawTextFmt("{s}", .{d.slice}, d.text_area, d.text_area.h, Color.Black, .{});
            if (d.caret) |of| {
                gui.drawRectFilled(Rect.new(of + tr.x, tr.y + 2, 3, tr.h - 4), Color.Black);
            }
        }
    }
};

pub const GuiTest = struct {
    const Self = @This();

    arr: std.ArrayList(u8),
    pub fn init(alloc: std.mem.Allocator) Self {
        return .{ .arr = std.ArrayList(u8).init(alloc) };
    }
    pub fn deinit(self: *Self) void {
        self.arr.deinit();
    }

    pub fn update(self: *Self, wrap: *Os9Gui) !void {
        const gui = wrap.gui;
        const scale = wrap.scale;
        const area = gui.getArea() orelse return;
        gui.draw9Slice(area, Os9Gui.os9win, wrap.texture, scale);
        var vl = try wrap.beginSubLayout(area.inset(6 * scale), Gui.VerticalLayout, .{ .item_height = 20 * scale, .padding = .{ .bottom = 6 * scale } });
        defer wrap.endSubLayout();
        _ = vl;
        try wrap.textbox(&self.arr);
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
        std.mem.copy(u8, &zstring_buffer, str);
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

pub fn main() anyerror!void {
    //_ = graph.MarioData.dd;
    var gpa = std.heap.GeneralPurposeAllocator(.{ .retain_metadata = true, .never_unmap = false, .verbose_log = false, .stack_trace_frames = 8 }){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    var current_app: enum { keyboard_display, filebrowser, atlas_edit, gtest, lua_test } = .filebrowser;
    var arg_it = try std.process.ArgIterator.initWithAllocator(alloc);
    defer arg_it.deinit();
    const Arg = ArgUtil.Arg;
    const cli_opts = try (ArgUtil.parseArgs(&.{
        Arg("scale", .number, "The scale of the gui"),
        ArgUtil.ArgCustom("app", @TypeOf(current_app), "Which gui app to run"),
    }, &arg_it));

    if (cli_opts.app) |app|
        current_app = app;

    var scale = if (cli_opts.scale) |s| s else 2.0;
    var win = try graph.SDL.Window.createWindow("My window", .{
        .double_buffer = true,
        .window_flags = &.{
            graph.c.SDL_WINDOW_BORDERLESS,
            graph.c.SDL_WINDOW_UTILITY,
        },
        .window_size = .{ .x = 1920, .y = 1080 },
    });
    defer win.destroyWindow();

    graph.c.glLineWidth(1);

    //const init_size = graph.pxToPt(win.getDpi(), 100);
    const init_size = 8;
    var font = try graph.Font.init(alloc, std.fs.cwd(), "fonts/roboto.ttf", init_size, win.getDpi(), .{
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
        win.getDpi(),
        .{
            .codepoints_to_load = &[_]graph.Font.CharMapEntry{.{ .list = &icon_list }},
        },
    );
    defer icons.deinit();

    var stack_buffer: [600000]u8 = undefined;
    var stack_alloc = std.heap.FixedBufferAllocator.init(&stack_buffer);
    var gui = try Gui.Context.init(alloc, &stack_alloc, .{ .x = 0, .y = 0, .w = 3840, .h = 2160 }, &font, &icons);
    defer gui.deinit();

    Gui.hash_timer = try std.time.Timer.start();
    Gui.hash_time = 0;

    var gui_draw_context = try Gui.GuiDrawContext.init();
    defer gui_draw_context.deinit();

    var draw = graph.ImmediateDrawingContext.init(alloc, win.getDpi());
    defer draw.deinit();

    var parent_area = graph.Rec(0, 0, 0, 0);

    var percent_usage: f32 = 0;

    //var draw_line_debug: bool = false;

    const gui_frac: f32 = 0.3;
    _ = gui_frac * 0.1;
    var gui_timer = try std.time.Timer.start();
    var gui_time: u64 = 0;
    //var dcall_count: usize = 0;

    var atlas_editor = AtlasEditor.init(alloc);
    defer atlas_editor.deinit();

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

    var kbd = KeyboardDisplay.init(alloc);
    defer kbd.deinit();

    var gt = GuiTest.init(alloc);
    defer gt.deinit();

    var os9gui = try Os9Gui.init(alloc, scale, &gui);
    defer os9gui.deinit();

    //NEEDS TO BE SET BEFORE LUA RUNS
    os9_ctx = os9gui;
    //BEGIN LUA
    var L = lua.luaL_newstate();
    lua.luaL_openlibs(L);
    Lua.register(L);
    const lf = lua.luaL_loadfilex(L, "script.lua", "bt");
    Lua.checkError(L, lua.lua_pcallk(L, 0, lua.LUA_MULTRET, 0, 0, null));
    _ = lf;
    const lparam = Lua.getGlobal(L, "params", struct { window_x: i32, window_y: i32, scale: f32 });
    win.setWindowSize(lparam.window_x, lparam.window_y);
    win.centerWindow();

    //END LUA

    //graph.c.glPolygonMode(graph.c.GL_FRONT_AND_BACK, graph.c.GL_LINE);
    while (!win.should_exit) {
        try draw.begin(0x2f2f2fff, win.screen_dimensions.toF());
        win.pumpEvents(); //Important that this is called after beginDraw for input lag reasons

        switch (gui.text_input_state.state) {
            .start => win.startTextInput(),
            .stop => win.stopTextInput(),
            .cont => gui.text_input_state.buffer = win.text_input,
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

        {
            const r = graph.Rec(0, 0, win.screen_dimensions.x, win.screen_dimensions.y);
            parent_area = r;
            //parent_area = graph.Rec(r.x + r.w / 4, r.y + r.h / 4, r.w / 2, r.h / 2);
            //_ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = parent_area }, .{});
            _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = parent_area }, .{});
            defer gui.endLayout();
            switch (current_app) {
                .keyboard_display => try kbd.update(&os9gui),
                .lua_test => {
                    if (gui.getArea()) |win_area| {
                        const border_area = win_area.inset(6 * os9_ctx.scale);
                        const area = border_area.inset(6 * os9_ctx.scale);
                        gui.draw9Slice(win_area, Os9Gui.os9win, os9_ctx.texture, os9_ctx.scale);
                        gui.draw9Slice(border_area, Os9Gui.os9in, os9_ctx.texture, os9_ctx.scale);
                        _ = try gui.beginLayout(Gui.SubRectLayout, .{ .rect = area }, .{});
                        defer gui.endLayout();

                        _ = lua.lua_getglobal(L, "docrap");
                        Lua.checkError(L, lua.lua_pcallk(L, 0, 0, 0, 0, null));
                    }
                },
                //.lua_test => try luaTest(alloc: std.mem.Allocator),
                .atlas_edit => {
                    try atlas_editor.update(&os9gui);
                },
                .gtest => {
                    try gt.update(&os9gui);
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
            }
        }

        //draw.test9(Rec(0, 0, 400, 400), 0xffffffff);
        //draw.test9(Rec(0, 0, 400, 400), Os9Gui.os9win, os9_ctx.texture, 5);
        try gui_draw_context.drawGui(&draw, &font, parent_area, &gui, win.screen_dimensions.x, win.screen_dimensions.y);
        //const fs = 40;
        //var cy = struct {
        //    val: f32 = 300,
        //    fn get(self: *@This()) f32 {
        //        self.val += fs;
        //        return self.val;
        //    }
        //}{};

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
        //if (draw_line_debug) {
        //    var y: f32 = cy.get();
        //    var it = gui.layout_cache.first;
        //    while (it != null) : (it = it.?.next) {
        //        const color = if (gui.mouse_grab_id) |h| if (h.layout_hash == it.?.data.hash) Color.Blue else Color.White else Color.White;
        //        if (it.?.data.was_init) {
        //            ctx.drawRect(graph.Rec(0, y, fs, fs), Color.Red);
        //        }
        //        ctx.drawTextFmt(0, y, "{s}{d}", .{ nspace(it.?.depth * 2), it.?.data.hash & 0xfff }, &font, fs, color);
        //        y = cy.get();
        //        const dd = it.?.data.rec;
        //        const xx = dd.x - 400 + @as(f32, @floatFromInt(it.?.depth)) * 40;
        //        const h = dd.h;
        //        const of = h * 0.2;
        //        try ctx.drawLine(.{ .x = @as(f32, @floatFromInt(it.?.depth)) * fs + 30, .y = y - fs / 2 }, .{ .x = xx, .y = dd.y + dd.h / 2 }, Color.Red);
        //        try ctx.drawLine(.{ .x = xx, .y = dd.y + of }, .{ .x = xx, .y = dd.y + dd.h - 2 * of }, Color.Blue);
        //        try ctx.drawLine(.{ .x = xx, .y = dd.y + of }, .{ .x = dd.x, .y = dd.y }, Color.Blue);
        //        try ctx.drawLine(.{ .x = xx, .y = dd.y + dd.h - 2 * of }, .{ .x = dd.x, .y = dd.y + dd.h }, Color.Blue);
        //    }
        //}

        try draw.end();
        win.swap();
    }
}
