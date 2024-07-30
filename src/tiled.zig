//TODO
//have a way to "bake" a tiled tsj file from the asset hash_map thing.
//it would take a previous version of the tileset, keeping ids constant for any existing tiles.
//It would allow tiled maps to use our texture atlas instead of a seperate one
const std = @import("std");
pub const TileMap = struct {
    pub const JTileset = struct {
        columns: u32,
        image: []const u8,
        tileheight: u32,
        tilewidth: u32,

        //A external tileset only defines these two fields
        source: ?[]const u8 = null,
        firstgid: u32,
    };

    //Only for collections of images
    pub const ExternalTileset = struct {
        pub const TileImage = struct {
            id: u32,
            image: []const u8,
            imageheight: u32,
            imagewidth: u32,

            pub fn compare(_: void, lhs: TileImage, rhs: TileImage) bool {
                return std.ascii.lessThanIgnoreCase(lhs.image, rhs.image);
            }

            pub fn compareId(_: void, l: TileImage, r: TileImage) bool {
                return l.id < r.id;
            }
        };
        tiles: []const TileImage,
        tileheight: u32, //This should be set to the maxiumum height of all tiles
        tilewidth: u32,
        tilecount: u32,
        type: enum { tileset } = .tileset,
        version: []const u8 = "1.10",
        name: []const u8,
        columns: u32 = 0,
        grid: struct {
            height: u32 = 1,
            orientation: enum { orthogonal } = .orthogonal,
            width: u32 = 1,
        } = .{},
        margin: u32 = 0,
        spacing: u32 = 0,
    };

    pub const LayerType = enum {
        tilelayer,
        imagelayer,
        objectgroup,
        group,
    };

    pub const PropertyType = enum {
        int,
        string,
        float,
        color,
        file,
        object,
        bool,
    };

    pub const PropertyValue = union(PropertyType) {
        int: i64,
        string: []const u8,
        float: f32,
        color: u32,
        file: []const u8,
        object: usize,
        bool: bool,
    };

    pub const LayerClass = enum {
        entity,
        collision,
        bg,
        entity_proto,
        component_proto,
    };

    pub const Chunk = struct { data: []u32, height: u32, width: u32, x: i32, y: i32 };

    pub const Property = struct {
        name: []const u8,
        //type: PropertyType,
        value: PropertyValue,

        pub fn jsonParse(alloc: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            if (.object_begin != try source.next()) return error.UnexpectedToken;

            var r: @This() = undefined;
            var t: PropertyType = undefined;
            var val_str: []const u8 = "";
            while (true) {
                const name_token: ?std.json.Token = try source.nextAllocMax(alloc, .alloc_if_needed, options.max_value_len.?);
                const field_name = switch (name_token.?) {
                    inline .string, .allocated_string => |slice| slice,
                    .object_end => {
                        break;
                    },
                    else => {
                        return error.UnexpectedToken;
                    },
                };
                const eql = std.mem.eql;
                if (eql(u8, field_name, "name")) {
                    r.name = try std.json.innerParse([]const u8, alloc, source, options);
                } else if (eql(u8, field_name, "type")) {
                    t = try std.json.innerParse(PropertyType, alloc, source, options);
                } else if (eql(u8, field_name, "value")) {
                    const token = try source.nextAllocMax(alloc, .alloc_always, options.max_value_len.?);
                    const slice = switch (token) {
                        inline .number, .allocated_number, .string, .allocated_string => |slice| slice,
                        inline .true => "true",
                        inline .false => "false",
                        else => return error.UnexpectedToken,
                    };
                    val_str = slice;
                }
            }

            const pf = std.fmt.parseFloat;
            r.value = switch (t) {
                .color => .{
                    .color = blk: {
                        if (val_str[0] != '#') return error.UnexpectedToken;
                        var buffer: [10]u8 = undefined;
                        const hb = std.fmt.hexToBytes(&buffer, val_str[1..val_str.len]) catch return error.UnexpectedToken;

                        break :blk @as(u32, @intCast(hb[0])) |
                            ((@as(u32, @intCast(hb[1]))) << 24) |
                            ((@as(u32, @intCast(hb[2]))) << 16) |
                            ((@as(u32, @intCast(hb[3]))) << 8);
                    },
                },
                .bool => .{ .bool = (std.mem.eql(u8, val_str, "true")) },
                .object => .{ .object = @intFromFloat(try pf(f32, val_str)) },
                .int => .{ .int = @intFromFloat(try pf(f32, val_str)) },
                .string => .{ .string = val_str },
                .float => .{ .float = try pf(f32, val_str) },
                .file => .{ .file = val_str },
            };
            return r;
        }
    };

    pub const Object = struct {
        name: []const u8,
        height: f32,
        width: f32,
        x: f32,
        y: f32,
        type: ?[]const u8 = null,
        visible: bool = true,
        gid: ?u32 = null,
        id: ?usize = null,
        properties: ?[]Property = null,
    };

    pub const Layer = struct {
        //Global fields
        type: LayerType,

        //tile fields
        data: ?[]u32 = null,
        height: ?u32 = null,
        width: ?u32 = null,
        chunks: ?[]Chunk = null,

        //img fields
        image: ?[]const u8 = null,

        //obj fields
        class: ?LayerClass = null,
        objects: ?[]Object = null,

        properties: ?[]Property = null,
    };

    infinite: bool,
    height: i32,
    layers: []Layer,

    tilesets: ?[]JTileset,

    properties: ?[]Property = null,
};

