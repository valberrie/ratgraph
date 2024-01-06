const std = @import("std");
const Cache = @import("gui_cache.zig");
//TODO
//Annotate all functions with what state they depend on. Make it easier to ensure proper state. For instance  gui.scissor depends on scroll_
//
//Idea: Parametric rects IDk. Somehow make a rect depend on another rects values. Probably stupid

const json = std.json;
const clamp = std.math.clamp;
const graph = @import("graphics.zig");
const Vec2f = graph.Vec2f;
const Vec2i = struct {
    const Self = @This();

    pub fn toF(self: Self) Vec2f {
        return .{ .x = @as(f32, @floatFromInt(self.x)), .y = @as(f32, @floatFromInt(self.y)) };
    }

    x: i16,
    y: i16,
};

const Rect = graph.Rect;
const SRect = struct {
    const Self = @This();
    //TODO rename to inset
    pub fn scale(self: Self, amount: i16) Self {
        return .{ .x = self.x + amount, .y = self.y + amount, .w = self.w - amount * 2, .h = self.h - amount * 2 };
    }

    pub fn new(x: i16, y: i16, w: i16, h: i16) Self {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn toF32(self: Self) graph.Rect {
        return .{ .x = @as(f32, @floatFromInt(self.x)), .y = @as(f32, @floatFromInt(self.y)), .w = @as(f32, @floatFromInt(self.w)), .h = @as(f32, @floatFromInt(self.h)) };
    }

    pub fn pos(self: Self) Vec2i {
        return .{ .x = self.x, .y = self.y };
    }

    x: i16,
    y: i16,
    w: i16,
    h: i16,
};

const Hsva = graph.Hsva;
const Color = graph.CharColor;
const itc = graph.itc;

//TODO reduce memory footprint of these structs?
//Colors could be aliased.
//A Rect could probably be represented by 4 shorts
pub const DrawCommand = union(enum) {
    rect_9border: struct {
        r: Rect,
        uv: Rect,
        scale: f32,
        texture: graph.Texture,
        cutout_start: f32,
        cutout_end: f32,
    },
    rect_9slice: struct {
        r: Rect,
        uv: Rect,
        scale: f32,
        texture: graph.Texture,
    },

    rect_filled: struct {
        r: Rect,
        color: Color,
    },

    rect_textured: struct {
        r: Rect,
        color: Color,
        uv: Rect,
        texture: graph.Texture,
    },

    rect_outline: struct {
        r: Rect,
        color: Color,
    },

    rect_filled_multi_color: struct {
        r: Rect,
        colors: [4]Color,
    },

    line: struct {
        a: Vec2f,
        b: Vec2f,
        color: Color,
    },

    text: struct {
        font: *graph.Font,
        pos: Vec2i,
        size: f32,
        string: []const u8,
        color: Color,
    },

    scissor: struct {
        area: ?Rect = null,
    },

    set_camera: struct {
        cam_area: ?Rect = null,
        offset: Vec2f = .{ .x = 0, .y = 0 },
        win_area: ?Rect = null,
    },
};

//TODO bitset type that takes an enum and gives each field a mask bit. see github.com/emekoi/bitset-zig

pub const Justify = enum { right, left, center };
pub const Orientation = enum { horizontal, vertical };

//TODO Replace with std.EnumArray. Study how std.EnumMap uses "mixin"
pub fn EnumMap(comptime Enum: type, comptime child_type: type) type {
    const info = @typeInfo(Enum);
    if (info != .Enum) @compileError("EnumMap expects an enum");
    var struct_fields: [info.Enum.fields.len]std.builtin.Type.StructField = undefined;
    for (info.Enum.fields, 0..) |field, i| {
        if (i != field.value) @compileError("EnumMap only supports default valued enums");
        struct_fields[i] = .{ .name = field.name, .type = child_type, .default_value = null, .is_comptime = false, .alignment = 0 };
    }
    const DataType = @Type(.{ .Struct = .{ .layout = .Auto, .fields = &struct_fields, .decls = &.{}, .is_tuple = false } });

    return struct {
        value: [info.Enum.fields.len]child_type,

        pub fn new(values: DataType) @This() {
            var arr: [info.Enum.fields.len]child_type = undefined;
            inline for (info.Enum.fields, 0..) |field, i| {
                arr[i] = @field(values, field.name);
            }
            return .{ .value = arr };
        }

        pub fn newSingle(val: child_type) @This() {
            var arr: [info.Enum.fields.len]child_type = undefined;
            std.mem.set(child_type, &arr, val);
            return .{ .value = arr };
        }

        pub fn _switch(self: @This(), val: Enum) child_type {
            const i = @intFromEnum(val);
            return self.value[i];
        }
    };
}

pub const my_map = EnumMap(Justify, u8);

pub const InputState = struct {
    pub const DefaultKeyboardState = graph.SDL.Window.KeyboardStateT.initEmpty();
    //TODO switch to using new graphics.zig MouseState
    //make clickwidget support rightClicks, double click etc
    //Figure out textinput
    mouse_pos: Vec2f = .{ .x = 0, .y = 0 },
    mouse_delta: Vec2f = .{ .x = 0, .y = 0 },
    mouse_left_held: bool = false,
    mouse_left_clicked: bool = false,
    mouse_wheel_delta: f32 = 0,
    mouse_wheel_down: bool = false,
    keyboard_state: *const graph.SDL.Window.KeyboardStateT = &DefaultKeyboardState,
    keys: []const graph.SDL.KeyState = &.{},
};

fn opaqueSelf(comptime self: type, ptr: *anyopaque) *self {
    return @as(*self, @ptrCast(@alignCast(ptr)));
}

pub const SubRectLayout = struct {
    rect: Rect,
    index: u32 = 0,
    hidden: bool = false,

    fn hash(self: *anyopaque, bounds: Rect) u64 {
        return dhash(.{ .r = bounds, .d = opaqueSelf(SubRectLayout, self).* });
    }

    pub fn getArea(bounds: Rect, anyself: *anyopaque) ?Rect {
        const self = opaqueSelf(@This(), anyself);
        _ = bounds;
        if (self.index > 0) return null;
        self.index += 1;
        return self.rect;
    }
};

pub const TableLayout = struct {
    const Self = @This();
    hidden: bool = false,

    //Config
    columns: u32,
    item_height: f32,

    //State
    current_y: f32 = 0,
    column_index: u32 = 0,

    pub fn hash(self: *anyopaque, bounds: Rect) u64 {
        return dhash(.{ .r = bounds, .d = opaqueSelf(@This(), self).* });
    }

    pub fn getArea(bounds: Rect, anyself: *anyopaque) ?Rect {
        const self = opaqueSelf(@This(), anyself);
        if (self.current_y > bounds.h) return null;

        const col_w = bounds.w / @as(f32, @floatFromInt(self.columns));

        const ci = @as(f32, @floatFromInt(self.column_index));
        const area = graph.Rec(bounds.x + col_w * ci, bounds.y + self.current_y, col_w, self.item_height);
        self.column_index += 1;
        if (self.column_index >= self.columns) {
            self.column_index = 0;
            self.current_y += self.item_height;
        }

        return area;
    }
};

pub const VerticalLayout = struct {
    const Self = @This();
    padding: graph.Padding = .{ .top = 0, .bottom = 0, .left = 0, .right = 0 },
    item_height: f32,
    current_h: f32 = 0,
    hidden: bool = false,
    next_height: ?f32 = null,
    clip_bounds: ?Rect = null,

    pub fn hash(self: *anyopaque, bounds: Rect) u64 {
        return dhash(.{ .r = bounds, .d = opaqueSelf(@This(), self).* });
    }

    fn getArea(bounds: Rect, anyself: *anyopaque) ?Rect {
        const self = opaqueSelf(@This(), anyself);
        const h = if (self.next_height) |nh| nh else self.item_height;
        self.next_height = null;

        if (self.current_h + self.padding.top > bounds.h or self.hidden) //We don't add h yet because the last element can be partially displayed. (if clipped)
            return null;

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
};

pub const HorizLayout = struct {
    const floating_pixel_error = 0.3; //If we switch to ints this won't be a problem. but doing math will be annoying
    paddingh: f32 = 20,
    index: usize = 0,
    count: usize,
    current_w: f32 = 0,
    hidden: bool = false,

    pub fn hash(self: *anyopaque, bounds: Rect) u64 {
        return dhash(.{ .r = bounds, .d = opaqueSelf(@This(), self).* });
    }

    pub fn getArea(bounds: Rect, anyself: *anyopaque) ?Rect {
        const self = opaqueSelf(@This(), anyself);
        defer self.index += 1;
        const fc: f32 = @floatFromInt(self.count);

        const w = (bounds.w - self.paddingh * (fc - 1)) / fc;
        //const w = (bounds.w - self.paddingh) / @as(f32, @floatFromInt(self.count));
        //defer self.current_w += w + self.paddingh;
        defer self.current_w += w + self.paddingh;

        return .{ .x = bounds.x + self.current_w, .y = bounds.y, .w = w, .h = bounds.h };
    }
};

pub const Layout = struct {
    const Self = @This();
    const HashFnSig = *const fn (*anyopaque, Rect) u64;
    const GetAreaFnSig = *const fn (bounds: Rect, self: *anyopaque) ?Rect;

    bounds: Rect,

    hash_layout: ?HashFnSig = null,
    layout_data: ?*anyopaque = null,
    get_area: ?GetAreaFnSig = null,

    parent_scroll_bounds: ?Rect = null,

    last_requested_bounds: ?Rect = null,

    pub fn setNew(self: *Self, comptime Layout_T: type, layout_data: *anyopaque) void {
        self.layout_data = layout_data;
        self.hash_layout = &@field(Layout_T, "hash");
        self.get_area = &@field(Layout_T, "getArea");
    }

    pub fn isSet(self: *Self) bool {
        return (self.get_area != null and self.hash_layout != null and self.layout_data != null);
    }

    pub fn getArea(self: *Self) ?Rect {
        self.last_requested_bounds = self.get_area.?(self.bounds, self.layout_data.?);
        return self.last_requested_bounds;
    }

    pub fn hash(self: *Self) u64 {
        return self.hash_layout.?(self.layout_data.?, self.bounds);
    }

    pub fn reset(self: *Self) void {
        self.layout_data = null;
        self.get_area = null;
        self.hash_layout = null;
    }
};

pub const RetainedState = struct {
    //Implementation of https://rxi.github.io/textbox_behaviour.html
    pub const TextInput = struct {
        const Self = @This();
        const uni = std.unicode;
        const edit_keys_list = graph.Bind(&.{
            .{ "left", "left" },
            .{ "right", "right" },
            .{ "backspace", "Backspace" },
        });

        const SingleLineMovement = enum {
            left,
            right,
            next_word_end,
            prev_word_end,
            start,
            end,
        };

        codepoints: std.ArrayList(u8),

        //As the chars array contains utf8, these are the first byte indicies of codepoints.
        head: i32,
        tail: i32,

        //TODO properly support unicode. Don't know how this will be done. Can we write an iterator than can move both ways?
        fn move_to(self: *Self, movement: SingleLineMovement) void {
            const max = @as(i32, @intCast(self.codepoints.items.len));
            switch (movement) {
                .left => {
                    self.head = clamp(self.head - 1, 0, max);
                    self.tail = self.head;
                },
                .right => {
                    self.head = clamp(self.head + 1, 0, max);
                    self.tail = self.head;
                },
                else => {},
            }
        }

        fn select_to(self: *Self, movement: SingleLineMovement) void {
            _ = self;
            _ = movement;
        }

        fn delete_to(self: *Self, movement: SingleLineMovement) void {
            const max = @as(i32, @intCast(self.codepoints.items.len));
            switch (movement) {
                .left => {
                    if (self.codepoints.items.len == 0 or self.head == 0) return;
                    self.head -= 1;
                    self.head = clamp(self.head, 0, max);
                    self.tail = self.head;
                    _ = self.codepoints.orderedRemove(@as(usize, @intCast(self.head)));
                },
                else => {},
            }
        }

        pub fn init(alloc: std.mem.Allocator) Self {
            return Self{ .codepoints = std.ArrayList(u8).init(alloc), .head = 0, .tail = 0 };
        }

        pub fn deinit(self: *Self) void {
            self.codepoints.deinit();
        }

        pub fn getSlice(self: *Self) []const u8 {
            return self.codepoints.items;
        }

        pub fn setCaret(self: *Self, pos: usize) void {
            if (pos > self.codepoints.items.len) return;
            self.head = @as(i32, @intCast(pos));
            self.tail = @as(i32, @intCast(pos));
        }

        pub fn reset(self: *Self, new_str: []const u8) !void {
            try self.codepoints.resize(0);
            try self.codepoints.appendSlice(new_str);
            self.head = 0;
            self.tail = 0;
        }

        pub fn handleEventsOpts(
            tb: *TextInput,
            text_input: []const u8,
            input_state: InputState,
            opts: struct { numbers_only: bool = false },
        ) !void {
            const StaticData = struct {
                var are_binds_init: bool = false;
                var key_binds: edit_keys_list = undefined;
            };
            if (!StaticData.are_binds_init) {
                StaticData.are_binds_init = true;
                StaticData.key_binds = edit_keys_list.init();
            }

            var it = std.unicode.Utf8Iterator{ .bytes = text_input, .i = 0 };
            var codepoint = it.nextCodepointSlice();
            while (codepoint != null) : (codepoint = it.nextCodepointSlice()) {
                if (opts.numbers_only) {
                    switch (codepoint.?[0]) {
                        '0'...'9', '-', '.' => {},
                        else => continue,
                    }
                }
                if (tb.head != tb.tail) {
                    //try tb.chars.replaceRange(tb.tail, tb.head - tb.tail, codepoint.?);
                    //tb.tail = tb.head;
                } else {
                    try tb.codepoints.insertSlice(@as(usize, @intCast(tb.head)), codepoint.?);
                    tb.head += @as(i32, @intCast(codepoint.?.len));
                    tb.tail = tb.head;
                }
            }

            for (input_state.keys) |key| {
                switch (StaticData.key_binds.get(key.scancode)) {
                    .left => tb.move_to(.left),
                    .right => tb.move_to(.right),
                    .backspace => tb.delete_to(.left),
                    else => {},
                }
            }
        }

        pub fn handleEvents(tb: *TextInput, text_input: []const u8, input_state: InputState) !void {
            try tb.handleEventsOpts(text_input, input_state, .{});
        }
    };

    pub const ElementData = union(enum) {
        text_box: TextInput,
        float: f32,

        pub fn deinit(self: *ElementData) void {
            switch (self.*) {
                .text_box => self.text_box.deinit(),
                .float => {},
            }
        }
    };

    data: ElementData,
};

pub const ClickState = enum(u8) {
    none,
    hover,
    hover_no_focus,
    click,
    click_teleport,
    held,
    click_release,
    double,
};
pub const ClickStateColors = EnumMap(ClickState, Color);

//TODO Some sort of drawMultiWidget(anywidget, list of args) would be cool
//in order to be usefull a lambda function to transform items in a slice to argument lists would have to be provided
//If a struct provides a guiDraw function this could be called
//so gui.drawMulti(my_slice) would iterate my_slice and call guiDraw on each

//TODO add some sort of anotations to Context functions to show level of feature support.
//What Widgets do varius ui's have
//Nuklear:
//  Textbox
//  Button
//  Checkbox
//  Radio
//  Selectable?
//  Slider
//  ProgressBar
//  ColorPicker
//  TextEdit
//  Chart
//  PopUp
//  ComboBox
//  Context
//  Tooltip
//  Menu

pub var hash_time: u64 = 0;
pub var hash_timer: std.time.Timer = undefined;

pub inline fn dhash(state: anytype) u64 {
    hash_timer.reset();
    defer hash_time += hash_timer.read();
    var hasher = std.hash.Wyhash.init(0);
    hashW(&hasher, state, .Deep);
    return hasher.final();
}

//A wrapper over std autoHash to allow hashing floats. All the floats being hashed are pixel coordinates. They are first scaled by 10 before being truncated and hashed
pub fn hashW(hasher: anytype, key: anytype, comptime strat: std.hash.Strategy) void {
    const Key = @TypeOf(key);
    switch (@typeInfo(Key)) {
        .Struct => |info| {
            inline for (info.fields) |field| {
                hashW(hasher, @field(key, field.name), strat);
            }
        },
        .Pointer => {},
        .Opaque => {},
        .Optional => if (key) |k| hashW(hasher, k, strat),
        .Float => {
            std.hash.autoHashStrat(hasher, @as(i32, @intFromFloat(key * 10)), strat);
        },
        else => std.hash.autoHashStrat(hasher, key, strat),
    }
}

pub const ButtonStyle = struct {
    bg: Hsva,
    top: Hsva,
    bot: Hsva,
};
pub var bstyle: ButtonStyle = .{
    .bg = graph.colorToHsva(Color.Gray),
    .top = graph.colorToHsva(Color.White),
    .bot = graph.colorToHsva(Color.Black),
};

//TODO Is hashing the type name really a good idea
pub const OpaqueDataStore = struct {
    const Self = @This();
    const DataStoreMapT = std.StringHashMap(DataItem);

    pub const DataItem = struct {
        type_name_hash: u64,
        data: []u8,
    };

    keys: std.ArrayList([]const u8),
    map: DataStoreMapT,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Self {
        return Self{ .keys = std.ArrayList([]const u8).init(alloc), .map = DataStoreMapT.init(alloc), .alloc = alloc };
    }

    pub fn deinit(self: *Self) void {
        var vit = self.map.valueIterator();
        var item = vit.next();
        while (item) |v| : (item = vit.next()) {
            self.alloc.free(v.data);
        }
        for (self.keys.items) |key| {
            self.alloc.free(key);
        }

        self.keys.deinit();
        self.map.deinit();
    }

    pub fn store(self: *Self, comptime data_type: type, name: []const u8) !struct {
        data: *data_type,
        is_init: bool,
    } {
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHashStrat(&hasher, @typeName(data_type), .Shallow);
        const hash = hasher.final();

        var is_init = false;
        if (!self.map.contains(name)) {
            is_init = true;
            const name_store = try self.alloc.alloc(u8, name.len);
            std.mem.copy(u8, name_store, name);
            try self.keys.append(name_store);
            const data_untyped = try self.alloc.alloc(u8, @sizeOf(data_type));
            //const data = @as(*data_type, @ptrCast(@alignCast(data_untyped)));
            //data.* = init_value;
            try self.map.put(name_store, .{ .type_name_hash = hash, .data = data_untyped });
        }
        const v = self.map.get(name) orelse unreachable;
        if (v.type_name_hash != hash) return error.wrongType;
        return .{ .data = @as(*data_type, @ptrCast(@alignCast(v.data))), .is_init = is_init };
    }
};

test "Opaque data store basic usage" {
    const alloc = std.testing.allocator;
    const expect = std.testing.expect;
    var ds = OpaqueDataStore.init(alloc);
    defer ds.deinit();

    const val = try ds.store(i32, "my_var", 0);
    try expect(val.* == 0);
    const val2 = try ds.store(i32, "my_var", 0);
    val2.* += 4;
    try expect(val.* == 4);
}

pub const Console = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    lines: std.ArrayList([]const u8),

    pub fn init(alloc: std.mem.Allocator) Self {
        return Self{ .alloc = alloc, .lines = std.ArrayList([]const u8).init(alloc) };
    }
    pub fn deinit(self: *Self) void {
        for (self.lines.items) |line| {
            self.alloc.free(line);
        }
        self.lines.deinit();
    }

    pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        var line = std.ArrayList(u8).init(self.alloc);
        try line.writer().print(fmt, args);
        try self.lines.append(try line.toOwnedSlice());
    }
};
//TODO Seperate context into two structs.
// A core struct for the low level gui stuff and a basic widgets struct other things can compose

