pub const DELTA: f32 = 1e-10;
const std = @import("std");

//TODO
//Delete col3d and use ColCtx(3,f32)
//add slide and bounce response types
//Given two objects which response should we use?
pub fn ColCtx(DIM: usize, FT: type) type {
    return struct {
        const V = [DIM]FT;
        const ZeroV = [_]FT{0} ** DIM;
        const AABB = struct {
            p: V,
            x: V,
        };

        pub usingnamespace switch (DIM) {
            2 => struct {
                pub fn detectCollision(r1: anytype, r2: anytype, goal: anytype, other_i: u32) ?CollisionResult {
                    return detectCollisionRaw(
                        .{
                            .p = [2]f32{ r1.x, r1.y },
                            .x = [2]f32{ r1.w, r1.h },
                        },
                        .{
                            .p = [2]f32{ r2.x, r2.y },
                            .x = [2]f32{ r2.w, r2.h },
                        },
                        [2]f32{ goal.x, goal.y },
                        other_i,
                    );
                }
            },
            3 => struct {
                pub fn detectCollision(c1: anytype, c2: anytype, goal: anytype, other_i: u32) ?CollisionResult {
                    return detectCollisionRaw(
                        .{ .p = c1.pos.data, .x = c1.ext.data },
                        .{ .p = c2.pos.data, .x = c2.ext.data },
                        goal.data,
                        other_i,
                    );
                }
            },
            else => struct {},
        };

        /// a[i] - b[i]
        pub fn subV(a: V, b: V) V {
            var ret = a;
            for (0..DIM) |i| {
                ret[i] -= b[i];
            }
            return ret;
        }

        pub fn lenV(a: V) FT {
            var sum: FT = 0;
            for (0..DIM) |i| {
                sum += a[i] * a[i];
            }
            return @sqrt(sum);
        }

        /// Return the minimum component
        pub fn minV(a: V) FT {
            var min = std.math.floatMax(FT);
            for (0..DIM) |i| {
                min = @min(min, a[i]);
            }
            return min;
        }

        pub const LBRes = struct {
            ti: FT = 0,
            ti2: FT = 0,
            normal: V,
            norm2: V = ZeroV,
        };

        pub const CollisionResult = struct {
            overlaps: bool,
            ti: FT,
            move: V,
            normal: V,
            touch: V,
            other_i: u32,

            item: AABB,
            other: AABB,

            pub fn lessThan(ctx: void, lhs: @This(), rhs: @This()) bool {
                _ = ctx;
                if (lhs.ti == rhs.ti)
                    return squareDistance(lhs.item, lhs.other) < squareDistance(lhs.item, rhs.other);
                return lhs.ti < rhs.ti;
            }
        };

        pub fn squareDistance(r1: AABB, r2: AABB) FT {
            var total: FT = 0;
            for (0..DIM) |i| {
                total += std.math.pow(FT, r1.p[i] - r2.p[i] + (r1.x[i] - r2.x[i]) / 2, 2);
            }
            return total;
        }

        /// Return the 1d point[a,b] nearest to x
        pub fn nearest(x: FT, a: FT, b: FT) FT {
            return if (@abs(a - x) < @abs(b - x)) a else b;
        }

        pub fn sign(a: FT) FT {
            if (a < 0)
                return -1;
            if (a == 0)
                return 0;
            return 1;
        }

        pub fn nearestCorner(r: AABB, p: V) V {
            var ret: V = undefined;
            for (0..DIM) |i| {
                ret[i] = nearest(p[i], r.p[i], r.p[i] + r.x[i]);
            }
            return ret;
        }

        pub fn containsPoint(r: AABB, p: V) bool {
            var ret = true;
            for (0..DIM) |i| {
                ret = ret and p[i] - r.p[i] > DELTA and r.p[i] + r.x[i] - p[i] > DELTA;
            }
            return ret;
        }

        pub fn minkowsky_diff(r1: AABB, r2: AABB) AABB {
            var ret: AABB = undefined;
            for (0..DIM) |i| {
                ret.p[i] = r2.p[i] - r1.p[i] - r1.x[i];
                ret.x[i] = r1.x[i] + r2.x[i];
            }
            return ret;
        }

        pub fn lbClip(norm: V, p: FT, q: FT, ti1: *FT, ti2: *FT, n1: *V, n2: *V) bool {
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

        pub fn liang_barsky(clip_window: AABB, start: V, end: V, ti1_: ?FT, ti2_: ?FT) ?LBRes {
            var ti1 = ti1_ orelse 0;
            var ti2 = ti2_ orelse 1;
            var delta = end;
            for (0..DIM) |i| {
                delta[i] -= start[i];
            }
            var norm1 = ZeroV;
            var norm2 = ZeroV;

            for (0..DIM) |i| {
                var nneg = ZeroV;
                var npos = ZeroV;
                nneg[i] = -1;
                npos[i] = 1;
                if (!lbClip(nneg, -delta[i], start[i] - clip_window.p[i], &ti1, &ti2, &norm1, &norm2))
                    return null;
                if (!lbClip(npos, delta[i], clip_window.p[i] + clip_window.x[i] - start[i], &ti1, &ti2, &norm1, &norm2))
                    return null;
            }

            return LBRes{
                .ti = ti1,
                .ti2 = ti2,
                .normal = norm1,
                .norm2 = norm2,
            };
        }

        pub fn detectCollisionRaw(r1: AABB, r2: AABB, goal: V, other_i: u32) ?CollisionResult {
            const delta = subV(goal, r1.p);
            const mdiff = minkowsky_diff(r1, r2);
            var overlaps = false;
            var ti: ?f32 = null;

            var norm = ZeroV;

            //if the Minkowsky diff intersects the origin it is already overlapping
            if (containsPoint(mdiff, ZeroV)) {
                const point = nearestCorner(mdiff, ZeroV);
                var area: FT = -1;
                for (0..DIM) |i| {
                    area *= @min(r1.x[i], @abs(point[i]));
                }
                //econst wi = @min(r1.w, @abs(point.x));
                //econst hi = @min(r1.h, @abs(point.y));
                ti = area;
                //ti = -wi * hi; // ti is the negative area of intersection
                overlaps = true;
            } else {
                if (liang_barsky(mdiff, ZeroV, delta, -std.math.floatMax(f32), std.math.floatMax(f32))) |lb| {
                    if (lb.ti < 1 and @abs(lb.ti - lb.ti2) >= DELTA and (0 < lb.ti + DELTA or 0 == ti and lb.ti2 > 0)) {
                        ti = lb.ti;
                        norm = lb.normal;
                        overlaps = false;
                    }
                }
            }
            if (ti == null) return null;

            var tv = ZeroV;
            if (overlaps) {
                if (lenV(delta) < DELTA) {
                    var np = nearestCorner(mdiff, ZeroV);
                    //Find the minimum component and set all others to zero
                    var mi: usize = 0;
                    var min: FT = std.math.floatMax(FT);
                    for (0..DIM) |i| {
                        if (@abs(np[i]) < min) {
                            min = @abs(np[i]);
                            mi = i;
                        }
                    }
                    for (0..DIM) |i| {
                        if (i == mi)
                            continue;
                        np[i] = 0;
                    }
                    for (0..DIM) |i| {
                        norm[i] = sign(np[i]);
                    }
                    tv = ZeroV;
                    //tx = r1.x + np.x;
                    //ty = r1.y + np.y;
                } else {
                    const lb = liang_barsky(mdiff, ZeroV, delta, -std.math.floatMax(f32), 1) orelse return null;
                    norm = lb.normal;
                    for (0..DIM) |i| {
                        tv[i] = r1.p[i] + delta[i] * lb.ti;
                    }
                }

                //norm = Norm.fromSigns(if(np.x > 0) 1, np.y);
            } else {
                for (0..DIM) |i| {
                    tv[i] = r1.p[i] + delta[i] * ti.?;
                }
            }

            return CollisionResult{
                .overlaps = overlaps,
                .item = r1,
                .other = r2,
                .ti = ti.?,
                .move = delta,
                .normal = norm,
                .touch = tv,
                .other_i = other_i,
            };
        }
    };
}

const TC = ColCtx(2, f32);
const ex = std.testing.expectEqual;
test "nearest" {
    try ex(1, TC.nearest(0, 1, 2));
    try ex(2, TC.nearest(3, 1, 2));
    try ex(-3, TC.nearest(-1, -3, 2));
}

test "nearestCorner" {
    try ex([_]f32{ 0, 1 }, TC.nearestCorner(.{
        .p = [_]f32{ 0, 0 },
        .x = [_]f32{ 1, 1 },
    }, [_]f32{ 0, 10 }));
}

test "containsPoint" {
    try ex(TC.containsPoint(.{
        .p = [_]f32{ 0, 0 },
        .x = [_]f32{ 1, 1 },
    }, [_]f32{ 0.5, 0.5 }), true);
}

test "minkowskyDiff" {
    const a = TC.AABB{ .p = [_]f32{ 1, 1 }, .x = [_]f32{ 1, 1 } };
    const b = TC.AABB{ .p = [_]f32{ 3, 3 }, .x = [_]f32{ 1, 1 } };
    const e = TC.AABB{ .p = [_]f32{ 1, 1 }, .x = [_]f32{ 2, 2 } };

    try ex(TC.minkowsky_diff(a, b), e);
}
