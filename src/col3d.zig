const std = @import("std");
const za = @import("zalgebra");
pub const DELTA: f32 = 1e-10;

pub fn CollisionType(comptime rect_type: type, comptime vector_type: type) type {
    _ = vector_type;
    return struct {
        pub const Cube = struct {
            pos: Vec,
            ext: Vec,
        };
        const Rect = rect_type;

        pub const LBRes = struct {
            ti: f32,
            normal: Vec,
        };

        pub const CollisionResult = struct {
            /// The objects were overlapped before move
            overlaps: bool,
            /// Percentage of "delta" moved at collision
            ti: f32,
            /// The delta vector passed to fn detectCollision
            delta: Vec,
            /// The normal of the collision, from the moved's perspective
            normal: Vec,
            /// The new position vector for the moved aabb
            touch: Vec,

            pub fn lessThan(ctx: void, lhs: @This(), rhs: @This()) bool {
                _ = ctx;
                return lhs.ti < rhs.ti;
            }
        };

        pub fn nearest(x: f32, a: f32, b: f32) f32 {
            return if (@abs(a - x) < @abs(b - x)) a else b;
        }

        pub fn nearestCorner(r: Cube, point: Vec) Vec {
            return Vec.new(
                nearest(point.x(), r.pos.x(), r.pos.x() + r.ext.x()),
                nearest(point.y(), r.pos.y(), r.pos.y() + r.ext.y()),
                nearest(point.z(), r.pos.z(), r.pos.z() + r.ext.z()),
            );
        }

        pub fn containsPoint(r: Cube, p: Vec) bool {
            const m = p.sub(r.pos);
            const mx = r.pos.add(r.ext).sub(p);
            return m.x() > DELTA and m.y() > DELTA and m.z() > DELTA and mx.x() > DELTA and mx.y() > DELTA and mx.z() > DELTA;
        }

        /// Liang barsky clipping in 3D.
        pub fn liang_barsky(clip_window: Cube, start: Vec, end: Vec) ?LBRes {
            const min = clip_window.pos;
            const max = clip_window.pos.add(clip_window.ext);
            const p1 = -(end.x() - start.x());
            const p2 = -p1;
            const p3 = -(end.y() - start.y());
            const p4 = -p3;

            const p5 = -(end.z() - start.z());
            const p6 = -p5;

            const q1 = start.x() - min.x();
            const q2 = max.x() - start.x();
            const q3 = start.y() - min.y();
            const q4 = max.y() - start.y();

            const q5 = start.z() - min.z();
            const q6 = max.z() - start.z();

            if ((p1 == 0 and q1 < 0) or (p2 == 0 and q2 < 0) or (p3 == 0 and q3 < 0) or (p4 == 0 and q4 < 0) or (p5 == 0 and q5 < 0) or (p6 == 0 and q6 < 0))
                return null; // parallel to window

            var max_neg: f32 = 0;
            var min_pos: f32 = 1;
            var normal: Vec = Vec.new(0, 0, 0);

            if (p1 != 0) { //x
                const r1 = q1 / p1;
                const c2 = q2 / p2;
                if (p1 < 0) { //line is going right
                    if (r1 > max_neg) {
                        max_neg = r1;
                        normal = Vec.new(-1, 0, 0);
                    }
                    min_pos = if (c2 > min_pos) min_pos else c2;
                } else {
                    if (c2 > max_neg) {
                        max_neg = c2;
                        normal = Vec.new(1, 0, 0);
                    }
                    min_pos = if (r1 > min_pos) min_pos else r1;
                }
            }
            if (p3 != 0) {
                const r3 = q3 / p3;
                const r4 = q4 / p4;
                if (p3 < 0) {
                    if (r3 > max_neg) {
                        max_neg = r3;
                        normal = Vec.new(0, -1, 0);
                    }
                    min_pos = if (r4 > min_pos) min_pos else r4;
                } else {
                    if (r4 > max_neg) {
                        max_neg = r4;
                        normal = Vec.new(0, 1, 0);
                    }
                    min_pos = if (r3 > min_pos) min_pos else r3;
                }
            }

            if (p5 != 0) {
                const r5 = q5 / p5;
                const r6 = q6 / p6;
                if (p5 < 0) {
                    if (r5 > max_neg) {
                        max_neg = r5;
                        normal = Vec.new(0, 0, -1);
                    }
                    min_pos = if (r6 > min_pos) min_pos else r6;
                } else {
                    if (r6 > max_neg) {
                        max_neg = r6;
                        normal = Vec.new(0, 0, 1);
                    }
                    min_pos = if (r5 > min_pos) min_pos else r5;
                }
            }

            if (max_neg > min_pos)
                return null;
            if (normal.length() == 0)
                return null;
            return .{ .ti = max_neg, .normal = normal };
        }

        pub fn minkowsky_diff(r1: Cube, c2: Cube) Cube {
            const pd = c2.pos.sub(r1.pos);
            return .{
                .pos = pd.sub(r1.ext),
                .ext = r1.ext.add(c2.ext),
            };
        }

        /// Simulate a movement of aabb c1 along vector delta.
        /// Determine where it first collides with aabb c2
        pub fn detectCollision(c1: Cube, c2: Cube, delta: Vec) ?CollisionResult {
            //const delta = goal.sub(c1.pos);
            const mdiff = minkowsky_diff(c1, c2);
            var overlaps = false;
            var ti: ?f32 = null;

            var norm: Vec = Vec.new(0, 0, 0);

            //if the Minkowsky diff intersects the origin it is already overlapping
            if (containsPoint(mdiff, Vec.zero())) {
                const point = nearestCorner(mdiff, Vec.zero());
                const wi = @min(c1.ext.x(), @abs(point.x()));
                const hi = @min(c1.ext.y(), @abs(point.y()));
                const li = @min(c1.ext.z(), @abs(point.z()));
                ti = -wi * hi * li; // ti is the negative area of intersection
                overlaps = true;
            } else {
                //item tunnels into other
                if (liang_barsky(mdiff, Vec.zero(), delta)) |lb| {
                    ti = lb.ti;
                    norm = lb.normal;
                    overlaps = false;
                }
            }
            if (ti == null) return null;

            var touch = Vec.zero();
            if (overlaps) {
                var np = nearestCorner(mdiff, Vec.zero()).toArray();
                var min: usize = 0;
                //find minumum, zero all others
                for (np, 0..) |n, i| {
                    if (@abs(n) < @abs(np[min]))
                        min = i;
                }
                for (0..np.len) |i| {
                    if (i == min) continue;
                    np[i] = 0;
                }
                const n = Vec.fromSlice(&np);
                norm = n.norm();

                touch = c1.pos.add(n);
            } else {
                touch = c1.pos.add(delta.scale(ti.?));
            }

            return CollisionResult{
                .overlaps = overlaps,
                .ti = ti.?,
                .delta = delta,
                .normal = norm.negate(),
                .touch = touch.add(norm.scale(0.01)), // TODO how can we do away with this?
            };
        }
    };
}

