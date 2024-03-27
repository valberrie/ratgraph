const c = @import("c.zig");
pub const za = @import("zalgebra");
const std = @import("std");
pub const glID = c.GLuint;
const ptypes = @import("types.zig");
const Vec2f = ptypes.Vec2f;
const Vec2i = ptypes.Vec2i;
const Vec3f = ptypes.Vec3f;
const Color = ptypes.Color;
const CharColor = ptypes.CharColor;
const Rect = ptypes.Rect;
const V3 = za.Vec3;
const itc = ptypes.itc;

pub const Vertex = packed struct { x: f32, y: f32, z: f32, r: f32, g: f32, b: f32, a: f32 };

const log = std.log.scoped(.GL);
pub const PrimitiveMode = enum(u32) {
    points = c.GL_POINTS,
    line_strip = c.GL_LINE_STRIP,
    line_loop = c.GL_LINE_LOOP,
    lines = c.GL_LINES,
    line_strip_adjacency = c.GL_LINE_STRIP_ADJACENCY,
    lines_adjacency = c.GL_LINES_ADJACENCY,
    triangle_strip = c.GL_TRIANGLE_STRIP,
    triangle_fan = c.GL_TRIANGLE_FAN,
    triangles = c.GL_TRIANGLES,
    triangle_strip_adjacency = c.GL_TRIANGLE_STRIP_ADJACENCY,
    triangles_adjacency = c.GL_TRIANGLES_ADJACENCY,
    patches = c.GL_PATCHES,
};

pub fn checkError() void {
    var err = c.glGetError();
    while (err != c.GL_NO_ERROR) : (err = c.glGetError()) {
        const str = switch (err) {
            c.GL_INVALID_ENUM => "An unacceptable value is specified for an enumerated argument. The offending command is ignored and has no other side effect than to set the error flag.",
            c.GL_INVALID_VALUE => "A numeric argument is out of range. The offending command is ignored and has no other side effect than to set the error flag.",
            c.GL_INVALID_OPERATION => "The specified operation is not allowed in the current state. The offending command is ignored and has no other side effect than to set the error flag.",
            c.GL_INVALID_FRAMEBUFFER_OPERATION => "The framebuffer object is not complete. The offending command is ignored and has no other side effect than to set the error flag.",
            c.GL_OUT_OF_MEMORY => "There is not enough memory left to execute the command. The state of the GL is undefined, except for the state of the error flags, after this error is recorded.",
            c.GL_STACK_UNDERFLOW => "An attempt has been made to perform an operation that would cause an internal stack to underflow.",
            c.GL_STACK_OVERFLOW => "An attempt has been made to perform an operation that would cause an internal stack to overflow.",
            else => unreachable,
        };
        log.warn("glGetError: {s}", .{str});
    }
}

pub fn passUniform(shader: c_uint, uniform_name: [*c]const u8, data: anytype) void {
    const uniform_location = c.glGetUniformLocation(shader, uniform_name);
    switch (@TypeOf(data)) {
        za.Mat4 => c.glUniformMatrix4fv(uniform_location, 1, c.GL_FALSE, &data.data[0][0]),
        else => @compileError("GL.passUniform type not implemented: " ++ @typeName(@TypeOf(data))),
    }
}

pub fn bufferData(buffer_type: glID, handle: glID, comptime item: type, slice: []item) void {
    c.glBindBuffer(buffer_type, handle);
    c.glBufferData(
        buffer_type,
        @as(c_long, @intCast(slice.len)) * @sizeOf(item),
        slice.ptr,
        c.GL_STATIC_DRAW,
    );
    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
}

