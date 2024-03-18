const std = @import("std");
const stb = @import("stb");

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
        \\Usage: xs-sprite SPRITE_FILE OUTPUT_IMAGE
        \\
        \\Converts proprietary sprite into a png file + json metadata.
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

    const input_file = args[1];
    const output_file = args[2];

    try std.io.getStdOut().writer().print(
        \\
        \\Input file : "{s}"
        \\Output file: "{s}"
        \\
    , .{ input_file, output_file });

    const sprite_data = try std.fs.cwd().readFileAlloc(allocator, input_file, std.math.maxInt(usize));
    defer allocator.free(sprite_data);

    if (!isCweSprite(sprite_data)) return try std.io.getStdErr().writer().print("This is not a CWE sprite. Bye!\n", .{});

    const info = try getInfo(sprite_data);
    const data = try decodePixelData(allocator, info, sprite_data);
    defer allocator.free(data);

    if (std.fs.path.dirname(output_file)) |dir| try std.fs.cwd().makePath(dir);

    try stb.writeImageToFile(allocator, std.mem.sliceAsBytes(data), .{ info.width, info.height * info.frames }, 4, output_file);
}

const Color = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

const Info = struct {
    version_minor: u32,
    version_major: u32,
    key: u32,
    data_start: u32,
    len: u32,
    frames: u32,
    is_spx: bool,
    pallete: [256]Color,

    unk0: u32,
    unk1: u32,
    unk2: u32,
    unk3: u32,
    format: Format,
    unk5: u32,
    unk6: u32,

    center_x: u16,
    center_y: u16,
    width: u16,
    height: u16,
    fi_a: u16,
    fi_b: u16,

    const Format = enum(u32) {
        a = 0x1000,
        b = 0x7000,
        c = 0x8003,
    };
};

pub fn isCweSprite(data: []const u8) bool {
    if (data.len < 10) return false;
    return std.mem.eql(u8, data[0..10], "CWE sprite");
}

pub fn getInfo(data: []const u8) !Info {
    if (data.len < 19) return error.InvalidMetadata;

    const version_minor = std.mem.bytesToValue(u32, data[11..15]);
    const version_major = std.mem.bytesToValue(u32, data[15..19]);

    const is_spx: bool = brk: {
        if (version_minor == 36 and version_major == 12) break :brk false;
        if (version_minor == 44 and version_major == 18) break :brk true;
        return error.InvalidMetadata;
    };

    const header_size: u32 = if (is_spx) 59 else 51;

    if (data.len < header_size) return error.InvalidMetadata;

    const key = std.mem.bytesToValue(u32, data[19..23]);
    const len = std.mem.bytesToValue(u32, if (is_spx) data[51..55] else data[43..47]);
    const frame_count = std.mem.bytesToValue(u32, if (is_spx) data[55..59] else data[47..51]);

    const unk0 = std.mem.bytesToValue(u32, data[23..27]);
    const unk1 = std.mem.bytesToValue(u32, data[27..31]);
    const unk2 = std.mem.bytesToValue(u32, data[31..35]);
    const unk3 = std.mem.bytesToValue(u32, data[35..39]);
    const format = if (unk3 == 4) Info.Format.a else std.mem.bytesToValue(Info.Format, data[39..43]);
    const unk5 = if (is_spx) std.mem.bytesToValue(u32, data[43..47]) else 0;
    const unk6 = if (is_spx) std.mem.bytesToValue(u32, data[47..51]) else 0;

    const frame_def_start = header_size + len;
    const offset_begin = std.mem.bytesToValue(u32, data[frame_def_start + 0 .. frame_def_start + 4]);
    const frame_null = std.mem.bytesToValue(u32, data[frame_def_start + 0 .. frame_def_start + 4]);
    _ = offset_begin; // autofix
    _ = frame_null; // autofix
    const center_x = std.mem.bytesToValue(u16, data[frame_def_start + 8 .. frame_def_start + 10]);
    const center_y = std.mem.bytesToValue(u16, data[frame_def_start + 10 .. frame_def_start + 12]);
    const width = std.mem.bytesToValue(u16, data[frame_def_start + 12 .. frame_def_start + 14]);
    const height = std.mem.bytesToValue(u16, data[frame_def_start + 14 .. frame_def_start + 16]);
    const fi_a = if (is_spx) std.mem.bytesToValue(u16, data[frame_def_start + 16 .. frame_def_start + 18]) else 0;
    const fi_b = if (is_spx) std.mem.bytesToValue(u16, data[frame_def_start + 18 .. frame_def_start + 20]) else 0;

    const frame_data_size: usize = if (is_spx) 20 else 16;
    // const frame_data_size = 16;

    const pallete_start = header_size + len + frame_data_size * frame_count;

    for (0..frame_count) |i| {
        const offset = frame_def_start + frame_data_size * i;

        const w = std.mem.bytesToValue(u16, data[offset + 12 .. offset + 14]);
        const h = std.mem.bytesToValue(u16, data[offset + 14 .. offset + 16]);
        const a = std.mem.bytesToValue(u16, data[offset + 16 .. offset + 18]);
        const b = std.mem.bytesToValue(u16, data[offset + 18 .. offset + 20]);

        std.debug.print("w: {}, h: {}, a: {}, b: {}\n", .{ w, h, a, b });
    }

    var pallete: [256]Color = undefined;

    if (unk1 == 2 and unk2 == 1 and unk3 == 1) {
        const color_stride = 3;

        for (pallete[0..], 0..) |*entry, i| {
            entry.r = data[pallete_start + i * color_stride + 0];
            entry.g = data[pallete_start + i * color_stride + 1];
            entry.b = data[pallete_start + i * color_stride + 2];
            entry.a = 255;
        }
    } else if (unk1 == 1 and unk2 == 4 and unk3 == 4) {
        const color_stride = 4;

        for (pallete[0..], 0..) |*entry, i| {
            entry.r = data[pallete_start + i * color_stride + 0] *| 4;
            entry.g = data[pallete_start + i * color_stride + 1] *| 4;
            entry.b = data[pallete_start + i * color_stride + 2] *| 4;
            entry.a = 0xff - data[pallete_start + i * color_stride + 3] *| 4;
        }
    } else {
        @panic("Unknown pallete format");
    }

    return .{
        .version_minor = version_minor,
        .version_major = version_major,
        .key = key,
        .data_start = header_size,
        .len = len,
        .frames = frame_count,
        .width = width,
        .height = height,
        .is_spx = is_spx,
        .pallete = pallete,
        .unk0 = unk0,
        .unk1 = unk1,
        .unk2 = unk2,
        .unk3 = unk3,
        .format = format,
        .unk5 = unk5,
        .unk6 = unk6,
        .center_x = center_x,
        .center_y = center_y,
        .fi_a = fi_a,
        .fi_b = fi_b,
    };
}

