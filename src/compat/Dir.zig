const std = @import("std");

const File = std.fs.File;

const compat = @import("compat.zig");

const Io = compat.Io;

const Self = @This();

pub fn cwd() Self {
    return .{};
}

pub fn realPathFileAlloc(
    self: Self,
    io: Io,
    sub_path: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    _ = self;
    _ = io;
    return std.fs.cwd().realpathAlloc(allocator, sub_path);
}

pub fn openFileAbsolute(io: Io, absolute_path: []const u8, options: File.OpenFlags) !File {
    _ = io;
    return std.fs.openFileAbsolute(absolute_path, options);
}
