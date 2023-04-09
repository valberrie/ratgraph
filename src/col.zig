const std = @import("std");

const graph = @import("graphics.zig");
pub const ColRect = graph.Rect;

pub const SparseSet = graph.SparseSet;

//pub const ColRect = struct {
//    x: f32,
//    y: f32,
//    w: f32,
//    h: f32,
//};

pub fn containsPoint(low: f32, high: f32, point: f32) bool {
    return (low - point > 0) != (high - point > 0);
}

pub fn doLinesOverlap(low1: f32, high1: f32, low2: f32, high2: f32) bool {
    return !(low1 > high2 or high1 < low2);
}

pub fn slope(x1: f32, x2: f32, y1: f32, y2: f32) Vec2f {
    return .{ .y = (y2 - y1), .x = x2 - x1 };
}

pub const Collision = struct {
    x: ?f32,
    y: ?f32,
    perc: f32,
    overlaps: bool,

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

    return result;
}

pub const Vec2f = struct {
    x: f32,
    y: f32,
};

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
        const RectSet: type = SparseSet(struct { rect: ColRect, i: u32 }, u32);

        rect_set: RectSet,

        pub fn init(alloc: *const std.mem.Allocator) Self {
            return .{
                .rect_set = RectSet.init(alloc) catch unreachable,
            };
        }

        pub fn deinit(self: *Self) void {
            self.rect_set.deinit();
        }

        pub fn add(self: *Self, rect: ColRect) !u32 {
            //TODO Add and remove functions need to treat data arrays as memory? or something, reuse empty slots rather than always appending

            return try self.rect_set.add(.{ .rect = rect, .i = 0 });
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

        pub fn slide(self: *Self, alloc: *const std.mem.Allocator, id: u32, dx: f32, dy: f32) anyerror!Collision {
            var ldx = dx;
            var ldy = dy;
            var cols = std.ArrayList(Collision).init(alloc.*);
            defer cols.deinit();

            var ret = Collision{ .x = null, .y = null, .perc = 0, .normal = false, .overlaps = false, .other_i = 0 };
            const pl = try self.rect_set.getPtr(id);
            for (self.rect_set.dense.items) |other_opt| {
                if (other_opt.i == id) continue;
                const other = other_opt;

                const col = detectCollision(pl.rect, other.rect, .{ .x = pl.rect.x + dx, .y = pl.rect.y + dy }, other_opt.i);
                if (col.x != null or col.y != null) {
                    try cols.append(col);
                }
            }
            if (cols.items.len > 1) {
                std.sort.insertionSort(Collision, cols.items, Vec2f{ .x = 0, .y = 0 }, sortByCompletion);
            }
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
