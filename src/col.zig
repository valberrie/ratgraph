const std = @import("std");

const graph = @import("graphics.zig");
pub const ColRect = graph.Rect;
const Vec2f = graph.Vec2f;

pub const SparseSet = graph.SparseSet;
const collision_set = SparseSet(ColRect);

pub var simulate_move_time: u64 = 0;
pub fn simulateMove(game: anytype, cols: *std.ArrayList(Collision), id: u32, dx: f32, dy: f32) !void {
    var timer = try std.time.Timer.start();
    defer simulate_move_time += timer.read();
    const pl = try game.ecs.get(id, .col_rect);

    const area = graph.Rect.hull(pl, pl.addV(dx, dy));
    var rects_to_check = try game.grid.getObjectsInArea(game.temp_alloc.allocator(), area);

    for (rects_to_check.items) |o_id| {
        if (o_id == id) continue;
        if (try game.ecs.getOpt(o_id, .collision_type) == null) continue;

        const col = detectCollision(pl, try game.ecs.get(o_id, .col_rect), .{ .x = pl.x + dx, .y = pl.y + dy }, o_id);
        if (col.x != null or col.y != null or col.overlaps) {
            try cols.append(col);
        }
    }

    //var col_it = game.ecs.iterator(.collision_type);
    //while (col_it.next()) |other_opt| {
    //    if (other_opt.i == id) continue;
    //    const col = detectCollision(pl, try game.ecs.get(other_opt.i, .col_rect), .{ .x = pl.x + dx, .y = pl.y + dy }, other_opt.i);
    //    if (col.x != null or col.y != null or col.overlaps) {
    //        try cols.append(col);
    //    }
    //}
    if (cols.items.len > 1) {
        std.sort.insertion(Collision, cols.items, Vec2f{ .x = 0, .y = 0 }, sortByCompletion);
    }
}

pub fn simulateMoveNew(game: anytype, cols: *std.ArrayList(Collision), id: u32, dx: f32, dy: f32) !void {
    var timer = try std.time.Timer.start();
    defer simulate_move_time += timer.read();
    const plc = try game.ecs.get(id, .collide);
    const pl = plc.rect;

    const area = graph.Rect.hull(pl, pl.addV(dx, dy));
    var rects_to_check = try game.grid.getObjectsInArea(game.temp_alloc.allocator(), area);

    for (rects_to_check.items) |o_id| {
        if (o_id == id) continue;
        const other = try game.ecs.get(o_id, .collide);
        if (other.kind == .nocollide) continue;

        const col = detectCollision(pl, other.rect, .{ .x = pl.x + dx, .y = pl.y + dy }, o_id);
        if (col.x != null or col.y != null or col.overlaps) {
            try cols.append(col);
        }
    }

    //var col_it = game.ecs.iterator(.collide);
    //while (col_it.next()) |other_opt| {
    //    if (other_opt.i == id) continue;
    //    if (other_opt.item.kind == .nocollide) continue;
    //    const col = detectCollision(pl, (try game.ecs.get(other_opt.i, .collide)).rect, .{ .x = pl.x + dx, .y = pl.y + dy }, other_opt.i);
    //    if (col.x != null or col.y != null or col.overlaps) {
    //        try cols.append(col);
    //    }
    //}
    if (cols.items.len > 1) {
        std.sort.insertion(Collision, cols.items, Vec2f{ .x = 0, .y = 0 }, sortByCompletion);
    }
}

pub fn doRectsOverlap(r1: ColRect, r2: ColRect) bool {
    return !(r1.x > r2.x + r2.w or r2.x > r1.x + r1.w or r1.y > r2.y + r2.h or r2.y > r1.y + r1.h);
}

pub fn containsPoint(low: f32, high: f32, point: f32) bool {
    return (low - point > 0) != (high - point > 0);
}

pub fn doLinesOverlap(low1: f32, high1: f32, low2: f32, high2: f32) bool {
    return !(low1 > high2 or high1 < low2);
}

pub fn slope(x1: f32, x2: f32, y1: f32, y2: f32) Vec2f {
    return .{ .y = (y2 - y1), .x = x2 - x1 };
}

//TODO helper functions for checking the side of collision
pub const Collision = struct {
    x: ?f32,
    y: ?f32,
    perc: f32,
    overlaps: bool,

    //TODO use enum values instead of bool, .left, .right, .top, .bottom
    normal: bool,

    //other: ColRect,
    other_i: u32,
};

pub fn sortByCompletion(goal: Vec2f, a: Collision, b: Collision) bool {
    _ = goal;
    return a.perc < b.perc;
}

pub fn lerpPoint(start: f32, end: f32, point: f32) f32 {
    return (point - start) / (end - start);
}

