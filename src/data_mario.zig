const std = @import("std");
const graph = @import("graphics.zig");

pub fn genJsonType(comptime T: type) type {
    const array_list_name = @typeName(std.ArrayList(u8));
    const array_list_pre = array_list_name[0 .. std.mem.indexOfPos(u8, array_list_name, 0, "u8") orelse @compileError("broken")];
    const name = @typeName(T);
    const info = @typeInfo(T);
    switch (info) {
        .Struct => |s| {
            if ((name.len > array_list_pre.len) and std.mem.eql(u8, array_list_pre, name[0..array_list_pre.len])) {
                @compileLog("THis is an array list " ++ name);
                inline for (s.fields) |f| {
                    if (std.mem.eql(u8, f.name, "items")) {
                        const ctype = @typeInfo(f.type).Pointer.child;
                        _ = genJsonType(ctype);
                    }
                }
            } else {
                @compileLog("not array list " ++ name);
                inline for (s.fields) |f| {
                    _ = genJsonType(f.type);
                }
            }
        },
        .Pointer, .Enum, .Union => @compileError("not supported"),
        else => {},
        //else => T,
    }
    return u8;
}

pub const dd = genJsonType(Map);

pub const MapJson = struct {
    pub const Layer = struct {
        pub const Tile = struct {
            ts_name_index: u16,
            index: u16,
            x: i32,
            y: i32,
            w: i32,
            h: i32,

            pub fn lessThan(ctx: void, lhs: Tile, rhs: Tile) bool {
                _ = ctx;
                const mi = std.math.maxInt(i32);
                const lix: i64 = @intCast(lhs.x);
                const liy: i64 = @intCast(lhs.y);
                const rix: i64 = @intCast(rhs.x);
                const riy: i64 = @intCast(rhs.y);
                const l = (@as(u64, @intCast(liy + mi)) << 32) + @as(u64, @intCast((lix + mi)));
                const r = (@as(u64, @intCast(riy + mi)) << 32) + @as(u64, @intCast((rix + mi)));
                return (l < r);
            }

            pub fn order(ctx: void, lhs: Tile, rhs: Tile) std.math.Order {
                const lix: i64 = @intCast(lhs.x);
                const liy: i64 = @intCast(lhs.y);
                const rix: i64 = @intCast(rhs.x);
                const riy: i64 = @intCast(rhs.y);
                _ = ctx;
                const mi: i64 = std.math.maxInt(i32);
                const l = (@as(u64, @intCast(liy + mi)) << 32) + @as(u64, @intCast((lix + mi)));
                const r = (@as(u64, @intCast(riy + mi)) << 32) + @as(u64, @intCast((rix + mi)));
                return std.math.order(l, r);
            }
        };

        tiles: []Tile,
    };
    layers: []Layer,
    map_name: []const u8,
    tileset_name_map: [][]u8,
    ref_img_pos: graph.Rect = graph.Rec(0, 0, 0, 0),
    ref_img_path: []const u8 = "",
};