threadlocal var propertiesToStructErrorCtx: struct {
    base_type_name: []const u8 = "",
    last_property_name: ?[]const u8 = null,
    last_property_field: ?[]const u8 = null,

    pub fn printError(self: @This(), props: []const TileMap.Property) void {
        std.debug.print("{s} {s} {s}\n", .{ self.base_type_name, self.last_property_name orelse "", self.last_property_field orelse "" });
        std.debug.print("Provided properties: \n", .{});
        for (props) |p| {
            std.debug.print("{s}: {any}\n", .{ p.name, p.value });
        }
    }
} = .{};

//fix bug, this ignores namespaces
//a.g.b
//c.c.b
//both match b
//problem is names are not
pub fn parseField(
    field_name: []const u8,
    field_type: type,
    default: ?field_type,
    properties: []const TileMap.Property,
    property_mask: []bool,
    namespace_offset: usize,
) !field_type {
    //std.debug.print("BEGIN\n", .{});
    //for (properties, 0..) |p, i| {
    //    std.debug.print("\t{s} {any} {s}\n", .{ p.name, property_mask[i], field_name });
    //}
    const cinfo = @typeInfo(field_type);
    switch (cinfo) {
        .Struct => {
            propertiesToStructErrorCtx.last_property_name = @typeName(field_type);
            propertiesToStructErrorCtx.last_property_field = field_name;
            for (properties, 0..) |p, i| {
                if (property_mask[i]) {
                    const pname = if (namespace_offset >= p.name.len) {
                        property_mask[i] = false;
                        continue;
                    } else p.name[namespace_offset..];
                    const ns = if (std.mem.indexOfScalar(u8, pname, '.')) |n| pname[0..n] else pname;
                    if (!std.mem.eql(u8, field_name, ns)) {
                        property_mask[i] = false;
                    }
                }
            }
            return propertiesToStructRecur(field_type, properties, property_mask, namespace_offset + field_name.len + 1) catch |err| switch (err) {
                error.nonDefaultFieldNotProvided => {
                    if (default) |d|
                        return d;
                    return err;
                },
                else => return err,
            };
        },
        else => {
            for (properties, 0..) |p, i| {
                const pname = if (namespace_offset >= p.name.len) continue else p.name[namespace_offset..];
                if (property_mask[i] and std.mem.eql(u8, field_name, pname)) {
                    return switch (cinfo) {
                        .Bool => p.value.bool,
                        .Optional => |o| try parseField(field_name, o.child, null, properties, property_mask, namespace_offset),
                        .Int => if (p.value == .int) std.math.lossyCast(field_type, p.value.int) else std.math.lossyCast(field_type, p.value.object),
                        .Float => p.value.float,
                        .Enum => |e| blk: {
                            inline for (e.fields) |ef| {
                                if (std.mem.eql(u8, ef.name, p.value.string))
                                    break :blk @enumFromInt(ef.value);
                            }
                            std.debug.print("INVALID ENUM {s} for {s} {s}\n", .{ p.value.string, @typeName(field_type), field_name });
                            return error.invalidEnumValue;
                        },
                        .Pointer => |po| blk: {
                            if (po.size == .Slice and po.child == u8)
                                break :blk p.value.string;
                            @compileError("unable to parse type" ++ @typeName(field_type));
                        },
                        else => @compileError("unable to parse type " ++ @typeName(field_type)),
                    };
                }
            }
            if (default == null) {
                propertiesToStructErrorCtx.printError(properties);
                std.debug.print("FIELD MISSING {s} {s} \n", .{ field_name, @typeName(field_type) });
                return error.nonDefaultFieldNotProvided;
            }
        },
    }
    return default.?;
}

