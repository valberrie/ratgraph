const std = @import("std");
const graph = @import("graphics.zig");
const gui = @import("gui.zig");

const SparseSet = graph.SparseSet;

const aabb = @import("col.zig");

const ecs = @import("registry.zig");

const c = @cImport(@cInclude("tree_sitter/api.h"));

const SubTileset = graph.SubTileset;

const intToColor = graph.intToColor;
const itc = intToColor;
const Color = graph.CharColor;

const pow = std.math.pow;
const sqrt = std.math.sqrt;

const text = @embedFile("main.zig");
const my_str =
    \\There are usually two sets of metrics for a single glyph:
    \\ Those used to represent glyphs in horizontal text layouts
    \\ (Latin, Cyrillic, Arabic, Hebrew, etc.), and those used 
    \\ to represent glyphs in vertical text layouts 
    \\ (Chinese, Japanese, Korean, Mongolian, etc.).
;

pub fn quadForm(a: f32, b: f32, C: f32) ?[2]f32 {
    const discrim = pow(f32, b, 2) - (4 * a * C);

    return if (discrim < 0) null else .{ (-b + std.math.sqrt(discrim)) / (2 * a), (-b - std.math.sqrt(discrim)) / (2 * a) };
}

fn intVel(accel: f32, dt: f32, v0: f32) f32 {
    return (std.math.pow(f32, dt, 2) * accel / 2) + v0 * dt;
}

pub fn printSlice(slice: anytype, comptime fmt: ?[]const u8) void {
    const fmt_str = if (fmt) |f| "i: {d} " ++ f else "i: {d} {any}\n";
    for (slice) |item, i| {
        std.debug.print(fmt_str, .{ i, item });
    }
}

pub const MarioMap = struct {
    pub const ItemType = enum {
        const Self = @This();

        static,
        background,
        head_banger,
        mystery_box,
        enemy,
        trigger,

        pub fn jsonStringify(
            value: Self,
            options: std.json.StringifyOptions,
            out_stream: anytype,
        ) !void {
            try std.json.stringify(@enumToInt(value), options, out_stream);
        }
    };

    pub const CollisionObject = struct {};

    pub const HeadBanger = struct {
        const frame_pos = [_]f32{ -1, -3, -5, -6, -6, -7, -7, -7, -6, -5, -4, -3, -1, 1 };
        active: bool = false,
        frame: u8 = 0,
        time_active: f32 = 0,
    };

    pub const MysteryBox = struct {};

    pub const Mushroom = struct {
        const MushroomTile = TileSetInfo{ .ti = 0, .si = 11 };
        time_active: f32 = 0,
    };

    pub const Coord = struct {
        x: f32 = 0,
        y: f32 = 0,
    };

    pub const TileSetInfo = struct {
        ti: usize = 0,
        si: usize = 0,
    };
};

const mario_map_fields: ecs.FieldList = &.{
    .{ .ftype = MarioMap.Coord, .name = "coord" },
    .{ .ftype = MarioMap.TileSetInfo, .name = "tile_set_info" },
    .{ .ftype = MarioMap.CollisionObject, .name = "collidable" },
    .{ .ftype = MarioMap.HeadBanger, .name = "head_banger" },
    .{ .ftype = MarioMap.MysteryBox, .name = "mystery_box" },
    .{ .ftype = MarioMap.Mushroom, .name = "mushroom" },
};
pub const MarioTileMap = ecs.Registry(mario_map_fields);