//Instead of seperating layout hashes and widget hashes, can we just give each item a hash that depends on the parent hash
pub const Context = struct {
    pub var dealloc_count: u32 = 0;
    pub var alloc_count: u32 = 0;
    const Self = @This();
    const LayoutStackT = std.SinglyLinkedList(Layout);
    const RetainedHashMapT = std.StringHashMap(RetainedState);

    //Used for hashing
    const WidgetTypes = enum {
        button,
        color_picker,
        slider,
        propertyTable,
        checkbox,
        textbox,
        text_label,
        print_label,
    };

    pub const WidgetState = enum {
        init,
        input_changed,
        style_changed,
        no_change,
        dirty,
    };

    const LayoutCacheData = struct {
        const WidgetDataChildT = f32;
        const WidgetDataT = std.AutoHashMap(u64, WidgetDataChildT);
        hash: u64,

        rec: Rect,

        widget_index: u32 = 0,
        dirty: bool = true,

        widget_hashes: std.ArrayList(u64) = undefined,
        widget_hash_index: u32 = 0,

        widget_data: WidgetDataT = undefined,

        was_init: bool = true, //Exist to draw debug indicator for fresh nodes
        is_init: bool = false,
        pub fn init(self: *@This(), alloc: std.mem.Allocator) void {
            if (self.is_init) unreachable;
            alloc_count += 1;
            self.is_init = true;
            self.widget_hashes = std.ArrayList(u64).init(alloc);
            self.widget_data = WidgetDataT.init(alloc);
        }

        pub fn deinit(self: *@This()) void {
            if (self.is_init) {
                self.widget_data.deinit();
                dealloc_count += 1;
                self.widget_hashes.deinit();
            } else {
                unreachable;
            }
        }

        pub fn getWidgetData(self: *@This(), init_value: WidgetDataChildT) !*WidgetDataChildT {
            const res = try self.widget_data.getOrPut(self.widget_hashes.items[self.widget_hash_index]);
            if (!res.found_existing) {
                res.value_ptr.* = init_value;
            }
            return res.value_ptr;
        }

        fn eql(a: @This(), b: @This()) bool {
            return a.hash == b.hash;
        }
    };
    const LayoutCacheT = Cache.StackCache(LayoutCacheData, LayoutCacheData.eql, .{ .log_debug = false });

    const Popup = struct {
        area: Rect,
    };

    pub const ImplementationStatus = enum(u8) {
        not_to_be_used,
        requires_additional_features,
        proof_of_concept,
        complete,
    };

    pub const Scroll = struct {
        virtual_bounds: Rect,
        layout: *VerticalLayout,
        scroll_bar_rec: Rect,
        pos: *f32,
    };

    pub const ScrollData = struct {
        vertical: ?Rect,
        horiz: ?Rect,
        offset: *Vec2f,
        bar_w: f32,
    };

    pub const VLayoutScrollData = struct {
        data: ScrollData,
        layout: *VerticalLayout,
    };

    no_caching: bool = true,

    console: Console,
    font: *graph.Font,
    icon_font: *graph.Font,

    layout: Layout,

    stack_alloc: *std.heap.FixedBufferAllocator,
    alloc: std.mem.Allocator,
    layout_stack: LayoutStackT = .{},
    command_list: std.ArrayList(DrawCommand),

    command_list_popup: std.ArrayList(DrawCommand),

    data_store: OpaqueDataStore,
    //retained_data: RetainedHashMapT,
    retained_alloc: std.mem.Allocator,
    //retained_data_key_store: std.ArrayList([]const u8),
    focused_element: []const u8 = "",
    namespace: []const u8 = "global",
    //TODO change naming system, state from last frame should be prefixed with last_frame or exist inside a last_frame_state struct
    old_namespace: []const u8 = "",

    scratch_buf: [256]u8 = undefined,
    strings: [2048]u8 = undefined,
    str_index: usize = 0,

    layout_cache: LayoutCacheT,
    current_layout_cache_data: ?*LayoutCacheData = null,

    input_state: InputState = .{},

    //State for slider()
    // Stores the difference between slider_val and @trunc(slider_val) to prevent losing non integer changes in &val every frame.
    // Depends on clickWidget
    focused_slider_state: f32 = 0,
    draggable_state: Vec2f = .{ .x = 0, .y = 0 },

    //TODO a better system to deal with compose edits and returning a text_editing_rect to SDL for proper rendering of ibus compose editor
    text_input_state: enum { start, stop, _continue, disabled } = .disabled,
    text_input: []const u8 = "",
    text_input_index: ?u32 = null,
    text_input_hash: ?u64 = null,
    textbox_state: RetainedState.TextInput,
    textbox_number: ?*u8 = null,

    enum_drop_down_scroll: Vec2f = .{ .x = 0, .y = 0 },

    //State for clickWidget()
    // The hash of the layout that has grabbed the mouse. Gets reset when mouse != held
    mouse_grabbed_by_hash: ?u64 = null,
    mouse_released: bool = false,
    mouse_widget_index: u64 = 0,

    click_timer: u64 = 0,
    last_clicked: ?struct { hash: u64, index: u64 } = null,

    popup: ?Popup = null,
    popup_scroll_bounds: ?Rect = null,
    //TODO there can only ever be one beginPopup call in a layout. Ensure this

    popup_hash: ?u64 = null,
    popup_index: ?u32 = null,
    in_popup: bool = false,
    /// Represents the screen space area of the current scroll area, when a nested scroll section is created,
    /// it is always clipped to exist inside the parent scroll_bounds
    scroll_bounds: ?Rect = null,
    scroll_claimed_mouse: bool = false,

    last_frame_had_popup: bool = false,

    pub fn storeString(self: *Self, str: []const u8) []const u8 {
        if (str.len + self.str_index >= self.strings.len) {
            const slice = self.alloc.alloc(u8, str.len) catch unreachable;
            std.mem.copy(u8, slice, str);
            return slice;
        }

        const sl = self.strings[self.str_index .. self.str_index + str.len];
        std.mem.copy(u8, sl, str);
        defer self.str_index += str.len;

        return sl;
    }

    //pub fn loadRetainedData(self: *Self, fully_qualified_name: []const u8, data: RetainedState) !void {
    //    const mem = try self.retained_alloc.alloc(u8, fully_qualified_name.len);
    //    std.mem.copy(u8, mem, fully_qualified_name);
    //    try self.retained_data_key_store.append(mem);
    //    try self.retained_data.putNoClobber(mem, data);
    //}

    pub fn isKeyDown(self: *Self, scancode: graph.keycodes.Scancode) bool {
        return self.input_state.keyboard_state.isSet(@intFromEnum(scancode));
    }

    pub fn qualifyName(self: *const Self, name: []const u8) ![]const u8 {
        const qn = try self.alloc.alloc(u8, name.len + self.namespace.len + 1);
        std.mem.copy(u8, qn, self.namespace);
        qn[self.namespace.len] = ':';
        std.mem.copy(u8, qn[self.namespace.len + 1 ..], name);
        return qn;
    }

    pub fn getArea(self: *Self) ?Rect {
        const new_area = self.layout.getArea();
        return new_area;
    }

    pub fn getTransientIndex(self: *Self) u32 {
        if (self.current_layout_cache_data) |ld| {
            ld.widget_index += 1;
            return ld.widget_index;
        }
        unreachable;
    }

    pub fn isCurrentTextInput(self: *Self, hash: u64, index: usize) bool {
        if (self.text_input_hash) |h| {
            if (self.text_input_index) |ind| {
                return (hash == h and ind == index);
            }
        }
        return false;
    }

    //TODO multi hash!!
    //Data common to all widgets:
    //area
    //a widget_type
    pub fn getWidgetState(self: *Self, dependent_data: anytype) WidgetState {
        const result: WidgetState = blk: {
            const hash = dhash(dependent_data);
            if (self.current_layout_cache_data) |ld| {
                if (ld.dirty) break :blk .dirty;
                if (ld.is_init != true) unreachable;
                defer ld.widget_hash_index += 1;
                if (ld.widget_hash_index >= ld.widget_hashes.items.len) { //append to list and return .init
                    ld.widget_hashes.append(hash) catch unreachable;
                    break :blk .init;
                } else { //Compare and either overwrite or return
                    if (hash == ld.widget_hashes.items[ld.widget_hash_index])
                        break :blk .no_change;
                    ld.widget_hashes.items[ld.widget_hash_index] = hash;
                    //TODO notify child layouts
                    break :blk .input_changed;
                }
            }
            unreachable;
        };
        if (self.no_caching)
            return .init;
        return result;
    }

    pub fn init(alloc: std.mem.Allocator, stack_alloc: *std.heap.FixedBufferAllocator, bounds: Rect, font: *graph.Font, icon_font: *graph.Font) !Self {
        //TODO change stack_alloc from a FixedBufferAllocator to a ArenaAllocator
        return Self{
            .console = Console.init(alloc),
            .data_store = OpaqueDataStore.init(alloc),
            .layout = .{ .bounds = bounds },
            .layout_stack = .{},
            .layout_cache = try LayoutCacheT.init(alloc),
            .stack_alloc = stack_alloc,
            .alloc = stack_alloc.allocator(),
            .font = font,
            .icon_font = icon_font,
            //.retained_data = RetainedHashMapT.init(alloc),
            .retained_alloc = alloc,
            //.retained_data_key_store = std.ArrayList([]const u8).init(alloc),
            .command_list = std.ArrayList(DrawCommand).init(stack_alloc.allocator()),
            .command_list_popup = std.ArrayList(DrawCommand).init(stack_alloc.allocator()),
            .textbox_state = RetainedState.TextInput.init(alloc),
            //.textbox_state = .{ .chars = std.ArrayList(u8).init(alloc), .head = 0, .tail = 0 },
        };
    }

    pub fn reset(self: *Self, input_state: InputState) !void {
        self.str_index = 0;
        self.scroll_claimed_mouse = false;

        try self.layout_cache.begin();
        if (self.scroll_bounds != null) return error.unmatchedBeginScroll;
        if (std.mem.indexOfScalar(u8, self.namespace, ':') != null)
            return error.unmatchedPushNamespace;
        if (self.layout_stack.len() > 0)
            return error.unmatchedBeginLayout;
        self.command_list.deinit();
        self.command_list_popup.deinit();
        self.text_input_state = switch (self.text_input_state) {
            .disabled => .disabled,
            .stop => .disabled,
            ._continue => .stop,
            .start => .stop,
        };
        self.stack_alloc.reset();
        self.command_list = std.ArrayList(DrawCommand).init(self.alloc);
        self.command_list_popup = std.ArrayList(DrawCommand).init(self.alloc);
        self.input_state = input_state;

        self.layout.reset();
        self.click_timer += 1;

        if (self.popup) |p| {
            if (self.input_state.mouse_left_clicked and !graph.rectContainsPoint(p.area, self.input_state.mouse_pos)) {
                self.popup = null;
                self.popup_hash = null;
                self.popup_index = null;
            }
        }
        if (self.mouse_released) {
            self.mouse_grabbed_by_hash = null;
            self.mouse_released = false;
        }
        if (!self.input_state.mouse_left_held and self.mouse_grabbed_by_hash != null) {
            //ld.mouse_focus_widget_index = null;

            self.mouse_released = true;
            //self.mouse_grabbed_by_hash = null;
        }
        //if (self.popup_area) |area| {
        //    if (self.input_state.mouse_left_clicked) {
        //        _ = area;
        //    }
        //}

        //Popup related stuff
        //self.popup_draw_index = null;
        //self.popup_draw_index_end = null;

        if (!self.last_frame_had_popup) {
            self.popup = null;
            self.popup_hash = null;
            self.popup_index = null;
        }
        self.last_frame_had_popup = false;
    }

    pub fn deinit(self: *Self) void {
        //for (self.retained_data_key_store.items) |item| {
        //    self.retained_alloc.free(item);
        //}
        //var vit = self.retained_data.valueIterator();
        //var item = vit.next();
        //while (item != null) : (item = vit.next()) {
        //    item.?.data.deinit();
        //}

        //self.retained_data_key_store.deinit();
        //self.retained_data.deinit();
        self.layout_cache.deinit();
        self.console.deinit();
        self.textbox_state.deinit();
        self.data_store.deinit();
    }

    pub fn setNamespace(self: *Self, new_namespace: []const u8) void {
        if (!std.mem.eql(u8, new_namespace, self.old_namespace)) {
            self.layout_cache.clear() catch unreachable;
            self.old_namespace = self.namespace;
            self.namespace = new_namespace;
        }
    }

    pub fn pushNamespace(self: *Self, child_name: []const u8) !void {
        const name = try self.qualifyName(child_name);
        self.namespace = name;
    }

    pub fn popNamespace(self: *Self) void {
        self.namespace = self.namespace[0..std.mem.lastIndexOfScalar(u8, self.namespace, ':').?];
    }

    pub fn clickWidget(self: *Self, rec: Rect, opts: struct {
        teleport_area: ?Rect = null,
    }) ClickState {
        const ld = self.current_layout_cache_data.?;
        const index = self.getTransientIndex();

        if (self.popup) |p| {
            //TODO this will fail sometimes because we can't garantee popup has been called before this click widget
            //Can set layout to have popup flag or something
            if (!self.in_popup and graph.rectContainsPoint(p.area, self.input_state.mouse_pos)) return .none;
        }

        const containsCursor = graph.rectContainsPoint(rec, self.input_state.mouse_pos);
        const clicked = self.input_state.mouse_left_clicked;

        if (self.mouse_grabbed_by_hash) |hash| {
            if (hash == ld.hash) {
                if (self.mouse_widget_index == index) {
                    if (self.mouse_released) {
                        self.click_timer = 0;
                        self.last_clicked = .{ .hash = hash, .index = index };
                        self.mouse_grabbed_by_hash = null;
                        return .click_release;
                    }
                    return .held;
                }
            }
        } else {
            if (self.scroll_bounds) |sb| {
                if (!graph.rectContainsPoint(sb, self.input_state.mouse_pos))
                    return .none;
            }
            if (opts.teleport_area) |parent_area| {
                if (clicked and !containsCursor and graph.rectContainsPoint(parent_area, self.input_state.mouse_pos)) {
                    self.mouse_widget_index = index;
                    self.mouse_grabbed_by_hash = ld.hash;
                    return .click_teleport;
                }
            }
            const ret: ClickState = if (containsCursor) (if (clicked) .click else .hover) else .none;
            if (ret == .click) {
                self.mouse_widget_index = index;
                self.mouse_grabbed_by_hash = ld.hash;
                const double_click_time = 10;
                if (self.click_timer < double_click_time) {
                    if (self.last_clicked) |lc| {
                        if (lc.hash == ld.hash and lc.index == index) {
                            return .double;
                        }
                    }
                }
            }
            return ret;
        }

        return if (containsCursor) .hover_no_focus else .none;
    }

    pub fn draggable(self: *Self, area: Rect, mdelta_scale: Vec2f, x_val: anytype, y_val: anytype, opts: struct {
        x_min: ?f32 = null,
        x_max: ?f32 = null,
        y_min: ?f32 = null,
        y_max: ?f32 = null,
    }) ClickState {
        const Helper = struct {
            const Type = std.builtin.Type;

            fn getVal(comptime info: Type, val: anytype) f32 {
                return switch (info) {
                    .Int => @floatFromInt(val.*),
                    .Float => @as(f32, @floatCast(val.*)),
                    .Void => 0,
                    else => @compileError("invalid type"),
                };
            }

            fn addDelta(comptime info: Type, val: *f32, delta: f32, trunc_state: *f32) void {
                if (info == .Int or info == .Float)
                    val.* += delta + trunc_state.*;
                if (info == .Int)
                    trunc_state.* = val.* - @trunc(val.*);
            }

            fn setVal(comptime info: Type, valptr: anytype, val: f32, min: ?f32, max: ?f32) void {
                const math = std.math;
                switch (info) {
                    .Float => {
                        valptr.* = math.clamp(val, if (min) |m| m else math.f32_min, if (max) |mx| mx else math.f32_max);
                    },
                    .Int => {
                        const cval = math.clamp(val, if (min) |m| m else math.minInt(@Type(info)), if (max) |mx| mx else math.maxInt(@Type(info)));
                        valptr.* = @as(@typeInfo(@TypeOf(valptr)).Pointer.child, @intFromFloat(@trunc(cval)));
                    },
                    .Void => {},
                    else => @compileError("invalid type"),
                }
            }
        };
        const xptrinfo = @typeInfo(@TypeOf(x_val));
        const xinfo = @typeInfo(xptrinfo.Pointer.child);
        const yptrinfo = @typeInfo(@TypeOf(y_val));
        const yinfo = @typeInfo(yptrinfo.Pointer.child);

        var val: Vec2f = .{ .x = Helper.getVal(xinfo, x_val), .y = Helper.getVal(yinfo, y_val) };
        const click = self.clickWidget(area, .{});

        if (click == .click) {
            self.draggable_state = .{ .x = 0, .y = 0 };
        }
        if (click == .click or click == .held) {
            Helper.addDelta(xinfo, &val.x, mdelta_scale.x * self.input_state.mouse_delta.x, &self.draggable_state.x);
            Helper.addDelta(yinfo, &val.y, mdelta_scale.y * self.input_state.mouse_delta.y, &self.draggable_state.y);
        }
        Helper.setVal(xinfo, x_val, val.x, opts.x_min, opts.x_max);
        Helper.setVal(yinfo, y_val, val.y, opts.y_min, opts.y_max);
        return click;
    }

    pub fn beginLayout(self: *Self, comptime Layout_T: type, layout_data: Layout_T, opts: struct { bg: Color = itc(0x222222ff) }) !*Layout_T {
        const new_layout = try self.alloc.create(Layout_T);
        new_layout.* = layout_data;

        const old_layout = self.layout;
        if (self.layout.isSet()) {
            if (Layout_T == SubRectLayout) {
                self.layout.bounds = layout_data.rect;
            } else {
                const child_area = self.getArea();
                self.layout.bounds = child_area orelse Rect.new(0, 0, 0, 0);
                if (child_area == null)
                    new_layout.hidden = true;
            }
        }

        const node = try self.alloc.create(LayoutStackT.Node);
        node.next = null;
        node.data = old_layout;
        self.layout_stack.prepend(node);
        self.layout.setNew(Layout_T, new_layout);

        { //Layout cache
            const dirty = if (self.current_layout_cache_data) |ld| ld.dirty else false;
            try self.layout_cache.push(.{ .hash = self.layout.hash(), .rec = self.layout.bounds });
            self.current_layout_cache_data = self.layout_cache.getCacheDataPtr();
            const ld = self.current_layout_cache_data.?;
            ld.widget_index = 0;
            ld.widget_hash_index = 0;

            if (dirty or !ld.is_init or self.no_caching) {
                _ = opts;
                //self.drawRectFilled(self.layout.bounds, opts.bg);
            }

            if (!ld.is_init) {
                ld.init(self.retained_alloc);
            } else {
                ld.was_init = false;
            }

            ld.dirty = dirty;
        }
        return new_layout;
    }

    pub fn endLayout(self: *Self) void {
        self.layout_cache.pop() catch unreachable;
        self.current_layout_cache_data = self.layout_cache.getCacheDataPtr();
        //const ld = self.current_layout_cache_data.?;
        //if()
        if (self.current_layout_cache_data) |ld| {
            if (!ld.is_init) unreachable;
        }
        if (self.layout_stack.popFirst()) |layout| {
            self.layout = layout.data;
            self.alloc.destroy(layout);
        } else {
            unreachable;
        }
    }

    pub fn beginPopup(self: *Self, area: Rect) !void {
        _ = try self.beginLayout(SubRectLayout, .{ .rect = area }, .{});
        self.last_frame_had_popup = true;
        self.in_popup = true;
        self.popup = .{ .area = area };
    }

    pub fn endPopup(self: *Self) void {
        self.in_popup = false;
        if (self.popup_hash == null)
            self.popup = null;
        self.endLayout();
    }

    pub fn skipArea(self: *Self) void {
        _ = self.getArea();
    }

    pub fn draw(self: *Self, command: DrawCommand) void {
        if (self.in_popup) {
            self.command_list_popup.append(command) catch unreachable;
        } else {
            self.command_list.append(command) catch unreachable;
        }
    }

    pub fn drawSetCamera(self: *Self, cam: DrawCommand) void {
        self.command_list.append(cam) catch unreachable;
    }

    pub fn scissor(self: *Self, r: ?Rect) void {
        self.draw(.{ .scissor = .{ .area = r } });
        //if (self.command_list.items.len > 0) {
        //    const last = &self.command_list.items[self.command_list.items.len - 1];
        //    switch (last.*) {
        //        .scissor => |sc| {
        //            if (sc.area != null) {
        //                if (r == null) { //delete both
        //                }
        //                last.*.scissor.area = r;
        //                return;
        //            }
        //        },
        //        else => {},
        //    }
        //}
        //self.draw(.{ .scissor = .{ .area = r } });
        //self.command_list.append(.{ .scissor = .{ .area = r } }) catch unreachable;
    }

    pub fn drawText(self: *Self, string: []const u8, pos: Vec2f, size: f32, color: Color) void {
        self.draw(.{ .text = .{ .string = self.storeString(string), .pos = pos.toI(i16, Vec2i), .size = size, .color = color, .font = self.font } });
    }

    pub fn drawIcon(self: *Self, icon: u21, pos: Vec2f, size: f32, color: Color) void {
        var out: [4]u8 = undefined;
        const count = std.unicode.utf8Encode(icon, &out) catch unreachable;
        self.draw(.{ .text = .{ .string = self.storeString(out[0..count]), .pos = pos.toI(i16, Vec2i), .size = size, .color = color, .font = self.icon_font } });
    }

    pub fn drawLine(self: *Self, a: Vec2f, b: Vec2f, color: Color) void {
        self.draw(.{ .line = .{ .a = a, .b = b, .color = color } });
    }

    pub fn drawRectFilled(self: *Self, r: Rect, color: Color) void {
        self.draw(.{ .rect_filled = .{ .r = r, .color = color } });
    }

    pub fn drawRectOutline(self: *Self, r: Rect, color: Color) void {
        self.draw(.{ .rect_outline = .{ .r = r, .color = color } });
    }

    pub fn drawRectTextured(self: *Self, r: Rect, color: Color, uv: Rect, t: graph.Texture) void {
        self.draw(.{ .rect_textured = .{ .r = r, .color = color, .uv = uv, .texture = t } });
    }

    pub fn drawRectMultiColor(self: *Self, r: Rect, colors: [4]Color) void {
        self.draw(.{ .rect_filled_multi_color = .{ .r = r, .colors = colors } });
    }

    pub fn draw9Border(self: *Self, r: Rect, tr: Rect, texture: graph.Texture, scale: f32, cutout_start: f32, cutout_end: f32) void {
        self.draw(.{ .rect_9border = .{
            .r = r,
            .uv = tr,
            .texture = texture,
            .scale = scale,
            .cutout_start = cutout_start,
            .cutout_end = cutout_end,
        } });
    }

    pub fn draw9Slice(self: *Self, r: Rect, tr: Rect, texture: graph.Texture, scale: f32) void {
        self.draw(.{ .rect_9slice = .{
            .r = r,
            .uv = tr,
            .texture = texture,
            .scale = scale,
        } });
    }

    pub fn drawTextFmt(
        self: *Self,
        comptime fmt: []const u8,
        args: anytype,
        area: Rect,
        size: f32,
        color: Color,
        opts: struct { justify: Justify = .left },
    ) void {
        var fbs = std.io.FixedBufferStream([]u8){ .pos = 0, .buffer = &self.scratch_buf };
        fbs.writer().print(fmt, args) catch unreachable;
        const slice = fbs.getWritten();
        const bounds = self.font.textBounds(slice, size);
        const last_char_index = self.font.nearestGlyphX(slice, size, .{ .x = bounds.x, .y = bounds.y }) orelse slice.len;

        const x = switch (opts.justify) {
            .left => area.x,
            .right => area.x + area.w - bounds.x,
            .center => area.x + area.w / 2 - bounds.x / 2,
        };
        const sl = if (last_char_index < slice.len) slice[0..last_char_index] else slice;
        self.drawText(sl, Vec2f.new(x, area.y), size, color);
    }

    pub fn spinner(self: *Self, val: *f32) void {
        //TODO add way of timing how long left mouse has been held
        //on click value changes by a user provided inc value. After held_time has been exceeded start applying inc at a fixed rate
        //Add support for ints and floats
        const rec = self.getArea() orelse return;
        const dec_button = Rect.new(rec.x, rec.y, rec.h, rec.h);
        const inc_button = Rect.new(rec.x + rec.w - rec.h, rec.y, rec.h, rec.h);

        const dec_click = self.clickWidget(dec_button, .{});
        const inc_click = self.clickWidget(inc_button, .{});

        if (dec_click == .held or dec_click == .click)
            val.* -= 0.1;
        if (inc_click == .held or inc_click == .click)
            val.* += 0.1;

        self.drawRectFilled(rec, Color.Black);
        self.drawRectFilled(dec_button, Color.White);
        self.drawRectFilled(inc_button, Color.White);
        self.drawTextFmt("{d:.2}", .{val.*}, rec, rec.h, Color.White, .{ .justify = .center });
    }

    pub fn checkboxNotify(self: *Self, label: []const u8, checked: *bool) bool {
        const rec = self.getArea() orelse return false;
        const click = self.clickWidget(rec, .{});
        const wstate = self.getWidgetState(.{ .t = WidgetTypes.checkbox, .rec = rec, .name = label, .s = click });
        var changed = false;
        if (click == .click) {
            checked.* = !checked.*;
            changed = true;
        }
        if (wstate != .no_change) {
            self.drawRectFilled(rec, Color.Gray);
            const inset = rec.inset(rec.h * 0.1);
            const check_outer = graph.Rec(inset.x, inset.y, inset.h, inset.h);
            const check_inner = check_outer.inset(check_outer.h * 0.2);
            self.drawRectFilled(check_outer, Color.White);
            self.drawRectOutline(check_outer, Color.Black);
            if (checked.*) {
                _ = check_inner;
                self.drawIcon(0xEB7B, rec.pos(), rec.h, Color.Black);
            }

            self.drawText(label, .{ .x = rec.x + rec.h, .y = rec.y }, rec.h, Color.Black);
        }
        return changed;
    }

    pub fn checkbox(self: *Self, label: []const u8, checked: *bool) void {
        _ = self.checkboxNotify(label, checked);
    }

    pub fn tabs(self: *Self, comptime list_type: type, selected: *list_type) !list_type {
        const info = @typeInfo(list_type);
        const fields = info.Enum.fields;
        _ = try self.beginLayout(HorizLayout, .{ .count = fields.len }, .{});
        defer self.endLayout();
        inline for (fields) |field| {
            if (self.buttonEx(.{
                .name = field.name,
            })) {
                selected.* = @as(list_type, @enumFromInt(field.value));
            }
        }

        return selected.*;
    }

    pub fn colorInline(self: *Self, color: *Hsva) !void {
        //TODO the following 4 fields could be moved into a single struct for convience with a single function call
        const rec = self.getArea() orelse return;
        const ld = self.current_layout_cache_data.?;
        const index = self.getTransientIndex();

        const click = self.clickWidget(rec, .{});
        const wstate = self.getWidgetState(.{ .c = click, .r = rec, .cc = color.* });

        if (self.popup_index) |ind| {
            if (self.popup_hash) |hash| {
                if (hash == ld.hash and ind == index) {
                    const lrq = self.layout.last_requested_bounds orelse graph.Rec(0, 0, 0, 0);
                    const pr = graph.Rec(lrq.x, lrq.y, 700, 700);
                    try self.beginPopup(pr);
                    //_ = try self.beginLayout(SubRectLayout, .{ .rect = pr });
                    //defer self.endLayout();
                    defer self.endPopup();
                    self.colorPicker(color);
                }
            }
        } else {
            if (click == .click) {
                self.popup_index = index;
                self.popup_hash = ld.hash;
                self.last_frame_had_popup = true;
            }
        }
        if (wstate != .no_change)
            self.drawRectFilled(rec, graph.hsvaToColor(color.*));
    }

    //TODO what happens when the enum has lots of values and can't fit on the screen. Add scrolling function.
    //Should typing and autocompleting a value be a function
    pub fn enumDropDown(self: *Self, comptime enumT: type, enum_val: *enumT) !void {
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
                    //try self.beginPopup(graph.Rec(lrq.x, lrq.y, lrq.w, h * @intToFloat(f32, num_field)));
                    const popup_rec = graph.Rec(lrq.x, lrq.y, lrq.w, h * 5);
                    try self.beginPopup(popup_rec);
                    if (try self.beginVLayoutScroll(&self.enum_drop_down_scroll, .{ .item_height = h })) |scroll| {

                        //if (try self.beginScroll(&self.enum_drop_down_scroll, .{ .item_height = h }, .{})) |scroll| {
                        //    defer self.endScroll(scroll);
                        //_ = try self.beginLayout(VerticalLayout, .{ .item_height = h, .paddingv = 0 });

                        inline for (info.Enum.fields) |field| {
                            if (self.button(field.name)) {
                                if (!done) {
                                    enum_val.* = @as(enumT, @enumFromInt(field.value));
                                    self.popup_index = null;
                                    self.popup_hash = null;
                                    done = true;
                                }
                            }
                            //self.drawText(field.name, arec.pos(), arec.h, Color.Black);
                        }
                        try self.endVLayoutScroll(scroll);
                    }

                    //self.endLayout();
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
            self.drawRectFilled(rec, Color.Black);
            const scale = h / 20;
            self.drawRectFilled(Rect.newV(rec.pos(), rec.dim().sub(.{ .x = scale, .y = scale })), Color.White);
            const inner = rec.inset(scale);
            self.drawRectFilled(inner, itc(0xaaaaaaff));

            self.drawText(@tagName(enum_val.*), .{ .x = inner.x + scale * 6, .y = inner.y }, inner.h, Color.Black);
        }
    }

    pub fn buttonEx(self: *Self, opts: struct {
        name: []const u8 = "",
        mouse_colors: ClickStateColors = ClickStateColors.new(.{ .none = Color.Gray, .held = Color.Blue, .click = Color.Blue, .hover = Color.Green, .hover_no_focus = Color.Gray, .click_teleport = Color.Gray, .click_release = Color.Blue, .double = Color.Gray }),
        label_size: ?f32 = null,
    }) bool {
        const arec = self.getArea() orelse return false;
        const rec = arec.inset(1);
        const click = self.clickWidget(rec, .{});
        const wstate = self.getWidgetState(.{
            .t = WidgetTypes.button,
            .rec = rec,
            .name = opts.name,
            .color = opts.mouse_colors._switch(.none),
        });

        if (wstate != .no_change or click != .none) {
            self.drawRectFilled(arec, switch (click) {
                else => itc(0x444444ff),
                .hover => itc(0x555555ff),
                .click, .held => itc(0x111111ff),
            });

            const border_perc = 0.1;
            //    self.drawRectFilled(graph.Rec(arec.x, arec.y, arec.w, arec.h * border_perc), itc(0x777777ff));
            //    self.drawRectFilled(graph.Rec(arec.x, arec.y + arec.h * 1 - border_perc, arec.w, arec.h * border_perc), itc(0x222222ff));
            //self.drawRectFilled(rec, opts.mouse_colors._switch(click));

            if (opts.name.len > 0)
                self.drawText(opts.name, .{ .x = rec.x, .y = rec.y + rec.h * border_perc }, opts.label_size orelse rec.h * (1 - border_perc * 2), Color.White);
        }
        return click == .click;
    }

    pub fn button(self: *Self, name: []const u8) bool {
        return self.buttonEx(.{ .name = name });
    }

    pub fn drawConsole(self: *Self, console: Console, line_height: f32) void {
        const area = self.getArea() orelse return;
        const count: usize = @intFromFloat(area.h / line_height);
        var start: usize = 0;
        if (count < console.lines.items.len) {
            start = console.lines.items.len - count;
        }
        var y: f32 = 0;
        self.drawRectFilled(area, Color.Black);
        for (console.lines.items[start..]) |line| {
            self.drawText(line, .{ .x = area.x, .y = area.y + y }, line_height, Color.White);
            y += line_height;
        }
    }

    pub fn printLabel(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        const rec = self.getArea() orelse return;
        const wstate = self.getWidgetState(.{ .t = WidgetTypes.print_label, .name = fmt, .r = rec });
        if (wstate == .no_change) return;

        var fbs = std.io.FixedBufferStream([]u8){ .pos = 0, .buffer = &self.scratch_buf };
        try fbs.writer().print(fmt, args);
        self.drawRectFilled(rec, Color.Gray);
        self.drawText(fbs.getWritten(), rec.pos(), rec.h, Color.White);
    }

    pub fn textLabel(self: *Self, name: []const u8) void {
        const rec = self.getArea() orelse return;

        const wstate = self.getWidgetState(.{ .t = WidgetTypes.text_label, .rec = rec.toIntRect(i16, SRect), .name = name });
        if (wstate != .no_change) {
            self.drawRectFilled(rec, Color.Gray);
            self.drawText(name, rec.pos(), rec.h, Color.White);
        }
    }

    //Only vertical for now

    pub fn beginScrollN(self: *Self, offset: *Vec2f, opts: struct {
        horiz_scroll: bool = true,
        vertical_scroll: bool = true,
        bar_w: f32 = 60,
        w: f32,
        h: f32,
    }) !?ScrollData {
        var area = self.getArea() orelse return null;

        if (opts.horiz_scroll)
            area.h -= opts.bar_w;
        if (opts.vertical_scroll)
            area.w -= opts.bar_w;

        var clipped_area = area;
        //Scroll exists inside a scroll. Push bounds and offset into parent layout
        if (self.scroll_bounds) |parent_b| {
            self.layout.parent_scroll_bounds = parent_b;

            if (area.x < parent_b.x) { //Passed the left, clip left
                clipped_area.x = parent_b.x;
                if (clipped_area.x + clipped_area.w > parent_b.x + parent_b.w)
                    clipped_area.w = (parent_b.x + parent_b.w) - clipped_area.x;
            } else if (area.x + area.w > parent_b.x + parent_b.w) { //Passed the right, clip right
                clipped_area.w = (parent_b.x + parent_b.w) - clipped_area.x;
            }

            if (area.y < parent_b.y) {
                clipped_area.y = parent_b.y;
            } else if (area.y + area.h > parent_b.y + parent_b.h) {
                clipped_area.h = (parent_b.y + parent_b.h) - clipped_area.y;
            }
        }

        self.scroll_bounds = clipped_area;
        self.scissor(clipped_area);
        _ = try self.beginLayout(SubRectLayout, .{ .rect = graph.Rec(area.x - offset.x, area.y - offset.y, opts.w, opts.h) }, .{});

        return ScrollData{
            .horiz = if (opts.horiz_scroll) graph.Rec(area.x, area.y + area.h, area.w, opts.bar_w) else null,
            .vertical = if (opts.vertical_scroll) graph.Rec(area.x + area.w, area.y, opts.bar_w, area.h) else null,
            .bar_w = opts.bar_w,
            .offset = offset,
        };
    }

    pub fn endScrollN(self: *Self, scroll_data: ScrollData, vbounds: Vec2f, hbounds: Vec2f) !void {
        self.endLayout(); //SubRectLayout

        if (self.mouse_grabbed_by_hash == null and !self.scroll_claimed_mouse and graph.rectContainsPoint(self.scroll_bounds.?, self.input_state.mouse_pos)) {
            self.scroll_claimed_mouse = true;
            scroll_data.offset.y = std.math.clamp(scroll_data.offset.y + self.input_state.mouse_wheel_delta * -40, vbounds.x, vbounds.y);
        }

        self.scroll_bounds = self.layout.parent_scroll_bounds;
        self.scissor(self.scroll_bounds);

        if (scroll_data.horiz) |hrec| {
            _ = try self.beginLayout(SubRectLayout, .{ .rect = hrec }, .{});
            try self.sliderOpts(&scroll_data.offset.x, hbounds.x, hbounds.y, .{ .orientation = .horizontal, .draw_text = false });
            self.endLayout();
        }
        if (scroll_data.vertical) |vrec| {
            _ = try self.beginLayout(SubRectLayout, .{ .rect = vrec }, .{});
            try self.sliderOpts(&scroll_data.offset.y, vbounds.x, vbounds.y, .{ .orientation = .vertical, .draw_text = false });
            self.endLayout();
        }
    }

    pub fn beginVLayoutScroll(self: *Self, scr: *Vec2f, layout: VerticalLayout) !?VLayoutScrollData {
        const bar_w = 60;
        if (try self.beginScrollN(scr, .{
            .w = self.layout.bounds.w - bar_w,
            .h = 10000,
            .vertical_scroll = true,
            .horiz_scroll = false,
            .bar_w = bar_w,
        })) |scroll| {
            return .{ .layout = try self.beginLayout(VerticalLayout, layout, .{}), .data = scroll };
        }
        return null;
    }

    pub fn endVLayoutScroll(self: *Self, data: VLayoutScrollData) !void {
        const dl = data.layout.*;
        self.endLayout();
        const scr_dist = dl.current_h - data.data.vertical.?.h;
        try self.endScrollN(data.data, .{ .x = 0, .y = if (scr_dist < 0) 1 else scr_dist }, .{ .x = 0, .y = 1 });
    }

    //TODO types of sliders
    //Desktop Gui like slider than you slide a shuttle around
    //spinner kind

    pub fn sliderOpts(self: *Self, value: anytype, min: anytype, max: anytype, opts: struct {
        orientation: Orientation = .horizontal,
        draw_text: bool = true,
        handle_w: ?f32 = null,
        handle_perc: f32 = 0.99,
        bounds_check: bool = true,
        label_text: ?[]const u8 = null,
    }) !void {
        const lmin = std.math.lossyCast(f32, min);
        const lmax = std.math.lossyCast(f32, max);
        const lval = std.math.lossyCast(f32, value.*);
        const horiz = (opts.orientation == .horizontal);
        const ptrinfo = @typeInfo(@TypeOf(value));
        const child_type = ptrinfo.Pointer.child;
        if (ptrinfo != .Pointer) @compileError("slider requires a pointer for value");
        const info = @typeInfo(child_type);
        if (opts.bounds_check and (lval < lmin or lval > lmax)) return error.valueOutOfBounds;

        const arec = self.getArea() orelse return;
        const rec = if (horiz) arec.inset(8) else arec.inset(8).swapAxis();

        const handle_w = blk: {
            if (opts.handle_w) |hw| {
                break :blk hw;
            }
            const ww = rec.w * (rec.w / (lmax - lmin));
            const MIN_W = 40;
            _ = ww;
            _ = MIN_W;
            break :blk 40;

            //break :blk std.math.clamp(ww, MIN_W, rec.w);
        };
        const mdel = if (horiz) self.input_state.mouse_delta.x else self.input_state.mouse_delta.y;
        const mpos = if (horiz) self.input_state.mouse_pos.x else self.input_state.mouse_pos.y;
        const scale = (rec.w - handle_w) / (lmax - lmin);
        //const scale = switch (info) {
        //    .Float => (rec.w - handle_w) / @floatCast(f32, max - min),
        //    .Int => (rec.w - handle_w) / @intToFloat(f32, max - min),
        //    else => @compileError("slider only accepts pointers to ints or floats. Provided: " ++ @typeName(@TypeOf(value))),
        //};
        var val: f32 = switch (info) {
            .Float => @as(f32, @floatCast(value.*)),
            .Int => @as(f32, @floatFromInt(value.*)),
            else => @compileError("invalid type"),
        };

        var handle = Rect{
            .x = rec.x + (val - min) * scale,
            .y = rec.y + (rec.h - (rec.h * opts.handle_perc)) / 2,
            .w = handle_w,
            .h = rec.h * opts.handle_perc,
        };
        handle = if (horiz) handle else handle.swapAxis();
        const clicked = if (handle_w >= rec.w) .none else self.clickWidget(handle, .{});
        //const clicked = self.clickWidget(handle, .{});

        const wstate = self.getWidgetState(.{ .t = WidgetTypes.slider, .r = handle });

        if (clicked == .click) {
            self.focused_slider_state = 0;
        }

        if (clicked == .held or clicked == .click) {
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
            (if (horiz) handle.x else handle.y) = rec.x + (val - lmin) * scale;
        }

        if (self.mouse_grabbed_by_hash == null and !self.scroll_claimed_mouse and graph.rectContainsPoint(rec, self.input_state.mouse_pos)) {
            self.scroll_claimed_mouse = true;
            switch (info) {
                .Float => {},
                .Int => {
                    val += self.input_state.mouse_wheel_delta;
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
                (if (horiz) handle.x else handle.y) = rec.x + (@trunc(val) - min) * scale;
            },
            else => @compileError("invalid type"),
        }

        if (wstate != .no_change) {
            self.drawRectFilled(arec, itc(0x111111ff));
            self.drawRectFilled(handle, itc(0x777777ff));
            if (!opts.draw_text) return;
            const tt = if (opts.label_text) |t| t else "";
            if (info == .Float) {
                self.drawTextFmt("{s}{d:.2}", .{ tt, val }, rec, rec.h, Color.White, .{ .justify = .center });
            } else {
                self.drawTextFmt("{s}{d:.0}", .{ tt, @trunc(val) }, arec, arec.h, Color.White, .{ .justify = .center });
            }
        }
    }

    pub fn slider(self: *Self, value: anytype, min: anytype, max: anytype) !void {
        try self.sliderOpts(value, min, max, .{});
    }

    pub fn textboxNumber(self: *Self, number: anytype) !void {
        const info = @typeInfo(@TypeOf(number));
        if (info != .Pointer or info.Pointer.is_const) @compileError("textboxNumber expects a mutable pointer to a number: " ++ @typeName(@TypeOf(number)));
        const number_type = info.Pointer.child;
        const rec = self.getArea() orelse return;

        const ld = self.current_layout_cache_data.?;
        const index = self.getTransientIndex();
        const click = self.clickWidget(rec, .{});
        const state = self.getWidgetState(.{
            .rec = rec.toIntRect(i16, SRect),
            .n = switch (@typeInfo(number_type)) {
                .Int => number.*,
                .Float => @as(i64, @intFromFloat(number.*)),
                else => unreachable,
            },
        });

        var is_drawn = false;
        if (self.text_input_hash) |hash| {
            if (self.text_input_index) |ind| {
                if (hash == ld.hash and ind == index) {
                    const tb = &self.textbox_state;
                    self.text_input_state = switch (self.text_input_state) {
                        .start => ._continue,
                        .disabled => .start,
                        ._continue, .stop => ._continue,
                    };
                    try tb.handleEventsOpts(
                        self.text_input,
                        self.input_state,
                        .{ .numbers_only = true },
                    );
                    const sl = self.textbox_state.getSlice();
                    if (state != .no_change) {
                        self.drawTextFmt("{s}", .{sl}, rec, rec.h, Color.Black, .{});
                        const caret_x = self.font.textBounds(sl[0..@as(usize, @intCast(tb.head))], rec.h).x;
                        self.drawRectFilled(Rect.new(caret_x + rec.x, rec.y + 2, 3, rec.h - 4), Color.Black);
                    }

                    number.* = switch (@typeInfo(number_type)) {
                        .Int => std.fmt.parseInt(number_type, sl, 10) catch blk: {
                            //TODO disallow non numeric chars from being entered in the first place
                            break :blk number.*;
                        },
                        .Float => std.fmt.parseFloat(number_type, sl) catch number.*,
                        else => @compileError("unsupported type: " ++ @typeName(number_type)),
                    };

                    is_drawn = true;
                }
            }
        }
        if (!is_drawn and state != .no_change)
            self.drawTextFmt("{d}", .{number.*}, rec, rec.h, Color.Black, .{});
        if (click == .click) {
            if (self.isCurrentTextInput(ld.hash, index)) {
                const cin = self.font.nearestGlyphX(self.textbox_state.getSlice(), rec.h, self.input_state.mouse_pos.sub(rec.pos()));
                if (cin) |cc| {
                    self.textbox_state.setCaret(cc - 1);
                }
            } else {
                self.text_input_hash = ld.hash;
                self.text_input_index = index;
                try self.textbox_state.reset("");
                try self.textbox_state.codepoints.writer().print("{d}", .{number.*});
                self.textbox_state.head = @as(i32, @intCast(self.textbox_state.codepoints.items.len));
                self.textbox_state.tail = self.textbox_state.head;
            }
        }
    }

    pub fn textbox(self: *Self, buffer: *[]u8, buffer_alloc: std.mem.Allocator) !void {
        const area = self.getArea() orelse return;
        self.drawRectFilled(area, Color.Gray);
        const ld = self.current_layout_cache_data.?;
        const index = self.getTransientIndex();
        const click = self.clickWidget(area, .{});
        var is_drawn = false;
        if (self.isCurrentTextInput(ld.hash, index)) {
            const tb = &self.textbox_state;
            self.text_input_state = switch (self.text_input_state) {
                .start => ._continue,
                .disabled => .start,
                ._continue, .stop => ._continue,
            };
            try tb.handleEventsOpts(
                self.text_input,
                self.input_state,
                .{},
            );
            const sl = self.textbox_state.getSlice();
            self.drawText(sl, area.pos(), area.h, Color.White);
            const caret_x = self.font.textBounds(sl[0..@as(usize, @intCast(tb.head))], area.h).x;
            self.drawRectFilled(Rect.new(caret_x + area.x, area.y + 2, 3, area.h - 4), Color.Black);
            is_drawn = true;

            if (!std.mem.eql(u8, sl, buffer.*)) {
                buffer.* = try buffer_alloc.realloc(buffer.*, sl.len);
                std.mem.copy(u8, buffer.*, sl);
                std.debug.print("New buffer {s}\n", .{buffer.*});
            }
        }
        if (!is_drawn) {
            self.drawText(buffer.*, area.pos(), area.h, Color.White);
        }
        if (click == .click) {
            if (self.isCurrentTextInput(ld.hash, index)) {
                const cin = self.font.nearestGlyphX(self.textbox_state.getSlice(), area.h, self.input_state.mouse_pos.sub(area.pos()));
                if (cin) |cc| {
                    self.textbox_state.setCaret(cc - 1);
                }
            } else {
                self.text_input_hash = ld.hash;
                self.text_input_index = index;
                try self.textbox_state.reset("");
                try self.textbox_state.codepoints.writer().print("{s}", .{buffer.*});
                self.textbox_state.head = @as(i32, @intCast(self.textbox_state.codepoints.items.len));
                self.textbox_state.tail = self.textbox_state.head;
            }
        }
    }

    pub fn textBoxOpts(self: *Self, name: []const u8, opts: struct { fully_qualified: bool = false, label: ?[]const u8 = null }) !void {
        //TODO fix textbox handleEvents;
        _ = self;
        _ = name;
        _ = opts;
        return;
        // const qualified_name = if (opts.fully_qualified) name else try self.qualifyName(name);
        // const label = if (opts.label) |lab| lab else name;

        // const rec = self.getArea() orelse return;

        // const text_height = rec.h / 5.0;
        // const title_rec = Rect.new(rec.x, rec.y + text_height / 2, rec.w, rec.h / 5.0 * 2.0);
        // const box_rect = Rect{ .x = rec.x, .y = rec.y + title_rec.h, .w = rec.w, .h = rec.h / 5.0 * 3 };
        // const inner_rect = box_rect.inset(5);

        // if (self.retained_data.getEntry(qualified_name)) |entr| {
        //     const tb = &entr.value_ptr.data.text_box;
        //     const hovered = graph.rectContainsPoint(box_rect, self.input_state.mouse_pos);

        //     const clicked = hovered and self.input_state.mouse_left_clicked;
        //     if (clicked) {
        //         self.focused_element = entr.key_ptr.*;
        //     }
        //     const focused = blk: {
        //         if (std.mem.eql(u8, self.focused_element, qualified_name)) {
        //             self.text_input_state = switch (self.text_input_state) {
        //                 .start => ._continue,
        //                 .disabled => .start,
        //                 ._continue, .stop => ._continue,
        //             };
        //             try tb.handleEvents(
        //                 self.text_input,
        //                 self.input_state,
        //             );
        //             break :blk true;
        //         }
        //         break :blk false;
        //     };

        //     self.drawRectFilled(box_rect, Color.White);
        //     self.drawRectFilled(inner_rect, Color.Black);

        //     const text_height_ = box_rect.h / 3.0;
        //     const text_x_offset = text_height / 2;
        //     const text_rect = Rect.new(inner_rect.x + text_x_offset, box_rect.y + text_height, text_height, inner_rect.x - text_x_offset);
        //     self.drawText(tb.chars.items, text_rect.pos(), text_height_, Color.White);
        //     self.drawText(label, title_rec.pos(), text_height, Color.Gray);
        //     if (focused) {
        //         const caret_x = self.font.textBounds(tb.chars.items[0..@intCast(usize, tb.head)], text_height_).x;
        //         self.drawRectFilled(Rect.new(caret_x + text_rect.x + 6, text_rect.y + 2, 3, text_height_ - 4), Color.White);
        //     }
        // } else {
        //     //TODO don't have this single frame delay, draw on the first invocation of textBoxOpts
        //     const qf = try self.retained_alloc.alloc(u8, qualified_name.len);
        //     std.mem.copy(u8, qf, qualified_name);
        //     try self.retained_data_key_store.append(qf);

        //     var arr = std.ArrayList(u8).init(self.retained_alloc);

        //     try self.retained_data.put(qf, .{ .data = .{ .text_box = .{ .chars = arr, .head = 0, .tail = 0 } } });
        // }
    }

    pub fn textBox(self: *Self, name: []const u8) !void {
        try self.textBoxOpts(name, .{});
    }

    pub fn colorPicker(self: *Self, color: *Hsva) void {
        const hue_slider_w = 70;
        //const sv_size = 500;
        const rec = self.getArea() orelse return;
        const sv_area = Rect.new(rec.x, rec.y, rec.w - hue_slider_w, rec.h);
        const h_area = Rect.new(rec.x + rec.w - hue_slider_w, rec.y, hue_slider_w, rec.h);
        const wstate = self.getWidgetState(.{ .t = WidgetTypes.color_picker, .r = rec.toIntRect(i16, SRect) });

        var hsva = color.*;
        const hs = 15;
        var sv_handle = Rect.new(sv_area.x + hsva.s * sv_area.w - hs / 2, sv_area.y + (1.0 - hsva.v) * sv_area.h - hs / 2, hs, hs);

        const hue_handle_height = 15;
        var hue_handle = Rect.new(h_area.x, h_area.y + h_area.h * hsva.h / 360.0 - hue_handle_height / 2, h_area.w, hue_handle_height);

        const clicked = self.clickWidget(sv_handle, .{ .teleport_area = sv_area });
        const mpos = self.input_state.mouse_pos;
        switch (clicked) {
            .click, .held => {
                const mdel = self.input_state.mouse_delta;

                hsva.s += mdel.x / sv_area.w;
                hsva.v += -mdel.y / sv_area.h;

                hsva.s = std.math.clamp(hsva.s, 0, 1);
                hsva.v = std.math.clamp(hsva.v, 0, 1);

                if (mpos.x > sv_area.x + sv_area.w)
                    hsva.s = 1.0;
                if (mpos.x < sv_area.x)
                    hsva.s = 0.0;

                if (mpos.y > sv_area.y + sv_area.h)
                    hsva.v = 0.0;
                if (mpos.y < sv_area.y)
                    hsva.v = 1.0;
            },
            .click_teleport => {
                hsva.s = (mpos.x - sv_area.x) / sv_area.w;
                hsva.v = (1.0 - (mpos.y - sv_area.y) / sv_area.h);
                hsva.s = std.math.clamp(hsva.s, 0, 1);
                hsva.v = std.math.clamp(hsva.v, 0, 1);
            },

            else => {},
        }

        sv_handle = Rect.new(sv_area.x + hsva.s * sv_area.w - hs / 2, sv_area.y + (1.0 - hsva.v) * sv_area.h - hs / 2, hs, hs);

        const hue_clicked = self.clickWidget(hue_handle, .{ .teleport_area = h_area });
        switch (hue_clicked) {
            .click, .held => {
                const mdel = self.input_state.mouse_delta;
                hsva.h += 360 * mdel.y / h_area.h;
                hsva.h = std.math.clamp(hsva.h, 0, 360);

                if (self.input_state.mouse_pos.y > h_area.y + h_area.h)
                    hsva.h = 360.0;
                if (self.input_state.mouse_pos.y < h_area.y)
                    hsva.h = 0.0;
            },
            .click_teleport => {
                hsva.h = (mpos.y - h_area.y) / h_area.h * 360.0;
            },
            else => {},
        }
        hue_handle = Rect.new(h_area.x, h_area.y + h_area.h * hsva.h / 360.0 - hue_handle_height / 2, h_area.w, hue_handle_height);

        color.* = hsva;

        if (graph.rectContainsPoint(rec, self.input_state.mouse_pos) or wstate != .no_change or clicked != .none or hue_clicked != .none) {
            const Col = graph.CharColorNew;
            self.drawRectFilled(rec, Color.Gray);
            //Ported from Nuklear
            {
                const hue_colors: [7]Color = .{ Col(255, 0, 0, 255), Col(255, 255, 0, 255), Col(0, 255, 0, 255), Col(0, 255, 255, 255), Col(0, 0, 255, 255), Col(255, 0, 255, 255), Col(255, 0, 0, 255) };
                const hr = h_area;
                var i: u32 = 0;
                while (i < 6) : (i += 1) {
                    const fi = @as(f32, @floatFromInt(i));
                    self.drawRectMultiColor(Rect.new(hr.x, hr.y + fi * hr.h / 6.0, hr.w, hr.h / 6.0), .{
                        hue_colors[i], // 1
                        hue_colors[i + 1], //3
                        hue_colors[i + 1], //4
                        hue_colors[i], //2
                    });
                }
            }
            const temp = graph.hsvaToColor(.{ .h = hsva.h, .s = 1, .v = 1, .a = 1 });
            const black_trans = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
            self.drawRectMultiColor(sv_area, .{ Color.White, Color.White, temp, temp });
            self.drawRectMultiColor(sv_area, .{ black_trans, Color.Black, Color.Black, black_trans });

            self.drawRectFilled(sv_handle, Color.Black);
            self.drawRectFilled(hue_handle, Color.Black);
        }
    }

    fn isThisCurrentPopup(self: *Self, popup_index: u32) bool {
        const ld = self.current_layout_cache_data.?;
        if (self.popup_index) |ind| {
            if (self.popup_hash) |hash| {
                return (hash == ld.hash and ind == popup_index);
            }
        }
        return false;
    }

    fn editProperty(self: *Self, comptime propertyT: type, property: *propertyT) !void {
        const child_info = @typeInfo(propertyT);
        switch (child_info) {
            .Struct => {
                const o = property;
                switch (propertyT) {
                    graph.Hsva => try self.colorInline(property),
                    graph.Rect => try self.printLabel("Rect({d:.2} {d:.2} {d:.2} {d:.2})", .{ o.x, o.y, o.w, o.h }),
                    else => {
                        //self.drawText("Struct", .{ .x = rec.x + rec.w / 2, .y = rec.y + fi * item_height }, item_height, Color.Black);
                        const rec = self.getArea() orelse return;
                        const wstate = self.getWidgetState(.{ .p = rec });
                        const ld = self.current_layout_cache_data.?;
                        const index = self.getTransientIndex();
                        const click = self.clickWidget(rec, .{});
                        if (self.isThisCurrentPopup(index)) {
                            const lrq = self.layout.last_requested_bounds orelse return;
                            const pr = graph.Rec(lrq.x, lrq.y, 900, 700);
                            try self.beginPopup(pr);
                            defer self.endPopup();

                            //if (try self.beginLayout(try ld.getWidgetData(0), .{ .item_height = 3000 }, .{})) |scroll| {
                            //    defer self.endScroll(scroll);
                            //    try self.propertyTable(propertyT, property);
                            //}
                        } else {
                            if (click == .click) {
                                self.popup_index = index;
                                self.popup_hash = ld.hash;
                                self.last_frame_had_popup = true;
                            }
                        }

                        if (wstate != .no_change)
                            self.drawText("{Struct}", rec.pos(), rec.h, Color.Black);
                    },
                }
            },
            .Bool => {
                self.checkbox("cunt", property);
                //try self.printLabel("{any}", .{property.*});
            },
            .Enum => {
                try self.enumDropDown(propertyT, property);
            },
            .Int, .Float => {
                try self.textboxNumber(property);
            },
            .Pointer => |p| {
                switch (p.size) {
                    .Slice => {
                        switch (p.child) {
                            u8 => {
                                try self.printLabel("{s}", .{property.*});
                            },
                            else => {},
                        }
                    },
                    else => {
                        self.skipArea();
                    },
                }
            },
            else => {
                self.skipArea();
            },
        }
    }

    pub fn propertyTableHeight(self: *Self, comptime propertyT: type) f32 {
        _ = self;
        const item_height = 40;
        const info = @typeInfo(propertyT);
        return @as(f32, @floatFromInt(info.Struct.fields.len)) * item_height;
    }

    //TODO
    //What functions do we need to provide for property.
    //Number spinner.
    //boolean checkbox
    //Tuple drop down. (Vec3 is displayed as (x, y, z) can be dropped down to modify each component)
    pub fn propertyTable(self: *Self, comptime propertyT: type, property: *propertyT) !void {
        const info = @typeInfo(propertyT);
        //TODO check property is a struct

        const num = info.Struct.fields.len;
        const item_height = 40;
        const rec = self.getArea() orelse return;
        _ = try self.beginLayout(SubRectLayout, .{ .rect = rec }, .{});
        defer self.endLayout();

        _ = try self.beginLayout(TableLayout, .{ .item_height = item_height, .columns = 2 }, .{});
        defer self.endLayout();

        const wstate = self.getWidgetState(.{ .t = WidgetTypes.propertyTable, .r = rec.toIntRect(i16, SRect), .n = num });
        if (wstate != .no_change) {
            self.drawRectFilled(rec, Color.White);
        }

        inline for (info.Struct.fields) |field| {
            const ar = self.getArea() orelse return;
            if (wstate != .no_change) {
                self.drawText(field.name, ar.pos(), item_height, Color.Black);
            }
            const child_info = @typeInfo(field.type);
            switch (child_info) {
                .Optional => {
                    const op = @field(property, field.name);
                    if (op != null) {
                        try self.editProperty(@TypeOf(op.?), &(@field(property, field.name).?));
                    } else {
                        try self.printLabel("null", .{});
                    }
                },
                else => {
                    try self.editProperty(field.type, &@field(property, field.name));
                },
            }
        }

        if (wstate != .no_change) {
            self.drawLine(.{ .x = rec.x + rec.w / 2, .y = rec.y }, .{ .x = rec.x + rec.w / 2, .y = rec.y + item_height * @as(f32, @floatFromInt(num)) }, Color.Black);
            var i: u32 = 0;
            while (i <= num) : (i += 1) {
                self.drawLine(
                    .{ .x = rec.x, .y = rec.y + item_height * @as(f32, @floatFromInt(i)) },
                    .{ .x = rec.x + rec.w, .y = rec.y + item_height * @as(f32, @floatFromInt(i)) },
                    Color.Black,
                );
            }
        }
    }
};

