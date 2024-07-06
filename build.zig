const std = @import("std");

fn getSrcDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
const srcdir = getSrcDir();

pub fn linkLibrary(mod: *std.Build.Module) void {
    const cdir = "c_libs";

    const include_paths = [_][]const u8{
        "/usr/include",
        srcdir ++ "/" ++ cdir ++ "/freetype",
        srcdir ++ "/" ++ cdir ++ "/stb",
        srcdir ++ "/" ++ cdir,
        srcdir ++ "/" ++ cdir ++ "/libspng/spng",
    };

    for (include_paths) |path| {
        mod.addIncludePath(.{ .path = path });
    }

    const c_source_files = [_][]const u8{
        srcdir ++ "/" ++ cdir ++ "/stb_image_write.c",
        srcdir ++ "/" ++ cdir ++ "/stb_image.c",
        srcdir ++ "/" ++ cdir ++ "/stb/stb_vorbis.c",
        srcdir ++ "/" ++ cdir ++ "/stb_rect_pack.c",
        srcdir ++ "/" ++ cdir ++ "/libspng/spng/spng.c",
    };

    for (c_source_files) |cfile| {
        mod.addCSourceFile(.{ .file = .{ .path = cfile }, .flags = &[_][]const u8{"-Wall"} });
    }
    mod.link_libc = true;
    mod.linkSystemLibrary("sdl2", .{});
    mod.linkSystemLibrary("openal", .{});
    mod.linkSystemLibrary("sdl2_mixer", .{});
    mod.linkSystemLibrary("epoxy", .{});
    mod.linkSystemLibrary("freetype2", .{});
    mod.linkSystemLibrary("zlib", .{});
    mod.linkSystemLibrary("lua", .{});
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const mode = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "the_engine",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = mode,
    });
    b.installArtifact(exe);

    linkLibrary(&exe.root_module);
    const m = b.addModule("ratgraph", .{ .root_source_file = .{ .path = "src/graphics.zig" }, .target = target });
    linkLibrary(m);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "run app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = mode,
        .link_libc = true,
    });
    unit_tests.setExecCmd(&[_]?[]const u8{ "kcov", "kcov-output", null });
    linkLibrary(&unit_tests.root_module);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const zalgebra_dep = b.dependency("zalgebra", .{
        .target = target,
        .optimize = mode,
    });

    const zalgebra_module = zalgebra_dep.module("zalgebra");
    exe.root_module.addImport("zalgebra", zalgebra_module);
    unit_tests.root_module.addImport("zalgebra", zalgebra_module);
    m.addImport("zalgebra", zalgebra_module);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
