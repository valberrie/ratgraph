const std = @import("std");

const Types = [_]type{
    i8,   i16, i32, i64,
    u8,   u16, u32, u64,
    f16,  f32, f64, []const u8,
    bool,
};

fn typeId(comptime urtT: type) ?TypeEnum {
    comptime var T = urtT;
    const info = @typeInfo(T);
    if (info == .Enum) {
        T = info.Enum.tag_type;
    }
    inline for (Types, 0..) |ot, i| {
        if (?ot == T) return @enumFromInt(i * 2 + 1);
        if (ot == T) return @enumFromInt(i * 2);
    }
    return null;
}

const TypeEnum = blk: {
    var fields: [Types.len * 2]std.builtin.Type.EnumField = undefined;
    for (Types, 0..) |T, i| {
        fields[i * 2] = .{ .name = @typeName(T), .value = i * 2 };
        fields[i * 2 + 1] = .{ .name = "opt_" ++ @typeName(T), .value = i * 2 + 1 };
    }
    break :blk @Type(.{ .Enum = .{ .fields = &fields, .tag_type = u8, .decls = &.{}, .is_exhaustive = true } });
};

const TypeUnion = blk: {
    var fields: [Types.len * 2]std.builtin.Type.UnionField = undefined;
    for (Types, 0..) |T, i| {
        fields[i * 2] = .{ .name = @typeName(T), .type = T, .alignment = @alignOf(T) };
        fields[i * 2 + 1] = .{ .name = "opt_" ++ @typeName(T), .type = ?T, .alignment = @alignOf(?T) };
    }
    break :blk @Type(.{ .Union = .{ .fields = &fields, .decls = &.{}, .tag_type = TypeEnum, .layout = .auto } });
};

const Ta = struct {
    const MyEnum = enum(u8) { ass, wiper };
    one: f32,

    two: struct {
        a: i32,
        my_string: []const u8,
        en: MyEnum,
        opt: ?f32 = 32,
    },
};

pub const Location = struct {
    byte_offset: usize,
    t_index: TypeEnum,

    pub fn set(s: @This(), base_ptr: anytype, data: TypeUnion) !void {
        if (s.t_index != data) return error.wrongType;
        const tp: [*]u8 = @ptrCast(base_ptr);
        const info = @typeInfo(TypeUnion);
        inline for (info.Union.fields, 0..) |T, i| {
            if (i == @intFromEnum(s.t_index)) {
                const dp: *T.type = @alignCast(@ptrCast(tp + s.byte_offset));
                dp.* = @field(data, T.name);
            }
        }
    }
};

const Instruction = struct {
    byte_offset: usize,
    payload: TypeUnion,
};

//"one"
//"two.a"
pub fn resolveUrl(url: []const u8, comptime T: type, offset: usize) Location {
    const str = blk: {
        if (std.mem.indexOfScalar(u8, url, '.')) |dot_pos| {
            break :blk url[0..dot_pos];
        }
        break :blk url;
    };
    const eql = std.mem.eql;
    const Info = @typeInfo(T);
    if (Info != .Struct) unreachable;
    const S = Info.Struct;
    inline for (S.fields) |f| {
        if (eql(u8, f.name, str)) {
            const new_url = if (str.len == url.len) "" else url[str.len + 1 ..];
            if (new_url.len == 0) {
                return .{
                    .t_index = typeId(f.type) orelse unreachable,
                    .byte_offset = offset + @offsetOf(T, f.name),
                };
            } else {
                return resolveUrl(new_url, f.type, offset + @offsetOf(T, f.name));
            }
        }
    }
    unreachable;
}

pub fn attemptParse(t_id: TypeEnum, str: []const u8) !TypeUnion {
    const eql = std.mem.eql;
    const id = @intFromEnum(t_id);
    const info = @typeInfo(TypeUnion);

    inline for (info.Union.fields, 0..) |T, i| {
        if (i == id) {
            const in = @typeInfo(T.type);
            comptime var OT = T.type;
            if (in == .Optional) {
                if (eql(u8, str, "null")) {
                    return @unionInit(TypeUnion, T.name, null);
                }
                OT = in.Optional.child;
            }
            const inf = @typeInfo(OT);
            return @unionInit(TypeUnion, T.name, switch (inf) {
                .Int => try std.fmt.parseInt(OT, str, 10),
                .Float => try std.fmt.parseFloat(OT, str),
                .Bool => blk: {
                    if (eql(u8, "true", str))
                        break :blk true;
                    if (eql(u8, "false", str))
                        break :blk false;
                    return error.invalidBool;
                },
                .Pointer => |p| blk: {
                    if (p.size == .Slice and p.child == u8)
                        break :blk str; //TODO allocate dupe?
                    @compileError("not sup" ++ @typeName(OT));
                },
                else => @compileError("NOT SUP " ++ @typeName(OT)),
            });
        }
    }
    unreachable;
}
//bool
//optional

test "basic" {
    std.debug.print("SIZE OF {d}\n", .{@sizeOf(TypeUnion)});
    const inf = @typeInfo(TypeUnion);
    std.debug.print("{s}\n", .{@typeName(inf.Union.tag_type.?)});

    var t = Ta{ .one = 1, .two = .{ .a = 10, .my_string = "HELLO", .en = .ass } };
    const loc = resolveUrl("two.a", Ta, 0);
    t.one = 1;
    std.debug.print("{any}\n", .{resolveUrl("two.a", Ta, 0)});
    std.debug.print("before {any}\n", .{t});
    //try loc.uset(&t, 38);
    try loc.set(&t, .{ .i32 = 33 });
    try resolveUrl("two.my_string", Ta, 0).set(&t, .{ .@"[]const u8" = "WHAT THE FUCK" });
    try resolveUrl("two.opt", Ta, 0).set(&t, .{ .opt_f32 = null });
    try resolveUrl("two.opt", Ta, 0).set(&t, .{ .opt_f32 = 3232 });
    try resolveUrl("two.en", Ta, 0).set(&t, .{ .u8 = @intFromEnum(Ta.MyEnum.wiper) });

    const l2 = resolveUrl("two.a", Ta, 0);
    try l2.set(&t, try attemptParse(l2.t_index, "323"));

    std.debug.print("after {any}\n", .{t});
}
