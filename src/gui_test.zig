const std = @import("std");
const Gui = @import("gui.zig");
const graph = @import("graphics.zig");

test "init" {
    const alloc = std.testing.allocator;
    var gui = try Gui.Context.init(alloc);

    try gui.reset(.{}, graph.Rec(0, 0, 1000, 1000));
    gui.deinit();
}
