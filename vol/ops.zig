const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");

pub fn readFooterWithChecks(vol_file: std.fs.File) !types.Footer {
    try vol_file.seekFromEnd(-64);
    const footer = try vol_file.reader().readStruct(types.Footer);

    const hash = std.hash.Crc32.hash(std.mem.asBytes(&footer)[4..]);
    if (footer.crc32 != hash) return error.BadChecksum;

    if (!std.mem.eql(u8, std.mem.asBytes(&footer.guid_compression_type), std.mem.asBytes(&types.Footer.guid_deflate))) {
        return error.UnsupportedCompression;
    }

    return footer;
}

pub fn getTocEntrySlice(toc_buffer: []const u8) ![]align(1) const types.TocEntry {
    const string_table_offset = std.mem.bytesToValue(u32, toc_buffer[0..4]);
    if (@rem(string_table_offset, @sizeOf(types.TocEntry)) != 0) return error.BadStringTableOffset;
    return std.mem.bytesAsSlice(types.TocEntry, toc_buffer[4 .. 4 + string_table_offset]);
}

pub fn getTocString(toc_buffer: []const u8, offset: u32) ![]const u8 {
    const string_table_offset = std.mem.bytesToValue(u32, toc_buffer[0..4]);
    const label_base = toc_buffer[string_table_offset + 8 + offset ..];
    return label_base[0 .. std.mem.indexOf(u8, label_base, &.{0}) orelse return error.NoNullChar];
}

pub fn getTocLabel(toc_buffer: []const u8, entry: types.TocEntry) ![]const u8 {
    return try getTocString(toc_buffer, entry.string_offset_to_label);
}

pub fn getTocPath(toc_buffer: []const u8, entry: types.TocEntry) ![]const u8 {
    return try getTocString(toc_buffer, entry.string_offset_to_path);
}

pub fn getTocExtraDataBuf(toc_buffer: []const u8, entry: types.TocEntry) !?[]const u8 {
    const string_table_offset = std.mem.bytesToValue(u32, toc_buffer[0..4]);

    const base = switch (entry.additional_data_flag) {
        .none => return null,
        .value_u32 => toc_buffer[string_table_offset + 8 + @intFromEnum(entry.additional_data_offset) ..],
        _ => return error.UnsupportedFlag,
    };

    return switch (entry.additional_data_flag) {
        .value_u32 => base[0..4],
        else => unreachable,
    };
}

pub fn pathNoRoot(path: []const u8) []const u8 {
    const index = std.mem.indexOf(u8, path, ":") orelse return path;
    return path[index + 2 ..];
}

pub fn loadChunk(allocator: std.mem.Allocator, vol_file: std.fs.File, offset: usize) ![]const u8 {
    try vol_file.seekTo(offset);

    const chunk_header = try vol_file.reader().readStructEndian(types.ChunkHeader, .little);
    if (!chunk_header.magicVerify()) return error.BadChunkMagic;

    const buffer = try allocator.alloc(u8, chunk_header.uncompressedLength());
    errdefer allocator.free(buffer);

    switch (chunk_header.type) {
        .raw => if (try vol_file.readAll(buffer) != buffer.len) return error.IncompleteRead,
        .compressed => {
            var fbs = std.io.fixedBufferStream(buffer);
            var br = std.io.bufferedReader(vol_file.reader());
            try std.compress.zlib.decompress(br.reader(), fbs.writer());
            if (try fbs.getPos() != buffer.len) return error.IncompleteRead;
        },
    }

    return buffer;
}

pub const ChunkInfo = struct {
    label: []const u8,
    path: []const u8,
    additional_data_type: types.TocEntry.ExtraDataFlag,
    additional_data: ?[]const u8,
};

pub fn dumpChunk(vol_file: std.fs.File, toc_buffer: []const u8, toc_entry: types.TocEntry, dump_dir: std.fs.Dir) !ChunkInfo {
    try vol_file.seekTo(toc_entry.chunk_offset);

    const chunk_header = try vol_file.reader().readStructEndian(types.ChunkHeader, .little);
    if (!chunk_header.magicVerify()) return error.BadChunkMagic;

    const path = pathNoRoot(try getTocPath(toc_buffer, toc_entry));

    switch (chunk_header.type) {
        .raw => {
            if (std.fs.path.dirname(path)) |dir_path| try dump_dir.makePath(dir_path);

            const out_file = try dump_dir.createFile(path, .{});
            defer out_file.close();

            try out_file.writeFileAll(vol_file, .{
                .in_offset = try vol_file.getPos(),
                .in_len = chunk_header.uncompressedLength(),
            });
        },
        .compressed => {
            if (std.fs.path.dirname(path)) |dir_path| try dump_dir.makePath(dir_path);

            const out_file = try dump_dir.createFile(path, .{});
            defer out_file.close();

            var br = std.io.bufferedReader(vol_file.reader());
            var bw = std.io.bufferedWriter(out_file.writer());

            try std.compress.zlib.decompress(br.reader(), bw.writer());
            try bw.flush();
        },
    }

    return .{
        .path = path,
        .label = try getTocLabel(toc_buffer, toc_entry),
        .additional_data_type = toc_entry.additional_data_flag,
        .additional_data = try getTocExtraDataBuf(toc_buffer, toc_entry),
    };
}

