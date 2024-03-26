const std = @import("std");
const graph = @import("graphics.zig");
const Vec2f = graph.Vec2f;
//const Vec2f = struct { x: f32, y: f32 };

pub const Argument = enum {
    string,
    override,
    number,
    vec2,
    flag, //doesn't expect argument
};

pub const ArgItem = struct {
    name: []const u8,
    doc: []const u8,
    arg_type: Argument,
    type_override: ?type = null,
};

pub fn Arg(comptime name: []const u8, comptime T: Argument, comptime doc_string: []const u8) ArgItem {
    return .{ .name = name, .arg_type = T, .doc = doc_string };
}

pub fn ArgCustom(comptime name: []const u8, comptime T: type, comptime doc_string: []const u8) ArgItem {
    return .{ .name = name, .arg_type = .override, .doc = doc_string, .type_override = T };
}

// Generate a struct containing a field for each item in arg_list.
// call parseArgs(arg_list_struct, arg_iterator) to populate struct.
// parseArgs will return errors using Argumnent's doc field.
// the default argument --help will print list of args and doc string.

fn generateArgStruct(comptime arg_list: []const ArgItem) type {
    const Type = std.builtin.Type;
    var fields: [arg_list.len]Type.StructField = undefined;
    inline for (arg_list, 0..) |arg, i| {
        const T = ?switch (arg.arg_type) {
            .override => if (arg.type_override) |t| t else @compileError("Impossible"),
            .string => []const u8,
            .number => f32,
            .flag => bool,
            .vec2 => Vec2f,
        };
        fields[i] = .{ .name = arg.name, .type = T, .default_value = null, .is_comptime = false, .alignment = @alignOf(T) };
    }

    return @Type(Type{ .Struct = .{ .layout = .Auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
}

pub fn parseArgs(comptime arg_list: []const ArgItem, arg_it: anytype) !generateArgStruct(arg_list) {
    var parsed: generateArgStruct(arg_list) = undefined;
    inline for (arg_list) |field| {
        @field(parsed, field.name) = null;
    }
    const eql = std.mem.eql;
    const pf = std.fmt.parseFloat;
    const exe_name = arg_it.next() orelse return error.invalidArgIt;
    _ = exe_name;

    while (arg_it.next()) |arg| {
        var matched_arg: bool = false;
        inline for (arg_list) |field| {
            if (eql(u8, arg, "--" ++ field.name)) {
                matched_arg = true;
                @field(parsed, field.name) = switch (field.arg_type) {
                    .string => arg_it.next() orelse {
                        std.debug.print("Expected string for argument: --{s}, {s}\n", .{ field.name, field.doc });
                        return error.missingArg;
                    },
                    .number => try pf(f32, (arg_it.next() orelse {
                        std.debug.print("Expected number for argument: --{s}, {s}\n", .{ field.name, field.doc });
                        return error.missingArg;
                    })),
                    .flag => true,
                    .vec2 => blk: {
                        const x = try pf(f32, arg_it.next() orelse {
                            std.debug.print("Expected vector for argument: --{s}, {s}\n", .{ field.name, field.doc });
                            return error.missingArg;
                        });
                        const y = try pf(f32, arg_it.next() orelse {
                            std.debug.print("Expected vector for argument: --{s}, {s}\n", .{ field.name, field.doc });
                            return error.missingArg;
                        });
                        break :blk .{ .x = x, .y = y };
                    },
                    .override => blk: {
                        const info = @typeInfo(field.type_override.?);
                        switch (info) {
                            .Enum => |e| {
                                const str_name = arg_it.next() orelse {
                                    std.debug.print("Expected enum value for argument --{s}, {s}\n", .{ field.name, field.doc });
                                    std.debug.print("Possible values: \n", .{});
                                    inline for (e.fields) |f|
                                        std.debug.print("\t{s}\n", .{f.name});
                                    return error.missingArg;
                                };
                                inline for (e.fields) |f| {
                                    if (std.mem.eql(u8, f.name, str_name)) {
                                        break :blk @enumFromInt(f.value);
                                    }
                                }
                                std.debug.print("Expected enum value for argument --{s}, {s}\n", .{ field.name, field.doc });
                                std.debug.print("Possible values: \n", .{});
                                inline for (e.fields) |f|
                                    std.debug.print("\t{s}\n", .{f.name});
                                return error.invalidEnumValue;
                            },
                            else => @compileError("Unsupported custom arg type: " ++ @typeName(field.type_override.?)),
                        }
                    },
                };
            }
        }
        if (!matched_arg) {
            std.debug.print("--help:print this help\n", .{});
            inline for (arg_list) |field| {
                std.debug.print("{s}:{s}\t{s}\n", .{ field.name, @tagName(field.arg_type), field.doc });
            }
            std.process.exit(0);
        }
    }

    return parsed;
}

const TestIterator = struct {
    const Self = @This();

    args: []const []const u8,
    index: usize = 0,

    pub fn next(self: *Self) ?[]const u8 {
        if (self.index >= self.args.len)
            return null;
        defer self.index += 1;
        return self.args[self.index];
    }
};

// In normal programs std.process.ArgIterator.initWithAllocator(alloc); can be used
test "vector" {
    var test_it = TestIterator{ .args = &.{ "--my_vec", "0", "12" } };
    const args = try parseArgs(&.{
        Arg("my_vec", .vec2, "Do the vector number"),
    }, &test_it);
    if (args.parsed.my_vec) |v| {
        std.debug.print("{any}\n", .{v});
    }
}

test "basic" {
    var test_it = TestIterator{ .args = &.{ "--my_num", "0", "--level", "shits" } };
    const args = try parseArgs(&.{
        Arg("my_num", .number, "A number used for something"),
        Arg("fast", .flag, "Move the game fast"),
        Arg("level", .string, "Overide the level to load."),
    }, &test_it);

    if (args.parsed.my_num) |num| {
        std.debug.print("my num {d}\n", .{num});
    }
}
