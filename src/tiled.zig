const std = @import("std");
pub const TileMap = struct {
    pub const JTileset = struct {
        columns: u32,
        image: []const u8,
        tileheight: u32,
        tilewidth: u32,
        firstgid: u32,
        //source: ?[]const u8 = null,
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

pub fn parseField(field_name: []const u8, field_type: type, default: ?field_type, properties: []const TileMap.Property, namespace_offset: usize) !field_type {
    const cinfo = @typeInfo(field_type);
    switch (cinfo) {
        .Struct => return try propertiesToStruct(field_type, properties, namespace_offset + field_name.len + 1),
        else => {
            for (properties) |p| {
                const pname = if (namespace_offset >= p.name.len) continue else p.name[namespace_offset..];
                if (std.mem.eql(u8, field_name, pname)) {
                    return switch (cinfo) {
                        .Bool => p.value.bool,
                        .Optional => |o| try parseField(field_name, o.child, null, properties, namespace_offset),
                        .Int => std.math.lossyCast(field_type, p.value.int),
                        .Float => p.value.float,
                        .Enum => |e| blk: {
                            inline for (e.fields) |ef| {
                                if (std.mem.eql(u8, ef.name, p.value.string))
                                    break :blk @enumFromInt(ef.value);
                            }
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
                std.debug.print("FIELD MISSING {s} {s}\n", .{ field_name, @typeName(field_type) });
                return error.nonDefaultFieldNotProvided;
            }
        },
    }
    return default.?;
}

pub fn propertiesToStruct(struct_type: type, properties: []const TileMap.Property, namespace_offset: usize) !struct_type {
    var ret: struct_type = undefined;
    const info = @typeInfo(struct_type);
    inline for (info.Struct.fields) |field| {
        @field(ret, field.name) = try parseField(
            field.name,
            field.type,
            if (field.default_value) |dv| @as(*const field.type, @ptrCast(@alignCast(dv))).* else null,
            properties,
            namespace_offset,
        );
    }
    return ret;
}

test "prop to struct" {
    const mys = struct {
        crass: i64,
        dookie: []const u8,
        a: struct { b: i64 },
        d: struct { g: struct { a: []const u8 } },
    };
    const props = [_]TileMap.Property{
        .{ .name = "crass", .value = .{ .int = 10 } },
        .{ .name = "a.b", .value = .{ .int = 10 } },
        .{ .name = "d.g.a", .value = .{ .string = "fuckery" } },
    };

    _ = try propertiesToStruct(mys, &props, 0);
}

//a function that given a struct and an array of , attempts to fill that struct with properties, obeying namespacing
//for each nondefault field of struct, see if there is a matching field in array.
//what if not a primitive?
//do this recursively
