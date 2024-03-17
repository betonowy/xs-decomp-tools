const std = @import("std");

const VolCompressedHeader = extern struct {
    magic: [2]u8,
    flags: u16,
    len_compressed: u32,
    len_uncompressed: u32,

    pub fn verifyMagic(self: *const @This()) bool {
        return std.mem.eql(u8, &self.magic, "VF") and self.flags == 0x8000; // only compressed flag is currently supported
    }
};

fn printUsage() !void {
    try std.io.getStdErr().writeAll(
        \\
        \\Usage: xs-volpack INPUT_DIRECTORY VOL_FILE
        \\
        \\Packs all enumerated streams unpacked with xs-volunpack
        \\into .vol file. Directories are created if missing.
        \\
        \\
    );
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) std.debug.print("Main allocator has leaked memory.", .{});
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) return try printUsage();

    const input_dir = args[1];
    const output_file = args[2];

    try std.io.getStdOut().writer().print(
        \\Input dir  : "{s}"
        \\Output file: "{s}"
        \\
    , .{ input_dir, output_file });
}
