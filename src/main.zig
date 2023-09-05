const std = @import("std");
const graph = @import("graphics.zig");
const gui = @import("gui.zig");

const c = @import("c.zig");

usingnamespace @import("gui.zig");

const mcBlockAtlas = @import("mc_block_atlas.zig");

const SparseSet = graph.SparseSet;

const aabb = @import("col.zig");

const ecs = @import("registry.zig");

const SubTileset = graph.SubTileset;

const intToColor = graph.intToColor;
const itc = intToColor;
const Color = graph.CharColor;

const pow = std.math.pow;
const sqrt = std.math.sqrt;

const scancodes = @import("keycodes.zig");

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
        w: f32 = 0,
        h: f32 = 0,
    };

    pub const TileSetInfo = struct {
        ti: usize = 0,
        si: usize = 0,
    };

    pub const Physics = struct {
        dx: f32 = 0,
        dy: f32 = 0,
    };

    pub const Player = struct {};
};

const mario_map_fields: ecs.FieldList = &.{
    .{ .ftype = MarioMap.Coord, .name = "coord" },
    .{ .ftype = MarioMap.TileSetInfo, .name = "tile_set_info" },
    .{ .ftype = MarioMap.CollisionObject, .name = "collidable" },
    .{ .ftype = MarioMap.HeadBanger, .name = "head_banger" },
    .{ .ftype = MarioMap.MysteryBox, .name = "mystery_box" },
    .{ .ftype = MarioMap.Mushroom, .name = "mushroom" },
    .{ .ftype = MarioMap.Physics, .name = "physics" },
    .{ .ftype = MarioMap.Player, .name = "player" },
};
pub const MarioTileMap = ecs.Registry(mario_map_fields);

pub fn collisionUpdate(reg: *MarioTileMap, alloc: std.mem.Allocator) !void {
    const system = MarioTileMap.createSystemSet(&.{ .coord, .collidable, .physics });
    for (reg.data.physics.dense.items) |col_item| {
        const id = col_item.i;
        const entity = try reg.getEntitySetPtr(id, system);
        var cols = std.ArrayList(aabb.Collision).init(alloc);
        defer cols.deinit();
        try simulateMove(reg, &cols, id);
        var dx = entity.physics.dx;
        var dy = entity.physics.dy;
        const eps = aabb.eps;

        if (cols.items.len > 0) {
            const col = cols.items[0];
            if (col.x) |cx| {
                var sec_cols = std.ArrayList(aabb.Collision).init(alloc);
                defer sec_cols.deinit();
                entity.physics.dx = 0;
                try simulateMove(reg, &sec_cols, id);
                entity.coord.x = cx - if (col.normal) -eps else entity.coord.w + eps;
                if (sec_cols.items.len > 0) {
                    if (col.y) |cy| {
                        entity.coord.y = cy - if (col.normal) -eps else entity.coord.h + eps;
                    }
                }
                dx = 0;
                dy = 0;
            }
            if (col.y) |cy| {
                entity.coord.y = cy - if (col.normal) -eps else entity.coord.h + eps;
                var sec_cols = std.ArrayList(aabb.Collision).init(alloc);
                defer sec_cols.deinit();
                entity.physics.dy = 0;
                try simulateMove(reg, &sec_cols, id);

                if (sec_cols.items.len > 0) {
                    if (col.x) |cx| {
                        entity.coord.x = cx - if (col.normal) -eps else entity.coord.w + eps;
                    }
                }
                dy = 0;
                dx = 0;
            }
        }
        entity.physics.dx = 0;
        entity.physics.dy = 0;
        entity.coord.x += dx;
        entity.coord.y += dy;

        //if (cols.items.len > 0) {
        //    const col = cols.items[0];
        //    if (col.x) |cx| {
        //        entity.coord.x = cx - if (col.normal) -aabb.eps else entity.coord.w + aabb.eps;
        //    }
        //}
    }
}

