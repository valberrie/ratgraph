const std = @import("std");
const graph = @import("graphics.zig");
const gui = @import("gui.zig");
const V2f = graph.Vec2f;

const pow = std.math.pow;
const sqrt = std.math.sqrt;

pub fn quadForm(a: f32, b: f32, C: f32) ?[2]f32 {
    const discrim = pow(f32, b, 2) - (4 * a * C);

    return if (discrim < 0) null else .{ (-b + std.math.sqrt(discrim)) / (2 * a), (-b - std.math.sqrt(discrim)) / (2 * a) };
}

pub fn printSlice(slice: anytype, comptime fmt: ?[]const u8) void {
    const fmt_str = if (fmt) |f| "i: {d} " ++ f else "i: {d} {any}\n";
    for (slice, 0..) |item, i| {
        std.debug.print(fmt_str, .{ i, item });
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    var win = try graph.SDL.Window.createWindow("zig-game-engine", .{});
    defer win.destroyWindow();

    var asset_dir = try std.fs.cwd().openDir("mario_assets", .{});
    defer asset_dir.close();

    var dpix: u32 = @as(u32, @intFromFloat(win.getDpi()));
    const init_size = 72;
    var font = try graph.Font.init(alloc, std.fs.cwd(), "fonts/sfmono.otf", init_size, dpix, .{});
    defer font.deinit();

    var draw = graph.NewCtx.init(alloc, win.getDpi());
    defer draw.deinit();

    while (!win.should_exit) {
        try draw.begin(0x2f2f2fff);
        win.pumpEvents();

        //draw.text(.{ .x = 1000, .y = 200 }, "Test string ____.!", &font, 72, 0xffffffff);
        draw.triangle(V2f.new(0, 0), V2f.new(250, 100), V2f.new(500, 0), 0xffff00ff);

        draw.triangle(V2f.new(500, 500), V2f.new(1000, 1000), V2f.new(1400, 700), 0xffffffff);
        draw.rect(graph.Rec(0, 0, 1000, 10), 0xffffffff);
        draw.rectTex(graph.Rec(0, 0, 1000, 1000), font.texture.rect(), 0xffffffff, font.texture);

        draw.text(win.mouse.pos, "hello", &font, 12, 0xffffffff);
        draw.line(win.mouse.pos, V2f.new(0, 0), 0xffffffff);

        draw.end(win.screen_width, win.screen_height, graph.za.Mat4.identity());
        win.swap();
    }
}
