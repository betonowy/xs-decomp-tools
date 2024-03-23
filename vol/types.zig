const std = @import("std");
const builtin = @import("builtin");

pub const ChunkHeader = extern struct {
    magic: [2]u8 = "VF".*,
    type: Type,
    metadata: Metadata,

    pub const Metadata = extern struct {
        field_a: u32,
        field_b: u32,
    };

    pub const Type = enum(u16) {
        compressed = 0x8000,
        raw = 0x0,
    };

    pub fn magicVerify(self: *const @This()) bool {
        return std.mem.eql(u8, &self.magic, "VF");
    }

    pub fn nextChunkOffset(self: *const @This(), current: u32) u32 {
        return current + @sizeOf(@This()) + self.chunkLength();
    }

    pub fn checksum(self: *const @This()) !u32 {
        return switch (self.type) {
            .compressed => error.InvalidChunkType,
            .raw => self.metadata.field_a,
        };
    }

    pub fn chunkLength(self: *const @This()) u32 {
        return switch (self.type) {
            .compressed => self.metadata.field_a,
            .raw => self.metadata.field_b,
        };
    }

    pub fn uncompressedLength(self: *const @This()) u32 {
        return switch (self.type) {
            .compressed => self.metadata.field_b,
            .raw => self.metadata.field_b,
        };
    }

    comptime {
        std.debug.assert(12 == @sizeOf(@This()));
    }
};

pub const TocEntry = extern struct {
    chunk_index: u16 = 0,
    additional_data_flag: ExtraDataFlag = .none,
    chunk_offset: u32 = 0,
    string_offset_to_label: u32 = 0,
    additional_data_offset: ExtraDataOffset = .invalid,
    string_offset_to_path: u32 = 0,
    file_length: u32 = 0,
    unknown_flag: UnknownFlag = .the_only_known_value,
    filetime: std.os.windows.FILETIME = std.mem.zeroes(std.os.windows.FILETIME),

    pub const ExtraDataFlag = enum(u16) { none = 0xb00, value_u32 = 0xf00, _ };
    pub const ExtraDataOffset = enum(u32) { invalid = 0xffffffff, _ };
    pub const UnknownFlag = enum(u32) { the_only_known_value = 0x20, _ };

    comptime {
        std.debug.assert(36 == @sizeOf(@This()));
    }
};

pub const Footer = extern struct {
    crc32: u32,
    total_size_of_chunks: u32,
    guid_compression_type: std.os.windows.GUID,
    guid_machine: std.os.windows.GUID,
    flag_32: u32 = flag_32_default,
    filetime: std.os.windows.FILETIME,
    length_of_last_chunk: u16,
    flag_16: u16 = flag_16_default,
    signature: [8]u8 = chaos_works_signature,

    pub const chaos_works_signature = " cweVOLF".*;
    pub const flag_32_default = 0x27110000;
    pub const flag_16_default = 0x4000;

    pub const guid_deflate = std.mem.bytesToValue(std.os.windows.GUID, &[_]u8{
        0x80, 0xe0, 0xe5, 0xb6, 0x07, 0x6e, 0xd1, 0x11,
        0x97, 0xdc, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00,
    });

    pub const guid_lzss = std.mem.bytesToValue(std.os.windows.GUID, &[_]u8{
        0x02, 0x5d, 0x35, 0xce, 0x39, 0x65, 0xd1, 0x11,
        0x97, 0xdc, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00,
    });

    pub const guid_rle8 = std.mem.bytesToValue(std.os.windows.GUID, &[_]u8{
        0x03, 0x5d, 0x35, 0xce, 0x39, 0x65, 0xd1, 0x11,
        0x97, 0xdc, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00,
    });

    pub const guid_no_compression = std.mem.bytesToValue(std.os.windows.GUID, &[_]u8{
        0x04, 0x5d, 0x35, 0xce, 0x39, 0x65, 0xd1, 0x11,
        0x97, 0xdc, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00,
    });

    pub const guid_lzari = std.mem.bytesToValue(std.os.windows.GUID, &[_]u8{
        0x83, 0x31, 0xd8, 0x8e, 0xb2, 0x66, 0xd1, 0x11,
        0x97, 0xdc, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00,
    });

    pub const guid_lzhuf = std.mem.bytesToValue(std.os.windows.GUID, &[_]u8{
        0x43, 0xc6, 0x9a, 0x62, 0xd6, 0x66, 0xd1, 0x11,
        0x97, 0xdc, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00,
    });

    pub const guid_packer_deflate = std.mem.bytesToValue(std.os.windows.GUID, &[_]u8{
        0x01, 0x5d, 0x35, 0xce, 0x39, 0x65, 0xd1, 0x11,
        0x97, 0xdc, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00,
    });

    comptime {
        std.debug.assert(64 == @sizeOf(@This()));
    }
};
