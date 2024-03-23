const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const stb = b.addModule("stb", .{
        .root_source_file = .{ .path = "thirdparty/stb.zig" },
        .target = target,
        .optimize = optimize,
    });
    stb.addIncludePath(.{ .path = "thirdparty" });

    const utils = b.addModule("utils", .{
        .root_source_file = .{ .path = "utils/root.zig" },
        .target = target,
        .optimize = optimize,
    });

    const vol = b.addModule("vol", .{
        .root_source_file = .{ .path = "vol/root.zig" },
        .target = target,
        .optimize = optimize,
    });
    vol.addImport("utils", utils);

    {
        const xs_sprite = b.addExecutable(.{
            .name = "xs-sprite",
            .root_source_file = .{ .path = "app/sprite.zig" },
            .target = target,
            .optimize = optimize,
        });
        xs_sprite.linkLibC();
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
            .root_source_file = .{ .path = "app/vol.zig" },
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