pub fn detectCollision(r1: MarioMap.Coord, r2: MarioMap.Coord, goal: aabb.Vec2f, other_i: u32) aabb.Collision {
    const m = aabb.slope(r1.x, goal.x, r1.y, goal.y);

    var result = aabb.Collision{ .x = null, .y = null, .overlaps = false, .perc = 1.0, .normal = false, .other_i = other_i };
    if (m.x > 0 and aabb.containsPoint(r1.x, goal.x, r2.x - r1.w)) {
        const mm = m.y / m.x;
        const c1 = r1.y - ((r1.x + r1.w) * mm);
        if (aabb.doLinesOverlap(mm * r2.x + c1, mm * r2.x + c1 + r1.h, r2.y, r2.y + r2.h)) {
            result.x = r2.x;
            result.perc = aabb.lerpPoint(r1.x, goal.x, r2.x - r1.w);
            result.normal = false;
        }
    } else if (m.x < 0 and aabb.containsPoint(goal.x, r1.x, r2.x + r2.w)) {
        const mm = m.y / m.x;
        const c1 = r1.y - (r1.x * mm);
        const p1 = mm * (r2.x + r2.w) + c1;
        if (aabb.doLinesOverlap(p1, p1 + r1.h, r2.y, r2.y + r2.h)) {
            result.x = r2.x + r2.w;
            result.perc = 1 - aabb.lerpPoint(goal.x, r1.x, r2.x + r2.w);
            result.normal = true;
        }
    }

    if (m.y > 0 and aabb.containsPoint(r1.y, goal.y, r2.y - r1.h)) {
        const mm = m.x / m.y;
        const c1 = r1.x - ((r1.y + r1.h) * mm);
        if (aabb.doLinesOverlap(mm * r2.y + c1, mm * r2.y + c1 + r1.w, r2.x, r2.x + r2.w)) {
            result.y = r2.y;
            result.perc = aabb.lerpPoint(r1.y, goal.y, r2.y - r1.h);
            result.normal = false;
        }
    } else if (m.y < 0 and aabb.containsPoint(goal.y, r1.y, r2.y + r2.h)) {
        const mm = m.x / m.y;
        const c1 = r1.x - (r1.y * mm);
        const p1 = mm * (r2.y + r2.h) + c1;
        if (aabb.doLinesOverlap(p1, p1 + r1.w, r2.x, r2.x + r2.w)) {
            result.y = r2.y + r2.h;
            result.perc = 1 - aabb.lerpPoint(goal.y, r1.y, r2.y + r2.h);
            result.normal = true;
        }
    }

    return result;
}

pub fn simulateMove(reg: *MarioTileMap, cols: *std.ArrayList(aabb.Collision), id: u32) !void {
    const system = MarioTileMap.createSystemSet(&.{ .coord, .collidable, .physics });
    //TODO check if the id has specified components
    const entity = try reg.getEntitySetPtr(id, system);
    if (entity.physics.dx != 0 or entity.physics.dy != 0) {
        const col_system = MarioTileMap.createSystemSet(&.{ .coord, .collidable });
        for (reg.data.collidable.dense.items) |col_item| { //TODO spacial indexing scheme
            if (col_item.i == id) continue;
            const other_ent = try reg.getEntitySetPtr(col_item.i, col_system);
            const col = detectCollision(entity.coord.*, other_ent.coord.*, .{ .x = entity.coord.x + entity.physics.dx, .y = entity.coord.y + entity.physics.dy }, col_item.i);
            if (col.x != null or col.y != null) {
                try cols.append(col);
            }
        }
    }
    if (cols.items.len > 1) {
        std.sort.insertionSort(aabb.Collision, cols.items, aabb.Vec2f{ .x = 0, .y = 0 }, aabb.sortByCompletion);
    }
}

