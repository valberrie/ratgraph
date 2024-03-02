const std = @import("std");
const lua = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});

pub const Lua = struct {
    const Self = @This();
    pub const c = lua;
    pub const Ls = ?*lua.lua_State;
    var zstring_buffer: [512]u8 = undefined;

    state: Ls,

    pub fn init() @This() {
        var l = lua.luaL_newstate();
        lua.luaL_openlibs(l);
        return .{
            .state = l,
        };
    }

    pub fn loadAndRunFile(self: *Self, filename: [*c]const u8) void {
        const lf = lua.luaL_loadfilex(self.state, filename, "bt");
        Lua.checkError(self.state, lua.lua_pcallk(self.state, 0, lua.LUA_MULTRET, 0, 0, null));
        _ = lf;
    }

    pub fn callLuaFunction(self: *Self, fn_name: [*c]const u8) !void {
        _ = lua.lua_getglobal(self.state, fn_name);
        const err = lua.lua_pcallk(self.state, 0, 0, 0, 0, null);
        Lua.checkError(self.state, err);
        if (err != 0)
            return error.luaError;
    }

    pub fn reg(self: *Self, name: [*c]const u8, fn_: ?*const fn (Ls) callconv(.C) c_int) void {
        lua.lua_register(self.state, name, fn_);
    }

    pub fn regN(self: *Self, fns: []const struct { [*c]const u8, ?*const fn (Ls) callconv(.C) c_int }) void {
        for (fns) |fnp| {
            lua.lua_register(self.state, fnp[0], fnp[1]);
        }
    }

    pub fn checkError(L: Ls, err: c_int) void {
        if (err != 0) {
            var len: usize = 0;
            const str = lua.lua_tolstring(L, 1, &len);
            std.debug.print("{s}\n", .{str[0..len]});
            lua.lua_pop(L, 1);
        }
    }

    pub export fn printStack(L: Ls) c_int {
        std.debug.print("STACK: \n", .{});
        const top = lua.lua_gettop(L);
        var i: i32 = 1;
        while (i <= top) : (i += 1) {
            const t = lua.lua_type(L, i);
            switch (t) {
                lua.LUA_TSTRING => std.debug.print("STRING: {s}\n", .{tostring(L, i)}),
                lua.LUA_TBOOLEAN => std.debug.print("BOOL: {any}\n", .{lua.lua_toboolean(L, i)}),
                lua.LUA_TNUMBER => std.debug.print("{d}\n", .{tonumber(L, i)}),
                else => std.debug.print("{s}\n", .{lua.lua_typename(L, t)}),
            }
        }
        std.debug.print("END STACK\n", .{});
        return 0;
    }

    pub fn tonumber(L: Ls, idx: c_int) lua.lua_Number {
        var is_num: c_int = 0;
        return lua.lua_tonumberx(L, idx, &is_num);
    }

    pub fn tostring(L: Ls, idx: c_int) []const u8 {
        var len: usize = 0;
        const str = lua.lua_tolstring(L, idx, &len);
        return str[0..len];
    }

    pub fn zstring(str: []const u8) [*c]const u8 {
        std.mem.copy(u8, &zstring_buffer, str);
        zstring_buffer[str.len] = 0;
        return &zstring_buffer[0];
    }

    pub fn register(L: Ls) void {
        lua.lua_register(L, "printStack", printStack);
        lua.lua_register(L, "label", Lua.label);
        lua.lua_register(L, "checkbox", Lua.checkbox);
        lua.lua_register(L, "getArea", Lua.getArea);
        lua.lua_register(L, "beginV", Lua.beginVertical);
        lua.lua_register(L, "pushHeight", Lua.pushHeight);
        lua.lua_register(L, "endV", Lua.endVertical);
        lua.lua_register(L, "button", Lua.button);
        lua.lua_register(L, "slider", Lua.slider);
        //lua.lua_register(L, "getStruct", getStruct);
        lua.lua_register(L, "giveData", giveData);
    }

    pub fn getArg(L: Ls, comptime s: type, idx: c_int) s {
        const in = @typeInfo(s);
        return switch (in) {
            .Float => @floatCast(lua.luaL_checknumber(L, idx)),
            .Int => std.math.lossyCast(s, lua.luaL_checkinteger(L, idx)),
            .Enum => blk: {
                var len: usize = 0;
                const str = lua.luaL_checklstring(L, idx, &len);
                const h = std.hash.Wyhash.hash;
                inline for (in.Enum.fields) |f| {
                    if (h(0, f.name) == h(0, str[0..len])) {
                        break :blk @enumFromInt(f.value);
                    }
                }
            },
            .Bool => lua.lua_toboolean(L, idx) == 1,
            .Pointer => |p| {
                if (p.child == u8 and p.size == .Slice) {
                    var len: usize = 0;
                    const str = lua.luaL_checklstring(L, idx, &len);
                    //defer lua.lua_pop(L, 1);
                    return str[0..len];
                } else {
                    @compileError("Can't get slice from lua " ++ p);
                }
            },
            .Struct => {
                var ret: s = undefined;
                inline for (in.Struct.fields) |f| {
                    const lt = lua.lua_getfield(L, idx, zstring(f.name));
                    @field(ret, f.name) = switch (lt) {
                        lua.LUA_TNIL => if (f.default_value) |d| @as(*const f.type, @ptrCast(@alignCast(d))).* else undefined,
                        else => getArg(L, f.type, -1),
                    };
                    lua.lua_pop(L, 1);
                }
                return ret;
            },
            else => @compileError("getV type not supported " ++ @typeName(s)),
        };
    }

    pub fn getGlobal(L: Ls, name: []const u8, comptime s: type) s {
        _ = lua.lua_getglobal(L, zstring(name));
        switch (@typeInfo(s)) {
            .Struct => {
                return getArg(L, s, 1);
            },
            else => @compileError("not supported"),
        }
    }

    pub fn pushV(L: Ls, s: anytype) void {
        const info = @typeInfo(@TypeOf(s));
        switch (info) {
            .Struct => |st| {
                lua.lua_newtable(L);
                inline for (st.fields) |f| {
                    _ = lua.lua_pushstring(L, zstring(f.name));
                    pushV(L, @field(s, f.name));
                    lua.lua_settable(L, -3);
                }
            },
            .Enum => {
                const str = @tagName(s);
                _ = lua.lua_pushlstring(L, zstring(str), str.len);
            },
            .Optional => {
                if (s == null) {
                    lua.lua_pushnil(L);
                } else {
                    pushV(L, s.?);
                }
            },
            .Union => lua.lua_pushnil(L),
            .Float => lua.lua_pushnumber(L, s),
            .Bool => lua.lua_pushboolean(L, if (s) 1 else 0),
            .Int => lua.lua_pushinteger(L, std.math.lossyCast(i64, s)),
            .Pointer => |p| {
                if (p.size == .Slice) {
                    if (p.child == u8) {
                        _ = lua.lua_pushlstring(L, zstring(s), s.len);
                    } else {
                        lua.lua_pushnil(L);
                        return;
                    }
                } else {
                    //@compileError("Can't send slice to lua " ++ p);
                }
            },
            else => @compileError("pusnhV don't work with: " ++ s),
        }
    }

    //pub export fn getStruct(L: Ls) c_int {
    //    pushV(L, MyStruct{});
    //    return 1;
    //}

    pub export fn giveData(L: Ls) c_int {
        lua.lua_settop(L, 2);
        const d2 = getArg(L, f32, 1);
        const d3 = getArg(L, struct { num: f32, name: []const u8 }, 2);
        lua.lua_pop(L, 2);
        std.debug.print("{any} {any}\n", .{ d2, d3 });
        return 0;
    }

    //pub export fn checkbox(L: Ls) c_int {
    //    lua.lua_settop(L, 2);
    //    const str = getArg(L, []const u8, 1);
    //    var boolean = getArg(L, bool, 2);
    //    _ = os9_ctx.checkbox(str, &boolean);
    //    pushV(L, boolean);
    //    return 1;
    //}

    //pub export fn getArea(L: Ls) c_int {
    //    const area = os9_ctx.gui.getArea();
    //    if (area) |a| {
    //        pushV(L, a);
    //        return 1;
    //    }
    //    return 0;
    //}

    //pub export fn beginVertical(L: Ls) c_int {
    //    _ = L;
    //    os9_ctx.vlayout = os9_ctx.gui.beginLayout(Gui.VerticalLayout, .{ .item_height = 20 * os9_ctx.scale, .padding = .{ .bottom = 6 * os9_ctx.scale } }, .{}) catch unreachable;
    //    return 0;
    //}

    //pub export fn pushHeight(L: Ls) c_int {
    //    lua.lua_settop(L, 1);
    //    const n = getArg(L, f32, 1);
    //    if (os9_ctx.vlayout) |vl| {
    //        vl.pushHeight(@floatCast(n));
    //    }
    //    return 0;
    //}

    //pub export fn endVertical(L: Ls) c_int {
    //    _ = L;
    //    os9_ctx.gui.endLayout();
    //    os9_ctx.vlayout = null;
    //    return 0;
    //}

    //pub export fn slider(L: Ls) c_int {
    //    lua.lua_settop(L, 1);
    //    //lua.lua_checktype(L, 1, lua.LUA_TTABLE);

    //    _ = lua.lua_getfield(L, 1, "val");
    //    var val: f64 = lua.luaL_checknumber(L, -1);
    //    os9_ctx.slider(&val, 0, 100);
    //    lua.lua_pushnumber(L, val);
    //    lua.lua_setfield(L, 1, "val");

    //    return 0;
    //}

    //pub export fn button(L: Ls) c_int {
    //    lua.lua_settop(L, 1);
    //    const str = getArg(L, []const u8, 1);
    //    pushV(L, os9_ctx.button(str));
    //    return 1;
    //}

    //pub export fn label(L: Ls) c_int {
    //    lua.lua_settop(L, 1);
    //    const str = getArg(L, []const u8, 1);
    //    os9_ctx.label("{s}", .{str});
    //    return 0;
    //}
};
