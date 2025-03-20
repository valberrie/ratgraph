const std = @import("std");

///Much of this is copied from std.unicode.Utf8Iterator
pub const BiDirectionalUtf8Iterator = struct {
    bytes: []const u8,
    i: usize,

    pub fn nextCodepointSlice(it: *BiDirectionalUtf8Iterator) ?[]const u8 {
        if (it.i >= it.bytes.len) {
            return null;
        }

        const cp_len = std.unicode.utf8ByteSequenceLength(it.bytes[it.i]) catch unreachable;
        it.i += cp_len;
        return it.bytes[it.i - cp_len .. it.i];
    }

    pub fn nextCodepoint(it: *BiDirectionalUtf8Iterator) ?u21 {
        const slice = it.nextCodepointSlice() orelse return null;
        return std.unicode.utf8Decode(slice) catch unreachable;
    }

    /// Look ahead at the next n codepoints without advancing the iterator.
    /// If fewer than n codepoints are available, then return the remainder of the string.
    pub fn peek(it: *BiDirectionalUtf8Iterator, n: usize) []const u8 {
        const original_i = it.i;
        defer it.i = original_i;

        var end_ix = original_i;
        var found: usize = 0;
        while (found < n) : (found += 1) {
            const next_codepoint = it.nextCodepointSlice() orelse return it.bytes[original_i..];
            end_ix += next_codepoint.len;
        }

        return it.bytes[original_i..end_ix];
    }

    pub fn prevCodepointSlice(it: *BiDirectionalUtf8Iterator) ?[]const u8 {
        if (it.i == 0) return null;

        const start_i: usize = it.i;
        it.i -= 1;
        while (it.i > 0 and (it.bytes[it.i] >> 6) ^ 0b10 == 0) : (it.i -= 1) {}

        return it.bytes[it.i..start_i];
    }

    pub fn prevCodepoint(it: *BiDirectionalUtf8Iterator) ?u21 {
        if (it.i == 0) return null;
        const slice = it.prevCodepointSlice() orelse return null;
        return std.unicode.utf8Decode(slice) catch unreachable;
    }
};

test "backwards" {
    std.debug.print("CRASS\n", .{});
    const str = "test strありがと 猫 more ";
    std.debug.print("{s}\n", .{str});

    var it = BiDirectionalUtf8Iterator{ .bytes = str, .i = 0 };
    while (it.nextCodepoint()) |cp| {
        _ = cp;
    }
    while (it.prevCodepoint()) |cp| {
        std.debug.print("{u}\n", .{cp});
    }
}