pub fn propertiesToStruct(struct_type: type, type_name: []const u8, properties: []const TileMap.Property, property_mask: []bool, namespace_offset: usize) !struct_type {
    propertiesToStructErrorCtx.base_type_name = type_name;
    return try propertiesToStructRecur(struct_type, properties, property_mask, namespace_offset);
}

fn propertiesToStructRecur(struct_type: type, properties: []const TileMap.Property, property_mask: []bool, namespace_offset: usize) !struct_type {
    var ret: struct_type = undefined;
    const info = @typeInfo(struct_type);
    inline for (info.Struct.fields) |field| {
        @field(ret, field.name) = try parseField(
            field.name,
            field.type,
            if (field.default_value) |dv| @as(*const field.type, @ptrCast(@alignCast(dv))).* else null,
            properties,
            property_mask,
            namespace_offset,
        );
    }
    return ret;
}

//write a new function.
//this one takes a pointer to struct_type and a single tiled.property

//a function that given a struct and an array of , attempts to fill that struct with properties, obeying namespacing
//for each nondefault field of struct, see if there is a matching field in array.
//what if not a primitive?
//do this recursively

///name_rect_map is a std.hash_map that maps png paths to rectangles
pub fn rebakeTileset(
    alloc: std.mem.Allocator,
    name_rect_map: anytype,
    dir: std.fs.Dir,
    path_prefix: []const u8, // path relative to 'dir' to prepend to each image path, should probably end in a slash
    output_filename: []const u8, // relative to dir
) !void {
    const TileImage = TileMap.ExternalTileset.TileImage;
    var aa = std.heap.ArenaAllocator.init(alloc);

    defer aa.deinit();
    const al = aa.allocator();
    const old_set: ?TileMap.ExternalTileset = blk: {
        const jslice = dir.readFileAlloc(al, output_filename, std.math.maxInt(usize)) catch break :blk null;
        const parsed = try std.json.parseFromSlice(TileMap.ExternalTileset, al, jslice, .{ .ignore_unknown_fields = true });
        break :blk parsed.value;
    };
    var it = name_rect_map.iterator();

    var tiles = std.ArrayList(TileImage).init(al);
    if (old_set) |os|
        try tiles.appendSlice(os.tiles);

    var name_id_map = std.StringHashMap(u32).init(al);
    for (tiles.items) |t|
        try name_id_map.put(t.image, t.id);

    std.sort.heap(TileImage, tiles.items, {}, TileImage.compareId);
    //start inclusive ,end exclusive. representing ids
    var freelist = std.ArrayList(struct { start: u32, end: u32 }).init(alloc); //Uses allocator instead of arena as it will be modified a lot.
    defer freelist.deinit();
    {
        var start: u32 = 0;
        if (tiles.items.len > 0) {
            for (tiles.items) |t| {
                if (start == t.id) {
                    start += 1;
                    continue;
                }
                var end = start;
                while (end < t.id) : (end += 1) {}
                try freelist.append(.{ .start = start, .end = end });
                start = t.id + 1;
            }
        }
        try freelist.append(.{ .start = start, .end = std.math.maxInt(u32) });
    }

    var max_w: u32 = 0;
    var max_h: u32 = 0;

    while (it.next()) |item| {
        var new_name = std.ArrayList(u8).init(al);
        try new_name.appendSlice(path_prefix);
        try new_name.appendSlice(item.key_ptr.*);
        try new_name.appendSlice(".png");
        if (name_id_map.get(new_name.items) != null) {
            continue;
        }
        const new_id = blk: {
            var range = &freelist.items[0];
            while (range.start == range.end) {
                _ = freelist.orderedRemove(0);
                if (freelist.items.len == 0)
                    return error.noIdsLeft;
                range = &freelist.items[0];
            }
            defer range.start += 1;
            break :blk range.start;
        };

        const h: u32 = @intFromFloat(item.value_ptr.h);
        const w: u32 = @intFromFloat(item.value_ptr.w);
        max_w = @max(max_w, w);
        max_h = @max(max_h, h);
        try tiles.append(.{
            .id = new_id,
            .image = new_name.items,
            .imageheight = h,
            .imagewidth = w,
        });
    }

    std.sort.heap(TileImage, tiles.items, {}, TileImage.compare);
    const new_tsj = TileMap.ExternalTileset{
        .tiles = tiles.items,
        .tileheight = max_h,
        .tilewidth = max_w,
        .tilecount = @intCast(tiles.items.len),
        .name = "test output",
    };
    var outfile = dir.createFile(output_filename, .{}) catch unreachable;
    std.json.stringify(new_tsj, .{}, outfile.writer()) catch unreachable;
    outfile.close();
}

