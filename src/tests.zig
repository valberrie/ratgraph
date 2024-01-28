const std = @import("std");
pub const a = @import("gui_cache.zig");
pub const b = @import("gui_test.zig");
test "new" {
    std.debug.print("FKCstais\n", .{});
    std.debug.print("FKCstais\n", .{});
}

test {
    std.testing.refAllDecls(@This());
}
