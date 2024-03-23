const std = @import("std");
const utils = @import("utils");

pub const types = @import("types.zig");
pub const validation = @import("validation.zig");
pub const ops = @import("ops.zig");

pub fn validate(allocator: std.mem.Allocator, path: []const u8) !bool {
    const vol_file = try std.fs.cwd().openFile(path, .{});
    defer vol_file.close();

    if (!try validation.report(try validation.footer(vol_file), "Validate footer")) return false;
    if (!try validation.report(try validation.tocAndChunks(allocator, vol_file), "Validate TOC and chunks")) return false;

    return true;
}

const root_json_filename = "root.json";

pub fn unpack(allocator: std.mem.Allocator, src_file_path: []const u8, dst_dir_path: []const u8) !void {
    const vol_file = try std.fs.cwd().openFile(src_file_path, .{});
    defer vol_file.close();

    var dst_dir = try std.fs.cwd().makeOpenPath(dst_dir_path, .{});
    defer dst_dir.close();

    const footer = try ops.readFooterWithChecks(vol_file);
    const toc_buffer = try ops.loadChunk(allocator, vol_file, footer.total_size_of_chunks - footer.length_of_last_chunk);
    defer allocator.free(toc_buffer);
    const toc_entries = try ops.getTocEntrySlice(toc_buffer);

    var dump_info_arr = std.ArrayList(ops.ChunkInfo).init(allocator);
    defer dump_info_arr.deinit();

    for (toc_entries) |entry| try dump_info_arr.append(try ops.dumpChunk(vol_file, toc_buffer, entry, dst_dir));

    const root_json = try dst_dir.createFile(root_json_filename, .{});
    defer root_json.close();
    var bw = std.io.bufferedWriter(root_json.writer());

    try std.json.stringify(dump_info_arr.items, .{ .whitespace = .indent_4, .emit_nonportable_numbers_as_strings = true }, bw.writer());
    try bw.writer().writeAll("\n");
    try bw.flush();
}

pub fn pack(allocator: std.mem.Allocator, src_dir_path: []const u8, dst_file_path: []const u8) !void {
    var src_dir = try std.fs.cwd().openDir(src_dir_path, .{});
    defer src_dir.close();

    if (std.fs.path.dirname(dst_file_path)) |path| try std.fs.cwd().makePath(path);
    const vol_file = try std.fs.cwd().createFile(dst_file_path, .{});
    defer vol_file.close();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const root_json_bytes = try src_dir.readFileAlloc(arena.allocator(), root_json_filename, std.math.maxInt(usize));
    const dump_info = try std.json.parseFromSliceLeaky([]ops.ChunkInfo, arena.allocator(), root_json_bytes, .{ .allocate = .alloc_if_needed });

    var string_table = std.ArrayList(u8).init(allocator);
    defer string_table.deinit();

    var toc_entries_arr = std.ArrayList(types.TocEntry).init(allocator);
    defer toc_entries_arr.deinit();

    for (dump_info, 0..) |*info, i| {
        const toc_entry = try ops.storeStrings(info, &string_table);
        try toc_entries_arr.append(try ops.appendChunk(vol_file, info.*, src_dir, @intCast(i), toc_entry));
    }

    const table_entry = try ops.appendToc(vol_file, toc_entries_arr.items, string_table.items);
    try ops.appendFooter(vol_file, table_entry);
}
