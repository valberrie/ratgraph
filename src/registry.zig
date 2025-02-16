const std = @import("std");
pub const sparseset = @import("graphics/sparse_set.zig");
pub const SparseSet = sparseset.SparseSet;

pub const MapField = struct {
    ftype: type,
    name: [:0]const u8,
    allow_getPtr: bool = true,
    callback: ?struct {
        /// Called on component creation, args are user_data, *ftype, EcsIndex
        create_pointer: type = void,
        /// Called on component destroy, args are user_data, ftype, EcsIndex
        destroy_pointer: type = void,
        /// Called once on Ecs Reset, args are user_data. []const container_struct(ftype,ID_TYPE)
        reset_pointer: type = void,
        user_data: type = void,
    } = null,
};

pub fn Component(comptime name: [:0]const u8, comptime _type: type) MapField {
    return .{ .ftype = _type, .name = name };
}

pub const ComponentCreateCallback = fn (user_ctx: anytype, component: anytype) void;

pub const FieldList = []const MapField;

pub const ID_TYPE = u32;
pub const NULLMARKER = sparseset.NullMarker(ID_TYPE);

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
    callbacks: type,
    aggregate_type: type,
    file_proto_type: type,
} {
    const TypeInfo = std.builtin.Type;

    var union_fields: [fields.len]TypeInfo.UnionField = undefined;
    var reg_fields: [fields.len]TypeInfo.StructField = undefined;
    var json_fields: [fields.len]TypeInfo.StructField = undefined;

    var enum_fields: [fields.len]TypeInfo.EnumField = undefined;

    var queued_fields: [fields.len]TypeInfo.StructField = undefined;
    const num_cbs = 4;
    var callback_fields: [fields.len * num_cbs]TypeInfo.StructField = undefined;

    var big_ent_type: [fields.len]TypeInfo.StructField = undefined;
    var file_proto_types: [fields.len]TypeInfo.UnionField = undefined;

    inline for (fields, 0..) |f, lt_i| {
        //const inner_struct = container_struct(f.ftype, ID_TYPE);
        const anynull: ?f.ftype = null;
        big_ent_type[lt_i] = .{
            .name = f.name,
            .type = ?f.ftype,
            .default_value = &anynull,
            .is_comptime = false,
            .alignment = 0,
        };
        reg_fields[lt_i] = .{
            .name = f.name,
            .type = SparseSet(f.ftype, ID_TYPE),
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
        json_fields[lt_i] = .{
            .name = f.name,
            .type = struct {
                pub const Entry = struct {
                    id: ID_TYPE,
                    data: f.ftype,
                };
                entries: []Entry,
            },
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
        union_fields[lt_i] = .{
            .name = f.name,
            .type = f.ftype,
            .alignment = @alignOf(f.ftype),
        };

        //Test if f.ftype has a field called prototype and use it instead
        if (@hasDecl(f.ftype, "Prototype")) {
            file_proto_types[lt_i] = .{
                .name = f.name,
                .type = f.ftype.Prototype,
                .alignment = @alignOf(f.ftype.Prototype),
            };
        } else {
            file_proto_types[lt_i] = union_fields[lt_i];
        }

        const cb_type = if (f.callback) |cb| cb.create_pointer else void;
        callback_fields[lt_i * num_cbs] = .{
            .name = f.name ++ "create",
            .type = cb_type,
            .alignment = @alignOf(cb_type),
            .is_comptime = false,
            .default_value = null,
        };
        callback_fields[(lt_i * num_cbs) + 1] = .{
            .name = f.name ++ "data",
            .type = if (f.callback) |cb| cb.user_data else void,
            .alignment = @alignOf(if (f.callback) |cb| cb.user_data else void),
            .is_comptime = false,
            .default_value = null,
        };
        callback_fields[(lt_i * num_cbs) + 2] = .{
            .name = f.name ++ "destroy",
            .type = if (f.callback) |cb| cb.destroy_pointer else void,
            .alignment = @alignOf(if (f.callback) |cb| cb.destroy_pointer else void),
            .is_comptime = false,
            .default_value = null,
        };
        callback_fields[(lt_i * num_cbs) + 3] = .{
            .name = f.name ++ "reset",
            .type = if (f.callback) |cb| cb.reset_pointer else void,
            .alignment = @alignOf(if (f.callback) |cb| cb.reset_pointer else void),
            .is_comptime = false,
            .default_value = null,
        };
        enum_fields[lt_i] = .{
            .name = f.name,
            .value = lt_i,
        };

        queued_fields[lt_i] = .{
            .name = f.name,
            .type = std.ArrayList(f.ftype),
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
    const lt = .auto;

    return .{
        .aggregate_type = @Type(TypeInfo{ .Struct = .{
            .layout = lt,
            .fields = big_ent_type[0..],
            .decls = &.{},
            .is_tuple = false,
        } }),
        .callbacks = @Type(TypeInfo{ .Struct = .{
            .layout = lt,
            .fields = callback_fields[0..],
            .decls = &.{},
            .is_tuple = false,
        } }),
        .file_proto_type = @Type(TypeInfo{ .Union = .{
            .layout = lt,
            .fields = file_proto_types[0..],
            .decls = &.{},
            .tag_type = null,
        } }),
        .union_type = @Type(TypeInfo{ .Union = .{
            .layout = lt,
            .fields = union_fields[0..],
            .decls = &.{},
            .tag_type = EnumType,
        } }),
        .tombstone_bit = fields.len,
        .reg = @Type(TypeInfo{ .Struct = .{
            .layout = lt,
            .fields = reg_fields[0..],
            .decls = &.{},
            .is_tuple = false,
        } }),
        .json = @Type(TypeInfo{ .Struct = .{
            .layout = lt,
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
            .layout = lt,
            .fields = queued_fields[0..],
            .decls = &.{},
            .is_tuple = false,
        } }),
        .component_bit_set = std.bit_set.IntegerBitSet(fields.len + 1), //+ 1 for the tombstone bit
    };
}

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
        pub const SleepTimer = struct {
            i: ID_TYPE,
            time: usize,
        };

        callbacks: Types.callbacks,
        data: Types.reg,

        ///All entities have an entry in this array. The bitset represents what components are attached to this entity.
        entities: std.ArrayList(Types.component_bit_set),
        sleep_timers: std.ArrayList(SleepTimer),

        slept: SleptT,

        get_call_count: usize = 0,

        pub fn Type(comptime component_type: Components) type {
            return Fields[@intFromEnum(component_type)].ftype;
        }

        pub fn ContainerType(comptime component_type: Components) type {
            return sparseset.container_struct(Type(component_type), ID_TYPE);
        }

        pub fn Iterator(comptime component_type: Components) type {
            return struct {
                const childT = Fields[@intFromEnum(component_type)].ftype;
                const Ch = SparseSet(childT, ID_TYPE);
                //const childT = Fields[@intFromEnum(component_type)].ftype;
                child_it: Ch.Iterator,

                //Index into sparse, IE current entity id
                i: ID_TYPE,

                slept: *SleptT,

                pub fn next(self: *@This()) ?*childT {
                    while (self.child_it.next()) |item| {
                        if (self.slept.getOpt(self.child_it.i) == null) {
                            self.i = self.child_it.i;
                            return item;
                        }
                    }
                    return null;
                }
            };
        }

        pub fn init(alloc: std.mem.Allocator) !Self {
            var ret: Self = undefined;
            inline for (field_names_l) |comp| {
                @field(ret.data, comp.name) = try SparseSet(comp.ftype, ID_TYPE).init(alloc);
            }
            ret.entities = std.ArrayList(Types.component_bit_set).init(alloc);
            ret.slept = try SleptT.init(alloc);
            ret.sleep_timers = std.ArrayList(SleepTimer).init(alloc);

            return ret;
        }

        pub fn deinit(self: *Self) void {
            inline for (field_names_l, 0..) |field, i| {
                if (std.meta.hasFn(field.ftype, "deinit")) {
                    var t_it = self.iterator(@enumFromInt(i));
                    while (t_it.next()) |item|
                        item.deinit();
                }
                @field(self.data, field.name).deinit();
            }
            self.sleep_timers.deinit();
            self.slept.deinit();
            self.entities.deinit();
        }

        pub fn stringToComponent(string: []const u8) ?Components {
            const h = std.hash.Wyhash.hash;
            inline for (Fields, 0..) |f, i| {
                if (h(0, f.name) == h(0, string)) {
                    return @enumFromInt(i);
                }
            }
            return null;
        }

        fn call_create_callback(self: *Self, comptime component_type: Components, comp: anytype, id: ID_TYPE) void {
            const fname = @tagName(component_type) ++ "create";
            const data = @tagName(component_type) ++ "data";
            if (@TypeOf(@field(self.callbacks, fname)) != void) {
                @field(self.callbacks, fname)(@field(self.callbacks, data), comp, id);
            }
        }

        fn call_destroy_callback(self: *Self, comptime component_type: Components, comp: anytype, id: ID_TYPE) void {
            const fname = @tagName(component_type) ++ "destroy";
            const data = @tagName(component_type) ++ "data";
            if (@TypeOf(@field(self.callbacks, fname)) != void) {
                @field(self.callbacks, fname)(@field(self.callbacks, data), comp, id);
            }
        }

        fn call_reset_callback(self: *Self, comptime component_type: Components, dense: anytype, dense_lut: anytype) void {
            const fname = @tagName(component_type) ++ "reset";
            const data = @tagName(component_type) ++ "data";
            if (@TypeOf(@field(self.callbacks, fname)) != void) {
                @field(self.callbacks, fname)(@field(self.callbacks, data), dense, dense_lut);
            }
        }

        pub fn registerCallback(
            self: *Self,
            comptime component_type: Components,
            create_fn: anytype,
            destroy_fn: anytype,
            reset_fn: anytype,
            user_data: anytype,
        ) void {
            @field(self.callbacks, @tagName(component_type) ++ "create") = create_fn;
            @field(self.callbacks, @tagName(component_type) ++ "destroy") = destroy_fn;
            @field(self.callbacks, @tagName(component_type) ++ "reset") = reset_fn;
            @field(self.callbacks, @tagName(component_type) ++ "data") = user_data;
        }

        //FIXME what happens in very long running games?
        //Worst case we create and destroy 1000 entities per second
        //with 2**32 that gives us roughly 1200 hours before wraparound
        //A bigger issue is the sparse sets
        //
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

                        try @field(self.data, field.name).insert(new_ent, @field(comp, field.name));
                        ent.set(comp_i);
                        //self.call_create_callback(@enumFromInt(i), @field(comp, field.name), new_ent);
                        const ptr = try @field(self.data, field.name).getPtr(new_ent);
                        self.call_create_callback(@enumFromInt(i), ptr, new_ent);
                    }
                }
            }
            return new_ent;
        }

        pub fn destroyAll(self: *Self) !void {
            inline for (field_names_l, 0..) |field, i| {
                self.call_reset_callback(@enumFromInt(i), @field(self.data, field.name).dense.items, @field(self.data, field.name).dense_index_lut.items);
                if (std.meta.hasFn(field.ftype, "deinit")) {
                    var t_it = self.iterator(@enumFromInt(i));
                    while (t_it.next()) |item|
                        item.deinit();
                }
                try @field(self.data, field.name).empty();
            }
            try self.entities.resize(0);
        }

        pub fn destroyEntity(self: *Self, index: ID_TYPE) !void {
            const ent = try self.getEntity(index);
            inline for (field_names_l, 0..) |field, i| {
                if (ent.isSet(i)) {
                    var d = (try @field(self.data, field.name).remove(index));
                    self.call_destroy_callback(@enumFromInt(i), &d, index);
                }
            }
            ent.* = Types.component_bit_set.initEmpty();
            ent.set(Types.tombstone_bit);
        }

        pub fn isEntity(self: *Self, index: ID_TYPE) bool {
            return !((index >= self.entities.items.len) or self.entities.items[index].isSet(Types.tombstone_bit));
        }

        pub fn getEntity(self: *const Self, entity_index: ID_TYPE) !*Types.component_bit_set {
            if (entity_index >= self.entities.items.len) {
                std.debug.print("ID {d}\n", .{entity_index});
                return error.invalidEntityId;
            }

            const ent = &self.entities.items[entity_index];
            if (ent.isSet(Types.tombstone_bit)) {
                std.debug.print("ID {d}\n", .{entity_index});
                return error.invalidEntityId;
            }
            return ent;
        }

        pub fn attach(self: *Self, index: ID_TYPE, comptime component_type: Components, component: anytype) !void {
            try self.attachComponent(index, component_type, component);
        }

        pub fn attachC(self: *Self, index: ID_TYPE, component: Types.union_type) !void {
            const ent = try self.getEntity(index);
            const comp_id = @intFromEnum(component);
            inline for (field_names_l, 0..) |field, i| {
                if (i == comp_id) {
                    if (ent.isSet(i)) return error.componentAlreadyAttached;
                    try @field(self.data, field.name).insert(index, .{ .i = index, .item = @field(component, field.name) });
                    ent.set(i);
                    const ptr = try @field(self.data, field.name).getPtr(index);
                    self.call_create_callback(@enumFromInt(i), &ptr.item, index);
                    return;
                }
            }
        }

        pub fn set(self: *Self, index: ID_TYPE, comptime component_type: Components, component: anytype) !void {
            const ent = try self.getEntity(index);
            const comp: usize = @intFromEnum(component_type);
            if (!ent.isSet(comp)) return error.componentNotAttached;
            const ptr = try @field(self.data, @tagName(component_type)).getPtr(index);
            ptr.* = component;
        }

        pub fn attachComponentAndCreate(self: *Self, index: ID_TYPE, comptime component_type: Components, component: anytype) !void {
            if (!self.isEntity(index)) {
                if (index >= self.entities.items.len) { //Entity outside of range, append tombstones
                    var tomb = Types.component_bit_set.initEmpty();
                    tomb.set(Types.tombstone_bit);
                    try self.entities.appendNTimes(tomb, index - self.entities.items.len + 1);
                }
                self.entities.items[index].unset(Types.tombstone_bit);
            }
            try self.attachComponent(index, component_type, component);
        }

        pub fn attachComponent(self: *Self, index: ID_TYPE, comptime component_type: Components, component: anytype) !void {
            const comp: usize = @intFromEnum(component_type);
            const ent = try self.getEntity(index);
            if (ent.isSet(comp)) return error.componentAlreadyAttached;

            try @field(self.data, @tagName(component_type)).insert(index, component);
            ent.set(@intFromEnum(component_type));
            const ptr = try @field(self.data, @tagName(component_type)).getPtr(index);
            self.call_create_callback(component_type, ptr, index);
        }

        pub fn removeComponentOpt(self: *Self, index: ID_TYPE, comptime component_type: Components) !?Fields[@intFromEnum(component_type)].ftype {
            const comp: usize = @intFromEnum(component_type);
            const ent = try self.getEntity(index);
            if (!ent.isSet(comp)) return null;
            ent.unset(comp);
            var d = try @field(self.data, @tagName(component_type)).remove(index);
            self.call_destroy_callback(component_type, &d, index);
            return d;
        }

        pub fn removeComponent(self: *Self, index: ID_TYPE, comptime component_type: Components) !Fields[@intFromEnum(component_type)].ftype {
            return try self.removeComponentOpt(index, component_type) orelse return error.componentNotAttached;
        }

        pub fn removeAllExcept(self: *Self, index: ID_TYPE, comptime components_to_keep: []const Components) !void {
            var keeper_set = Types.component_bit_set.initEmpty();
            for (components_to_keep) |ci| {
                keeper_set.set(@intFromEnum(ci));
            }
            const ent = try self.getEntity(index);
            inline for (field_names_l, 0..) |field, i| {
                if (ent.isSet(i) and !keeper_set.isSet(i)) {
                    var d = (try @field(self.data, field.name).remove(index));
                    self.call_destroy_callback(@enumFromInt(i), &d, index);
                }
            }
            ent.* = keeper_set;
        }

        //pub fn getPtrI(self: *Self, index:ID_TYPE, comptime component_type:Components)!

        pub fn getPtrAllow(self: *Self, index: ID_TYPE, comptime component_type: Components) !*Fields[@intFromEnum(component_type)].ftype {
            self.get_call_count += 1;
            const ent = try self.getEntity(index);
            if (!ent.isSet(@intFromEnum(component_type))) return error.componentNotAttached;
            return try @field(self.data, @tagName(component_type)).getPtr(index);
        }

        pub fn getPtr(self: *Self, index: ID_TYPE, comptime component_type: Components) !*Fields[@intFromEnum(component_type)].ftype {
            if (Fields[@intFromEnum(component_type)].allow_getPtr == false)
                @compileError("allow_getPtr false on: " ++ @tagName(component_type));
            self.get_call_count += 1;
            const ent = try self.getEntity(index);
            if (!ent.isSet(@intFromEnum(component_type))) return error.componentNotAttached;
            return try @field(self.data, @tagName(component_type)).getPtr(index);
        }

        pub fn getContainer(self: *Self, index: ID_TYPE, comptime component_type: Components) !ContainerType(component_type) {
            const ent = try self.getEntity(index);
            if (!ent.isSet(@intFromEnum(component_type))) return error.componentNotAttached;
            return .{ .item = (try @field(self.data, @tagName(component_type)).getPtr(index)).*, .i = index };
        }

        pub fn get(self: *Self, index: ID_TYPE, comptime component_type: Components) !Fields[@intFromEnum(component_type)].ftype {
            return (try self.getPtrAllow(index, component_type)).*;
        }

        pub fn getOptPtr(self: *Self, index: ID_TYPE, comptime component_type: Components) !?*Fields[@intFromEnum(component_type)].ftype {
            const ent = try self.getEntity(index);
            if (!ent.isSet(@intFromEnum(component_type))) return null;
            return try self.getPtr(index, component_type);
        }

        pub fn getOpt(self: *Self, index: ID_TYPE, comptime component_type: Components) !?Fields[@intFromEnum(component_type)].ftype {
            self.get_call_count += 1;
            const ent = try self.getEntity(index);
            if (!ent.isSet(@intFromEnum(component_type))) return null;
            return try @field(self.data, @tagName(component_type)).get(index);
        }

        pub fn iterator(self: *Self, comptime component_type: Components) Iterator(component_type) {
            return .{ .child_it = @field(self.data, @tagName(component_type)).denseIterator(), .slept = &self.slept, .i = 0 };
        }

        pub fn appendWakeEvent(self: *Self, index: ID_TYPE, time: usize) !void {
            try self.sleep_timers.append(.{ .i = index, .time = time });
        }

        pub fn updateSleepTimers(self: *Self) !void {
            var delete = std.ArrayList(usize).init(self.sleep_timers.allocator);
            defer delete.deinit();
            for (self.sleep_timers.items, 0..) |*item, i| {
                if (item.time == 0) {
                    try delete.append(i);
                    try self.wakeEntity(item.i);
                } else {
                    item.time -= 1;
                }
            }
            var i: usize = delete.items.len;
            while (i > 0) : (i -= 1) {
                _ = self.sleep_timers.swapRemove(delete.items[i - 1]);
            }
        }

        pub fn sleepEntity(self: *Self, index: ID_TYPE) !void {
            self.slept.insert(index, .{}) catch |err| switch (err) {
                error.indexOccupied => {}, //We can sleep a sleeping entity
                else => return err,
            };
        }

        pub fn wakeEntity(self: *Self, index: ID_TYPE) !void {
            _ = self.slept.remove(index) catch |err| switch (err) {
                error.invalidIndex => {}, //We can wake a non sleeping entity
                else => return err,
            };
        }

        pub fn hasComponent(self: *Self, index: ID_TYPE, comptime component_type: Components) !bool {
            return (try self.getEntity(index)).isSet(@intFromEnum(component_type));
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
                .layout = .auto,
                .fields = fields[0..],
                .decls = &.{},
                .is_tuple = false,
            } });
        }

        pub fn getSetPtr(self: *Self, index: ID_TYPE, comptime set_type: type) !set_type {
            var result: set_type = undefined;
            const info = @typeInfo(set_type);
            inline for (info.Struct.fields) |field| {
                @field(result, field.name) = try @field(self.data, field.name).getPtr(index);
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