pub const TestEnum = enum {
    val1,
    two,
    three,
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

pub fn deSerializeJson(file_name: []const u8, comptime schema: type, alloc: std.mem.Allocator) !schema {
    @setEvalBranchQuota(10000);
    const cwd = std.fs.cwd();
    const saved = cwd.openFile(file_name, .{}) catch null;
    if (saved) |file| {
        var buf: []const u8 = try file.readToEndAlloc(alloc, 1024 * 1024);
        defer alloc.free(buf);

        var token_stream = std.json.TokenStream.init(buf);
        var ret = try std.json.parse(schema, &token_stream, .{ .allocator = alloc });
        defer std.json.parseFree(schema, ret, .{ .allocator = alloc });
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

//fn getArchetype(list of entitytypes)

fn testHsvImage(alloc: std.mem.Allocator, h: f32) !graph.Texture {
    //HSV
    //S is the x axis
    //V is the y axis
    var bmp = try graph.Bitmap.initBlank(alloc, 250, 250);
    defer bmp.data.deinit();
    defer bmp.writeToBmpFile(alloc, "debug/hsv.bmp") catch unreachable;

    var timer = try std.time.Timer.start();

    var vy: u32 = 0;
    while (vy < bmp.h) : (vy += 1) {
        var sx: u32 = 0;
        while (sx < bmp.w) : (sx += 1) {
            const V = @intToFloat(f32, vy) / @intToFloat(f32, bmp.h);
            const S = @intToFloat(f32, sx) / @intToFloat(f32, bmp.w);
            const C = V * S;
            const hp = h / 60.0;
            const X = C * (1 - @fabs(@mod(hp, 2) - 1));
            const rgb1 = switch (@floatToInt(u32, hp)) {
                0 => graph.za.Vec3.new(C, X, 0),
                1 => graph.za.Vec3.new(X, C, 0),
                2 => graph.za.Vec3.new(0, C, X),
                3 => graph.za.Vec3.new(0, X, C),
                4 => graph.za.Vec3.new(X, 0, C),
                5 => graph.za.Vec3.new(C, 0, X),
                else => unreachable,
            };
            const M = V - C;
            const index = ((bmp.h - vy - 1) * bmp.w + sx) * 4;
            const d = bmp.data.items[index .. index + 4];
            for (d) |*dd, i| {
                if (i == 3) {
                    dd.* = 0xff;
                    break;
                }
                dd.* = @floatToInt(u8, (M + rgb1.data[i]) * 256);
            }
        }
    }

    const time = timer.read();
    std.debug.print("Time took: {d}\n", .{time});

    return graph.Texture.fromArray(bmp.data.items, bmp.w, bmp.h, .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    var testmap = graph.Bind(&.{.{ "fuck", "a" }}).init();

    var win = try graph.SDL.Window.createWindow("My window");
    defer win.destroyWindow();

    var ctx = try graph.GraphicsContext.init(alloc, 163);
    defer ctx.deinit();

    const mc_atlas = try mcBlockAtlas.buildAtlas(alloc);
    defer mc_atlas.deinit(alloc);

    var timer = try std.time.Timer.start();
    var mario_atlas = try graph.Atlas.initFromJsonFile("mario_assets/tileset_manifest.json", alloc, null);
    defer mario_atlas.deinit();
    const time_took = timer.read();
    std.debug.print("Loaded mario in {d}ms\n", .{time_took / std.time.ns_per_ms});

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

    sd = try deSerializeJson("debug/save.json", SaveData, alloc);

    defer serialJson("debug/save.json", sd);

    var dpix: u32 = @floatToInt(u32, win.getDpi());
    std.debug.print("DPI: {d}\n", .{dpix});
    const init_size = 18;
    var font = try graph.Font.init("fonts/sfmono.otf", alloc, init_size, dpix, &(graph.Font.CharMaps.AsciiBasic ++ graph.Font.CharMaps.Apple), null);
    defer font.deinit();

    var sdat = gui.SaveData{ .x = 200, .y = 0 };
    sdat = try deSerializeJson("debug/gui.json", gui.SaveData, alloc);

    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();
    _ = rand;

    var camera = graph.Camera3D{};
    //const my_image = try graph.loadPngIntoTexture("sky.png", alloc);

    win.grabMouse(true);
    var cubes = graph.Cubes.init(alloc, mc_atlas.texture.id, ctx.tex_shad);
    defer cubes.deinit();
    {
        const index = cubes.vertices.items.len;
        try cubes.vertices.appendSlice(&graph.cube(0, 0, 0, 1, 1, 1, mc_atlas.getTextureRec(1), mc_atlas.texture.w, mc_atlas.texture.h, null));
        try cubes.indicies.appendSlice(&graph.genCubeIndicies(@intCast(u32, index)));
        cubes.vertices.items[0].g = 0;
        cubes.vertices.items[0].b = 0;
        cubes.vertices.items[1].r = 0;
        cubes.vertices.items[1].b = 0;
        cubes.setData();
    }
    //const my_texture = try testHsvImage(alloc.*, 0);

    var newtri = graph.NewTri.init(alloc);
    defer newtri.deinit();

    //var testbatch = graph.NewBatch(graph.NewTri.Vert, .{ .index_buffer = false }).init(alloc.*);
    //var testbatchebo = graph.NewBatch(graph.NewTri.Vert, .{ .index_buffer = true }).init(alloc.*);

    try newtri.quad(graph.Rec(50, 50, 100, 100), 10000);

    graph.GL.checkError();

    var draw = graph.NewCtx.init(alloc, win.getDpi());
    defer draw.deinit();
    while (!win.should_exit) {
        try draw.begin(graph.itc(0x2f2f2fff));
        win.pumpEvents();

        try draw.rect(graph.Rec(72, 72, 72, 72), 0xff00ffff);

        try draw.rectPt(graph.Rec(72, 72, 72, 72), 0xffffffff);
        try draw.rectTex(graph.Rec(100, 100, 1000, 1000), graph.Rec(0, 0, 1, 1), 0xffffffff, mario_atlas.texture);

        draw.end(win.screen_width, win.screen_height, graph.za.Mat4.identity());
        win.swap();
    }

    while (!win.should_exit) {
        try ctx.beginDraw(intToColor(0x2f2f2fff), true);
        win.pumpEvents(); //Important that this is called after beginDraw for input lag reasons
        camera.update(&win);

        {
            var buf: [300]u8 = undefined;
            var fbs = std.io.FixedBufferStream([]u8){ .buffer = buf[0..], .pos = 0 };
            //try fbs.writer().print("{any} \n{any}", .{ cam_pos.data, camera_front.data });

            ctx.drawText(50, 300, buf[0..fbs.pos], &font, 16, intToColor(0xffffffff));
        }

        for (win.keys.slice()) |key| {
            switch (testmap.get(key.scancode)) {
                .fuck => std.debug.print("FUCK pressed\n", .{}),
                else => {},
            }
        }

        try ctx.drawCircle(400, 400, 4000, itc(0xff0000ff));
        //try ctx.drawRectTex(graph.Rec(0, 0, 2000, 2000), graph.Rec(0, 0, mario_atlas.texture.w, mario_atlas.texture.h), itc(0xffffffff), mario_atlas.texture);
        //ctx.ptRect(200, 200, 72, 72, graph.itc(0x00ffffff));

        //ctx.drawRect(.{ .x = 0, .y = 0, .w = 100, .h = 100 }, intToColor(0xffff00ff));
        //try ctx.drawRectTex(graph.Rec(600, 600, 1000, 1000), graph.Rec(0, 0, @intToFloat(f32, my_texture.w), @intToFloat(f32, my_texture.h)), itc(0xffffffff), my_texture);

        ctx.drawFPS(sd.fps_posx, sd.fps_posy, &font);

        //ctx.drawRectCol(graph.Rec(0, 0, win.screen_height, win.screen_height), .{ itc(0xffffffff), itc(0xff), itc(0xff), itc(0xffffffff) });
        //ctx.drawRect(graph.Rec(0, 0, win.screen_height, win.screen_height), itc(0xff00006f));
        //ctx.drawRectCol(graph.Rec(0, 0, win.screen_height, win.screen_height), .{ itc(0x33000011), itc(0xff), itc(0xff), itc(0xff0000fa) });

        //try ctx.drawT

        ctx.endDraw(win.screen_width, win.screen_height);

        win.swap();
    }
}
