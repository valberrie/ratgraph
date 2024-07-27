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
