const std = @import("std");
const types = @import("types.zig");

pub fn report(value: bool, msg: []const u8) !bool {
    for (msg.len + 11) |_| try std.io.getStdOut().writeAll("*");
    try std.io.getStdOut().writeAll("*\n");
    try std.io.getStdOut().writer().print("* {s}: {s} *\n", .{ msg, if (value) "Passed" else "Failed" });
    for (msg.len + 11) |_| try std.io.getStdOut().writeAll("*");
    try std.io.getStdOut().writeAll("*\n");
    return value;
}

pub fn footer(vol_file: std.fs.File) !bool {
    try vol_file.seekTo(0);

    var last_chunk_offset: usize = 0;
    var last_chunk_size: usize = 0;

    const vol_footer: types.Footer = ret: while (true) {
        const bytes_left = try vol_file.getEndPos() - try vol_file.getPos();
        const chunk_header = try vol_file.reader().readStructEndian(types.ChunkHeader, .little);

        switch (chunk_header.magicVerify() and bytes_left != @sizeOf(types.Footer)) {
            true => {
                last_chunk_offset = @as(usize, @intCast(try vol_file.getPos())) - @sizeOf(types.ChunkHeader);
                last_chunk_size = chunk_header.chunkLength();

                try vol_file.reader().skipBytes(chunk_header.chunkLength(), .{});
            },
            false => {
                if (bytes_left != @sizeOf(types.Footer)) {
                    try std.io.getStdOut().writer().print("Invalid chunk magic, but it's not at footer offset. Diff: {}\n", .{bytes_left});
                    return false;
                }

                try vol_file.seekBy(-@sizeOf(types.ChunkHeader));
                break :ret try vol_file.reader().readStructEndian(types.Footer, .little);
            },
        }
    };

    try std.io.getStdOut().writeAll("Footer found\n");

    const checkSum = std.hash.Crc32.hash(std.mem.asBytes(&vol_footer)[4..]);

    if (vol_footer.crc32 != checkSum) {
        try std.io.getStdOut().writer().print("Checksum invalid! Is {x}, should be {x}\n", .{ vol_footer.crc32, checkSum });
        return false;
    }

    if (vol_footer.flag_16 != 0x4000) {
        try std.io.getStdOut().writeAll("Bad 0x4000 flag\n");
        return false;
    }

    if (vol_footer.flag_32 != 0x27110000) {
        try std.io.getStdOut().writeAll("Bad 0x27110000 flag\n");
        return false;
    }

    if (vol_footer.length_of_last_chunk != last_chunk_size + @sizeOf(types.ChunkHeader)) {
        try std.io.getStdOut().writeAll("Footer last chunk size is not correct\n");
        return false;
    }

    const expected_total_size_of_chunks = try vol_file.getEndPos() - 64;

    if (vol_footer.total_size_of_chunks != expected_total_size_of_chunks) {
        try std.io.getStdOut().writer().print(
            "Total size of chunks is not correct, should be {}, is {}\n",
            .{ expected_total_size_of_chunks, vol_footer.total_size_of_chunks },
        );
        return false;
    }

    return true;
}