//given a struct and a base.sub.field string, return the byte offset of field
pub fn getOffsetRecursive(comptime stype: type, path: []const u8, offset: usize) usize {
    const info = @typeInfo(stype);
    inline for (info.Struct.fields) |f| {
        switch (@typeInfo(f.type)) {
            .Int, .Float, .Bool => {
                if (std.mem.eql(u8, path, f.name))
                    return @offsetOf(stype, f.name) + offset;
            },
            .Struct => {
                const first_dot = std.mem.indexOfScalar(u8, path, '.');
                if (first_dot) |fd| {
                    const name = path[0..fd];
                    if (std.mem.eql(u8, name, f.name)) {
                        return getOffsetRecursive(f.type, path[fd + 1 ..], @offsetOf(stype, f.name));
                    }
                }
            },
            else => {},
        }
    }
    return 0;
}

pub fn setStructFromProperty(comptime stype: type, field_name: []const u8, ptr: *stype, name: []const u8, value: TileMap.PropertyValue) !void {
    const info = @typeInfo(stype);
    if (!std.mem.eql(u8, name, field_name) and info != .Struct)
        return error.notGOOD;
    switch (info) {
        .Int => {
            ptr.* = if (value == .int) std.math.lossyCast(stype, value.int) else std.math.lossyCast(stype, value.object);
            return;
        },
        .Struct => |s| {
            //"myname" sub = myname, name = myname
            //"my.name" sub = my, name = name
            const fd = std.mem.indexOfScalar(u8, name, '.');
            const sub_name = name[0 .. fd orelse name.len];
            if (name.len == 0)
                return;
            inline for (s.fields) |f| {
                if (std.mem.eql(u8, sub_name, f.name)) {
                    return setStructFromProperty(f.type, f.name, &@field(ptr, f.name), if (fd) |ff| name[ff + 1 ..] else name, value);
                }
            }
            return error.notFoundStructField;
        },
        .Optional => |o| {
            if (@typeInfo(o.child) == .Struct)
                return error.optNotAllowedOnStruct;
            var opt: o.child = undefined;
            defer ptr.* = opt;
            return setStructFromProperty(o.child, field_name, &opt, name, value);
        },
        .Enum => |e| {
            inline for (e.fields) |ef| {
                if (std.mem.eql(u8, ef.name, value.string)) {
                    ptr.* = @enumFromInt(ef.value);
                    return;
                }
            }
            std.debug.print("INVALID ENUM {s} for {s} {s}\n", .{ value.string, @typeName(stype), name });
            return error.invalidEnumValue;
        },
        .Float => {
            ptr.* = value.float;
            return;
        },
        .Bool => {
            ptr.* = value.bool;
            return;
        },
        .Pointer => |po| {
            if (po.size == .Slice and po.child == u8) {
                ptr.* = value.string;
                return;
            }
            @compileError("unable to parse type" ++ @typeName(stype));
        },
        else => @compileError("unable to parse type " ++ @typeName(stype)),
    }
}

test "prop2struct" {
    const S = struct {
        tex: f32 = 0,
        sub: struct {
            b: i32 = 0,
            tex: bool = false,
        } = .{},
        sus: struct {
            b: i32 = 0,
        } = .{},
    };
    var s = S{};
    try setStructFromProperty(S, "", &s, "tex", .{ .float = 68 });
    try setStructFromProperty(S, "", &s, "sub.b", .{ .int = 22 });
    try setStructFromProperty(S, "", &s, "sus.b", .{ .int = 11 });
    try setStructFromProperty(S, "", &s, "sub.tex", .{ .bool = true });
    std.debug.print("{any}\n", .{s});

    //var mask = [_]bool{ true, true, true };
    //_ = try propertiesToStruct(S, "S", &.{
    //    .{ .name = "tex", .value = .{ .int = 0 } },
    //    .{ .name = "sub.b", .value = .{ .int = 0 } },
    //    .{ .name = "sus.b", .value = .{ .int = 0 } },
    //}, &mask, 0);
}
