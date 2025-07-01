const std = @import("std");
const graph = @import("../graphics.zig");
const Gui = graph.Gui;
const gui_app = @import("../gui_app.zig");
const Os9Gui = gui_app.Os9Gui;
const Color = graph.Colori;
const Rect = graph.Rect;
const Vec2f = graph.Vec2f;
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

//Support mouse back button
//Fix drawing of lines,
//fix resizing of columnss
//Remove that stupid double clicking crap
//Add a right click menu
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
        bookmarks: []const Bookmark,
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
        settings,
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
        const file: ?std.fs.File = settings_dir.openFile("file_browser_config.json", .{}) catch |err| switch (err) {
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

        if (file == null) {
            for (DefaultBookmarks) |db| {
                try ret.bookmarks.append(.{
                    .name = try alloc.dupe(u8, db.name),
                    .abs_path = try alloc.dupe(u8, db.abs_path),
                    .err_msg = db.err_msg,
                });
            }
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
            for (json_p.value.bookmarks) |bm| {
                try ret.bookmarks.append(.{ .name = try alloc.dupe(u8, bm.name), .abs_path = try alloc.dupe(u8, bm.abs_path), .err_msg = null });
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
            const persist = PersistSettings{ .column_widths = widths, .show_hidden = self.show_hidden, .bookmarks = self.bookmarks.items };
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
        var it_dir = self.dir.openDir(".", .{ .iterate = true }) catch {
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
            const alloc_name = try self.alloc.dupe(u8, item.name);
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
            inline for (info.@"enum".fields, 0..) |field, i| {
                if (std.mem.eql(u8, field.name, ext))
                    return @enumFromInt(i);
            }
        }
        return .unknown;
    }

    fn filepreview(self: *Self, wrap: *Os9Gui) !void {
        const gui = &wrap.gui;
        const area = gui.getArea() orelse return;
        gui.draw9Slice(area, wrap.style.getRect(.basic_inset), wrap.style.texture, wrap.scale);
        const na = area.inset(wrap.style.getRect(.basic_inset).w / 3);
        if (self.file_preview) |fp| {
            gui.drawRectTextured(na, Color.White, fp.texture.rect(), fp.texture);
        }
    }

    fn fileItem(self: *Self, wrap: *Os9Gui, entry: DirEntry, index: usize, columns: []const FileColumn, bg: ?u32) !bool {
        const gui = &wrap.gui;
        const rec = gui.getArea() orelse return false;
        const pada = 4;
        if (bg) |bb| {
            gui.drawRectFilled(rec, bb);
        }
        var cx: f32 = 0;
        if (index == self.selected)
            gui.drawRectFilled(rec, wrap.style.config.colors.text_highlight);
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
                    }), .{ .x = ico.x, .y = ico.y + ico.h / 3 }, ico.h * 0.7, Color.Black, wrap.icon_font);
                    const ir = graph.Rec(r.x + ico.w, r.y, r.w - ico.w, r.h);
                    if (wrap.font.nearestGlyphX(entry.name, rec.h, .{ .x = col.width - ico.w, .y = rec.h / 2 }, true)) |glyph_index| {
                        if (glyph_index > 2)
                            gui.drawTextFmt("{s}…", .{entry.name[0..glyph_index]}, ir, rec.h, Color.Black, .{}, wrap.font);
                    } else {
                        gui.drawTextFmt("{s}", .{entry.name}, ir, rec.h, Color.Black, .{}, wrap.font);
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
                    gui.drawTextFmt("{d: >3}{s}", .{ val[0], val[1] }, r, rec.h, Color.Black, .{}, wrap.font);
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
                    }, r, r.h * 0.8, Color.Black, .{}, wrap.font);
                },
                .ftype => {
                    gui.drawTextFmt("{s}", .{@tagName(entry.kind)}, r, r.h * 0.8, Color.Black, .{}, wrap.font);
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
        const gui = &wrap.gui;
        const item_height = wrap.style.config.default_item_h * wrap.scale;
        const win_area = gui.getArea() orelse return;
        const border_area = win_area.inset(6 * wrap.scale);
        const area = border_area.inset(6 * wrap.scale);
        //const w_id = gui.getId();

        const popup_area = area.inset(area.w / 5);
        if (self.dialog_state != .none) {
            try gui.beginWindow(popup_area);
            defer gui.endWindow();
            gui.draw9Slice(popup_area, wrap.style.getRect(.window_outer_small), wrap.style.texture, wrap.scale);
            gui.draw9Slice(popup_area.inset(6 * wrap.scale), wrap.style.getRect(.basic_inset), wrap.style.texture, wrap.scale);
            switch (self.dialog_state) {
                .none => {},
                .settings => {
                    _ = try wrap.beginSubLayout(popup_area.inset(12 * wrap.scale), Gui.VerticalLayout, .{ .item_height = item_height });
                    defer wrap.endSubLayout();
                    if (wrap.button("Cancel")) {
                        self.dialog_state = .none;
                    }
                },
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
                    if (wrap.buttonEx("Add", .{}, .{ .disabled = self.scratch_vec.items.len == 0 })) {
                        try self.bookmarks.append(.{
                            .name = try self.alloc.dupe(u8, self.scratch_vec.items),
                            .abs_path = try self.alloc.dupe(u8, self.path_str.?),
                        });
                        self.dialog_state = .none;
                    }
                    if (wrap.button("Cancel")) {
                        self.dialog_state = .none;
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
        gui.draw9Slice(win_area, wrap.style.getRect(.window_outer_small), wrap.style.texture, wrap.scale);
        gui.draw9Slice(border_area, wrap.style.getRect(.basic_inset), wrap.style.texture, wrap.scale);
        gui.draw9Border(left_side_outer, Os9Gui.os9line, wrap.style.texture, wrap.scale, 0, 0);

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
                        gui.drawRectFilled(rec, wrap.style.config.colors.text_highlight);
                }
                //const vpad = rec.h * 0.1;
                //const tpos = graph.Vec2f.new(rec.x, rec.y + vpad);
                const color: u32 = if (bookmark.err_msg != null) Color.Red else Color.Black;
                const tr = blk: {
                    if (bookmark.err_msg != null) {
                        const d = rec.split(.vertical, rec.h);
                        gui.drawRectTextured(d[0], Color.White, Os9Gui.win_warning, wrap.style.texture);
                        break :blk d[1];
                    } else {
                        break :blk rec;
                    }
                };
                gui.drawTextFmt("{s}", .{bookmark.name}, tr, tr.h, color, .{}, wrap.font);
                gui.tooltip(bookmark.abs_path, rec.h, wrap.font);
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
            _ = try wrap.beginSubLayout(sp[1], Gui.VerticalLayout, .{ .item_height = item_height });
            defer wrap.endSubLayout();

            if (wrap.button("Add current Folder as bookmark")) {
                try self.scratch_vec.resize(0);
                self.dialog_state = .add_bookmark;
            }
            if (wrap.buttonEx("Remove selected bookmark", .{}, .{ .disabled = self.selected_bookmark == null })) {
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
            if (wrap.button("Settings")) {
                self.dialog_state = .settings;
            }
        }
        {
            gui.draw9Slice(main_area, wrap.style.getRect(.basic_inset), wrap.style.texture, wrap.scale);
            const ima = main_area.inset(wrap.scale * wrap.style.getRect(.basic_inset).w / 3);
            const root1 = ima.split(.horizontal, item_height);
            {
                const fheader = root1[0];
                gui.draw9Slice(fheader, wrap.style.getRect(.err), wrap.style.texture, wrap.scale); //window9
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
                    var evil: f32 = 0;
                    const d = gui.draggable(handle, .{ .x = 1, .y = 0 }, &cc.width, &evil, .{ .x_min = rec.h * 5, .x_max = rec.w });
                    _ = d;
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
                    }, Vec2f.new(rec.x + cx, rec.y), rec.h, Color.Black, wrap.font);
                    if (i == self.sorted_column_index) {
                        gui.drawIcon(Icons.get(
                            if (!self.sorted_column_ascending) .drop_up else .drop_down,
                        ), .{ .x = rec.x + cx + cc.width - rec.h, .y = rec.y }, rec.h, Color.Black, wrap.icon_font);
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
            if (try wrap.beginVScroll(&self.file_scroll, .{})) |file_scroll| {
                defer wrap.endVScroll(file_scroll);
                for (self.entries.items, 0..) |entry, i| {
                    const bgfile_color = 0xeeeeeeff;
                    if (try self.fileItem(wrap, entry, i, &self.columns, if (i % 2 != 0) bgfile_color else null))
                        break;
                }
                var cx: f32 = 0;
                for (self.columns[0 .. self.columns.len - 1]) |cc| {
                    cx += cc.width;
                    gui.drawLine(Vec2f.new(sa.x + cx, sa.y), Vec2f.new(sa.x + cx, sa.y + sa.h), Color.Black);
                }
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
            if (wrap.buttonEx("Ok", .{}, .{ .disabled = !(if (self.selected) |si| self.entries.items[si].kind == .file else false) })) {
                self.file = .{ .file_name = self.entries.items[self.selected.?].name, .dir = self.dir };
                self.flag = .ok_clicked;
            }
        }
    }
};