const Elevator = struct {
    const Self = @This();
    floor_count: u32 = 20,

    cab: Cab = Cab{ .y = 0 },

    hall_calls: std.bit_set.IntegerBitSet(20),
    cab_calls: std.bit_set.IntegerBitSet(20),

    direction: Direction = .none,

    //hall_calls: std.ArrayList(u32),
    //current_dest: ?u32,

    state: State = .parked,
    //top_speed: f32 = ((20 * 3)) * 6,
    top_speed: f32 = 40,

    parked_time: f32 = 0,
    park_timeout: f32 = 0.5,

    const Direction = enum { none, up, down };

    const Cab = struct {
        y: f32,

        vy: f32 = 0,
        ay: f32 = 15,

        count: u32 = 0,
    };

    const State = enum {
        //accel,
        //brake,
        moving,
        parked,
    };

    pub fn init(alloc: *const std.mem.Allocator) Self {
        _ = alloc;
        //return Self{ .hall_calls = std.ArrayList(u32).init(alloc.*), .current_dest = null };
        return Self{
            .hall_calls = std.bit_set.IntegerBitSet(20).initEmpty(),
            .cab_calls = std.bit_set.IntegerBitSet(20).initEmpty(),
            //.current_dest = null,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        //self.hall_calls.deinit();
    }

    pub fn getCabFloor(self: Self) u32 {
        if (self.cab.y == 0) return 0;
        return @floatToInt(u32, self.shaft_height / self.cab.y);
    }

    pub fn hallCall(self: *Self, floor: u32) void {
        self.hall_calls.set(floor);
    }

    pub fn cabCall(self: *Self, floor: u32) void {
        self.cab_calls.set(floor);
        //self.hall_calls.set(floor);
    }

    pub fn update(self: *Self, dt: f32) void {
        const abs = std.math.fabs;
        //const dest = @intToFloat(f32, self.current_dest orelse 0);

        const dest: f32 = blk: {
            const hallorcab = ((self.cab_calls.count() > 5) or self.hall_calls.count() == 0);
            const callset = if (hallorcab) &self.cab_calls else &self.hall_calls;

            switch (self.state) {
                .parked => {
                    self.parked_time += dt;

                    if (self.parked_time > self.park_timeout and callset.count() > 0) {
                        //self.state = .accel;
                    } else {
                        break :blk self.cab.y;
                    }
                },
                .moving => {},
            }

            //TODO replace ay with brake
            //This determines the maximum distance from the cab position we can brake to zero to.
            const min_dist = abs(pow(f32, self.cab.vy, 2)) / (2 * self.cab.ay);
            switch (self.direction) {
                .none, .down => { //Going towards positive
                    var i = if (self.cab.vy >= 0) @floatToInt(usize, @round(self.cab.y + min_dist)) else @floatToInt(usize, self.cab.y - min_dist);
                    while (i < callset.capacity()) : (i += 1) {
                        if (callset.isSet(i))
                            break :blk @intToFloat(f32, i);
                    }
                },
                .up => { //Going towards negative
                    var i = if (self.cab.vy <= 0) @floatToInt(usize, self.cab.y - min_dist) else @floatToInt(usize, @round(self.cab.y + min_dist));
                    while (i > 0) : (i -= 1) {
                        if (callset.isSet(i))
                            break :blk @intToFloat(f32, i);
                    }
                },
            }

            break :blk 0;
        };

        const af: f32 = if (dest > self.cab.y) 1 else -1;
        const accel = self.cab.ay * af;
        const brake = -accel;

        if (self.cab.y != dest) {
            if (true) { //TODO deal with dest being away from direction of movement
                const D = -2 * brake;
                const a = accel;
                const v0 = self.cab.vy;
                const x0 = self.cab.y;

                if (quadForm(
                    (std.math.pow(f32, a, 2) / D) + (a / 2),
                    ((v0 * a) / -brake) + v0,
                    (std.math.pow(f32, v0, 2) / D) - dest + x0,
                )) |qf| {
                    _ = qf;
                }
            }
        }

        //.accel => {
        //    const new_y = self.cab.y + intVel(accel, dt, self.cab.vy);
        //    const new_v = self.cab.vy + accel * dt;

        //    if (std.math.pow(f32, new_v, 2) / abs(-2 * brake) > abs(dest - new_y)) {
        //        self.state = .brake;

        //        const D = -2 * brake;
        //        const a = accel;
        //        const v0 = self.cab.vy;
        //        const x0 = self.cab.y;

        //        const qf = quadForm(
        //            (std.math.pow(f32, a, 2) / D) + (a / 2),
        //            ((v0 * a) / -brake) + v0,
        //            (std.math.pow(f32, v0, 2) / D) - dest + x0,
        //        ) orelse unreachable;

        //        const max_dt = if (af == 1) qf[0] else qf[1];
        //        self.cab.y += intVel(accel, max_dt, self.cab.vy);
        //        self.cab.vy += accel * max_dt;
        //        self.update(dt - max_dt);
        //    } else {
        //        if (abs(self.cab.vy) < self.top_speed) {
        //            self.cab.y += intVel(accel, dt, self.cab.vy);
        //            self.cab.vy += accel * dt;
        //        } else {
        //            self.cab.y += self.cab.vy * dt;
        //        }
        //    }
        //},
        //.brake => {
        //    const new_v = self.cab.vy + brake * dt;

        //    if (abs(self.cab.vy) - abs(new_v) < 0) {
        //        self.state = .parked;
        //        //self.current_dest = null;
        //        const max_dt = self.cab.vy / self.cab.ay;
        //        self.cab.vy -= self.cab.ay * max_dt;
        //        self.cab.y += intVel(self.cab.ay, max_dt, self.cab.vy);

        //        const tolerance: f32 = 1.0 / 100.0;
        //        std.debug.print("{d} {d}\n", .{ self.cab.y, dest });
        //        if (self.cab.y + tolerance > dest) {
        //            self.cab_calls.unset(@floatToInt(u32, self.cab.y));
        //            self.hall_calls.unset(@floatToInt(u32, self.cab.y));
        //        }
        //        //self.cab.y = dest;
        //    } else {
        //        self.cab.vy += brake * dt;
        //        self.cab.y += intVel(-brake, dt, self.cab.vy);
        //    }
        //},
    }

    pub fn drawDebug(self: *Self, ctx: *graph.GraphicsContext, x: f32, y: f32, w: f32, h: f32) !void {
        const adj_y = (h / @intToFloat(f32, self.floor_count) * self.cab.y);
        const y_max = h;
        const interval = y_max / @intToFloat(f32, self.floor_count);
        {
            var i: u32 = 0;
            while (i < self.floor_count) : (i += 1) {
                ctx.drawRect(
                    .{ .x = x, .y = y + @intToFloat(f32, i) * interval, .w = w, .h = interval },
                    if (i % 2 == 0) intToColor(0xffffff88) else graph.WHITE,
                );
            }
        }

        ctx.drawRect(.{ .x = x + w / 4 - 2, .y = y, .w = 4, .h = h - adj_y }, intToColor(0x000000ff));
        ctx.drawRect(.{ .x = x + w / 4 - 10, .y = y + h - adj_y, .w = 20, .h = 40 }, intToColor(0x000000ff));
        ctx.drawRect(
            .{ .x = x, .y = y + adj_y, .w = w, .h = interval },
            //if (self.state == .brake) intToColor(0xff0000ff) else graph.GREEN,
            graph.GREEN,
        );

        {
            var it = self.hall_calls.iterator(.{});
            while (it.next()) |hc| {
                ctx.drawRect(.{ .x = x - 50, .y = y + @intToFloat(f32, hc) * interval, .w = 50, .h = interval / 2 }, intToColor(0xff00ffff));
            }

            var cit = self.cab_calls.iterator(.{});
            while (cit.next()) |hc| {
                ctx.drawRect(.{ .x = x - 100, .y = y + @intToFloat(f32, hc) * interval, .w = 50, .h = interval / 2 }, intToColor(0xff0080ff));
            }
        }
        // for (self.hall_calls.items) |call| {
        //     ctx.drawRect(.{ .x = x - 50, .y = y + @intToFloat(f32, call) * interval, .w = 50, .h = interval / 2 }, intToColor(0xff00ffff));
        // }
        //if (self.current_dest) |dest|
        //    ctx.drawRect(.{ .x = x - 50, .y = y + @intToFloat(f32, dest) * interval, .w = 50, .h = interval / 2 }, intToColor(0x00ffffff));

        ctx.drawRect(.{ .x = x + w / 2 - 2, .y = y, .w = 4, .h = adj_y }, intToColor(0x000000ff));

        {
            //const dest = @intToFloat(f32, self.current_dest orelse 0);
            //const af: f32 = if (dest > self.cab.y) 1 else -1;
            //const accel = self.cab.ay * af;
            //const brake = -accel;

            //const min_dest = pow(f32, self.cab.vy, 2) / (-2 * brake);
            //ctx.drawRect(.{ .x = x - 20, .y = y + adj_y, .w = 20, .h = min_dest * interval }, intToColor(0xff00ffff));
        }
    }
};

pub const Floor = struct {
    elevator_pos: f32 = 0,
    width: f32 = 400,
};

pub const TestEnum = enum {
    val1,
    two,
    three,
};

pub const Agent = struct {
    const Self = @This();

    floor_index: u32,
    x: f32,
    state: State = .idle,

    dest_floor: u32,
    dest_x: f32,

    temp_dest: ?f32 = null,

    pub const State = enum { idle, walking, elevate, elevate_wait };

    pub fn update(self: *Self, dt: f32, elevator: *Elevator) void {
        switch (self.state) {
            .idle => {
                if (self.x != self.dest_x or self.dest_floor != self.floor_index) {
                    self.state = .walking;
                }
            },
            .walking => {
                if (self.temp_dest) |ts| {
                    //TODO detect once arrived and decide next state (elevate or idle)
                    const sign: f32 = if (ts > self.x) 1 else -1;

                    const v = 80;

                    const dest_dt = (ts - self.x) / (sign * v);
                    if (dest_dt < dt) {
                        self.x += (sign * v * dest_dt);
                        self.temp_dest = null;
                    } else {
                        self.x += (sign * v * dt);
                    }
                } else {
                    if (self.dest_floor != self.floor_index) {
                        if (self.x != 0) {
                            self.temp_dest = 0; //For now we have only one elevator at x = 0
                        } else {
                            self.state = .elevate_wait;
                            switch (elevator.state) {
                                .parked => {
                                    if (@floatToInt(u32, elevator.cab.y) != self.floor_index) {
                                        elevator.hallCall(self.floor_index);
                                    } else {
                                        elevator.cabCall(self.dest_floor);
                                        elevator.cab.count += 1;
                                        self.state = .elevate;
                                        self.update(dt, elevator);
                                    }
                                },
                                else => {
                                    elevator.hallCall(self.floor_index);
                                },
                            }
                        }
                    } else if (self.x != self.dest_x) {
                        self.temp_dest = self.dest_x;
                    } else {
                        self.state = .idle;
                    }
                    //either find a temp_dest and call update again
                    //or if we have arrived, state = .idle
                }
            },
            .elevate_wait => {
                if (elevator.state == .parked and @floatToInt(u32, elevator.cab.y) == self.floor_index) {
                    elevator.cabCall(self.dest_floor);
                    self.state = .elevate;
                    elevator.cab.count += 1;
                    self.update(dt, elevator);
                }
            },
            .elevate => {
                if (elevator.state == .parked and @floatToInt(u32, elevator.cab.y) == self.dest_floor) {
                    self.floor_index = self.dest_floor;
                    elevator.cab.count -= 1;
                    self.state = .idle;
                }
            },
        }

        //Algorithm
        //switch(state)
        //idle ->
        //  if x!= dest_x or floor != dest_floor
        //  walk
    }

    pub fn drawDebug(self: *Self, ctx: *graph.GraphicsContext, cab_y: f32, x: f32, y: f32, floor_h: f32, col: Color) !void {
        const w = 10;
        const y_c: f32 = if (self.state == .elevate) (cab_y * floor_h) + floor_h - w else (@intToFloat(f32, self.floor_index + 1) * floor_h) - w;
        ctx.drawRect(.{ .x = self.x + x, .y = y_c + y, .w = w, .h = w }, col);
    }
};

const TextEditorBindings: graph.BindList = &.{
    .{ "down", "c" },
    .{ "tittis", "a" },
};
const EditorBindingEnum = graph.GenerateBindingEnum(TextEditorBindings);

const MainBindingEnum = graph.GenerateBindingEnum(MainBindings);
const MainBindings: graph.BindList = &.{
    .{ "exit", "A" },
    .{ "print", "P" },

    .{ "incTile", "q" },
    .{ "decTile", ";" },
    .{ "player_right", "d" },
    .{ "player_down", "s" },
    .{ "player_left", "a" },
    .{ "player_up", "w" },
    .{ "place_tile", "p" },
    .{ "erase_tile", "u" },
    .{ "editor_cy_inc", "c" },
};

const GameBindingEnum = graph.GenerateBindingEnum(GameBindings);
const GameBindings: graph.BindList = &.{
    .{ "right", "d" },
    .{ "up", "w" },
    .{ "left", "a" },
    .{ "down", "s" },
    .{ "jump", "space" },
};

const TileEditorBindingEnum = graph.GenerateBindingEnum(TileEditorBindings);
const TileEditorBindings: graph.BindList = &.{
    .{ "place_tile", "r" },
    .{ "editor_cy_inc", "c" },

    .{ "erase_tile", "e" },
    .{ "select_tile", "w" },
    .{ "zoom_map", "z" },
    .{ "fuck", "cunt" },
    .{ "alert", "i" },
};

const unique_colors = [_]Color{
    intToColor(0x00000088),
    intToColor(0x00FF0088),
    intToColor(0x0000FF88),
    intToColor(0xFF000088),
    intToColor(0x01FFFE88),
    intToColor(0xFFA6FE88),
    intToColor(0xFFDB6688),
    intToColor(0x00640188),
    intToColor(0x01006788),
    intToColor(0x95003A88),
    intToColor(0x007DB588),
    intToColor(0xFF00F688),
    intToColor(0xFFEEE888),
    intToColor(0x774D0088),
    intToColor(0x90FB9288),
    intToColor(0x0076FF88),
    intToColor(0xD5FF0088),
    intToColor(0xFF937E88),
    intToColor(0x6A826C88),
    intToColor(0xFF029D88),
    intToColor(0xFE890088),
    intToColor(0x7A478288),
    intToColor(0x7E2DD288),
    intToColor(0x85A90088),
    intToColor(0xFF005688),
    intToColor(0xA4240088),
    intToColor(0x00AE7E88),
    intToColor(0x683D3B88),
    intToColor(0xBDC6FF88),
    intToColor(0x26340088),
    intToColor(0xBDD39388),
    intToColor(0x00B91788),
    intToColor(0x9E008E88),
    intToColor(0x00154488),
    intToColor(0xC28C9F88),
    intToColor(0xFF74A388),
    intToColor(0x01D0FF88),
    intToColor(0x00475488),
    intToColor(0xE56FFE88),
    intToColor(0x78823188),
    intToColor(0x0E4CA188),
    intToColor(0x91D0CB88),
    intToColor(0xBE997088),
    intToColor(0x968AE888),
    intToColor(0xBB880088),
    intToColor(0x43002C88),
    intToColor(0xDEFF7488),
    intToColor(0x00FFC688),
    intToColor(0xFFE50288),
    intToColor(0x620E0088),
    intToColor(0x008F9C88),
    intToColor(0x98FF5288),
    intToColor(0x7544B188),
    intToColor(0xB500FF88),
    intToColor(0x00FF7888),
    intToColor(0xFF6E4188),
    intToColor(0x005F3988),
    intToColor(0x6B688288),
    intToColor(0x5FAD4E88),
    intToColor(0xA7574088),
    intToColor(0xA5FFD288),
    intToColor(0xFFB16788),
    intToColor(0x009BFF88),
    intToColor(0xE85EBE88),
};

pub fn deSerializeJson(file_name: []const u8, comptime schema: type, alloc: *const std.mem.Allocator) !schema {
    @setEvalBranchQuota(10000);
    const cwd = std.fs.cwd();
    const saved = cwd.openFile(file_name, .{}) catch null;
    if (saved) |file| {
        var buf: []const u8 = try file.readToEndAlloc(alloc.*, 1024 * 1024);
        defer alloc.free(buf);

        var token_stream = std.json.TokenStream.init(buf);
        var ret = try std.json.parse(schema, &token_stream, .{ .allocator = alloc.* });
        defer std.json.parseFree(schema, ret, .{ .allocator = alloc.* });
        return ret;
    }
    const ret: schema = undefined;
    return ret;
}

pub fn serialJson(file_name: []const u8, data: anytype) void {
    const cwd = std.fs.cwd();
    const file = cwd.createFile(file_name, .{}) catch unreachable;
    std.json.stringify(data, .{}, file.writer()) catch unreachable;
    file.writer().writeByte('\n') catch unreachable;
    file.close();
}

const Goomba = struct {
    const Self = @This();

    vx: f32 = 0,
    vy: f32 = 0,
    dx: f32 = 0,
    dy: f32 = 0,

    fn update(self: *Self) void {
        _ = self;
    }
};

const Mario = struct {
    const Self = @This();
    const CF = @as(f32, 0x10000);

    const min_walk_v = @as(f32, 0x130) / CF;
    const walk_a = @as(f32, 0x98) / CF;
    const run_a = @as(f32, 0xE4) / CF;
    const rel_a = @as(f32, 0xD0) / CF;
    const skid_a = @as(f32, 0x1A0) / CF;
    const max_walk_v = @as(f32, 0x1900) / CF;
    const max_walk_underwater_v = @as(f32, 0x1100) / CF;
    const max_walk_level_enter_V = @as(f32, 0xD00) / CF;
    const max_run_v = @as(f32, 0x2900) / CF;
    const skid_turnaround = @as(f32, 0x900) / CF;

    const Buttons = struct {
        right: bool,
        left: bool,
        b: bool,
        a: bool,
    };

    vx: f32 = 0,
    vy: f32 = 0,

    dx: f32 = 0,
    dy: f32 = 0,

    b_counter: u32 = 0,
    init_jump_v: f32 = 0,

    fn getGravity(self: Self, holding_a: bool) f32 {
        const v = std.math.fabs(self.vx);
        if (v < @as(f32, 0x1000) / CF) {
            return if (holding_a) @as(f32, 0x200) / CF else @as(f32, 0x700) / CF;
        } else if (v < @as(f32, 0x24FF) / CF) {
            return if (holding_a) @as(f32, 0x1E0) / CF else @as(f32, 0x600) / CF;
        } else {
            return if (holding_a) @as(f32, 0x280) / CF else @as(f32, 0x900) / CF;
        }
    }

    fn getJumpV(self: Self) f32 {
        const v = std.math.fabs(self.vx);
        if (v < @as(f32, 0x1000) / CF) {
            return @as(f32, 0x4000) / CF;
        } else if (v < @as(f32, 0x24FF) / CF) {
            return @as(f32, 0x4000) / CF;
        } else {
            return @as(f32, 0x5000) / CF;
        }
    }

    pub fn update(self: *Self, can_jump: bool, buttons: Buttons) void {
        const aa = if (buttons.b) run_a else walk_a;
        const maxv = if (buttons.b or self.b_counter < 10) max_run_v else max_walk_v;
        self.b_counter += 1;
        if (buttons.b)
            self.b_counter = 0;

        if (can_jump) {
            const sf: f32 = if (self.vx > 0) 1 else -1;
            if (buttons.left != buttons.right) {
                const df: f32 = if (buttons.left) -1 else 1;

                if (self.vx == 0) {
                    self.vx = min_walk_v * df;
                } else {
                    if (df != sf) {
                        self.vx = if (std.math.fabs(self.vx) <= skid_turnaround) -self.vx else self.vx + skid_a * df;
                    } else {
                        self.vx += aa * sf;
                        if (sf * self.vx > maxv)
                            self.vx = sf * maxv;
                    }
                }
            } else if (buttons.left == false and buttons.right == false and self.vx != 0) {
                self.vx = if (self.vx * sf < 0 or @trunc(self.vx * @as(f32, 0x100)) == 0) 0 else self.vx - sf * rel_a;
            }
        } else {
            const sf: f32 = if (self.vx > 0) 1 else -1;
            const maxfv = if (std.math.fabs(self.init_jump_v) > max_walk_v) max_run_v else max_walk_v;
            if (buttons.left != buttons.right) {
                const df: f32 = if (buttons.left) -1 else 1;
                if (df != sf) {
                    const secf: f32 = if (std.math.fabs(self.init_jump_v) < @as(f32, 0x1000) / CF) 0x98 else 0xD0;
                    self.vx += df * @as(f32, (if (std.math.fabs(self.vx) < max_walk_v)
                        secf
                    else
                        0xE4)) / CF;
                } else {
                    self.vx += sf * @as(f32, (if (sf * self.vx < max_walk_v) 0x98 else 0xE4)) / CF;
                    if (std.math.fabs(self.vx) > maxfv)
                        self.vx = sf * maxfv;
                }
            }
        }

        if (can_jump and buttons.a) {
            self.init_jump_v = self.vx;
            self.vy = 0;
            self.vy = -self.getJumpV();
        } else {
            const grav = self.getGravity(buttons.a);
            self.vy += grav;
            if (can_jump)
                self.vy = 0;
        }
        const sign: f32 = if (self.vy > 0) 1 else -1;
        if (sign * self.vy > @as(f32, 0x4800) / CF)
            self.vy = sign * @as(f32, 0x4800) / CF;

        self.dx += self.vx;
        self.dy += self.vy;
    }
};

pub const Bitmap = struct {
    data: std.ArrayList(u8),
    w: u32,
    h: u32,
};

const CollisionData = struct {
    const EntityType = enum {
        static,
        trigger,
        head_banger,
    };

    ent_type: EntityType = .static,
};

pub const EntityStorage = struct {
    pub const EntityTypes = enum {
        static_tile,
        enemy,
        trigger,
        mystery_block,
        banger_tile,
    };
};

pub extern fn tree_sitter_zig() *c.TSLanguage;

const src = @embedFile("main.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = &gpa.allocator();

    //{
    //    var parser = c.ts_parser_new();
    //    defer c.ts_parser_delete(parser);

    //    _ = c.ts_parser_set_language(parser, tree_sitter_zig());
    //    const test_json_src = src;

    //    var tree = c.ts_parser_parse_string(
    //        parser,
    //        null,
    //        test_json_src,
    //        test_json_src.len,
    //    );
    //    const root = c.ts_tree_root_node(tree);

    //    const str = c.ts_node_string(root);
    //}

    var main_bindings = try graph.BindingMap(MainBindingEnum).init(MainBindings, alloc);
    defer main_bindings.deinit();

    var editor_bindings = try graph.BindingMap(EditorBindingEnum).init(TextEditorBindings, alloc);
    defer editor_bindings.deinit();

    var tile_editor_bindings = try graph.BindingMap(TileEditorBindingEnum).init(TileEditorBindings, alloc);
    defer tile_editor_bindings.deinit();

    var game_bindings = try graph.BindingMap(GameBindingEnum).init(GameBindings, alloc);
    defer game_bindings.deinit();

    var win = try graph.SDL.Window.createWindow("My window");
    defer win.destroyWindow();

    var ctx = try graph.GraphicsContext.init(alloc);
    defer ctx.deinit();

    const SaveData = struct {
        fps_posx: f32 = 0,
        fps_posy: f32 = 40,
        elevx: f32 = 0,
        elevy: f32 = 0,
        build_x: f32 = 0,
        build_y: f32 = 0,
        build_floor_h: f32 = 0,
        test_tile_posx: f32 = 1000,
        test_tile_posy: f32 = 1000,
        show_tilesets: bool = false,
        draw_map: bool = true,
    };
    var sd: SaveData = .{};
    var tile_index: usize = 0;
    var tileset_index: usize = 0;

    const mario_img_path = "mario_assets/img/";
    const ref_img = try graph.loadPngFromPath(mario_img_path ++ "level1.png", alloc);
    var show_ref_img = false;

    const anim_text = try graph.loadPngFromPath(mario_img_path ++ "mario-anim.png", alloc);
    var anim: SubTileset = .{
        .start = .{ .x = 20, .y = 8 },
        .tw = 16,
        .th = 16,
        .pad = .{ .x = 2, .y = 2 },
        .num = .{ .x = 3, .y = 1 },
        .count = 3,
    };
    var anim_frame: usize = 0;

    var last_placed_index: u32 = 0;

    var bitmap = Bitmap{ .data = std.ArrayList(u8).init(alloc.*), .w = 256, .h = 256 };
    try bitmap.data.resize(bitmap.w * bitmap.h * 4);
    for (bitmap.data.items) |*pixel| {
        pixel.* = 0xff;
    }
    defer bitmap.data.deinit();

    var shroom: ?u32 = null;

    //const bitmap_texture = graph.Texture{ .id = graph.GL.colorTexture(bitmap.w, bitmap.h, bitmap.data.items), .w = bitmap.w, .h = bitmap.h };

    var anim_timer = try std.time.Timer.start();

    //const my_texture = try graph.loadPngFromPath("mario-tileset.png", alloc);
    const PixelEditor = struct {
        xoff: f32 = 0,
        yoff: f32 = 0,
        zf: f32 = 1.0,

        start_pointx: f32 = 0,
        start_pointy: f32 = 0,
    };
    var pe: PixelEditor = .{};

    var tile_map_zf: f32 = (224 / 16.0) / 2160.0;
    var tile_map_dx: f32 = 0;
    var tile_map_dy: f32 = 0;

    const letter_box_w: f32 = (tile_map_zf * 3840 - 16) / 2;

    var mouse_dx: f32 = 0;

    var mig_level: MarioTileMap = undefined;
    try mig_level.initFromJsonFile("mario_assets/migration.json", alloc);

    defer mig_level.deinit();
    //defer {
    //    var ret = mig_level.deinitToOwnedJson();
    //    serialJson("migration.json", ret);
    //    std.json.parseFree(MarioTileMap.Types.json, ret, .{ .allocator = alloc.* });
    //}

    var mario: Mario = Mario{};

    var sts: SubTileset = .{
        .start = .{ .x = 0, .y = 16 },
        .tw = 16,
        .th = 16,
        .pad = .{ .x = 1, .y = 1 },
        .num = .{ .x = 8, .y = 4 },
        .count = 8 * 4 - 1,
    };

    const pipe_ts = SubTileset{
        .start = .{ .x = 0, .y = 196 },
        .tw = 16,
        .th = 16,
        .pad = .{ .x = 1, .y = 1 },
        .num = .{ .x = 9, .y = 4 },
        .count = 9 * 4,
    };

    const tokens_ts = SubTileset{
        .start = .{ .x = 298, .y = 78 },
        .tw = 16,
        .th = 16,
        .pad = .{ .x = 1, .y = 1 },
        .num = .{ .x = 4, .y = 5 },
        .count = 4 * 5,
    };

    const clouds_ts = SubTileset{
        .start = .{ .x = 298, .y = 16 },
        .tw = 16,
        .th = 16,
        .pad = .{ .x = 1, .y = 1 },
        .num = .{ .x = 5, .y = 2 },
        .count = 5 * 2,
    };

    const shrooms_ts = SubTileset{
        .start = .{ .x = 0, .y = 8 },
        .tw = 16,
        .th = 16,
        .pad = .{ .x = 1, .y = 2 },
        .num = .{ .x = 1, .y = 2 },
        .count = 2,
    };
    const flowers = SubTileset{
        .start = .{ .x = 32, .y = 8 },
        .tw = 16,
        .th = 16,
        .pad = .{ .x = 2, .y = 2 },
        .num = .{ .x = 4, .y = 3 },
        .count = 12,
    };
    const stars = SubTileset{
        .start = .{ .x = 106, .y = 8 },
        .tw = 16,
        .th = 16,
        .pad = .{ .x = 2, .y = 2 },
        .num = .{ .x = 4, .y = 3 },
        .count = 12,
    };

    const mario_stand = SubTileset{
        .start = .{ .x = 0, .y = 8 },
        .tw = 16,
        .th = 16,
        .pad = .{ .x = 0, .y = 0 },
        .num = .{ .x = 1, .y = 1 },
        .count = 1,
    };
    const mario_slide = SubTileset{ .start = .{ .x = 76, .y = 8 }, .tw = 16, .th = 16, .pad = .{ .x = 0, .y = 0 }, .num = .{ .x = 1, .y = 1 }, .count = 1 };
    const mario_leap = SubTileset{ .start = .{ .x = 96, .y = 8 }, .tw = 16, .th = 16, .pad = .{ .x = 0, .y = 0 }, .num = .{ .x = 1, .y = 1 }, .count = 1 };
    const mario_fall = SubTileset{ .start = .{ .x = 116, .y = 8 }, .tw = 16, .th = 16, .pad = .{ .x = 0, .y = 0 }, .num = .{ .x = 1, .y = 1 }, .count = 1 };
    const mario_flag = SubTileset{ .start = .{ .x = 136, .y = 8 }, .tw = 16, .th = 16, .pad = .{ .x = 2, .y = 0 }, .num = .{ .x = 2, .y = 1 }, .count = 2 };
    const mario_swim = SubTileset{ .start = .{ .x = 174, .y = 8 }, .tw = 16, .th = 16, .pad = .{ .x = 2, .y = 0 }, .num = .{ .x = 5, .y = 1 }, .count = 5 };

    const goomba = SubTileset{ .start = .{ .x = 0, .y = 16 }, .tw = 16, .th = 16, .pad = .{ .x = 2, .y = 2 }, .num = .{ .x = 3, .y = 2 }, .count = 6 };
    const atlas = try graph.Atlas.init(&.{
        .{ .filename = mario_img_path ++ "mario-tileset.png", .tilesets = &.{ sts, pipe_ts, tokens_ts, clouds_ts } },
        .{ .filename = mario_img_path ++ "mario-anim.png", .tilesets = &.{ mario_stand, anim, mario_slide, mario_leap, mario_fall, mario_flag, mario_swim } },
        .{ .filename = mario_img_path ++ "mario-obj.png", .tilesets = &.{ shrooms_ts, flowers, stars } },
        .{ .filename = mario_img_path ++ "mario-enemy.png", .tilesets = &.{goomba} },
    }, alloc, 256);
    defer atlas.deinit();

    sd = try deSerializeJson("debug/save.json", SaveData, alloc);

    defer serialJson("debug/save.json", sd);

    var dpix: u32 = 163;
    const init_size = 18;
    var font = try graph.Font.init("fonts/sfmono.otf", alloc.*, init_size, dpix, &(graph.CharMaps.AsciiBasic ++ graph.CharMaps.Apple), null);
    defer font.deinit();

    var text_y: f32 = 400;

    var sdat = gui.SaveData{ .x = 200, .y = 0 };
    sdat = try deSerializeJson("debug/gui.json", gui.SaveData, alloc);
    //var gctx: gui.Window = .{ .font = &font, .font_size = 18, .x_init = sdat.x, .y_init = sdat.y, .width = 600, .title = @as([]const u8, "Panel") };
    var gctx = gui.Window.init(&font, gui.Window.Style{ .title_size = 10 }, sdat.x, sdat.y, 600, "Panel");
    defer serialJson("debug/gui.json", gui.SaveData{ .x = gctx.x_init, .y = gctx.y_init });

    var text_editor = try gui.TextEditor.init(alloc, src);
    defer text_editor.deinit();

    //_ = c.SDL_GetDisplayDPI(c.SDL_GetWindowDisplayIndex(win.win), &dpix, null, null);
    //std.debug.print("Dpi {d}\n", .{dpix});

    var showCrap = false;
    var mario_crap = true;

    var gray_out_inactive_layers = true;

    const fixed_font_text = try graph.loadPngFromPath(mario_img_path ++ "mario-text.png", alloc);
    var fixed_font = graph.FixedBitmapFont.init(fixed_font_text, .{
        .start = .{ .x = 264, .y = 8 },
        .tw = 8,
        .th = 8,
        .pad = .{ .x = 1, .y = 1 },
        .num = .{ .x = 16, .y = 3 },
        .count = 16 * 3 - 7,
    }, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-*!.");

    var cmds = gui.CmdBuf.init(alloc.*);
    defer cmds.deinit();
    var cmds_str_buf: [1000]u8 = undefined;

    var elevator = Elevator.init(alloc);
    defer elevator.deinit();
    //elevator.current_dest = 10;

    var elevator1 = Elevator.init(alloc);
    defer elevator1.deinit();
    //elevator.current_dest = 10;

    var building: [10]Floor = undefined;
    elevator.floor_count = 10;
    for (building) |*floor| {
        floor.elevator_pos = 0;
        floor.width = 2000;
    }

    var agents: [1]Agent = undefined;
    {
        var prng = std.rand.DefaultPrng.init(0);
        const r = prng.random();
        for (agents) |*ag| {
            ag.* = .{
                .floor_index = r.intRangeLessThanBiased(u32, 0, building.len - 1),
                .dest_floor = r.intRangeLessThanBiased(u32, 0, building.len - 1),
                .x = r.float(f32) * 2000 + 100,
                .dest_x = r.float(f32) * 2000 + 100,
            };
        }
    }

    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();
    _ = rand;

    var agent: Agent = .{ .floor_index = 0, .x = 300, .dest_floor = 8, .dest_x = 500 };
    var agent_2: Agent = .{ .floor_index = 5, .x = 100, .dest_floor = 2, .dest_x = 200 };

    var collision_ctx = aabb.CollisionContext().init(alloc);
    defer collision_ctx.deinit();
    //for (tile_map.items) |tile| {

    for (mig_level.data.collidable.dense.items) |cl| {
        const pos = (try mig_level.data.coord.get(cl.i)).item;
        try collision_ctx.insert(graph.Rec(pos.x, pos.y, 1, 1), cl.i);
        //_ = try collision_ctx.add(graph.Rec(@intToFloat(f32, pos.x), @intToFloat(f32, pos.y), 1, 1));
    }

    const player_col = try collision_ctx.add(.{ .x = 3.51, .y = 2, .w = 0.8, .h = 0.8 });

    var vy: f32 = 0;
    var grounded = false;
    //var dvy: f32 = 0;
    var show_elevator_crap = false;
    var collision_crap = true;
    var all_the_crap = true;

    while (!win.should_exit) {
        try ctx.beginDraw(intToColor(0x2f2f2fff));
        win.pumpEvents(); //Important that this is called after beginDraw for input lag reasons
        if (show_elevator_crap) {
            elevator.update(16.0 / 1000.0);
            //try elevator.drawDebug(&ctx, sd.build_x, sd.build_y, 100, (sd.build_floor_h * 10));

            agent.update(16.0 / 1000.0, &elevator);
            agent_2.update(16.0 / 1000.0, &elevator);

            for (agents) |*ag| {
                ag.update(16.0 / 1000.0, &elevator);
            }

            elevator1.update(16.0 / 1000.0);
            //try elevator1.drawDebug(&ctx, 200, 0, 50, 200);

            {
                try cmds.resize(0);

                gctx.begin(&cmds, cmds_str_buf[0..], win.mouse.pos, win.mouse.delta, win.mouse.left, win.mouse);

                gctx.floatSlide("Top speed", &elevator.top_speed, 0, 20);
                gctx.floatSlide("Accel", &elevator.cab.ay, 0, 50);
                gctx.floatSlide("FPS x", &sd.fps_posx, 0, @intToFloat(f32, win.screen_width));
                gctx.floatSlide("FPS y", &sd.fps_posy, 0, @intToFloat(f32, win.screen_height));
                gctx.floatSlide("elev x", &sd.elevx, 0, @intToFloat(f32, win.screen_width));
                gctx.floatSlide("elev y", &sd.elevy, 0, @intToFloat(f32, win.screen_height));
                gctx.floatSlide("build x", &sd.build_x, 0, @intToFloat(f32, win.screen_height));
                gctx.floatSlide("build y", &sd.build_y, 0, @intToFloat(f32, win.screen_width));
                gctx.floatSlide("build h", &sd.build_floor_h, 0, @intToFloat(f32, win.screen_height));

                {
                    var i: u32 = 0;
                    while (i < elevator.floor_count) : (i += 1) {
                        if (gctx.button()) {
                            elevator.hall_calls.set(i);
                            //var exists = false;
                            //for (elevator.hall_calls.items) |call| {
                            //    if (call == i) {
                            //        exists = true;
                            //        break;
                            //    }
                            //}
                            //if (!exists)
                            //    try elevator.hall_calls.append(i);
                            //if (elevator.current_dest == null)
                            //    elevator.current_dest = i;
                        }
                    }
                }
                gctx.label("cunt");
                gctx.end();

                //gui.drawCommands(cmds.items, &ctx, &font);
            }
            {
                switch (agent.state) {
                    .idle => ctx.drawText(100, 100, "idle", &font, 20, intToColor(0xffffffff)),
                    .elevate => ctx.drawText(100, 100, "elevate", &font, 20, intToColor(0xffffffff)),
                    .elevate_wait => ctx.drawText(100, 100, "elevate_wait", &font, 20, intToColor(0xffffffff)),
                    .walking => ctx.drawText(100, 100, "walking", &font, 20, intToColor(0xffffffff)),
                }

                var buf: [100]u8 = undefined;
                var bufStream = std.io.FixedBufferStream([]u8){ .buffer = &buf, .pos = 0 };
                try bufStream.writer().print("Count: {d}\nState: {any}", .{ elevator.cab.count, elevator.state });
                ctx.drawText(100, 150, buf[0..bufStream.pos], &font, 20, intToColor(0xffffffff));
            }

            {
                for (building) |floor, i| {
                    ctx.drawRect(.{
                        .x = sd.build_x,
                        .y = sd.build_y + (@intToFloat(f32, i) * sd.build_floor_h),
                        .w = floor.width,
                        .h = 10,
                    }, intToColor(0x111111ff));
                }
            }

            {
                var count: u32 = 0;
                for (agents) |*ag, i| {
                    const w = 10;
                    const max_w: u32 = 100 / w;
                    if (ag.state == .elevate) {
                        count += 1;
                        try ag.drawDebug(
                            &ctx,
                            elevator.cab.y,
                            sd.build_x + (w * @intToFloat(f32, count % max_w)),
                            sd.build_y - (w * @intToFloat(f32, @divFloor(count, max_w))),
                            sd.build_floor_h,
                            unique_colors[i % unique_colors.len],
                        );
                    } else {
                        try ag.drawDebug(&ctx, elevator.cab.y, sd.build_x, sd.build_y, sd.build_floor_h, unique_colors[i % unique_colors.len]);
                    }
                }
            }

            try agent.drawDebug(&ctx, elevator.cab.y, sd.build_x, sd.build_y, sd.build_floor_h, intToColor(0xff00ffff));
            try agent_2.drawDebug(&ctx, elevator.cab.y, sd.build_x, sd.build_y, sd.build_floor_h, intToColor(0xff00ffff));
            //{
            //    const y: f32 = if (agent.state == .elevate) (elevator.cab.y * sd.build_floor_h) + sd.build_y else @intToFloat(f32, agent.floor_index + 1) * sd.build_floor_h;
            //    ctx.drawRect(.{ .x = agent.x + sd.build_x, .y = y, .w = 50, .h = 50 }, intToColor(0xffff22ff));
            //}

        }

        ctx.drawRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 }, intToColor(0xffff00ff));

        {
            try cmds.resize(0);
            gctx.begin(&cmds, cmds_str_buf[0..], win.mouse.pos, win.mouse.delta, win.mouse.left, win.mouse);
            gctx.checkBox(&all_the_crap, "show all");
            if (all_the_crap) {
                gctx.checkBox(&show_elevator_crap, "show elevator crap");
                gctx.checkBox(&collision_crap, "collision crap");
                gctx.checkBox(&show_ref_img, "show ref img");
                gctx.checkBox(&grounded, "grounded");
                gctx.checkBox(&sd.draw_map, "show_map");

                gctx.floatSlide("pe Zoom", &pe.zf, -10, 10);
                gctx.floatSlide("xoff", &pe.xoff, -1000, 1000);
                gctx.floatSlide("yoff", &pe.yoff, -1000, 1000);
                gctx.floatSlide("zf", &tile_map_zf, -1000, 1000);
                //gctx.floatSlide("x", &collision_ctx.rects.items[0].?.rect.x, 0, 3840);
                //gctx.floatSlide("y", &collision_ctx.rects.items[0].?.rect.y, 0, 3840);
                gctx.floatSlide("text_y", &text_y, -30840, 3830);
                gctx.checkBox(&showCrap, "showCrap");
                gctx.checkBox(&gray_out_inactive_layers, "highlight current layer");
                if (gctx.button()) {
                    std.debug.print("Writing map\n", .{});
                    var ret = try mig_level.copyToOwnedJson();
                    serialJson("migration.json", ret);
                    std.json.parseFree(MarioTileMap.Types.json, ret, .{ .allocator = alloc.* });
                }
                {
                    const info = @typeInfo(MarioTileMap.Types.component_enum);
                    const entity_component_set = mig_level.entities.items[last_placed_index];
                    inline for (info.Enum.fields) |field, i| {
                        const init_value = entity_component_set.isSet(i);
                        var my_bool = init_value;
                        gctx.checkBox(&my_bool, field.name);

                        if (init_value == false and my_bool == true) {
                            try mig_level.attachComponent(last_placed_index, MarioTileMap.field_list[i].ftype, .{});
                        }
                    }
                }

                gctx.checkBox(&sd.show_tilesets, "Show tilesets");
                if (sd.show_tilesets) {
                    for (atlas.sets.items) |set, fti| {
                        const current_set = fti == tileset_index;

                        const this_item = gctx.item_index;
                        gctx.item_index += 1;

                        //const xoff = gctx.x + gctx.default_style.getLeft();
                        //const yoff = gctx.y + gctx.default_style.getTop();

                        const xoff = gctx.x;
                        const yoff = gctx.y;

                        const w = gctx.w;

                        const pw = w / 10;
                        const pad = 1;
                        const fac = pw + pad;
                        var i: i32 = 0;
                        while (i < set.count) : (i += 1) {
                            const rec = graph.Rect{ .x = xoff + fac * @intToFloat(f32, @mod(i, set.num.x)), .y = yoff + fac * @intToFloat(f32, @divFloor(i, set.num.x)), .w = pw, .h = pw };
                            gui.DrawCommand.drawTexRect(
                                &cmds,
                                rec,
                                set.getTexRec(@intCast(usize, i)),
                                atlas.texture,
                                itc(0xffffffff),
                            );
                            if (current_set and @intCast(usize, i) == tile_index) {
                                gui.DrawCommand.drawRect(&cmds, rec, 0, itc(0xff000022));
                            }
                        }

                        _ = this_item;
                        const bound_rect = graph.Rec(xoff, yoff, @intToFloat(f32, set.num.x) * fac, @intToFloat(f32, set.num.y) * fac);
                        if (gctx.m_down and gui.rectContainsPoint(bound_rect, gctx.m_old_x, gctx.m_old_y)) {
                            const col = @floatToInt(usize, @divFloor((gctx.m_old_x - bound_rect.x), fac));
                            const row = @floatToInt(usize, @divFloor((gctx.m_old_y - bound_rect.y), fac));
                            tile_index = (@intCast(usize, set.num.x) * row) + col;
                            tileset_index = fti;

                            //tile_index =
                        }
                        gctx.y = yoff + (@intToFloat(f32, set.num.y) * fac);
                    }
                }
            }
            var my_enum: TestEnum = .two;
            gctx.dropDownEnum(TestEnum, &my_enum);
            gctx.end();
        }
        const pl_rect = (try collision_ctx.get(player_col));
        const shit = -@trunc((-pl_rect.x + mouse_dx + 10) * 16) / 16;

        {
            for (win.keys.slice()) |key| {
                const tx = @floatToInt(i32, @divFloor(win.mouse.pos.x + shit / tile_map_zf, 1 / tile_map_zf));
                const ty = @floatToInt(i32, @divFloor(win.mouse.pos.y + 0.5 / tile_map_zf, 1 / tile_map_zf));
                switch (if (tile_editor_bindings.get(key.scancode)) |v| v else continue) {
                    .select_tile => {
                        if (win.mouse.wheel_delta > 0) {
                            if (tile_index + 1 == atlas.sets.items[tileset_index].count) {
                                tile_index = 0;
                                tileset_index = (tileset_index + 1) % atlas.sets.items.len;
                            } else {
                                tile_index = (tile_index + 1);
                            }
                        } else if (win.mouse.wheel_delta < 0) {
                            if (tile_index > 0) {
                                tile_index -= 1;
                            } else {
                                tileset_index = if (tileset_index > 0) tileset_index - 1 else atlas.sets.items.len - 1;
                                tile_index = atlas.sets.items[tileset_index].count - 1;
                            }
                        }
                    },
                    .place_tile => {
                        if (win.mouse.left) {
                            var occupied = false;
                            for (mig_level.data.coord.dense.items) |item| {
                                if (@floatToInt(i32, item.item.x) == tx and @floatToInt(i32, item.item.y) == ty) {
                                    occupied = true;
                                    break;
                                }
                            }
                            if (!occupied) {
                                const index = try mig_level.createEntity();

                                try mig_level.attachComponent(index, MarioMap.Coord, .{ .x = @intToFloat(f32, tx), .y = @intToFloat(f32, ty) });
                                try mig_level.attachComponent(index, MarioMap.TileSetInfo, .{ .ti = tile_index, .si = tileset_index });

                                std.debug.print("INDex of placed {d}\n", .{index});
                                last_placed_index = index;
                            }
                        }
                    },
                    .editor_cy_inc => {
                        text_editor.cy += 1;
                    },
                    .erase_tile => {
                        if (win.mouse.left) {
                            for (mig_level.data.coord.dense.items) |tile| {
                                if (@floatToInt(i32, tile.item.x) == tx and @floatToInt(i32, tile.item.y) == ty) {
                                    try mig_level.destroyEntity(tile.i);
                                    break;
                                }
                            }
                        }
                    },
                    .alert => {
                        std.debug.print("Alerting\n", .{});
                    },
                    .zoom_map => {
                        //tile_map_zf += win.mouse.wheel_delta / std.math.pow(f32, tile_map_zf, 2);
                        if (win.mouse.wheel_delta != 0 and tile_map_zf > std.math.f32_min) {
                            tile_map_zf += if (std.math.signbit(win.mouse.wheel_delta)) (0.1 * tile_map_zf) else -(0.1 * tile_map_zf);
                        }
                    },
                    else => {},
                }
            }
        }

        if (win.mouse.middle) {
            mouse_dx += win.mouse.delta.x / (1 / tile_map_zf);
            //tile_map_dx += win.mouse.delta.x / (1 / tile_map_zf);
            //tile_map_dy += win.mouse.delta.y / (1 / tile_map_zf);
        }

        try ctx.beginCameraDraw(win.screen_width, win.screen_height);

        if (mario_crap) {
            ctx.drawRect(graph.Rec(
                0,
                0,
                @intToFloat(f32, @divFloor(ref_img.w, 16)),
                @intToFloat(f32, @divFloor(ref_img.h, 16)),
            ), itc(0x5c94fcff));

            if (show_ref_img)
                try ctx.drawRectTex(graph.Rec(
                    @trunc(tile_map_dx),
                    @trunc(tile_map_dy),
                    @intToFloat(f32, @divFloor(ref_img.w, 16)),
                    @intToFloat(f32, @divFloor(ref_img.h, 16)),
                ), graph.Rec(0, 0, @intToFloat(f32, ref_img.w), @intToFloat(f32, ref_img.h)), itc(0xffffff4f), ref_img);

            if (sd.draw_map) {
                for (mig_level.data.coord.dense.items) |tile| {
                    const info = try mig_level.data.tile_set_info.get(tile.i);
                    try ctx.drawRectTex(
                        .{
                            .x = tile.item.x + @trunc(tile_map_dx),
                            .y = tile.item.y + @trunc(tile_map_dy),
                            .w = 1,
                            .h = 1,
                        },
                        atlas.getTexRec(info.item.si, info.item.ti),
                        //tile_sets[info.item.si].getTexRec(info.item.ti),
                        itc(0xffffffff),
                        atlas.texture,
                    );
                }
            }

            const sr = graph.Rec(
                @divFloor(win.mouse.pos.x + shit / tile_map_zf, 1 / tile_map_zf),
                @divFloor(win.mouse.pos.y + 0.5 / tile_map_zf, 1 / tile_map_zf),
                1,
                1,
            );
            try ctx.drawRectTex(
                sr,
                atlas.getTexRec(tileset_index, tile_index),
                //tile_sets[tileset_index].getTexRec(tile_index),
                itc(0xffffffff),
                atlas.texture,
            );

            if (collision_crap) {
                var can_jump = false;
                for (collision_ctx.rect_set.dense.items) |rec| {
                    const rr = rec.rect;
                    if (aabb.doLinesOverlap(rr.x, rr.x + rr.w, pl_rect.x, pl_rect.x + pl_rect.w)) {
                        if ((pl_rect.y + pl_rect.h < rr.y) and pl_rect.y + pl_rect.h + aabb.eps * 2.0 > rr.y) {
                            //ctx.drawRect(.{ .x = rr.x + @trunc(tile_map_dx), .y = rr.y + @trunc(tile_map_dy), .w = rr.w, .h = rr.h }, intToColor(0xffff00ff));
                            can_jump = true;
                            break;
                        }
                    }
                }
                mario.update(can_jump, .{
                    .right = win.keyboard_state.isSet(win.getScancodeFromName("d")),
                    .left = win.keyboard_state.isSet(win.getScancodeFromName("a")),
                    .b = win.keyboard_state.isSet(win.getScancodeFromName("n")),
                    .a = win.keyboard_state.isSet(win.getScancodeFromName("m")),
                });
                for (win.keys.slice()) |key| {
                    if (key.state != .held)
                        continue;
                    switch (if (game_bindings.get(key.scancode)) |v| v else continue) {
                        else => {},
                    }
                }

                //for (collision_ctx.rect_set.dense.items) |rect| {
                //    try ctx.drawRectOutlineThick(
                //        .{ .x = rect.rect.x + @trunc(tile_map_dx) - pl_rect.x, .y = rect.rect.y + @trunc(tile_map_dy), .w = rect.rect.w, .h = rect.rect.h },
                //        0,
                //        intToColor(0xffff00ff),
                //    );
                //}
                {
                    try ctx.drawRectTex(
                        graph.Rec(
                            @trunc((pl_rect.x + @trunc(tile_map_dx)) * 16) / 16,
                            @trunc((pl_rect.y + @trunc(tile_map_dy)) * 16) / 16,
                            pl_rect.w,
                            pl_rect.h,
                        ),
                        anim.getTexRec(anim_frame),
                        itc(0xffffffff),
                        anim_text,
                    );
                }
                const elapsed = anim_timer.read();
                if (elapsed / std.time.ns_per_ms > 100) {
                    anim_frame = (anim_frame + 1) % 3;
                    anim_timer.reset();
                }

                const col = try collision_ctx.slide(alloc, player_col, mario.dx, mario.dy);
                {
                    const other_mask = mig_level.entities.items[col.other_i];
                    if (other_mask.isSet(@enumToInt(MarioTileMap.Types.component_enum.head_banger)) and col.normal and col.y != null) {
                        //const o_ptr = try collision_ctx.getPtr(col.other_i);

                        const other_ptr = try mig_level.data.head_banger.getPtr(col.other_i);
                        other_ptr.item.active = true;
                        if (mig_level.hasComponent(col.other_i, .mystery_box)) {
                            const ts = try mig_level.data.tile_set_info.getPtr(col.other_i);
                            ts.item.ti += 3;
                        }
                        mario.vy = 0;
                    }
                }
                if (col.x != null)
                    mario.vx = 0;
                if (col.y != null and !col.normal) {
                    grounded = false;
                    vy = 0;
                }
                mario.dx = 0;
                mario.dy = 0;
            }
        }
        const dt = @intToFloat(f32, ctx.fps_time) / std.time.ns_per_ms;
        {
            if (shroom) |id| {
                const col = try collision_ctx.slide(alloc, id, dt / 1000, 0);
                _ = col;
                if (mig_level.getComponentPtr(id, .coord)) |coord| {
                    coord.x = (try collision_ctx.rect_set.get(id)).rect.x;
                }
            }
        }
        {
            //TODO Ugly, create way to edit entities during iteration without side effects
            var mushroom_to_create: ?graph.Vec2f = null;
            //for (mig_level.data.head_banger.dense.items) |*banger| {
            //TODO Think through pointer invaladitation etc
            //Pooling would help

            for (mig_level.entities.items) |it, uid| {
                const id = @intCast(u32, uid);
                if (it.isSet(@enumToInt(MarioTileMap.Types.component_enum.head_banger))) {
                    const system_type = MarioTileMap.createSystemSet(&.{ .coord, .head_banger });
                    var item_set = try mig_level.getEntitySetPtr(id, system_type);

                    if (item_set.head_banger.active) {
                        //const dt = 16.6; //TODO get actual dt

                        item_set.head_banger.time_active += dt;
                        const pos_offset = (0.18 * std.math.pow(f32, (item_set.head_banger.time_active / 16.6) - 7, 2) - 7.5) / 16.0;
                        //const pos_ptr = try mig_level.data.coord.getPtr(banger.i);
                        if (mig_level.getComponentPtr(id, .head_banger)) |ptr| {
                            _ = ptr;
                        }

                        //TODO move using a collision function
                        const col_ptr = try collision_ctx.rect_set.getPtr(id);
                        if (pos_offset > 0) {
                            item_set.head_banger.active = false;
                            item_set.head_banger.time_active = 0;
                            item_set.coord.y = col_ptr.rect.y;
                            if (mig_level.hasComponent(id, .mystery_box)) {
                                try mig_level.removeComponent(id, .head_banger);
                                mushroom_to_create = .{ .x = item_set.coord.x, .y = item_set.coord.y };
                            }
                            //if (mig_level.entities.items[id].isSet(@enumToInt(MarioTileMap.Types.component_enum.mystery_box))) {}
                        } else {
                            item_set.coord.y = col_ptr.rect.y + pos_offset;
                        }

                        //const frames = MarioMap.HeadBanger.frame_pos;
                        //if (banger.item.frame >= MarioMap.HeadBanger.frame_pos.len) {
                        //    pos_ptr.item.y -= (frames[frames.len - 1]) / 16.0;
                        //    banger.item.active = false;
                        //    banger.item.frame = 0;
                        //} else {
                        //    if (banger.item.frame > 0)
                        //        pos_ptr.item.y -= frames[banger.item.frame - 1] / 16.0;

                        //    pos_ptr.item.y += frames[banger.item.frame] / 16.0;
                        //    banger.item.frame += 1;
                        //}
                    }
                }
            }
            if (mushroom_to_create) |coord| {
                const ent = try mig_level.createEntity();
                try mig_level.attachComponent(ent, MarioMap.Mushroom, .{});
                try mig_level.attachComponent(ent, MarioMap.Coord, .{ .x = coord.x, .y = coord.y });
                try mig_level.attachComponent(ent, MarioMap.TileSetInfo, MarioMap.Mushroom.MushroomTile);
            }
        }
        for (mig_level.entities.items) |it, uid| {
            const id = @intCast(u32, uid);
            if (it.isSet(@enumToInt(MarioTileMap.Types.component_enum.mushroom))) {
                const system_type = MarioTileMap.createSystemSet(&.{ .coord, .mushroom });
                var item_set = try mig_level.getEntitySetPtr(id, system_type);
                if (item_set.mushroom.time_active < 1000) {
                    item_set.mushroom.time_active += dt;
                    item_set.coord.y -= (dt / 1000);
                    if (item_set.mushroom.time_active > 1000) {
                        try collision_ctx.insert(graph.Rec(item_set.coord.x, item_set.coord.y, 1, 1), id);
                        shroom = id;
                    }
                }
            }
        }

        try ctx.endCameraDraw(graph.Rec(
            0,
            0,
            @intToFloat(f32, win.screen_width) * tile_map_zf,
            @intToFloat(f32, win.screen_height) * tile_map_zf,
        ), .{
            .x = @trunc((-pl_rect.x + mouse_dx + 10) * 16) / 16 + (1.0 / 17.0),
            .y = -0.5,
        });
        ctx.drawRect(graph.Rec(0, 0, letter_box_w / tile_map_zf, 224 / 16 / tile_map_zf), itc(0x000000ff));
        ctx.drawRect(graph.Rec((tile_map_zf * 3840 - letter_box_w) / tile_map_zf, 0, letter_box_w / tile_map_zf, 224 / 16 / tile_map_zf), itc(0x000000ff));

        _ = fixed_font;
        //try ctx.drawFixedBitmapText(0, 0, 200, "/", fixed_font, itc(0xffffffff));
        //{
        //    var buf: [100]u8 = undefined;
        //    var bufStream = std.io.FixedBufferStream([]u8){ .buffer = &buf, .pos = 0 };
        //    try bufStream.writer().print("{d} scr: {d} off by {d} px", .{
        //        tile_map_dx,
        //        tile_map_dx / tile_map_zf,
        //        @mod(tile_map_dx / tile_map_zf, sw * tile_map_zf),
        //    });
        //    try ctx.drawText(100, 150, 0, buf[0..bufStream.pos], &font, 20, intToColor(0xffffffff));
        //}

        {

            //const fac = 50 * (sw * tile_map_zf);
            const fac = (1 / tile_map_zf);
            const lr = graph.Rect{
                .x = (@divFloor(win.mouse.pos.x - ((tile_map_dx - @trunc(tile_map_dx) * fac)), fac) * fac) +
                    (tile_map_dx - @trunc(tile_map_dx)) * fac,
                //@mod(tile_map_dx / tile_map_zf, sw * tile_map_zf),
                //.y = (@divFloor(win.mouse.pos.y, fac) - @mod(tile_map_dy)) * fac,
                .y = @divFloor(win.mouse.pos.y, fac) * fac,
                .w = fac,
                .h = fac,
            };
            //try ctx.drawRectTex(
            //    lr,
            //    sts.getTexRec(tile_index),
            //    itc(0xffffffff),
            //    my_texture,
            //);
            try ctx.drawRectOutlineThick(lr, 2, itc(0xffffff00));
        }

        //ctx.drawText(400, 400, "Hello this is my test String! Apple: \u{f8ff}\n\u{1001B8}", &font, 18, itc(0xffffffff));

        //try text_editor.draw(&ctx, &font, 10);

        //const scalf: f32 = 5;

        //const mp = win.mouse.pos;
        //if (win.mouse.left and mp.x / scalf < @intToFloat(f32, bitmap.w) and mp.y / scalf < @intToFloat(f32, bitmap.h) and mp.x >= 0 and mp.y >= 0) {
        //    const mx = @floatToInt(u32, mp.x / scalf);
        //    const my = @floatToInt(u32, mp.y / scalf);

        //    const index = ((my * bitmap.w) + mx) * 4;
        //    bitmap.data.items[index] = 0x00;
        //    bitmap.data.items[index + 1] = 0x00;
        //    bitmap.data.items[index + 2] = 0x00;

        //    graph.reDataTextureRGBA(bitmap_texture.id, bitmap.w, bitmap.h, bitmap.data.items);
        //}

        //try ctx.drawRectTex(graph.Rec(
        //    0,
        //    0,
        //    @intToFloat(f32, bitmap.w) * scalf,
        //    @intToFloat(f32, bitmap.h) * scalf,
        //), graph.Rec(
        //    0,
        //    0,
        //    @intToFloat(f32, bitmap.w),
        //    @intToFloat(f32, bitmap.h),
        //), itc(0xffffffff), bitmap_texture);

        gui.drawCommands(cmds.items, &ctx, &font);
        ctx.drawFPS(sd.fps_posx, sd.fps_posy, &font);
        ctx.endDraw(win.screen_width, win.screen_height);

        win.swap();
    }
}