pub fn generateVertexAttributes(vao: c_uint, vbo: c_uint, comptime T: anytype) void {
    const info = @typeInfo(T);
    switch (info) {
        .Struct => {
            const st = info.Struct;
            if (st.layout != .Packed) @compileError("generateVertexAttributes only supports packed structs");
            inline for (st.fields, 0..) |field, f_i| {
                switch (field.type) {
                    Vec2f => floatVertexAttrib(vao, vbo, f_i, 2, T, field.name),
                    Vec3f => floatVertexAttrib(vao, vbo, f_i, 3, T, field.name),
                    u16 => intVertexAttrib(vao, vbo, f_i, 1, T, field.name, c.GL_UNSIGNED_SHORT),
                    u32 => intVertexAttrib(vao, vbo, f_i, 1, T, field.name, c.GL_UNSIGNED_INT),
                    else => @compileError("generateVertexAttributes struct field type not supported: " ++ @typeName(field.field_type)),
                }
            }
        },
        else => @compileError("generateVertexAttributes expects a struct"),
    }
}

pub fn bufferSubData(buffer_type: glID, handle: glID, offset: usize, len: usize, comptime item: type, slice: []item) void {
    c.glBindBuffer(buffer_type, handle);
    c.glBufferSubData(
        buffer_type,
        @as(c_long, @intCast(offset)) * @sizeOf(item),
        @as(c_long, @intCast(len)) * @sizeOf(item),
        &slice[offset],
    );

    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
}

pub fn intVertexAttrib(vao: glID, vbo: glID, index: u32, num_elem: u32, comptime item: type, comptime starting_field: []const u8, int_type: c.GLenum) void {
    c.glBindVertexArray(vao);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    defer c.glBindVertexArray(0);
    defer c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

    const byte_offset = @offsetOf(item, starting_field);
    c.glVertexAttribIPointer(
        index,
        @as(c_int, @intCast(num_elem)),
        int_type,
        @sizeOf(item),
        if (byte_offset != 0) @as(*const anyopaque, @ptrFromInt(byte_offset)) else null,
    );
    c.glEnableVertexAttribArray(index);
}

pub fn floatVertexAttrib(vao: glID, vbo: glID, index: u32, size: u32, comptime item: type, comptime starting_field: []const u8) void {
    c.glBindVertexArray(vao);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    defer c.glBindVertexArray(0);
    defer c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

    const byte_offset = @offsetOf(item, starting_field);
    c.glVertexAttribPointer(
        index,
        @as(c_int, @intCast(size)),
        c.GL_FLOAT,
        c.GL_FALSE,
        @sizeOf(item),
        if (byte_offset != 0) @as(*const anyopaque, @ptrFromInt(byte_offset)) else null,
    );
    c.glEnableVertexAttribArray(index);
}

pub fn simpleDrawBatch(view: za.Mat4, model: za.Mat4, batch: anytype, has_ebo: bool) void {
    c.glUseProgram(batch.shader);
    c.glBindVertexArray(batch.vao);

    bufferData(c.GL_ARRAY_BUFFER, batch.vbo, Vertex, batch.vertices.items);
    if (has_ebo)
        bufferData(c.GL_ELEMENT_ARRAY_BUFFER, batch.ebo, u32, batch.indicies.items);

    c.glBindTexture(c.GL_TEXTURE_2D, 0);

    passUniform(batch.shader, "view", view);
    passUniform(batch.shader, "model", model);

    c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(batch.indicies.items.len)), c.GL_UNSIGNED_INT, null);
    //c.glBindVertexArray(0);

}

pub const Plane = enum { xy, yz, xz };
pub fn vertexTexturedDir(plane: Plane, x: f32, y: f32, z: f32, u: f32, v: f32, col: Color) VertexTextured {
    const p: struct { x: f32, y: f32, z: f32, u: f32, v: f32 } = switch (plane) {
        .xy => .{ .x = x, .y = y, .z = z, .u = u, .v = v },
        .yz => .{ .x = y, .y = z, .z = x, .u = u, .v = v },
        .xz => .{ .x = x, .y = z, .z = y, .u = u, .v = v },
    };
    return .{ .x = p.x, .y = p.y, .z = p.z, .u = p.u, .v = p.v, .r = col[0], .g = col[1], .b = col[2], .a = col[3] };
}