const Ct = CollisionType(void, za.Vec3);
const Vec = za.Vec3;
const exeql = std.testing.expectEqual;

test "nearest" {
    try std.testing.expectEqual(20, Ct.nearest(0, 20, 40));
}

test "lb 3d" {
    const win = Ct.Cube{ .pos = Vec.new(0, 0, 0), .ext = Vec.new(10, 10, 10) };
    try std.testing.expectEqual(@as(?Ct.LBRes, .{ .ti = 0.05, .normal = Vec.new(-1, 0, 0) }), Ct.liang_barsky(win, Vec.new(-1, 1, 1), Vec.new(19, 1, 1)));
}

test "detect basic" {
    const moved = Ct.Cube{ .pos = Vec.new(0, 0, 0), .ext = Vec.new(1, 1, 1) };
    const other = Ct.Cube{ .pos = Vec.new(10, -1, -1), .ext = Vec.new(10, 10, 10) };

    try exeql(@as(?Ct.CollisionResult, .{
        .overlaps = false,
        .ti = 0.45,
        .delta = Vec.new(20, 0, 0),
        .normal = Vec.new(1, 0, 0),
        .touch = Vec.new(9, 0, 0),
    }), Ct.detectCollision(moved, other, Vec.new(20, 0, 0)));
}
