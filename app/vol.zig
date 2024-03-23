const std = @import("std");
const vol = @import("vol");

fn printUsage() !void {
    try std.io.getStdErr().writeAll(
        \\
        \\Usage: xs-vol validate VOL_FILE_PATH
        \\       xs-vol pack DIRECTORY_PATH VOL_FILE_PATH
        \\       xs-vol unpack VOL_FILE_PATH DIRECTORY_PATH
        \\
        \\TODO help
        \\
        \\
    );
}

const Mode = enum {
    validate,
    pack,
    unpack,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) std.debug.print("Main allocator has leaked memory.", .{});
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) return try printUsage();

    switch (std.meta.stringToEnum(Mode, args[1]) orelse return try printUsage()) {
        .validate => {
            if (args.len != 3) return try printUsage();

            try switch (try vol.validate(allocator, args[2])) {
                true => std.io.getStdOut().writeAll(" This VOL file is valid\n"),
                false => std.io.getStdOut().writeAll(" This VOL file is invalid\n"),
            };
        },
        .pack => {
            if (args.len != 4) return try printUsage();
            try vol.pack(allocator, args[2], args[3]);
        },
        .unpack => {
            if (args.len != 4) return try printUsage();
            try vol.unpack(allocator, args[2], args[3]);
        },
    }
}
