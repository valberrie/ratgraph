const std = @import("std");

/// All the unicode codepoints is the [Zs] or Seperator, Space category
pub const unicode_space_seperator = [_]u21{ 0x0020, 0x00A0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x202f, 0x205f, 0x3000 };

///Much of this is adapted from std.unicode.Utf8Iterator
pub const BiDirectionalUtf8Iterator = struct {
    pub fn nextCodepointSlice(i: *usize, bytes: []const u8) ?[]const u8 {
        if (i.* >= bytes.len) {
            return null;
        }

        const cp_len = std.unicode.utf8ByteSequenceLength(bytes[i.*]) catch return null;
        i.* += cp_len;
        return bytes[i.* - cp_len .. i.*];
    }

    pub fn nextCodepoint(i: *usize, bytes: []const u8) ?u21 {
        const slice = nextCodepointSlice(i, bytes) orelse return null;
        return std.unicode.utf8Decode(slice) catch return null;
    }

    pub fn currentCodepoint(i: usize, bytes: []const u8) ?u21 {
        if (i >= bytes.len) return null;

        const cp_len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch return null;
        return std.unicode.utf8Decode(bytes[i .. i + cp_len]) catch return null;
    }

    pub fn prevCodepointSlice(i: *usize, bytes: []const u8) ?[]const u8 {
        if (i.* == 0) return null;

        const start_i: usize = i.*;
        i.* -= 1;
        //Every continuation byte starts with 0b10
        while (i.* > 0 and (bytes[i.*] >> 6) ^ 0b10 == 0) : (i.* -= 1) {}

        return bytes[i.*..start_i];
    }

    pub fn prevCodepoint(i: *usize, bytes: []const u8) ?u21 {
        if (i.* == 0) return null;
        const slice = prevCodepointSlice(i, bytes) orelse return null;
        return std.unicode.utf8Decode(slice) catch return null;
    }

    pub fn lastCodepointSlice(i: *usize, bytes: []const u8) ?[]const u8 {
        if (bytes.len == 0) return null;
        i.* = bytes.len;
        return prevCodepointSlice(i, bytes);
    }
};

test "backwards" {
    //broken
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
