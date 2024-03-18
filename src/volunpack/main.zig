const std = @import("std");

const VolCompressedHeader = extern struct {
    magic: [2]u8,
    flags: u16,
    len_compressed: u32,
    len_uncompressed: u32,

    pub fn verifyMagic(self: *const @This()) bool {
        return std.mem.eql(u8, &self.magic, "VF");
    }
};

fn printUsage() !void {
    try std.io.getStdErr().writeAll(
        \\
        \\Usage: xs-volunpack VOL_FILE OUTPUT_DIRECTORY
        \\
        \\Unpacks all data streams from .vol file and outputs them to
        \\the specified directory. Directory is created if missing.
        \\
        \\
    );
}

fn makeFileName(allocator: std.mem.Allocator, dir: []const u8, file_number: usize) ![]u8 {
    var stack_space = std.heap.stackFallback(64, allocator);
    const stack_allocator = stack_space.get();
    const filename = try std.fmt.allocPrint(stack_allocator, "vol_{d:0>4}.bin", .{file_number});
    defer stack_allocator.free(filename);
    return try std.fs.path.join(allocator, &.{ dir, filename });
}

fn writeFooterFile(allocator: std.mem.Allocator, dir: []const u8, file: std.fs.File) !void {
    var stack_space = std.heap.stackFallback(64, allocator);
    const stack_allocator = stack_space.get();
    const filename = try std.fmt.allocPrint(stack_allocator, "vol_footer.bin", .{});
    defer stack_allocator.free(filename);
    const path = try std.fs.path.join(allocator, &.{ dir, filename });
    defer allocator.free(path);
    try file.seekFromEnd(-0x40);
    var buffer: [0x40]u8 = undefined;
    if (try file.readAll(&buffer) != 0x40) unreachable;
    try std.fs.cwd().writeFile(path, &buffer);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) std.debug.print("Main allocator has leaked memory.", .{});
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) return try printUsage();

    const input_file = args[1];
    const output_dir = args[2];

    try std.io.getStdOut().writer().print(
        \\
        \\Input file: "{s}"
        \\Output dir: "{s}"
        \\
    , .{ input_file, output_dir });

    const vol_file_stat = try std.fs.cwd().statFile(input_file);
    const vol_file = try std.fs.cwd().openFile(input_file, .{});
    defer vol_file.close();
    var buffered_reader = std.io.bufferedReader(vol_file.reader());
    var counting_reader = std.io.countingReader(buffered_reader.reader());
    var vol_reader = counting_reader.reader();
    var file_counter: usize = 0;

    try std.fs.cwd().makePath(output_dir);

    var timer = try std.time.Timer.start();

    while (true) : (file_counter += 1) {
        var vol_header: VolCompressedHeader = undefined;
        {
            const read_len = try vol_reader.readAll(std.mem.asBytes(&vol_header));

            if (read_len == 0) {
                try std.io.getStdOut().writer().print(
                    \\
                    \\Reached expected EOF. Bye!
                    \\
                , .{});
                break;
            }

            if (read_len != @sizeOf(@TypeOf(vol_header))) {
                return error.UnexpectedEndOfFile;
            }

            if (!vol_header.verifyMagic()) {
                const skip_size = 64 - read_len;

                if (vol_file_stat.size - skip_size != counting_reader.bytes_read) {
                    std.debug.print("{} bytes unread!\n", .{vol_file_stat.size - counting_reader.bytes_read - read_len});
                    return error.InvalidHeaderMagic;
                }

                try std.io.getStdOut().writer().print(
                    \\
                    \\Skipping last {} bytes as I don't understand it, but writing as footer file just in case. Bye!
                    \\
                , .{skip_size + read_len});

                try writeFooterFile(allocator, output_dir, vol_file);
                break;
            }
        }

        const percent_progress = 100 * @as(f32, @floatFromInt(counting_reader.bytes_read)) / @as(f32, @floatFromInt(vol_file_stat.size));

        switch (vol_header.flags) {
            else => @panic("Unsupported flags"),
            0x0000 => {
                const uncompressed_data = try allocator.alloc(u8, vol_header.len_uncompressed);
                defer allocator.free(uncompressed_data);

                if (try vol_reader.read(uncompressed_data) != vol_header.len_uncompressed) {
                    return error.NotEnoughBytesRead;
                }

                const elapsed_time = @as(f32, @floatFromInt(timer.read())) * (1.0 / @as(comptime_float, std.time.ns_per_s));
                const decompression_speed = (@as(f32, @floatFromInt(counting_reader.bytes_read)) / (1024 * 1024)) / elapsed_time;

                const out_file_path = try makeFileName(allocator, output_dir, file_counter);
                defer allocator.free(out_file_path);
                try std.fs.cwd().writeFile(out_file_path, uncompressed_data);

                try std.io.getStdOut().writer().print(
                    "VOL unpack [{d: >5.1}%] [{d: >5.1} MiB/s] file #{d: <5}\r",
                    .{ percent_progress, decompression_speed, file_counter },
                );
            },
            0x8000 => {
                var zlib_read_counter = std.io.countingReader(vol_reader);
                var zlib_stream = try std.compress.zlib.decompressStream(allocator, zlib_read_counter.reader());
                defer zlib_stream.deinit();
                const zlib_reader = zlib_stream.reader();

                const uncompressed_data = try allocator.alloc(u8, vol_header.len_uncompressed);
                defer allocator.free(uncompressed_data);
                {
                    const read_len = try zlib_reader.readAll(uncompressed_data);

                    if (read_len != uncompressed_data.len) {
                        try std.io.getStdErr().writer().print(
                            \\
                            \\Expected {} bytes on output, decompressed {} bytes
                            \\
                        , .{ uncompressed_data.len, read_len });
                        return error.UnexpectedEndOfZlibStream;
                    }
                }
                try vol_reader.skipBytes(vol_header.len_compressed - zlib_read_counter.bytes_read, .{});

                const elapsed_time = @as(f32, @floatFromInt(timer.read())) * (1.0 / @as(comptime_float, std.time.ns_per_s));
                const decompression_speed = (@as(f32, @floatFromInt(counting_reader.bytes_read)) / (1024 * 1024)) / elapsed_time;

                const out_file_path = try makeFileName(allocator, output_dir, file_counter);
                defer allocator.free(out_file_path);
                try std.fs.cwd().writeFile(out_file_path, uncompressed_data);

                try std.io.getStdOut().writer().print(
                    "VOL unpack [{d: >5.1}%] [{d: >5.1} MiB/s] file #{d: <5}\r",
                    .{ percent_progress, decompression_speed, file_counter },
                );
            },
        }
    }
}
