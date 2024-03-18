const c = @cImport({
    @cDefine("STB_IMAGE_WRITE_IMPLEMENTATION", {});
    @cDefine("STB_IMAGE_WRITE_STATIC", {});
    @cInclude("stb/stb_image_write.h");
});

const std = @import("std");

pub fn writeImageToFile(allocator: std.mem.Allocator, bytes: []const u8, s: @Vector(2, u32), channels: u32, filename: []const u8) !void {
    const filename_z = try allocator.dupeZ(u8, filename);
    defer allocator.free(filename_z);

    if (bytes.len != @reduce(.Mul, s) * channels) return error.BufferLengthMetadataMismatch;

    if (c.stbi_write_png(filename.ptr, @intCast(s[0]), @intCast(s[1]), @intCast(channels), bytes.ptr, @intCast(s[0] * channels)) == 0) {
        return error.StbError;
    }
}
