const Self = @This();

const std = @import("std");

arr: std.ArrayList([]const u8),
current_index: usize,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .arr = std.ArrayList([]const u8).init(allocator),
        .current_index = 0,
    };
}

pub fn deinit(self: *Self) void {
    self.arr.deinit();
}

pub fn set(self: *Self, data: []const u8) !void {
    try self.arr.append(data);
}

pub fn get(self: *Self) ?[]const u8 {
    if (self.arr.items.len == 0) {
        return null;
    }

    if (self.current_index == self.arr.items.len) {
        self.current_index = 0;
        self.arr.clearAndFree();
        return null;
    }

    const element = self.arr.items[self.current_index];

    self.current_index += 1;

    return element;
}
