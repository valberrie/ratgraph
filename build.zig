const std = @import("std");

fn getSrcDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
const srcdir = getSrcDir();

pub fn linkLibrary(exe: *std.build.LibExeObjStep) void {
    const cdir = "c_libs";

    const include_paths = [_][]const u8{
        "/usr/include",
        srcdir ++ "/" ++ cdir ++ "/freetype",
        srcdir ++ "/" ++ cdir ++ "/stb",
        srcdir ++ "/" ++ cdir ++ "/libspng/spng",
    };

    for (include_paths) |path| {
        exe.addIncludePath(.{ .path = path });
    }

    const c_source_files = [_][]const u8{
        srcdir ++ "/" ++ cdir ++ "/stb_image_write.c",
        srcdir ++ "/" ++ cdir ++ "/stb_image.c",
        srcdir ++ "/" ++ cdir ++ "/stb_rect_pack.c",
        srcdir ++ "/" ++ cdir ++ "/libspng/spng/spng.c",
    };

    for (c_source_files) |cfile| {
        exe.addCSourceFile(.{ .file = .{ .path = cfile }, .flags = &[_][]const u8{"-Wall"} });
    }
    exe.linkLibC();
    exe.linkSystemLibrary("sdl2");
    exe.linkSystemLibrary("epoxy");
    exe.linkSystemLibrary("freetype2");
    exe.linkSystemLibrary("zlib");
    exe.linkSystemLibrary("lua");
}

//pub fn addPackage(exe: *std.build.LibExeObjStep, name: []const u8) void {
//    exe.addPackage(.{
//        .name = name,
//        .source = .{ .path = srcdir ++ "/src/graphics.zig" },
//        .dependencies = &[_]std.build.Pkg{.{ .name = "zalgebra", .source = .{ .path = srcdir ++ "/zig_libs/zalgebra/src/main.zig" } }},
//    });
//    //exe.addPackagePath(name, srcdir ++ "/src/graphics.zig");
//}

pub fn module(b: *std.Build, compile: *std.Build.Step.Compile) *std.Build.Module {
    linkLibrary(compile);
    return b.createModule(.{ .source_file = .{ .path = srcdir ++ "/src/graphics.zig" }, .dependencies = &[_]std.Build.ModuleDependency{.{ .name = "zalgebra", .module = zalgebra(b, compile) }} });
}

pub fn zalgebra(b: *std.Build, compile: *std.Build.Step.Compile) *std.Build.Module {
    const zalgebra_dep = b.dependency("zalgebra", .{
        .target = compile.target,
        .optimize = compile.optimize,
    });

    const zalgebra_module = zalgebra_dep.module("zalgebra");
    return zalgebra_module;
}

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    const mode = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "the_engine",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = mode,
    });
    b.installArtifact(exe);

    linkLibrary(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "run app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = mode,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const zalgebra_dep = b.dependency("zalgebra", .{
        .target = target,
        .optimize = mode,
    });

    const zalgebra_module = zalgebra_dep.module("zalgebra");
    exe.addModule("zalgebra", zalgebra_module);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