pub fn quadTex(pos: V3, w: f32, h: f32, plane: Plane, neg: bool, tr: Rect, tx_w: u32, tx_h: u32, color: CharColor) [4]VertexTextured {
    const un = normalizeTexRect(tr, tx_w, tx_h);
    const col = color.toFloat();
    const p: struct { x: f32, y: f32, z: f32 } = .{ .x = pos.data[0], .y = pos.data[1], .z = pos.data[2] };
    // zig fmt: off
    if (neg) {
        return .{
            vertexTexturedDir(plane, p.x,     p.y + h, p.z, un.x       , un.y + un.h, col),
            vertexTexturedDir(plane, p.x + w, p.y + h, p.z, un.x       , un.y       , col),
            vertexTexturedDir(plane, p.x + w, p.y,     p.z, un.x + un.w, un.y       , col),
            vertexTexturedDir(plane, p.x,     p.y,     p.z, un.x + un.w, un.y + un.h, col),
        };
    } else {
        return .{
            vertexTexturedDir(plane, p.x,     p.y,     p.z, un.x + un.w, un.y + un.h, col),
            vertexTexturedDir(plane, p.x + w, p.y,     p.z, un.x + un.w, un.y       , col),
            vertexTexturedDir(plane, p.x + w, p.y + h, p.z, un.x       , un.y       , col),
            vertexTexturedDir(plane, p.x,     p.y + h, p.z, un.x       , un.y + un.h, col),
        };
    }
    // zig fmt: on
}

pub fn cube(px: f32, py: f32, pz: f32, sx: f32, sy: f32, sz: f32, tr: Rect, tx_w: u32, tx_h: u32, colorsopt: ?[]const CharColor) [24]VertexTextured {
    const colors = if (colorsopt) |cc| cc else &[6]CharColor{
        itc(0x888888ff), //Front
        itc(0x888888ff), //Back
        itc(0x666666ff), //Bottom
        itc(0xffffffff), //Top
        itc(0xaaaaaaff),
        itc(0xaaaaaaff),
    };
    const un = normalizeTexRect(tr, @as(i32, @intCast(tx_w)), @as(i32, @intCast(tx_h)));
    // zig fmt: off
    return [_]VertexTextured{
        // front
        vertexTextured(px + sx, py + sy, pz, un.x + un.w, un.y + un.h, colors[0].toFloat()), //0
        vertexTextured(px + sx, py     , pz, un.x + un.w, un.y       , colors[0].toFloat()), //1
        vertexTextured(px     , py     , pz, un.x       , un.y       , colors[0].toFloat()), //2
        vertexTextured(px     , py + sy, pz, un.x       , un.y + un.h, colors[0].toFloat()), //3

        // back
        vertexTextured(px     , py + sy, pz + sz, un.x       , un.y + un.h, colors[1].toFloat()), //3
        vertexTextured(px     , py     , pz + sz, un.x       , un.y       , colors[1].toFloat()), //2
        vertexTextured(px + sx, py     , pz + sz, un.x + un.w, un.y       , colors[1].toFloat()), //1
        vertexTextured(px + sx, py + sy, pz + sz, un.x + un.w, un.y + un.h, colors[1].toFloat()), //0


        vertexTextured(px + sx, py, pz,      un.x+un.w,un.y + un.h, colors[2].toFloat()),
        vertexTextured(px + sx, py, pz + sz, un.x+un.w,un.y, colors[2].toFloat()),
        vertexTextured(px     , py, pz + sz, un.x,un.y, colors[2].toFloat()),
        vertexTextured(px     , py, pz     , un.x,un.y + un.h, colors[2].toFloat()),

        vertexTextured(px     , py + sy, pz     , un.x,un.y + un.h, colors[3].toFloat()),
        vertexTextured(px     , py + sy, pz + sz, un.x,un.y, colors[3].toFloat()),
        vertexTextured(px + sx, py + sy, pz + sz, un.x + un.w,un.y, colors[3].toFloat()),
        vertexTextured(px + sx, py + sy, pz, un.x + un.w,   un.y + un.h , colors[3].toFloat()),

        vertexTextured(px, py + sy, pz, un.x + un.w,un.y + un.h,colors[4].toFloat()),
        vertexTextured(px, py , pz, un.x + un.w,un.y,colors[4].toFloat()),
        vertexTextured(px, py , pz + sz, un.x,un.y,colors[4].toFloat()),
        vertexTextured(px, py + sy , pz + sz, un.x,un.y + un.h,colors[4].toFloat()),

        vertexTextured(px + sx, py + sy , pz + sz, un.x,un.y + un.h,colors[5].toFloat()),
        vertexTextured(px + sx, py , pz + sz, un.x,un.y,colors[5].toFloat()),
        vertexTextured(px + sx, py , pz, un.x + un.w,un.y,colors[5].toFloat()),
        vertexTextured(px + sx, py + sy, pz, un.x + un.w,un.y + un.h,colors[5].toFloat()),


    };
    // zig fmt: on

}

