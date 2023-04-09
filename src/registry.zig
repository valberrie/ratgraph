const std = @import("std");
const SparseSet = @import("sparse_set.zig").SparseSet;

pub const MapField = struct { ftype: type, name: []const u8 };
pub const FieldList = []const MapField;

pub const ID_TYPE = u32;

pub fn GenRegistryStructs(comptime fields: FieldList) struct {
    json: type,
    reg: type,
    component_enum: type,
    component_bit_set: type,
    queued: type,
} {
    const TypeInfo = std.builtin.Type;

    var reg_fields: [fields.len]TypeInfo.StructField = undefined;
    var json_fields: [fields.len]TypeInfo.StructField = undefined;

    var enum_fields: [fields.len]TypeInfo.EnumField = undefined;

    var queued_fields: [fields.len]TypeInfo.StructField = undefined;

    inline for (fields) |f, lt_i| {
        const inner_struct = struct { item: f.ftype, i: ID_TYPE };
        reg_fields[lt_i] = .{
            .name = f.name,
            .field_type = SparseSet(inner_struct, ID_TYPE),
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
        json_fields[lt_i] = .{
            .name = f.name,
            .field_type = []inner_struct,
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };

        enum_fields[lt_i] = .{
            .name = f.name,
            .value = lt_i,
        };

        queued_fields[lt_i] = .{
            .name = f.name,
            .field_type = std.ArrayList(inner_struct),
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }

    return .{
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
        .component_enum = @Type(TypeInfo{ .Enum = .{
            .layout = .Auto,
            .tag_type = u32,
            .fields = enum_fields[0..],
            .decls = &.{},
            .is_exhaustive = true,
        } }),
        .queued = @Type(TypeInfo{ .Struct = .{
            .layout = .Auto,
            .fields = queued_fields[0..],
            .decls = &.{},
            .is_tuple = false,
        } }),
        .component_bit_set = std.bit_set.IntegerBitSet(fields.len),
    };
}

pub fn Registry(comptime field_names_l: FieldList) type {
    return struct {
        const Self = @This();

        pub const Types = GenRegistryStructs(field_names_l);
        pub const field_list = field_names_l;
        pub const DeletionType = struct { id: ID_TYPE, component: Types.component_enum };

        data: Types.reg,

        //TODO make the api for regisetry stricter.
        //Should Iterating directly through a dense array be disallowed.
        //How do we remember to apply queued changes?

        //TODO deal with deletion
        entities: std.ArrayList(Types.component_bit_set),

        pub fn createSystemSet(comptime components: []const Types.component_enum) type {
            var fields: [components.len]std.builtin.Type.StructField = undefined;
            inline for (components) |comp, f_i| {
                fields[f_i] = .{
                    .name = field_names_l[@enumToInt(comp)].name,
                    .field_type = *field_names_l[@enumToInt(comp)].ftype,
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

        pub fn attachComponent(self: *Self, index: ID_TYPE, comptime component_type: type, component: component_type) !void {
            //TODO check if index exisits
            //const entity_mask = self.entities.items[index];
            var valid_component_type = false;
            inline for (field_names_l) |field, i| {
                if (field.ftype == component_type) {
                    valid_component_type = true;

                    self.entities.items[index].set(i);
                    try @field(self.data, field.name).insert(index, .{ .item = component, .i = index });
                }
            }
            if (!valid_component_type) {
                std.debug.print("FUCK\n", .{});
                //@compileError("Valid component type required: " ++ @typeName(@TypeOf(component)));
            }
        }

        pub fn removeComponent(self: *Self, index: ID_TYPE, component: Types.component_enum) !void {
            if (self.entities.items[index].isSet(@enumToInt(component))) {
                self.entities.items[index].unset(@enumToInt(component));
                inline for (field_names_l) |field, i| {
                    if (@enumToInt(component) == i) {
                        _ = try @field(self.data, field.name).remove(index);
                    }
                }
            }
        }

        pub fn hasComponent(self: *Self, index: ID_TYPE, comptime component: Types.component_enum) bool {
            return self.entities.items[index].isSet(@enumToInt(component));
        }

        pub fn getComponentPtr(self: *Self, index: ID_TYPE, comptime component: Types.component_enum) ?*field_names_l[@enumToInt(component)].ftype {
            if (self.entities.items[index].isSet(@enumToInt(component))) {
                return &((@field(self.data, field_names_l[@enumToInt(component)].name).getPtr(index) catch unreachable).item);
            } else {
                return null;
            }
            //return if( self.entities.items[index].isSet(@enumToInt(component))) [field_names_l[@enumToInt(component)]]
        }

        //pub fn getComponent(self: *Self, index:ID_TYPE, componont: Types.component_enum)?

        pub fn createEntity(self: *Self) !ID_TYPE {
            const index = @intCast(ID_TYPE, self.entities.items.len);
            try self.entities.append(Types.component_bit_set.initEmpty());
            return index;
        }

        pub fn destroyEntity(self: *Self, index: ID_TYPE) !void {
            //get mask
            //for each set bit remove component entry
            //remove entity from entity_set
            const mask = self.entities.items[index];
            //TODO deal with deletion from entity_set
            inline for (field_names_l) |field, i| {
                if (mask.isSet(i))
                    _ = try @field(self.data, field.name).remove(index);
            }
        }

        pub fn getEntitySetPtr(self: *Self, index: ID_TYPE, comptime system_type: type) !system_type {
            var result: system_type = undefined;
            const info = @typeInfo(system_type);
            inline for (info.Struct.fields) |field| {
                @field(result, field.name) = &((try @field(self.data, field.name).getPtr(index)).item);
            }
            return result;
        }

        pub fn getEntitySetIterator() type {
            return struct {
                pub fn init() void {}
            };
        }

        //Create a checking variable to ensure only one init function is called. Multi inits are ub;
        //TODO make init functions return self type rather than modify it
        pub fn initEmpty(self: *Self, alloc: *const std.mem.Allocator) !void {
            self.entities = std.ArrayList(Types.component_bit_set).init(alloc.*);
            self.queued_deletions = std.ArrayList(DeletionType).init(alloc.*);

            inline for (field_names_l) |field| {
                const fname = field.name;
                //@field(self.queued_additions, fname) = std.ArrayList(field.ftype).init(alloc.*);
                @field(self.queued_additions, fname) = @TypeOf(@field(self.queued_additions, fname)).init(alloc.*);

                @field(self.data, fname) = try @TypeOf(@field(self.data, fname)).init(alloc);
            }
        }

        pub fn initFromJsonFile(self: *Self, file_name: []const u8, alloc: *const std.mem.Allocator) !void {
            var level_loaded = false;
            var level_json: Types.json = undefined;

            const cwd = std.fs.cwd();
            const saved = cwd.openFile(file_name, .{}) catch null;
            if (saved) |file| {
                var buf: []const u8 = try file.readToEndAlloc(alloc.*, 1024 * 1024);
                defer alloc.free(buf);

                var token_stream = std.json.TokenStream.init(buf);
                level_json = std.json.parse(Types.json, &token_stream, .{ .allocator = alloc.*, .ignore_unknown_fields = true }) catch
                    unreachable;
                level_loaded = true;
            }

            try self.initFromJson(&level_json, alloc);
        }

        pub fn initFromJson(self: *Self, json_map: *Types.json, alloc: *const std.mem.Allocator) !void {
            self.entities = std.ArrayList(Types.component_bit_set).init(alloc.*);

            inline for (field_names_l) |field, comp_i| {
                const fname = field.name;

                @field(self.data, fname) = try @TypeOf(@field(self.data, fname)).fromOwnedDenseSlice(alloc.*, @field(json_map, fname));

                for (@field(self.data, fname).dense.items) |item| {
                    if (item.i >= self.entities.items.len)
                        try self.entities.appendNTimes(Types.component_bit_set.initEmpty(), item.i - self.entities.items.len + 1);

                    self.entities.items[item.i].set(comp_i);
                }
            }
        }

        pub fn copyToOwnedJson(self: *Self) !Types.json {
            var ret: Types.json = undefined;

            inline for (field_names_l) |field| {
                var clone = try @field(self.data, field.name).dense.clone();
                @field(ret, field.name) = clone.toOwnedSlice();
            }
            return ret;
        }

        pub fn deinitToOwnedJson(self: *Self) Types.json {
            self.entities.deinit();
            self.queued_deletions.deinit();

            var ret: Types.json = undefined;

            inline for (field_names_l) |field| {
                const fname = field.name;

                @field(self.queued_additions, field.name).deinit();

                @field(self.data, fname).sparse.deinit();
                @field(ret, fname) = @field(self.data, fname).dense.toOwnedSlice();
            }
            return ret;
        }

        pub fn deinit(self: *Self) void {
            self.entities.deinit();
            inline for (field_names_l) |field| {
                @field(self.data, field.name).deinit();
            }
        }
    };
}