pub const GuiDrawContext = struct {
    const Self = @This();

    main_rtexture: graph.RenderTexture,
    popup_rtexture: graph.RenderTexture,

    camera_offset: Vec2f = .{ .x = 0, .y = 0 },
    camera_bounds: ?Rect = null,
    win_bounds: Rect = graph.Rec(0, 0, 0, 0),

    pub fn init() !Self {
        return .{ .main_rtexture = try graph.RenderTexture.init(10, 10), .popup_rtexture = try graph.RenderTexture.init(10, 10) };
    }

    pub fn deinit(self: *Self) void {
        self.main_rtexture.deinit();
        self.popup_rtexture.deinit();
    }

    pub fn draw(self: *Self, ctx: *graph.GraphicsContext, font: *graph.Font, parea: Rect, gui: *Context, win_w: i32, win_h: i32) !void {
        // self.win_bounds = ctx.screen_bounds.toF32();
        // try self.main_rtexture.setSize(@as(i32, @intFromFloat(parea.w)), @as(i32, @intFromFloat(parea.h)));
        // self.main_rtexture.bind(true);
        // const sb = ctx.screen_bounds.toF32();
        // //ctx.screen_bounds = graph.Rec(parea.x, parea.y + parea.h, parea.x + parea.w, parea.y).toIntRect(i32, graph.IRect);
        // ctx.screen_bounds = graph.Rec(
        //     parea.x,
        //     sb.h - (parea.y + parea.h),
        //     parea.w,
        //     parea.h,
        //     //parea.x + parea.w,
        //     //sb.h - parea.y,
        // ).toIntRect(i32, graph.IRect);
        for (gui.command_list.items) |command| {
            //try drawCommand(command, &ctx, &font, rtext.w, rtext.h);
            try self.drawCommand(command, ctx, font);
        }
        try ctx.flush(.{ .x = 0, .y = 0 }, null);

        if (gui.popup) |p| {
            //try self.popup_rtexture.setSize(@as(i32, @intFromFloat(p.area.w)), @as(i32, @intFromFloat(p.area.w)));
            //self.popup_rtexture.bind(true);

            _ = p;
            //ctx.screen_bounds = graph.Rec(p.area.x, p.area.y + p.area.h, p.area.x + p.area.w, p.area.y).toIntRect(i32, graph.IRect);
            for (gui.command_list_popup.items) |command| {
                try self.drawCommand(command, ctx, font);
            }
            try ctx.flush(.{ .x = 0, .y = 0 }, null);
        }
        ctx.screen_bounds = graph.IRect.new(0, 0, win_w, win_h);
        graph.c.glBindFramebuffer(graph.c.GL_FRAMEBUFFER, 0);
        graph.c.glViewport(0, 0, win_w, win_h);

        //try ctx.drawRectTex(parea, parea, Color.White, self.main_rtexture.texture);

        const tr = self.main_rtexture.texture.rect();
        _ = parea;
        _ = tr;
        //try ctx.drawRectTex(parea, graph.Rec(0, 0, tr.w, -tr.h), Color.White, self.main_rtexture.texture);
        //try ctx.drawRectTex(parea, graph.Rec(0, 0, self.main_rtexture.texture.w, self.main_rtexture.texture.h), Color.White, self.main_rtexture.texture);
        //if (gui.popup) |p| {
        //    try ctx.drawRectTex(p.area, graph.Rec(0, 0, self.popup_rtexture.w, self.popup_rtexture.h), Color.White, self.popup_rtexture.texture);
        //}
    }

    pub fn drawCommand(self: *Self, command: DrawCommand, ctx: *graph.GraphicsContext, font: *graph.Font) !void {
        _ = font;
        switch (command) {
            .rect_filled => |rf| {
                ctx.drawRect(rf.r, rf.color);
            },
            .text => |t| {
                const p = t.pos.toF();

                ctx.drawText(p.x, p.y, t.string, t.font, t.size, t.color);
            },
            .line => |l| {
                try ctx.drawLine(l.a, l.b, l.color);
            },
            .rect_textured => |t| {
                try ctx.drawRectTex(t.r, t.uv, t.color, t.texture);
            },
            .rect_outline => |rl| {
                const r = rl.r;
                try ctx.drawLine(r.topL(), r.topR(), rl.color);
                try ctx.drawLine(r.topR(), r.botR(), rl.color);
                try ctx.drawLine(r.botR(), r.botL(), rl.color);
                try ctx.drawLine(r.botL(), r.topL(), rl.color);
            },
            .set_camera => |sc| {
                try ctx.flush(sc.offset, sc.cam_area);
                ctx.setViewport(sc.win_area);
            },
            .scissor => |s| {
                const c = graph.c;
                try ctx.flush(self.camera_offset, self.camera_bounds);
                if (s.area) |ar| {
                    c.glEnable(c.GL_SCISSOR_TEST);
                    c.glScissor(
                        @as(i32, @intFromFloat(ar.x)),
                        ctx.screen_bounds.h - @as(i32, @intFromFloat((ar.y + ar.h))),
                        //@floatToInt(i32, ar.y + ar.h) - ctx.screen_bounds.h,
                        @as(i32, @intFromFloat(ar.w)),
                        @as(i32, @intFromFloat(ar.h)),
                    );
                    //ctx.drawRect(graph.Rec(0, 0, 10000, 10000), Color.Blue);
                } else {
                    c.glDisable(c.GL_SCISSOR_TEST);
                }
            },
            .rect_filled_multi_color => |rf| {
                ctx.drawRectCol(rf.r, rf.colors);
            },
            .rect_9slice => |s| {
                try ctx.draw9Slice(s.r, s.uv, s.texture, s.scale);
            },
            .rect_9border => |s| {
                try ctx.draw9Border(s.r, s.uv, s.texture, s.scale, s.cutout_start, s.cutout_end);
            },
        }
    }
};
