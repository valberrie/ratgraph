const std = @import("std");
const testing = std.testing;

pub fn SparseSet(comptime child_type: type, comptime index_type: type) type {
    if (!std.meta.trait.hasField("i")(child_type)) {
        @compileError("Child type must have a i index variable");
    } else {
        const ch: child_type = undefined;
        if (@TypeOf(ch.i) != index_type)
            @compileError("Child type i variable type must index_type");
    }

    return struct {
        const Self = @This();
        const max_index = std.math.maxInt(index_type);
        const null_marker: index_type = max_index;

        //TODO implement cool algorothim for sparse array
        //ALGO:
        //  sparse is an array of chunks.
        //  A chunk contains a sparse array and a range
        //
        //  Determine a pack factor.
        //  Whenever a sub sparse array contains too few contigous items,
        //  split it into multiple sparse sub arrays
        //  range refers to the index distance to the next sub sparse array
        //
        //  Initially:
        //      our memory looks like: sparse_arrs[sub01{data: [], range = int32_max}]
        //
        //  To store the first item at index 1000:
        //      our memory looks like: sparse_arrs[sub01{data: [], range =999}, sub02{data = [item01_dense_index], range = (arbitrary)],
        //
        //
        //

        sparse: std.ArrayList(index_type),
        dense: std.ArrayList(child_type),

        pub fn init(alloc: *const std.mem.Allocator) !Self {
            var ret = Self{ .sparse = std.ArrayList(index_type).init(alloc.*), .dense = std.ArrayList(child_type).init(alloc.*) };
            return ret;
        }

        pub fn fromOwnedDenseSlice(alloc: std.mem.Allocator, slice: []child_type) !Self {
            var ret: Self = undefined;
            ret.dense = (std.ArrayList(child_type)).fromOwnedSlice(alloc, slice);
            ret.sparse = std.ArrayList(index_type).init(alloc);

            for (ret.dense.items) |item, i| {
                if (item.i == null_marker)
                    return error.invalidIndex;

                if (item.i >= ret.sparse.items.len)
                    try ret.sparse.appendNTimes(null_marker, item.i - ret.sparse.items.len + 1);

                ret.sparse.items[item.i] = @intCast(index_type, i);
            }

            return ret;
        }

        pub fn deinit(self: *Self) void {
            self.sparse.deinit();
            self.dense.deinit();
        }

        pub fn insert(self: *Self, index: index_type, item: child_type) !void {
            if (index < self.sparse.items.len and self.sparse.items[index] != null_marker)
                return error.indexOccupied;

            if (index >= self.sparse.items.len)
                try self.sparse.appendNTimes(null_marker, index - self.sparse.items.len + 1);

            self.sparse.items[index] = @intCast(index_type, self.dense.items.len);
            var new_item = item;
            new_item.i = @intCast(index_type, index);
            try self.dense.append(new_item);
            //TODO use errdefer to prevent garbage in sparse
        }

        pub fn add(self: *Self, item: child_type) !index_type {
            //TODO more effecient lookup of empty indicies
            var empty_index: ?index_type = null;
            for (self.sparse.items) |item_index, sp_i| {
                if (item_index == null_marker and sp_i != null_marker) {
                    empty_index = @intCast(index_type, sp_i);
                    break;
                }
            }

            if (empty_index == null) {
                empty_index = @intCast(index_type, self.sparse.items.len);
                try self.sparse.append(null_marker);
            }

            self.sparse.items[empty_index.?] = @intCast(index_type, self.dense.items.len);
            var new_item = item;
            new_item.i = @intCast(index_type, empty_index.?);
            try self.dense.append(new_item);
            return empty_index.?;
        }

        pub fn get(self: *Self, index: index_type) !child_type {
            const di = try self.getDenseIndex(index);
            return self.dense.items[di];
        }

        pub fn getPtr(self: *Self, index: index_type) !*child_type {
            const di = try self.getDenseIndex(index);
            return &self.dense.items[di];
        }

        pub fn getDenseIndex(self: *Self, index: index_type) !index_type {
            if (index >= self.sparse.items.len or self.sparse.items[index] == null_marker) {
                //std.debug.print("Index {d}\n", .{index});
                return error.invalidIndex;
            }

            return self.sparse.items[index];
        }

        pub fn remove(self: *Self, index: index_type) !child_type {
            const di = try self.getDenseIndex(index);
            self.sparse.items[index] = null_marker;

            if (self.dense.items.len - 1 == di) return self.dense.pop();

            const replacement_item = self.dense.pop();
            const old_item = self.dense.items[di];
            self.sparse.items[replacement_item.i] = di;
            self.dense.items[di] = replacement_item;
            return old_item;
        }
    };
}

const ItemType = struct {
    item: []const u8,
    i: u32,
};
const SetType = SparseSet(ItemType, u32);
test "Sparse set basic usage" {
    const a = testing.allocator;
    var sset = try SetType.init(&a);
    defer sset.deinit();

    const first_id = try sset.add(.{ .item = "first item", .i = 0 });
    std.debug.print("Ret {any}\n", .{sset.get(first_id)});
    std.debug.print("len: {d}\n", .{sset.sparse.items.len});

    const next_id = 300;
    try sset.insert(next_id, .{ .item = "my item", .i = 100 });

    std.debug.print("Ret {any}\n", .{sset.get(next_id)});
    std.debug.print("len: {d}\n", .{sset.sparse.items.len});

    _ = try sset.remove(first_id);
    std.debug.print("Ret {any}\n", .{sset.get(first_id)});
    std.debug.print("len: {d}\n", .{sset.sparse.items.len});
}
