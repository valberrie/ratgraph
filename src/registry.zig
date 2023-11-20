const std = @import("std");
const SparseSet = @import("sparse_set.zig").SparseSet;

pub const MapField = struct { ftype: type, name: []const u8 };

pub fn Component(comptime name: []const u8, comptime _type: type) MapField {
    return .{ .ftype = _type, .name = name };
}

pub const FieldList = []const MapField;

pub const ID_TYPE = u32;

fn container_struct(comptime t: type, comptime id: type) type {
    return struct { item: t, i: id = 0 };
}

//TODO to preserve iterators:
//deletions will create tombstones in dense rather than swapRemove
//additions are fine as they will be added to end of dense and our iterator can handle realloc mid iteration
//Tombstones in dense can later be removed whenever
pub fn GenRegistryStructs(comptime fields: FieldList) struct {
    tombstone_bit: usize,
    json: type,
    reg: type,
    component_enum: type,
    component_bit_set: type,
    queued: type,
    union_type: type,
} {
    const TypeInfo = std.builtin.Type;

    var union_fields: [fields.len]TypeInfo.UnionField = undefined;
    var reg_fields: [fields.len]TypeInfo.StructField = undefined;
    var json_fields: [fields.len]TypeInfo.StructField = undefined;

    var enum_fields: [fields.len]TypeInfo.EnumField = undefined;

    var queued_fields: [fields.len]TypeInfo.StructField = undefined;

    inline for (fields, 0..) |f, lt_i| {
        const inner_struct = container_struct(f.ftype, ID_TYPE);
        //const inner_struct = struct { item: f.ftype, i: ID_TYPE };
        reg_fields[lt_i] = .{
            .name = f.name,
            .type = SparseSet(inner_struct, ID_TYPE),
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
        json_fields[lt_i] = .{
            .name = f.name,
            .type = []inner_struct,
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
        union_fields[lt_i] = .{
            .name = f.name,
            .type = f.ftype,
            .alignment = @alignOf(f.ftype),
        };

        enum_fields[lt_i] = .{
            .name = f.name,
            .value = lt_i,
        };

        queued_fields[lt_i] = .{
            .name = f.name,
            .type = std.ArrayList(inner_struct),
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }
    const EnumType = @Type(TypeInfo{ .Enum = .{
        .tag_type = u32,
        .fields = enum_fields[0..],
        .decls = &.{},
        .is_exhaustive = true,
    } });

    return .{
        .union_type = @Type(TypeInfo{ .Union = .{
            .layout = .Auto,
            .fields = union_fields[0..],
            .decls = &.{},
            .tag_type = EnumType,
        } }),
        .tombstone_bit = fields.len,
        .reg = @Type(TypeInfo{ .Struct = .{
            .layout = .Auto,
            .fields = reg_fields[0..],
            .decls = &.{},
            .is_tuple = false,
        } }),
        .json = @Type(TypeInfo{ .Struct = .{
            .layout = .Auto,
            .fields = json_fields[0..],
            .decls = &.{},
            .is_tuple = false,
        } }),
        .component_enum = EnumType,
        //.component_enum = @Type(TypeInfo{ .Enum = .{
        //    .tag_type = u32,
        //    .fields = enum_fields[0..],
        //    .decls = &.{},
        //    .is_exhaustive = true,
        //} }),
        .queued = @Type(TypeInfo{ .Struct = .{
            .layout = .Auto,
            .fields = queued_fields[0..],
            .decls = &.{},
            .is_tuple = false,
        } }),
        .component_bit_set = std.bit_set.IntegerBitSet(fields.len + 1), //+ 1 for the tombstone bit
    };
}
//TODO generate a union of the types to allow for a function create(list_of_components_to_attach)
//where each item in the list is a member of union.

//TODO handle entity removal
//fn getEntity
//  Check that not greater than entities.len
//  check that entities[ent_index] != tombstone

pub fn Registry(comptime field_names_l: FieldList) type {
    return struct {
        const Self = @This();

        pub const Id = ID_TYPE;
        pub const Types = GenRegistryStructs(field_names_l);
        pub const Fields = field_names_l;
        pub const Components = Types.component_enum;
        pub const SleptT = SparseSet(struct { i: ID_TYPE = 0 }, ID_TYPE);

        data: Types.reg,

        ///All entities have an entry in this array. The bitset represents what components are attached to this entity.
        entities: std.ArrayList(Types.component_bit_set),

        slept: SleptT,

        pub fn Type(comptime component_type: Components) type {
            return Fields[@intFromEnum(component_type)].ftype;
        }

        pub fn ContainerType(comptime component_type: Components) type {
            return container_struct(Type(component_type), ID_TYPE);
        }

        pub fn Iterator(comptime component_type: Components) type {
            return struct {
                const childT = container_struct(Fields[@intFromEnum(component_type)].ftype, ID_TYPE);
                child_it: SparseSet(childT, ID_TYPE).Iterator,

                slept: *SleptT,

                pub fn next(self: *@This()) ?*childT {
                    while (self.child_it.next()) |item| {
                        if (self.slept.getOpt(item.i) == null)
                            return item;
                    }
                    return null;
                }
            };
        }

        pub fn init(alloc: std.mem.Allocator) !Self {
            var ret: Self = undefined;
            inline for (field_names_l) |comp| {
                @field(ret.data, comp.name) = try SparseSet(container_struct(comp.ftype, ID_TYPE), ID_TYPE).init(alloc);
            }
            ret.entities = std.ArrayList(Types.component_bit_set).init(alloc);
            ret.slept = try SleptT.init(alloc);

            return ret;
        }

        pub fn deinit(self: *Self) void {
            self.slept.deinit();
            self.entities.deinit();
            inline for (field_names_l) |field| {
                @field(self.data, field.name).deinit();
            }
        }

        pub fn createEntity(self: *Self) !ID_TYPE {
            const index = @as(ID_TYPE, @intCast(self.entities.items.len));
            try self.entities.append(Types.component_bit_set.initEmpty());
            return index;
        }

        pub fn create(self: *Self, components: []const Types.union_type) !ID_TYPE {
            const new_ent = try self.createEntity();
            const ent = try self.getEntity(new_ent);
            for (components) |comp| {
                inline for (field_names_l, 0..) |field, i| {
                    const comp_i: usize = @intFromEnum(comp);
                    if (comp_i == i) {
                        if (ent.isSet(comp_i)) return error.componentAlreadyAttached;

                        try @field(self.data, field.name).insert(new_ent, .{ .i = new_ent, .item = @field(comp, field.name) });
                        ent.set(comp_i);
                    }
                }
            }
            return new_ent;
        }

        pub fn destroyAll(self: *Self) !void {
            inline for (field_names_l) |field| {
                try @field(self.data, field.name).empty();
            }
            try self.entities.resize(0);
        }

        pub fn destroyEntity(self: *Self, index: ID_TYPE) !void {
            const ent = try self.getEntity(index);
            inline for (field_names_l, 0..) |field, i| {
                if (ent.isSet(i)) {
                    _ = (try @field(self.data, field.name).remove(index));
                }
            }
            ent.* = Types.component_bit_set.initEmpty();
            ent.set(Types.tombstone_bit);
        }

        pub fn getEntity(self: *const Self, entity_index: ID_TYPE) !*Types.component_bit_set {
            if (entity_index >= self.entities.items.len) return error.invalidEntityId;
            const ent = &self.entities.items[entity_index];
            if (ent.isSet(Types.tombstone_bit)) return error.invalidEntityId;
            return ent;
        }

        pub fn attach(self: *Self, index: ID_TYPE, comptime component_type: Components, component: anytype) !void {
            try self.attachComponent(index, component_type, component);
        }

        pub fn set(self: *Self, index: ID_TYPE, comptime component_type: Components, component: anytype) !void {
            const ent = try self.getEntity(index);
            const comp: usize = @intFromEnum(component_type);
            if (!ent.isSet(comp)) return error.componentNotAttached;
            const ptr = try @field(self.data, @tagName(component_type)).getPtr(index);
            ptr.item = component;
        }

        pub fn attachComponent(self: *Self, index: ID_TYPE, comptime component_type: Components, component: anytype) !void {
            const comp: usize = @intFromEnum(component_type);
            const ent = try self.getEntity(index);
            if (ent.isSet(comp)) return error.componentAlreadyAttached;

            try @field(self.data, @tagName(component_type)).insert(index, .{ .i = index, .item = component });
            ent.set(@intFromEnum(component_type));
        }

        pub fn removeComponent(self: *Self, index: ID_TYPE, comptime component_type: Components) !Fields[@intFromEnum(component_type)].ftype {
            const comp: usize = @intFromEnum(component_type);
            const ent = try self.getEntity(index);
            if (!ent.isSet(comp)) return error.componentNotAttached;
            ent.unset(comp);
            return (try @field(self.data, @tagName(component_type)).remove(index)).item;
        }

        pub fn removeAllExcept(self: *Self, index: ID_TYPE, comptime components_to_keep: []const Components) !void {
            var keeper_set = Types.component_bit_set.initEmpty();
            for (components_to_keep) |ci| {
                keeper_set.set(@intFromEnum(ci));
            }
            const ent = try self.getEntity(index);
            inline for (field_names_l, 0..) |field, i| {
                if (ent.isSet(i) and !keeper_set.isSet(i)) {
                    _ = (try @field(self.data, field.name).remove(index));
                }
            }
            ent.* = keeper_set;
        }

        //pub fn getPtrI(self: *Self, index:ID_TYPE, comptime component_type:Components)!

        pub fn getPtr(self: *Self, index: ID_TYPE, comptime component_type: Components) !*Fields[@intFromEnum(component_type)].ftype {
            const ent = try self.getEntity(index);
            if (!ent.isSet(@intFromEnum(component_type))) return error.componentNotAttached;
            return &((try @field(self.data, @tagName(component_type)).getPtr(index)).item);
        }

        pub fn getContainer(self: *Self, index: ID_TYPE, comptime component_type: Components) !ContainerType(component_type) {
            const ent = try self.getEntity(index);
            if (!ent.isSet(@intFromEnum(component_type))) return error.componentNotAttached;
            return (try @field(self.data, @tagName(component_type)).getPtr(index)).*;
        }

        pub fn get(self: *Self, index: ID_TYPE, comptime component_type: Components) !Fields[@intFromEnum(component_type)].ftype {
            return (try self.getPtr(index, component_type)).*;
        }

        pub fn getOpt(self: *Self, index: ID_TYPE, comptime component_type: Components) !?Fields[@intFromEnum(component_type)].ftype {
            const ent = try self.getEntity(index);
            if (!ent.isSet(@intFromEnum(component_type))) return null;
            return (try @field(self.data, @tagName(component_type)).get(index)).item;
        }

        pub fn iterator(self: *Self, comptime component_type: Components) Iterator(component_type) {
            return .{ .child_it = @field(self.data, @tagName(component_type)).denseIterator(), .slept = &self.slept };
        }

        pub fn sleepEntity(self: *Self, index: ID_TYPE) !void {
            try self.slept.insert(index, .{});
        }

        pub fn wakeEntity(self: *Self, index: ID_TYPE) !void {
            _ = try self.slept.remove(index);
        }

        //pub fn iterator(self: *Self, comptime component_type: Components) SparseSet(container_struct(Fields[@intFromEnum(component_type)].ftype, ID_TYPE), ID_TYPE).Iterator {
        //    return @field(self.data, @tagName(component_type)).denseIterator();
        //}

        pub fn printEntityInfo(self: *Self, index: ID_TYPE) void {
            std.debug.print("Entity Info: {d}\n", .{index});
            const ent = self.getEntity(index) catch {
                std.debug.print("\tError: Entity does not exist!\n", .{});
                return;
            };
            inline for (field_names_l, 0..) |field, i| {
                if (ent.isSet(i)) {
                    std.debug.print("\tcomponent: {d} {s}\n", .{ i, field.name });
                }
            }
        }

        pub fn setType(comptime components: []const Types.component_enum) type {
            var fields: [components.len]std.builtin.Type.StructField = undefined;
            inline for (components, 0..) |comp, f_i| {
                fields[f_i] = .{
                    .name = field_names_l[@intFromEnum(comp)].name,
                    .type = *field_names_l[@intFromEnum(comp)].ftype,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = 0,
                };
            }

            return @Type(std.builtin.Type{ .Struct = .{
                .layout = .Auto,
                .fields = fields[0..],
                .decls = &.{},
                .is_tuple = false,
            } });
        }

        pub fn getSetPtr(self: *Self, index: ID_TYPE, comptime set_type: type) !set_type {
            var result: set_type = undefined;
            const info = @typeInfo(set_type);
            inline for (info.Struct.fields) |field| {
                @field(result, field.name) = &((try @field(self.data, field.name).getPtr(index)).item);
            }
            return result;
        }

        //pub fn getEntitySetIterator() type {
        //    return struct {
        //        pub fn init() void {}
        //    };
        //}

        //Create a checking variable to ensure only one init function is called. Multi inits are ub;
        //TODO make init functions return self type rather than modify it
        //pub fn initEmpty(self: *Self, alloc: *const std.mem.Allocator) !void {
        //    self.entities = std.ArrayList(Types.component_bit_set).init(alloc.*);
        //    self.queued_deletions = std.ArrayList(DeletionType).init(alloc.*);

        //    inline for (field_names_l) |field| {
        //        const fname = field.name;
        //        //@field(self.queued_additions, fname) = std.ArrayList(field.ftype).init(alloc.*);
        //        @field(self.queued_additions, fname) = @TypeOf(@field(self.queued_additions, fname)).init(alloc.*);

        //        @field(self.data, fname) = try @TypeOf(@field(self.data, fname)).init(alloc);
        //    }
        //}

        //pub fn initFromJsonFile(self: *Self, file_name: []const u8, alloc: *const std.mem.Allocator) !void {
        //    var level_loaded = false;
        //    var level_json: Types.json = undefined;

        //    const cwd = std.fs.cwd();
        //    const saved = cwd.openFile(file_name, .{}) catch null;
        //    if (saved) |file| {
        //        var buf: []const u8 = try file.readToEndAlloc(alloc.*, 1024 * 1024);
        //        defer alloc.free(buf);

        //        var token_stream = std.json.TokenStream.init(buf);
        //        level_json = std.json.parse(Types.json, &token_stream, .{ .allocator = alloc.*, .ignore_unknown_fields = true }) catch
        //            unreachable;
        //        level_loaded = true;
        //    }

        //    try self.initFromJson(&level_json, alloc);
        //}

        //pub fn initFromJson(self: *Self, json_map: *Types.json, alloc: *const std.mem.Allocator) !void {
        //    self.entities = std.ArrayList(Types.component_bit_set).init(alloc.*);

        //    inline for (field_names_l, 0..) |field, comp_i| {
        //        const fname = field.name;

        //        @field(self.data, fname) = try @TypeOf(@field(self.data, fname)).fromOwnedDenseSlice(alloc.*, @field(json_map, fname));

        //        for (@field(self.data, fname).dense.items) |item| {
        //            if (item.i >= self.entities.items.len)
        //                try self.entities.appendNTimes(Types.component_bit_set.initEmpty(), item.i - self.entities.items.len + 1);

        //            self.entities.items[item.i].set(comp_i);
        //        }
        //    }
        //}

        //pub fn copyToOwnedJson(self: *Self) !Types.json {
        //    var ret: Types.json = undefined;

        //    inline for (field_names_l) |field| {
        //        var clone = try @field(self.data, field.name).dense.clone();
        //        @field(ret, field.name) = try clone.toOwnedSlice();
        //    }
        //    return ret;
        //}

        //pub fn deinitToOwnedJson(self: *Self) Types.json {
        //    self.entities.deinit();
        //    self.queued_deletions.deinit();

        //    var ret: Types.json = undefined;

        //    inline for (field_names_l) |field| {
        //        const fname = field.name;

        //        @field(self.queued_additions, field.name).deinit();

        //        @field(self.data, fname).sparse.deinit();
        //        @field(ret, fname) = @field(self.data, fname).dense.toOwnedSlice();
        //    }
        //    return ret;
        //}
    };
}

const TestEcs = Registry(&.{
    Component("pos", struct { x: i32, y: i32 }),
    Component("animation", struct { len: i32 }),
    Component("empty", struct {}),
});

//adding and removing componesnt to live entities
//Reming entire entities and all components.
//Iterating a set

test "Basic Registry Usage" {
    const expectError = std.testing.expectError;
    const alloc = std.testing.allocator;
    var ecs = try TestEcs.init(alloc);
    defer ecs.deinit();

    const ent_1 = try ecs.createEntity();
    try ecs.attachComponent(ent_1, .pos, .{ .x = 1, .y = 2 });
    try ecs.attachComponent(ent_1, .animation, .{ .len = 3 });
    try ecs.attachComponent(ent_1, .empty, .{});

    try expectError(error.invalidEntityId, ecs.attachComponent(100, .empty, .{})); //entity 100 should not exist
    try expectError(error.componentAlreadyAttached, ecs.attachComponent(ent_1, .empty, .{})); //we should not be allowed to attach twice

    _ = try ecs.removeComponent(ent_1, .pos);
    try ecs.destroyEntity(ent_1);
}
