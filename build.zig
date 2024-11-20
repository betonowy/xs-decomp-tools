const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vol = b.addModule("vol", .{ .root_source_file = b.path("vol/root.zig") });
    const stb = b.addModule("stb", .{ .root_source_file = b.path("thirdparty/stb.zig") });
    stb.addIncludePath(b.path("thirdparty"));

    default(b, vol, stb, target, optimize);
    release(b, vol, stb);
}

pub fn default(b: *std.Build, vol: *std.Build.Module, stb: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.Mode) void {
    {
        const xs_sprite = b.addExecutable(.{
            .name = "xs-sprite",
            .root_source_file = b.path("app/sprite.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        xs_sprite.addCSourceFile(.{ .file = b.path("thirdparty/stb.c") });
        xs_sprite.root_module.addImport("stb", stb);

        b.installArtifact(xs_sprite);
        const run_cmd = b.addRunArtifact(xs_sprite);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| run_cmd.addArgs(args);

        const run_step = b.step("run-sprite", "Run xs-sprite");
        run_step.dependOn(&run_cmd.step);
    }
    {
        const xs_vol = b.addExecutable(.{
            .name = "xs-vol",
            .root_source_file = b.path("app/vol.zig"),
            .target = target,
            .optimize = optimize,
        });
        xs_vol.root_module.addImport("vol", vol);

        b.installArtifact(xs_vol);
        const run_cmd = b.addRunArtifact(xs_vol);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| run_cmd.addArgs(args);

        const run_step = b.step("run-vol", "Run xs-vol");
        run_step.dependOn(&run_cmd.step);
    }
}

pub fn release(b: *std.Build, vol: *std.Build.Module, stb: *std.Build.Module) void {
    const step = b.step("release", "Make release to all platforms");

    const targets = [_]std.Target.Query{
        .{ .cpu_arch = .x86, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .x86, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .arm, .os_tag = .linux, .abi = .gnueabihf },
        .{ .cpu_arch = .arm, .os_tag = .linux, .abi = .musleabihf },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .x86, .os_tag = .windows },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .windows },
    };

    const optimize = std.builtin.OptimizeMode.ReleaseSmall;

    const compress_out = b.pathJoin(&.{ b.install_prefix, "release.tgz" });

    const compress = std.Build.addSystemCommand(b, &.{ "tar", "-C", b.install_prefix, "-caf", compress_out, "release" });
    step.dependOn(&compress.step);

    for (targets[0..]) |query| {
        const target = std.Build.resolveTargetQuery(b, query);
        const triple_string = target.result.zigTriple(b.allocator) catch @panic("OOM");

        const xs_vol = b.addExecutable(.{
            .name = b.fmt("xs-vol-{s}", .{triple_string}),
            .root_source_file = b.path("app/vol.zig"),
            .target = target,
            .optimize = optimize,
            .strip = true,
            .single_threaded = true,
            .pic = true,
        });
        xs_vol.root_module.addImport("vol", vol);

        const xs_sprite = b.addExecutable(.{
            .name = b.fmt("xs-sprite-{s}", .{triple_string}),
            .root_source_file = b.path("app/sprite.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .strip = true,
            .single_threaded = true,
            .pic = true,
        });
        xs_sprite.addCSourceFile(.{ .file = b.path("thirdparty/stb.c") });
        xs_sprite.root_module.addImport("stb", stb);

        const install_path = "release";
        const install_xs_vol = b.addInstallArtifact(xs_vol, .{ .dest_dir = .{ .override = .{ .custom = install_path } } });
        const install_xs_sprite = b.addInstallArtifact(xs_sprite, .{ .dest_dir = .{ .override = .{ .custom = install_path } } });

        compress.step.dependOn(&install_xs_vol.step);
        compress.step.dependOn(&install_xs_sprite.step);
    }
}
