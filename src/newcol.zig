pub const DELTA: f32 = 1e-10;
const std = @import("std");

pub fn CollisionType(comptime rect_type: type, comptime vector_type: type) type {
    return struct {
        const Rect = rect_type;
        const Vec = vector_type;

        pub const Norm = Vec;
        //pub const Norm = enum {
        //    top,
        //    left,
        //    bottom,
        //    right,
        //    none,

        //    pub fn fromSigns(xdisp: f32, ydisp: f32) Norm {
        //        if (xdisp != 0) {
        //            return if (xdisp > 0) .right else .left;
        //        }
        //        if (ydisp != 0) {
        //            return if (ydisp > 0) .bottom else .top;
        //        }
        //        return .none;
        //    }
        //};

        pub fn sign(a: f32) f32 {
            if (a < 0)
                return -1;
            if (a == 0)
                return 0;
            return 1;
        }

        pub const LBRes = struct {
            ti: f32 = 0,
            ti2: f32 = 0,
            normal: Norm,
            norm2: Norm = Vec.new(0, 0),
        };

        pub const CollisionResult = struct {
            overlaps: bool,
            ti: f32,
            move: Vec,
            normal: Norm,
            touch: Vec,
            other_i: u32,

            item: Rect,
            other: Rect,

            pub fn lessThan(ctx: void, lhs: @This(), rhs: @This()) bool {
                _ = ctx;
                if (lhs.ti == rhs.ti)
                    return squareDistance(lhs.item, lhs.other) < squareDistance(lhs.item, rhs.other);
                return lhs.ti < rhs.ti;
            }
        };

        pub fn nearest(x: f32, a: f32, b: f32) f32 {
            return if (@abs(a - x) < @abs(b - x)) a else b;
        }

        pub fn squareDistance(r1: Rect, r2: Rect) f32 {
            const dx = r1.x - r2.x + (r1.w - r2.w) / 2;
            const dy = r1.y - r2.y + (r1.h - r2.h) / 2;
            return dx * dx + dy * dy;
        }

        pub fn nearestCorner(r: Rect, point: Vec) Vec {
            return .{
                .x = nearest(point.x, r.x, r.x + r.w),
                .y = nearest(point.y, r.y, r.y + r.h),
            };
        }

        pub fn containsPoint(r: Rect, x: f32, y: f32) bool {
            return x - r.x > DELTA and y - r.y > DELTA and r.x + r.w - x > DELTA and r.y + r.h - y > DELTA;
        }

        pub fn liang_rewrite(clip_window: Rect, start: Vec, end: Vec, ti1_: ?f32, ti2_: ?f32) ?LBRes {
            var ti1 = ti1_ orelse 0;
            var ti2 = ti2_ orelse 1;
            const delta = end.sub(start);
            var norm1 = Vec.new(0, 0);
            var norm2 = Vec.new(0, 0);
            if (!lhelp(Vec.new(-1, 0), -delta.x, start.x - clip_window.x, &ti1, &ti2, &norm1, &norm2))
                return null;
            if (!lhelp(Vec.new(1, 0), delta.x, clip_window.x + clip_window.w - start.x, &ti1, &ti2, &norm1, &norm2))
                return null;
            if (!lhelp(Vec.new(0, -1), -delta.y, start.y - clip_window.y, &ti1, &ti2, &norm1, &norm2))
                return null;
            if (!lhelp(Vec.new(0, -1), delta.y, clip_window.y + clip_window.h - start.y, &ti1, &ti2, &norm1, &norm2))
                return null;

            return LBRes{
                .ti = ti1,
                .ti2 = ti2,
                .normal = norm1,
                .norm2 = norm2,
            };
        }

        pub fn lhelp(norm: Vec, p: f32, q: f32, ti1: *f32, ti2: *f32, n1: *Vec, n2: *Vec) bool {
            if (p == 0) {
                if (q <= 0) return false;
            } else {
                const r = q / p;
                if (p < 0) {
                    if (r > ti2.*)
                        return false;
                    if (r > ti1.*) {
                        ti1.* = r;
                        n1.* = norm;
                    }
                } else {
                    if (r < ti1.*) return false;
                    if (r < ti2.*) {
                        ti2.* = r;
                        n2.* = norm;
                    }
                }
            }
            return true;
        }

        pub fn minkowsky_diff(r1: Rect, r2: Rect) Rect {
            return .{
                .x = r2.x - r1.x - r1.w,
                .y = r2.y - r1.y - r1.h,
                .w = r1.w + r2.w,
                .h = r1.h + r2.h,
            };
        }

        pub fn detectCollision(r1: Rect, r2: Rect, goal: Vec, other_i: u32) ?CollisionResult {
            const delta: Vec = .{ .x = goal.x - r1.x, .y = goal.y - r1.y };
            const mdiff = minkowsky_diff(r1, r2);
            var overlaps = false;
            var ti: ?f32 = null;

            var norm: Norm = Vec.new(0, 0);

            //if the Minkowsky diff intersects the origin it is already overlapping
            if (containsPoint(mdiff, 0, 0)) {
                const point = nearestCorner(mdiff, .{ .x = 0, .y = 0 });
                const wi = @min(r1.w, @abs(point.x));
                const hi = @min(r1.h, @abs(point.y));
                ti = -wi * hi; // ti is the negative area of intersection
                overlaps = true;
            } else {
                if (liang_rewrite(mdiff, .{ .x = 0, .y = 0 }, delta, -std.math.floatMax(f32), std.math.floatMax(f32))) |lb| {
                    if (lb.ti < 1 and @abs(lb.ti - lb.ti2) >= DELTA and (0 < lb.ti + DELTA or 0 == ti and lb.ti2 > 0)) {
                        ti = lb.ti;
                        norm = lb.normal;
                        overlaps = false;
                    }
                }
            }
            if (ti == null) return null;

            var tx: f32 = 0;
            var ty: f32 = 0;
            if (overlaps) {
                if (delta.length() < DELTA) {
                    var np = nearestCorner(mdiff, .{ .x = 0, .y = 0 });
                    if (@abs(np.x) < @abs(np.y)) {
                        np.y = 0;
                    } else {
                        np.x = 0;
                    }
                    norm = Vec.new(sign(np.x), sign(np.y));
                    tx = 0;
                    ty = 0;
                    //tx = r1.x + np.x;
                    //ty = r1.y + np.y;
                } else {
                    const lb = liang_rewrite(mdiff, .{ .x = 0, .y = 0 }, delta, -std.math.floatMax(f32), 1) orelse return null;
                    norm = lb.normal;
                    tx = r1.x + delta.x * lb.ti;
                    ty = r1.y + delta.y * lb.ti;
                }

                //norm = Norm.fromSigns(if(np.x > 0) 1, np.y);
            } else {
                tx = r1.x + delta.x * ti.?;
                ty = r1.y + delta.y * ti.?;
            }

            return CollisionResult{
                .overlaps = overlaps,
                .item = r1,
                .other = r2,
                .ti = ti.?,
                .move = delta,
                .normal = norm,
                .touch = .{ .x = tx, .y = ty },
                .other_i = other_i,
            };
        }
    };
}

//Test cases
//Each of the four quadrants
//tunnel through, tunnel half, tunnel before
//rect already intersecting no delta, delta
//rect goes through corner