pub const Map = struct {
    const Self = @This();

    pub const Layer = struct {
        tiles: std.ArrayList(MapJson.Layer.Tile),
    };

    layers: std.ArrayList(Layer),
    map_name: std.ArrayList(u8),
    tileset_name_map: std.ArrayList(std.ArrayList(u8)),
    ref_img_pos: graph.Rect = graph.Rec(0, 0, 0, 0),
    ref_img_path: std.ArrayList(u8),

    ref_img_texture: ?graph.Texture = null,

    alloc: std.mem.Allocator,

    pub fn initFromJsonFile(alloc: std.mem.Allocator, dir: std.fs.Dir, json_filename: []const u8) !Self {
        const json_slice = try dir.readFileAlloc(alloc, json_filename, std.math.maxInt(usize));
        defer alloc.free(json_slice);

        var json_p = try std.json.parseFromSlice(MapJson, alloc, json_slice, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
        defer json_p.deinit();

        var ret: Self = .{
            .alloc = alloc,
            .layers = std.ArrayList(Layer).init(alloc),
            .map_name = std.ArrayList(u8).init(alloc),
            .tileset_name_map = std.ArrayList(std.ArrayList(u8)).init(alloc),
            .ref_img_path = std.ArrayList(u8).init(alloc),
        };
        for (json_p.value.layers) |layer| {
            try ret.layers.append(.{ .tiles = std.ArrayList(MapJson.Layer.Tile).init(alloc) });
            try ret.layers.items[ret.layers.items.len - 1].tiles.appendSlice(layer.tiles);
        }

        try ret.map_name.appendSlice(json_p.value.map_name);
        try ret.ref_img_path.appendSlice(json_p.value.ref_img_path);
        for (json_p.value.tileset_name_map) |name| {
            var new_name = std.ArrayList(u8).init(alloc);
            try new_name.appendSlice(name);
            try ret.tileset_name_map.append(new_name);
        }

        for (ret.layers.items) |*layer| {
            sortLayer(layer);
        }

        if (ret.ref_img_path.items.len > 0) {
            ret.ref_img_texture = try graph.Texture.initFromImgFile(alloc, dir, ret.ref_img_path.items, .{});
            if (ret.ref_img_pos.eql(graph.Rec(0, 0, 0, 0))) {
                ret.ref_img_pos = ret.ref_img_texture.?.rect();
            }
        }

        return ret;
    }

    pub fn sortLayer(layer: *Layer) void {
        std.sort.insertion(MapJson.Layer.Tile, layer.tiles.items, {}, MapJson.Layer.Tile.lessThan);
    }

    pub fn writeToJsonFile(self: *Self, parent_alloc: std.mem.Allocator, dir: std.fs.Dir, json_filename: []const u8) !void {
        for (self.layers.items) |*layer| {
            sortLayer(layer);
        }
        var a_alloc = std.heap.ArenaAllocator.init(parent_alloc);
        defer a_alloc.deinit();
        const alloc = a_alloc.allocator();

        var out_file = try dir.createFile(json_filename, .{});
        defer out_file.close();

        var j: MapJson = .{
            .map_name = try alloc.dupe(u8, self.map_name.items),
            .ref_img_path = try alloc.dupe(u8, self.ref_img_path.items),
            .layers = try alloc.alloc(MapJson.Layer, self.layers.items.len),
            .tileset_name_map = try alloc.alloc([]u8, self.tileset_name_map.items.len),
            .ref_img_pos = self.ref_img_pos,
        };
        for (self.layers.items, 0..) |item, i| {
            j.layers[i] = .{ .tiles = try alloc.dupe(MapJson.Layer.Tile, item.tiles.items) };
        }
        for (self.tileset_name_map.items, 0..) |item, i| {
            j.tileset_name_map[i] = try alloc.dupe(u8, item.items);
        }
        try std.json.stringify(j, .{}, out_file.writer());
    }

    pub fn deinit(self: *Self) void {
        for (self.layers.items) |*l|
            l.tiles.deinit();
        self.layers.deinit();
        self.map_name.deinit();
        for (self.tileset_name_map.items) |*item|
            item.deinit();
        self.tileset_name_map.deinit();
        self.ref_img_path.deinit();
    }

    pub fn appendLayer(self: *Self) !void {
        try self.layers.append(.{ .tiles = std.ArrayList(MapJson.Layer.Tile).init(self.alloc) });
    }

    pub fn getNearestTileIndex(self: *Self, layer_index: usize, pos: graph.Vec2f) ?usize {
        var tile: MapJson.Layer.Tile = undefined;
        tile.x = @intFromFloat(pos.x);
        tile.y = @intFromFloat(pos.y);
        if (std.sort.binarySearch(
            MapJson.Layer.Tile,
            tile,
            self.layers.items[layer_index].tiles.items,
            {},
            MapJson.Layer.Tile.order,
        )) |index| {
            return index;
        }
        return null;
    }
    pub fn getNearestTilePos(self: *Self, layer_index: usize, pos: graph.Vec2f) ?graph.Vec2f {
        if (self.getNearestTileIndex(layer_index, pos)) |index| {
            const t = self.layers.items[layer_index].tiles.items[index];
            return .{ .x = @floatFromInt(t.x), .y = @floatFromInt(t.y) };
        }
        return null;
    }

    pub fn placeTile(self: *Self, layer_index: usize, set_index: usize, tile_index: usize, pos: graph.Rect) !void {
        const xi: i32 = @intFromFloat(pos.x);
        const yi: i32 = @intFromFloat(pos.y);
        if (self.getNearestTilePos(layer_index, pos.pos())) |nearest| {
            if (@as(i32, @intFromFloat(nearest.x)) == xi and @as(i32, @intFromFloat(nearest.y)) == yi) {
                return;
            }
        }
        try self.layers.items[layer_index].tiles.append(.{
            .ts_name_index = @intCast(set_index),
            .index = @intCast(tile_index),
            .w = @intFromFloat(pos.w),
            .h = @intFromFloat(pos.h),
            .x = @intFromFloat(pos.x),
            .y = @intFromFloat(pos.y),
        });
        sortLayer(&self.layers.items[layer_index]);
    }

    pub fn removeTile(self: *Self, layer_index: usize, pos: graph.Vec2f) void {
        const xi: i32 = @intFromFloat(pos.x);
        const yi: i32 = @intFromFloat(pos.y);
        if (self.getNearestTileIndex(layer_index, pos)) |index| {
            const t = self.layers.items[layer_index].tiles.items[index];

            if (t.x == xi and t.y == yi) {
                _ = self.layers.items[layer_index].tiles.swapRemove(index);
                sortLayer(&self.layers.items[layer_index]);
            }
        }
    }

    pub fn updateAtlas(self: *Self, atlas: graph.BakedAtlas) !void {
        if (self.tileset_name_map.items.len != 0)
            return error.notImplemented;
        for (self.tileset_name_map.items) |*item|
            item.deinit();
        try self.tileset_name_map.resize(0);
        for (atlas.tilesets.items, 0..) |ts, index| {
            _ = index;
            try self.tileset_name_map.append(std.ArrayList(u8).init(self.alloc));
            try self.tileset_name_map.items[self.tileset_name_map.items.len - 1].appendSlice(ts.description);
        }
    }
};
