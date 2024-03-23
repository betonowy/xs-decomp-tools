const std = @import("std");

pub const StringStore = struct {
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