pub fn tocAndChunks(allocator: std.mem.Allocator, vol_file: std.fs.File) !bool {
    try vol_file.seekTo(0);

    var last_chunk_offset: usize = 0;
    var last_chunk_size: usize = 0;

    while (true) {
        const bytes_left = try vol_file.getEndPos() - try vol_file.getPos();
        const chunk_header = try vol_file.reader().readStructEndian(types.ChunkHeader, .little);

        switch (chunk_header.magicVerify() and bytes_left != @sizeOf(types.Footer)) {
            true => {
                last_chunk_offset = @as(usize, @intCast(try vol_file.getPos())) - @sizeOf(types.ChunkHeader);
                last_chunk_size = chunk_header.chunkLength();

                try vol_file.reader().skipBytes(chunk_header.chunkLength(), .{});
            },
            false => {
                if (bytes_left != @sizeOf(types.Footer)) {
                    try std.io.getStdOut().writer().print("Invalid chunk magic, but it's not at footer offset! Diff: {}\n", .{bytes_left});
                    return false;
                }
                break;
            },
        }
    }

    try std.io.getStdOut().writer().print("TOC found at offset: {}\n", .{last_chunk_offset});

    if (last_chunk_size == 0) {
        try std.io.getStdOut().writeAll("Chunk not found\n");
        return false;
    }

    try vol_file.seekTo(last_chunk_offset);
    const toc_chunk_header = try vol_file.reader().readStructEndian(types.ChunkHeader, .little);

    if (!toc_chunk_header.magicVerify()) {
        try std.io.getStdOut().writeAll("Invalid TOC chunk magic\n");
        return false;
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const toc_buffer = switch (toc_chunk_header.type) {
        .raw => ret: {
            try std.io.getStdOut().writeAll("Chunk is not compressed\n");
            const buffer = try arena.allocator().alloc(u8, toc_chunk_header.chunkLength());

            if (try vol_file.readAll(buffer) != buffer.len) {
                try std.io.getStdOut().writeAll("Unexpected EOF\n");
                return false;
            }

            break :ret buffer;
        },
        .compressed => ret: {
            try std.io.getStdOut().writeAll("Chunk is compressed\n");

            const buffer = try arena.allocator().alloc(u8, toc_chunk_header.uncompressedLength());

            var buffered_reader = std.io.bufferedReader(vol_file.reader());
            var zlib_decode_stream = std.io.fixedBufferStream(buffer);
            try std.compress.zlib.decompress(buffered_reader.reader(), zlib_decode_stream.writer());

            if (try zlib_decode_stream.getPos() != toc_chunk_header.uncompressedLength()) {
                try std.io.getStdOut().writer().print(
                    "Wrong decompress write length: should be {}, is {}\n",
                    .{ toc_chunk_header.uncompressedLength(), try zlib_decode_stream.getPos() },
                );
                return false;
            }

            break :ret buffer;
        },
    };

    try std.io.getStdOut().writer().print("TOC read, len {}\n", .{toc_buffer.len});

    var toc_fbs = std.io.fixedBufferStream(toc_buffer);

    const string_table_offset = try toc_fbs.reader().readInt(u32, .little) + @sizeOf(u32) * 2;
    const string_table = toc_buffer[string_table_offset..];

    const expected_string_table_len = std.mem.bytesToValue(u32, toc_buffer[string_table_offset - 4 .. string_table_offset]);

    if (string_table.len != expected_string_table_len) {
        try std.io.getStdOut().writer().print(
            "TOC string_table has incorrect length, len: {}, buffer left: {}\n",
            .{ expected_string_table_len, string_table.len },
        );
        return false;
    }

    var entries_count: usize = 0;

    while (true) {
        if (try toc_fbs.getPos() == string_table_offset - 4) {
            try std.io.getStdOut().writer().print("TOC end, {} entries\n", .{entries_count});
            break;
        }

        try std.io.getStdOut().writer().print("TOC entry #{}\n", .{entries_count});

        const toc_entry = try toc_fbs.reader().readStructEndian(types.TocEntry, .little);

        switch (toc_entry.unknown_flag) {
            .the_only_known_value => {},
            _ => |flag| {
                const value: u32 = @intFromEnum(flag);
                try std.io.getStdOut().writer().print("TOC 0x20 pattern is not present, {x} instead\n", .{value});
                return false;
            },
        }

        switch (toc_entry.additional_data_flag) {
            .value_u32 => |flag| {
                switch (toc_entry.additional_data_offset) {
                    _ => |e| {
                        const offset: u32 = @intFromEnum(e);
                        const something = @as(*align(1) const u32, @ptrCast(string_table.ptr + offset));
                        try std.io.getStdOut().writer().print("Additional data available: {x}\n", .{something.*});
                    },
                    .invalid => {
                        try std.io.getStdOut().writer().print(
                            "Additional data available flag present, but offset is invalid, flag: {x}\n",
                            .{@as(u16, @intFromEnum(flag))},
                        );
                        return false;
                    },
                }
            },
            .none => {},
            _ => |flag| {
                const value: u16 = @intFromEnum(flag);
                try std.io.getStdOut().writer().print("Unknown additional data flag: {x}\n", .{value});
                return false;
            },
        }

        if (toc_entry.chunk_index != entries_count) {
            try std.io.getStdOut().writer().print(
                "TOC chunk index is not valid, should be {}, is {}\n",
                .{ entries_count, toc_entry.chunk_index },
            );
            return false;
        }

        if (toc_entry.chunk_offset == 0 and toc_entry.chunk_index != 0) {
            try std.io.getStdOut().writeAll("First chunk offset is 0, but index is not\n");
            return false;
        }

        try vol_file.seekTo(toc_entry.chunk_offset);
        const file_chunk_header = try vol_file.reader().readStructEndian(types.ChunkHeader, .little);

        if (!file_chunk_header.magicVerify()) {
            try std.io.getStdOut().writeAll("TOC points to offset that does not have a valid chunk magic\n");
            return false;
        }

        if (toc_entry.file_length != file_chunk_header.uncompressedLength()) {
            try std.io.getStdOut().writer().print(
                "Chunk's uncompressed length doesn't match file length from TOC, should be {}, is {}\n",
                .{ toc_entry.file_length, file_chunk_header.uncompressedLength() },
            );
            return false;
        }

        try std.io.getStdOut().writer().print(
            \\    Label:        {s}
            \\    Path:         {s}
            \\    Offset:       {}
            \\    Length:       {}
            \\    Chunk Length: {}
            \\    FILETIME:     {}
            \\
        , .{
            @as([*:0]const u8, @ptrCast(string_table.ptr + toc_entry.string_offset_to_label)),
            @as([*:0]const u8, @ptrCast(string_table.ptr + toc_entry.string_offset_to_path)),
            toc_entry.chunk_offset,
            toc_entry.file_length,
            file_chunk_header.chunkLength(),
            std.os.windows.fileTimeToNanoSeconds(toc_entry.filetime),
        });

        switch (toc_chunk_header.type) {
            .raw => {
                try std.io.getStdOut().writeAll("Chunk is not compressed\n");
            },
            .compressed => {
                try std.io.getStdOut().writeAll("Chunk is compressed\n");

                const buffer = try allocator.alloc(u8, file_chunk_header.uncompressedLength());
                defer allocator.free(buffer);

                var buffered_reader = std.io.bufferedReader(vol_file.reader());
                var zlib_decode_stream = std.io.fixedBufferStream(buffer);
                try std.compress.zlib.decompress(buffered_reader.reader(), zlib_decode_stream.writer());

                const expected_write_len = file_chunk_header.uncompressedLength();

                if (try zlib_decode_stream.getPos() != expected_write_len) {
                    try std.io.getStdOut().writer().print(
                        "Wrong decompress write length: should be {}, is {}\n",
                        .{ expected_write_len, try zlib_decode_stream.getPos() },
                    );
                    return false;
                }
            },
        }

        entries_count += 1;
    }

    return true;
}
