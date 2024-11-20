const c = @cImport(@cInclude("stb/stb_image_write.h"));

const std = @import("std");

pub fn writeImageToFile(bytes: []const u8, s: @Vector(2, u32), channels: u32, file: std.fs.File) !void {
    if (bytes.len != @reduce(.Mul, s) * channels) return error.BufferLengthMetadataMismatch;

    const WriteCtx = struct {
        file: std.fs.File,

        pub fn write(ctx: ?*anyopaque, data: ?*anyopaque, size: c_int) callconv(.C) void {
            const self: *const @This() = @alignCast(@ptrCast(ctx.?));
            self.file.writeAll(@as([*]u8, @ptrCast(data.?))[0..@intCast(size)]) catch {};
        }
    };

    var ctx = WriteCtx{ .file = file };

    if (c.stbi_write_png_to_func(&WriteCtx.write, &ctx, @intCast(s[0]), @intCast(s[1]), @intCast(channels), bytes.ptr, @intCast(s[0] * channels)) == 0) {
        return error.StbError;
    }
}
