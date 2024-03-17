const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    {
        const xs_volunpack = b.addExecutable(.{
            .name = "xs-volunpack",
            .root_source_file = .{ .path = "src/volunpack/main.zig" },
            .target = target,
            .optimize = optimize,
        });

        b.installArtifact(xs_volunpack);
        const run_cmd = b.addRunArtifact(xs_volunpack);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run-volunpack", "Run xs-volunpack");
        run_step.dependOn(&run_cmd.step);
    }
    {
        const xs_volpack = b.addExecutable(.{
            .name = "xs-volpack",
            .root_source_file = .{ .path = "src/volpack/main.zig" },
            .target = target,
            .optimize = optimize,
        });

        b.installArtifact(xs_volpack);
        const run_cmd = b.addRunArtifact(xs_volpack);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run-volpack", "Run xs-volpack");
        run_step.dependOn(&run_cmd.step);
    }
}
