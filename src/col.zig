const std = @import("std");

const newcol = @import("newcol.zig");
pub const ColType = newcol.ColCtx(2, f32);

const graph = @import("graphics.zig");
const reg = @import("registry.zig");
pub const ColRect = graph.Rect;
const Vec2f = graph.Vec2f;

pub const SparseSet = graph.SparseSet;
const collision_set = SparseSet(ColRect);

pub var simulate_move_time: u64 = 0;

pub fn simulateMoveNew(game: anytype, cols: *std.ArrayList(ColType.CollisionResult), id: reg.ID_TYPE, goal: Vec2f) !void {
    var timer = try std.time.Timer.start();
    defer simulate_move_time += timer.read();
    const plc = try game.ecs.get(id, .collide);
    const pl = plc.rect;

    const area = graph.Rect.hull(pl, graph.Rect.newV(goal, pl.dim()));
    const rects_to_check = try game.grid.getObjectsInArea(game.temp_alloc.allocator(), area);

    for (rects_to_check.items) |o_id| {
        if (o_id == id) continue;
        const other = try game.ecs.get(o_id, .collide);
        if (other.kind == .nocollide) continue;

        if (ColType.detectCollision(pl, other.rect, goal, o_id)) |col| {
            try cols.append(col);
        }
    }

    if (cols.items.len > 1) {
        std.sort.insertion(ColType.CollisionResult, cols.items, {}, ColType.CollisionResult.lessThan);
    }
}

pub fn doRectsOverlap(r1: ColRect, r2: ColRect) bool {
    return !(r1.x > r2.x + r2.w or r2.x > r1.x + r1.w or r1.y > r2.y + r2.h or r2.y > r1.y + r1.h);
}

pub fn doLinesOverlap(low1: f32, high1: f32, low2: f32, high2: f32) bool {
    return !(low1 > high2 or high1 < low2);
}
