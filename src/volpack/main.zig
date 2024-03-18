const std = @import("std");

const VolCompressedHeader = extern struct {
    magic: [2]u8,
    flags: u16,
    len_compressed: u32,
    len_uncompressed: u32,

    pub fn init() @This() {
        return .{
            .magic = "VF".*,
            .flags = 0x8000,
            .len_compressed = 0,
            .len_uncompressed = 0,
        };
    }

    pub fn verifyMagic(self: *const @This()) bool {
        return std.mem.eql(u8, &self.magic, "VF"); // only compressed flag is currently supported
    }
};

const PathStore = struct {
    allocator: std.mem.Allocator,
    array_list: std.ArrayListUnmanaged([]u8),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator, .array_list = .{} };
    }

    pub fn deinit(self: *@This()) void {
        for (self.array_list.items) |str| self.allocator.free(str);
        self.array_list.deinit(self.allocator);
    }

    pub fn constSlice(self: *const @This()) [][]const u8 {
        return self.array_list.items;
    }

    pub fn add(self: *@This(), path: []const u8) !void {
        try self.array_list.append(self.allocator, try self.allocator.dupe(u8, path));
    }

    pub fn sort(self: *@This()) void {
        std.sort.pdq([]const u8, self.array_list.items, {}, pathLessThan);
    }

    fn pathLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
        const lhs_base = std.fs.path.basename(lhs);
        const rhs_base = std.fs.path.basename(rhs);
        const lhs_index = getIndexFromBasename(lhs_base) orelse std.math.maxInt(usize);
        const rhs_index = getIndexFromBasename(rhs_base) orelse std.math.maxInt(usize);
        return lhs_index < rhs_index;
    }

    pub fn getIndexFromBasename(basename: []const u8) ?usize {
        var iterator = std.mem.tokenizeAny(u8, basename, "_.");
        var index: ?usize = null;

        while (iterator.next()) |slice| {
            index = std.fmt.parseUnsigned(usize, slice, 10) catch continue;
            break;
        }

        return index;
    }

    pub fn isIndexedFilename(basename: []const u8) bool {
        return getIndexFromBasename(basename) != null;
    }

    pub fn isFooterFilename(basename: []const u8) bool {
        var iterator = std.mem.tokenizeAny(u8, basename, "_.");

        while (iterator.next()) |slice| {
            if (std.mem.eql(u8, slice, "footer")) return true;
        }

        return false;
    }
};

const MemWriter = struct {
    allocator: std.mem.Allocator,
    array: *Array,
    writer: Writer,

    const Array = std.ArrayList(u8);
    const Writer = std.io.Writer(*Array, anyerror, writeFn);

    pub fn init(allocator: std.mem.Allocator) !@This() {
        const array_ptr = try allocator.create(Array);
        array_ptr.* = Array.init(allocator);

        return .{
            .allocator = allocator,
            .array = array_ptr,
            .writer = .{ .context = array_ptr },
        };
    }

    pub fn deinit(self: *@This()) void {
        self.array.deinit();
        self.allocator.destroy(self.array);
    }

    fn writeFn(self: *Array, bytes: []const u8) anyerror!usize {
        try self.appendSlice(bytes);
        return bytes.len;
    }

    pub fn reset(self: *@This()) void {
        self.array.clearRetainingCapacity();
    }

    pub fn constSlice(self: *@This()) []const u8 {
        return self.array.items;
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

    const input_dir_path = args[1];
    const output_file_path = args[2];

    try std.io.getStdOut().writer().print(
        \\
        \\Input dir  : "{s}"
        \\Output file: "{s}"
        \\
    , .{ input_dir_path, output_file_path });

    var vol_dir = try std.fs.cwd().openDir(input_dir_path, .{ .iterate = true });
    defer vol_dir.close();

    var vol_store = PathStore.init(allocator);
    defer vol_store.deinit();

    var vol_footer_filename_opt: ?[]const u8 = null;
    defer if (vol_footer_filename_opt) |str| allocator.free(str);
    {
        var iterator = vol_dir.iterate();
        while (try iterator.next()) |path| {
            if (path.kind == .file) {
                if (PathStore.isIndexedFilename(path.name)) {
                    try vol_store.add(path.name);
                } else if (PathStore.isFooterFilename(path.name)) {
                    vol_footer_filename_opt = try allocator.dupe(u8, path.name);
                }
            }
        }

        vol_store.sort();
    }

    const vol_file = try std.fs.cwd().createFile(output_file_path, .{});
    defer vol_file.close();

    // var mem_writer = try MemWriter.init(allocator);
    // defer mem_writer.deinit();

    var timer = try std.time.Timer.start();
    var bytes_written_total: usize = 0;
    var compression_speed: f32 = 0;

    for (vol_store.constSlice(), 0..) |str, i| {
        // mem_writer.reset();

        const loaded_buffer = try vol_dir.readFileAlloc(allocator, str, std.math.maxInt(usize));
        defer allocator.free(loaded_buffer);
        // {
        //     var zlib_stream = try std.compress.zlib.compressStream(allocator, mem_writer.writer, .{ .level = .maximum });
        //     defer zlib_stream.deinit();
        //     try zlib_stream.writer().writeAll(loaded_buffer);
        //     try zlib_stream.finish();
        // }
        // bytes_written_total += mem_writer.constSlice().len;
        bytes_written_total += loaded_buffer.len;

        var header = VolCompressedHeader.init();
        header.len_uncompressed = @intCast(loaded_buffer.len);
        header.len_compressed = @intCast(loaded_buffer.len);
        header.flags = 0x0000;

        try vol_file.writeAll(std.mem.asBytes(&header));
        try vol_file.writeAll(loaded_buffer);

        const percent_progress = 100 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(vol_store.constSlice().len));
        const elapsed_time = @as(f32, @floatFromInt(timer.read())) * (1.0 / @as(comptime_float, std.time.ns_per_s));
        compression_speed = (@as(f32, @floatFromInt(bytes_written_total)) / (1024 * 1024)) / elapsed_time;

        try std.io.getStdOut().writer().print(
            "VOL pack [{d: >5.1}%] [{d: >5.1} MiB/s] file #{d: <5}\r",
            .{ percent_progress, compression_speed, i },
        );
    }

    try std.io.getStdOut().writer().print(
        \\VOL pack [{d: >5.1}%] [{d: >5.1} MiB/s] file #{d: <5}
        \\
    , .{ 100, compression_speed, vol_store.constSlice().len });

    if (vol_footer_filename_opt) |vol_footer_filename| {
        try std.io.getStdOut().writer().print("Appending footer file\n", .{});

        const footer_file = try vol_dir.openFile(vol_footer_filename, .{});
        defer footer_file.close();
        try vol_file.writeFileAll(footer_file, .{});
    } else {
        try std.io.getStdOut().writer().print("Footer file not found, nothing to append\n", .{});
    }

    try std.io.getStdOut().writer().print(
        \\All OK. Bye!
        \\
    , .{});
}