pub fn storeStrings(chunk_info: *ChunkInfo, string_table: *std.ArrayList(u8)) !types.TocEntry {
    const label_start = string_table.items.len;
    try string_table.appendSlice(chunk_info.label);
    chunk_info.label = string_table.items[label_start..];
    try string_table.append(0);

    const path_start = string_table.items.len;
    try string_table.appendSlice(chunk_info.path);
    chunk_info.path = string_table.items[path_start..];
    try string_table.append(0);

    return .{ .string_offset_to_label = @intCast(label_start), .string_offset_to_path = @intCast(path_start) };
}

pub fn appendChunk(vol_file: std.fs.File, chunk_info: ChunkInfo, src_dir: std.fs.Dir, chunk_index: u16, toc_entry: types.TocEntry) !types.TocEntry {
    const input_file = try src_dir.openFile(chunk_info.path, .{});
    const input_stat = try input_file.stat();

    const header_offset = try vol_file.getPos();
    {
        var bw = std.io.bufferedWriter(vol_file.writer());
        var br = std.io.bufferedReader(input_file.reader());

        try bw.writer().writeByteNTimes(0, @sizeOf(types.ChunkHeader));
        try std.compress.zlib.compress(br.reader(), bw.writer(), .{ .level = .best });
        try bw.flush();
    }
    const end_offset = try vol_file.getPos();
    try vol_file.seekTo(header_offset);

    var header: types.ChunkHeader = .{
        .type = .compressed,
        .metadata = .{
            .field_a = @intCast(end_offset - header_offset - @sizeOf(types.ChunkHeader)),
            .field_b = @intCast(input_stat.size),
        },
    };

    if (builtin.cpu.arch.endian() == .big) std.mem.byteSwapAllFields(@TypeOf(header), &header);

    try vol_file.writeAll(std.mem.asBytes(&header));
    try vol_file.seekTo(end_offset);

    return .{
        .chunk_index = chunk_index,
        .chunk_offset = @intCast(header_offset),
        .file_length = header.uncompressedLength(),
        .filetime = std.os.windows.nanoSecondsToFileTime(input_stat.mtime),
        // .additional_data_flag = chunk_info.additional_data_type,
        // .additional_data_offset = .invalid,
        .string_offset_to_label = toc_entry.string_offset_to_label,
        .string_offset_to_path = toc_entry.string_offset_to_path,
    };
}

pub fn appendToc(vol_file: std.fs.File, toc_entries: []const types.TocEntry, string_table: []const u8) !types.TocEntry {
    const header_offset = try vol_file.getPos();
    {
        var bw = std.io.bufferedWriter(vol_file.writer());
        try bw.writer().writeByteNTimes(0, @sizeOf(types.ChunkHeader));

        var compressor = try std.compress.zlib.compressor(bw.writer(), .{ .level = .best });

        try compressor.writer().writeInt(u32, @intCast(toc_entries.len * @sizeOf(types.TocEntry)), .little);

        for (toc_entries) |entry| switch (builtin.cpu.arch.endian()) {
            .little => try compressor.writer().writeStruct(entry),
            .big => {
                var swapped = entry;
                std.mem.byteSwapAllFields(types.TocEntry, &swapped);
                try compressor.writer().writeStruct(swapped);
            },
        };

        try compressor.writer().writeInt(u32, @intCast(string_table.len), .little);
        try compressor.writer().writeAll(string_table);
        try compressor.finish();
        try bw.flush();
    }

    const end_offset = try vol_file.getPos();
    try vol_file.seekTo(header_offset);

    var header: types.ChunkHeader = .{
        .type = .compressed,
        .metadata = .{
            .field_a = @intCast(end_offset - header_offset - @sizeOf(types.ChunkHeader)),
            .field_b = @intCast(std.mem.sliceAsBytes(toc_entries).len + string_table.len + 8),
        },
    };

    if (builtin.cpu.arch.endian() == .big) std.mem.byteSwapAllFields(@TypeOf(header), &header);

    try vol_file.writeAll(std.mem.asBytes(&header));
    try vol_file.seekTo(end_offset);

    return .{
        .chunk_offset = @intCast(header_offset),
        .file_length = header.uncompressedLength(),
    };
}

pub fn appendFooter(vol_file: std.fs.File, toc_entry: types.TocEntry) !void {
    var footer: types.Footer = .{
        .crc32 = 0,
        .filetime = std.os.windows.nanoSecondsToFileTime(std.time.nanoTimestamp()),
        .guid_compression_type = types.Footer.guid_deflate,
        .guid_machine = undefined,
        .length_of_last_chunk = std.math.cast(u16, try vol_file.getPos() - toc_entry.chunk_offset) orelse
            return error.TocTooBig,
        .total_size_of_chunks = @intCast(try vol_file.getPos()),
    };

    footer.crc32 = std.hash.Crc32.hash(std.mem.asBytes(&footer)[4..]);
    try vol_file.writeAll(std.mem.asBytes(&footer));
}
