const std = @import("std");

fn getSrcDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
const srcdir = getSrcDir();

//const LUA_SRC: ?[]const u8 = "lua5.4.7/src/";
const LUA_SRC = null;

pub const ToLink = enum {
    freetype,
    sdl,
    lua,
    openal,
};
pub fn linkLibrary(b: *std.Build, mod: *std.Build.Module, tolink: []const ToLink) void {
    const cdir = "c_libs";

    const include_paths = [_][]const u8{
        cdir ++ "/freetype",
        cdir ++ "/stb",
        cdir,
        cdir ++ "/libspng/spng",
    };

    for (include_paths) |path| {
        mod.addIncludePath(b.path(path));
    }

    const c_source_files = [_][]const u8{
        cdir ++ "/stb_image_write.c",
        cdir ++ "/stb_image.c",
        cdir ++ "/stb/stb_vorbis.c",
        cdir ++ "/stb_rect_pack.c",
        cdir ++ "/stb_truetype.c",
        cdir ++ "/libspng/spng/spng.c",
    };

    if (LUA_SRC) |lsrc| {
        const paths = [_][]const u8{ "lapi.c", "lauxlib.c", "lbaselib.c", "lcode.c", "lcorolib.c", "lctype.c", "ldblib.c", "ldebug.c", "ldo.c", "ldump.c", "lfunc.c", "lgc.c", "linit.c", "liolib.c", "llex.c", "lmathlib.c", "lmem.c", "loadlib.c", "lobject.c", "lopcodes.c", "loslib.c", "lparser.c", "lstate.c", "lstring.c", "lstrlib.c", "ltable.c", "ltablib.c", "ltm.c", "lundump.c", "lutf8lib.c", "lvm.c", "lzio.c" };
        inline for (paths) |p| {
            mod.addCSourceFile(.{ .file = b.path(lsrc ++ p), .flags = &[_][]const u8{"-Wall"} });
        }
    }

    for (c_source_files) |cfile| {
        mod.addCSourceFile(.{ .file = b.path(cfile), .flags = &[_][]const u8{"-Wall"} });
    }
    mod.link_libc = true;
    if (mod.resolved_target) |rt| {
        if (rt.result.os.tag == .windows) {
            //TODO the Windows build depends heavily on msys.
            //I have no clue how windows applications are supposed to be built.
            //distrubuting the binary requries, a setting lib path to msys/mingw64/bin, or copying the relevant dlls into the working dir.
            mod.addSystemIncludePath(.{ .cwd_relative = "/msys64//mingw64/include" });
            mod.addSystemIncludePath(.{ .cwd_relative = "/msys64//mingw64/include/freetype2" });
            mod.addLibraryPath(.{ .cwd_relative = "/msys64/mingw64/lib" });
            mod.linkSystemLibrary("epoxy", .{});
            mod.linkSystemLibrary("mingw32", .{});
            mod.linkSystemLibrary("SDL3.dll", .{});
            mod.linkSystemLibrary("c", .{});
            mod.linkSystemLibrary("opengl32", .{});
            mod.linkSystemLibrary("openal.dll", .{});
            mod.linkSystemLibrary("freetype.dll", .{});
            mod.linkSystemLibrary("z", .{});
        } else {
            mod.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
            mod.addSystemIncludePath(.{ .cwd_relative = "/usr/include/freetype2" });
            for (tolink) |tl| {
                const str = switch (tl) {
                    .lua => "lua",
                    .sdl => "SDL3",
                    .freetype => "freetype",
                    .openal => "openal",
                };
                mod.linkSystemLibrary(str, .{});
            }
            //mod.linkSystemLibrary("SDL3", .{});
            //mod.linkSystemLibrary("openal", .{});
            mod.linkSystemLibrary("epoxy", .{});
            //mod.linkSystemLibrary("freetype", .{});
            mod.linkSystemLibrary("z", .{});
        }
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const mode = b.standardOptimizeOption(.{});
    const build_gui = b.option(bool, "gui", "Build the gui test app") orelse false;

    const bake = b.addExecutable(.{
        .name = "assetbake",
        .root_source_file = b.path("src/assetbake.zig"),
        .target = target,
        .optimize = mode,
    });
    b.installArtifact(bake);
    const to_link = [_]ToLink{ .freetype, .sdl, .openal, .lua };
    linkLibrary(b, bake.root_module, &to_link);

    const exe = b.addExecutable(.{
        .name = "the_engine",
        .root_source_file = if (build_gui) b.path("src/gui_app.zig") else b.path("src/main.zig"),
        .target = target,
        .optimize = mode,
    });
    b.installArtifact(exe);

    linkLibrary(b, exe.root_module, &to_link);
    const m = b.addModule("ratgraph", .{ .root_source_file = b.path("src/graphics.zig"), .target = target });
    linkLibrary(b, m, &.{ .freetype, .sdl });

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "run app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = mode,
        .link_libc = true,
    });
    unit_tests.setExecCmd(&[_]?[]const u8{ "kcov", "kcov-output", null });
    linkLibrary(b, unit_tests.root_module, &to_link);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const zalgebra_dep = b.dependency("zalgebra", .{
        .target = target,
        .optimize = mode,
    });

    const zalgebra_module = zalgebra_dep.module("zalgebra");
    exe.root_module.addImport("zalgebra", zalgebra_module);
    bake.root_module.addImport("zalgebra", zalgebra_module);
    unit_tests.root_module.addImport("zalgebra", zalgebra_module);
    m.addImport("zalgebra", zalgebra_module);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