//TODO special case for already colliding rects
pub fn detectCollision(r1: ColRect, r2: ColRect, goal: Vec2f, other_i: u32) Collision {
    const m = slope(r1.x, goal.x, r1.y, goal.y);

    var result = Collision{ .x = null, .y = null, .overlaps = false, .perc = 1.0, .normal = false, .other_i = other_i };
    if (m.x > 0 and containsPoint(r1.x, goal.x, r2.x - r1.w)) {
        const mm = m.y / m.x;
        const c1 = r1.y - ((r1.x + r1.w) * mm);
        if (doLinesOverlap(mm * r2.x + c1, mm * r2.x + c1 + r1.h, r2.y, r2.y + r2.h)) {
            result.x = r2.x;
            result.perc = lerpPoint(r1.x, goal.x, r2.x - r1.w);
            result.normal = false;
        }
    } else if (m.x < 0 and containsPoint(goal.x, r1.x, r2.x + r2.w)) {
        const mm = m.y / m.x;
        const c1 = r1.y - (r1.x * mm);
        const p1 = mm * (r2.x + r2.w) + c1;
        if (doLinesOverlap(p1, p1 + r1.h, r2.y, r2.y + r2.h)) {
            result.x = r2.x + r2.w;
            result.perc = 1 - lerpPoint(goal.x, r1.x, r2.x + r2.w);
            result.normal = true;
        }
    }

    if (m.y > 0 and containsPoint(r1.y, goal.y, r2.y - r1.h)) {
        const mm = m.x / m.y;
        const c1 = r1.x - ((r1.y + r1.h) * mm);
        if (doLinesOverlap(mm * r2.y + c1, mm * r2.y + c1 + r1.w, r2.x, r2.x + r2.w)) {
            result.y = r2.y;
            result.perc = lerpPoint(r1.y, goal.y, r2.y - r1.h);
            result.normal = false;
        }
    } else if (m.y < 0 and containsPoint(goal.y, r1.y, r2.y + r2.h)) {
        const mm = m.x / m.y;
        const c1 = r1.x - (r1.y * mm);
        const p1 = mm * (r2.y + r2.h) + c1;
        if (doLinesOverlap(p1, p1 + r1.w, r2.x, r2.x + r2.w)) {
            result.y = r2.y + r2.h;
            result.perc = 1 - lerpPoint(goal.y, r1.y, r2.y + r2.h);
            result.normal = true;
        }
    }
    result.overlaps = doRectsOverlap(r1, r2);

    return result;
}

//pub const Vec2f = struct {
//    x: f32,
//    y: f32,
//};

//Entity
//Coord
//Collidable
//
//
//fn(reg:*Registry, dt){
//When do collisions occur/
//During physics moves
//
//
//}
//

pub const eps = 0.01;
pub fn CollisionContext() type {
    return struct {
        const Self = @This();
        const RectItem = struct { rect: ColRect, i: u32 };
        const RectSet: type = SparseSet(RectItem, u32);

        pub const CollisionIterator = struct {
            const ColIt = @This();
            cols: std.ArrayList(Collision),
            index: usize = 0,

            pub fn init(alloc: std.mem.Allocator) ColIt {
                return .{ .cols = std.ArrayList(Collision).init(alloc) };
            }

            pub fn deinit(self: *ColIt) void {
                self.cols.deinit();
            }

            pub fn reset(self: *ColIt) !void {
                self.index = 0;
                try self.cols.resize(0);
            }

            pub fn next(self: *ColIt) ?Collision {
                defer self.index += 1;

                if (self.index == self.cols.items.len)
                    return null;

                return self.cols.items[self.index];
            }
        };

        rect_set: RectSet,

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .rect_set = RectSet.init(alloc) catch unreachable,
            };
        }

        pub fn deinit(self: *Self) void {
            self.rect_set.deinit();
        }

        pub fn remove(self: *Self, id: u32) !void {
            _ = try self.rect_set.remove(id);
        }

        pub fn add(self: *Self, rect: ColRect) !u32 {
            return try self.rect_set.add(.{ .rect = rect, .i = 0 });
        }

        pub fn rectSlice(self: *Self) []const RectItem {
            return self.rect_set.dense.items;
        }

        pub fn insert(self: *Self, rect: ColRect, index: u32) !void {
            try self.rect_set.insert(index, .{ .i = index, .rect = rect });
        }

        pub fn get(self: *Self, id: u32) !ColRect {
            return (try self.rect_set.get(id)).rect;
        }

        pub fn getPtr(self: *Self, id: u32) !*ColRect {
            return &(try self.rect_set.getPtr(id)).rect;
        }

        pub fn simulateMove(self: *Self, cols: *std.ArrayList(Collision), id: u32, dx: f32, dy: f32) !void {
            const pl = try self.rect_set.getPtr(id);
            for (self.rect_set.dense.items) |other_opt| {
                if (other_opt.i == id) continue;
                const other = other_opt;

                const col = detectCollision(pl.rect, other.rect, .{ .x = pl.rect.x + dx, .y = pl.rect.y + dy }, other_opt.i);
                if (col.x != null or col.y != null or col.overlaps) {
                    try cols.append(col);
                }
            }
            if (cols.items.len > 1) {
                std.sort.insertion(Collision, cols.items, Vec2f{ .x = 0, .y = 0 }, sortByCompletion);
            }
        }

        pub fn slide(self: *Self, alloc: std.mem.Allocator, id: u32, dx: f32, dy: f32) anyerror!Collision {
            var ldx = dx;
            var ldy = dy;
            var cols = std.ArrayList(Collision).init(alloc);
            defer cols.deinit();

            var ret = Collision{ .x = null, .y = null, .perc = 0, .normal = false, .overlaps = false, .other_i = 0 };
            const pl = try self.rect_set.getPtr(id);
            try self.simulateMove(&cols, id, dx, dy);
            if (cols.items.len > 0) {
                const col = cols.items[0];
                if (col.x) |cx| {
                    pl.rect.x = cx - if (col.normal) -eps else pl.rect.w + eps;
                    _ = try self.slide(alloc, id, 0, dy);
                    ret = col;
                    ldx = 0;
                    ldy = 0;
                }
                if (col.y) |cy| {
                    pl.rect.y = cy - if (col.normal) -eps else pl.rect.h + eps;
                    _ = try self.slide(alloc, id, dx, 0);
                    ret = col;
                    ldy = 0;
                    ldx = 0;
                }
            }
            pl.rect.x += ldx;
            pl.rect.y += ldy;
            return ret;
        }
    };
}