pub fn genCubeIndicies(index: u32) [36]u32 {
    return [_]u32{
        index + 0,
        index + 1,
        index + 3,
        index + 1,
        index + 2,
        index + 3,

        index + 4,
        index + 5,
        index + 7,
        index + 5,
        index + 6,
        index + 7,

        index + 8,
        index + 9,
        index + 11,
        index + 9,
        index + 10,
        index + 11,

        index + 12,
        index + 13,
        index + 15,
        index + 13,
        index + 14,
        index + 15,

        index + 16,
        index + 17,
        index + 19,
        index + 17,
        index + 18,
        index + 19,

        index + 20,
        index + 21,
        index + 23,
        index + 21,
        index + 22,
        index + 23,
    };
}
pub fn createQuadTextured(r: Rect, z: f32, tr: Rect, tx_w: i32, tx_h: i32, color: Color) [4]VertexTextured {
    const un = normalizeTexRect(tr, tx_w, tx_h);
    // zig fmt: off
    return [_]VertexTextured {
        vertexTextured(r.x + r.w, r.y + r.h, z, un.x + un.w, un.y + un.h, color), //0
        vertexTextured(r.x + r.w, r.y      , z, un.x + un.w, un.y       , color), //1
        vertexTextured(r.x      , r.y      , z, un.x       , un.y       , color), //2
        vertexTextured(r.x      , r.y + r.h, z, un.x       , un.y + un.h, color), //3
    };
    // zig fmt: on
}
pub fn createQuadColor(r: Rect, z: f32, color: [4]CharColor) [4]Vertex {
    return [_]Vertex{
        vertex(r.x + r.w, r.y + r.h, z, color[2].toFloat()), //low right
        vertex(r.x + r.w, r.y, z, color[3].toFloat()), //up right
        vertex(r.x, r.y, z, color[0].toFloat()), //up left
        vertex(r.x, r.y + r.h, z, color[1].toFloat()), //low left
    };
}

pub fn createQuad(r: Rect, z: f32, color: Color) [4]Vertex {
    return [_]Vertex{
        vertex(r.x + r.w, r.y + r.h, z, color),
        vertex(r.x + r.w, r.y, z, color),
        vertex(r.x, r.y, z, color),
        vertex(r.x, r.y + r.h, z, color),
    };
}

pub fn normalizeTexRect(tr: Rect, tx_w: i32, tx_h: i32) Rect {
    const tw = @as(f32, @floatFromInt(tx_w));
    const th = @as(f32, @floatFromInt(tx_h));
    return .{
        .x = tr.x / tw,
        .y = tr.y / th,
        .w = tr.w / tw,
        .h = tr.h / th,
    };
}
pub const VertexTextured = packed struct { x: f32, y: f32, z: f32, u: f32, v: f32, r: f32, g: f32, b: f32, a: f32 };

pub fn vertex(x: f32, y: f32, z: f32, col: Color) Vertex {
    return .{ .x = x, .y = y, .z = z, .r = col[0], .g = col[1], .b = col[2], .a = col[3] };
}

pub fn vertexTextured(x: f32, y: f32, z: f32, u: f32, v: f32, col: Color) VertexTextured {
    return .{ .x = x, .y = y, .z = z, .u = u, .v = v, .r = col[0], .g = col[1], .b = col[2], .a = col[3] };
}