pub fn decodePixelData(allocator: std.mem.Allocator, info: Info, data: []const u8) ![]const Color {
    const image = try allocator.alloc(Color, info.frames * info.width * info.height);
    errdefer allocator.free(image);

    const sprite_region = data[info.data_start .. info.data_start + info.len];

    @memset(image, std.mem.zeroes(std.meta.Child(@TypeOf(image))));

    switch (info.is_spx) {
        true => try decodePixelDataSpx(info, sprite_region, image),
        false => try decodePixelDataNonSpx(info, sprite_region, image),
    }

    // switch (info.is_spx) {
    //     true => decodePixelDataSpx(info, sprite_region, image) catch {}, // catch empty for debugging
    //     false => decodePixelDataNonSpx(info, sprite_region, image) catch {},
    // }

    return image;
}

fn pixelIndex(cx: u32, cy: u32, cf: u32, info: Info) u32 {
    return cx + cy * info.width + cf * info.width * info.height;
}

fn isFinished(cx: u32, cy: u32, cf: u32, info: Info) bool {
    return pixelIndex(cx, cy, cf, info) >= pixelIndex(0, 0, info.frames, info);
}

pub fn decodePixelDataSpx(info: Info, data: []const u8, image: []Color) !void {
    var cx: u32 = 0;
    var cy: u32 = 0;
    var cf: u32 = 0;

    const Scanline = packed struct {
        size: u16,
        sections: u16,

        pub const end_of_chain: u16 = 0xffff;
        pub const skip: u16 = 0x0000;
    };

    const Section = packed struct {
        jump: u16,
        size: u16,
    };

    // std.debug.print(
    //     \\Info:
    //     \\
    //     \\major {}
    //     \\minor {}
    //     \\
    //     \\key        {x}
    //     \\data_start {}
    //     \\len        {}
    //     \\
    //     \\frames {}
    //     \\
    //     \\cx     {}
    //     \\cy     {}
    //     \\width  {}
    //     \\height {}
    //     \\fi_a   {}
    //     \\fi_b   {}
    //     \\
    //     \\is_spx {}
    //     \\
    //     \\unk0   {x}
    //     \\unk1   {x}
    //     \\unk2   {x}
    //     \\unk3   {x}
    //     \\format {}
    //     \\unk5   {x}
    //     \\unk6   {x}
    //     \\
    // , .{
    //     info.version_major,
    //     info.version_minor,
    //     info.key,
    //     info.data_start,
    //     info.len,
    //     info.frames,
    //     info.center_x,
    //     info.center_y,
    //     info.width,
    //     info.height,
    //     info.fi_a,
    //     info.fi_b,
    //     info.is_spx,
    //     info.unk0,
    //     info.unk1,
    //     info.unk2,
    //     info.unk3,
    //     info.format,
    //     info.unk5,
    //     info.unk6,
    // });

    var stream = std.io.fixedBufferStream(data);
    const reader = stream.reader();

    while (cf < info.frames) {
        var current_scanline: Scanline = undefined;

        current_scanline.size = try reader.readInt(u16, .little);

        if (current_scanline.size == Scanline.end_of_chain) {
            cy = 0;
            cf += 1;
            continue;
        }

        if (current_scanline.size == Scanline.skip) {
            cy += 1;
            continue;
        }

        current_scanline.sections = try reader.readInt(u16, .little);

        var index_in_scanline: u32 = 0;
        while (index_in_scanline < current_scanline.sections) : (index_in_scanline += 1) {
            const current_section = try reader.readStruct(Section);
            if (current_section.jump > info.width) @panic("X coord overshot!");

            cx += current_section.jump;

            var index_in_section: u32 = 0;
            while (index_in_section < current_section.size) : (index_in_section += 1) {
                const index = pixelIndex(cx, cy, cf, info);
                image[index] = info.pallete[try reader.readByte()];
                if (info.format == Info.Format.b) image[index].a = try reader.readByte();
                cx += 1;
            }
        }

        cx = 0;
        cy += 1;
    }

    if (try stream.getPos() == try stream.getEndPos()) return;

    if (try reader.readInt(u16, .little) == Scanline.end_of_chain and try stream.getPos() == try stream.getEndPos()) return;

    std.log.warn("Didn't read the whole sprite!\n", .{});
    std.log.warn("Pos: {}, End: {}\n", .{ try stream.getPos(), try stream.getEndPos() });
}

pub fn decodePixelDataNonSpx(info: Info, data: []const u8, image: []Color) !void {
    _ = info; // autofix
    _ = data; // autofix
    _ = image; // autofix
    @panic("Non spx data not implemented yet!");
}
