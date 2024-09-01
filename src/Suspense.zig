const Self = @This();

const std = @import("std");
const expect = std.testing.expect;

const Stack = std.DoublyLinkedList([]const u8);

allocator: std.mem.Allocator,
stack: Stack,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .stack = .{},
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    while (self.stack.pop()) |node| {
        self.allocator.destroy(node);
    }
}

pub fn set(self: *Self, data: []const u8) !void {
    const node = try self.allocator.create(Stack.Node);
    node.* = .{ .data = data };
    self.stack.append(node);
}

pub fn get(self: *Self) ?[]const u8 {
    if (self.stack.popFirst()) |node| {
        const ptr = node.data;
        self.allocator.destroy(node);
        return ptr;
    }

    return null;
}

test "should be able to init and deinit the stack" {
    var suspense = Self.init(std.testing.allocator);
    defer suspense.deinit();

    const some_string = "hello world";
    try suspense.set(some_string);

    try expect(std.mem.eql(u8, suspense.get().?, some_string));
}

test "should set new elements to the end but get from the start" {
    var suspense = Self.init(std.testing.allocator);
    defer suspense.deinit();

    try suspense.set("1");
    try suspense.set("2");
    try suspense.set("3");
    try suspense.set("4");
    try suspense.set("5");

    try expect(std.mem.eql(u8, suspense.get().?, "1"));
    try expect(std.mem.eql(u8, suspense.get().?, "2"));
    try expect(std.mem.eql(u8, suspense.get().?, "3"));
    try expect(std.mem.eql(u8, suspense.get().?, "4"));
    try expect(std.mem.eql(u8, suspense.get().?, "5"));
}

test "should return null when empty" {
    var suspense = Self.init(std.testing.allocator);
    defer suspense.deinit();

    try suspense.set("1");
    try suspense.set("2");

    try expect(std.mem.eql(u8, suspense.get().?, "1"));
    try expect(std.mem.eql(u8, suspense.get().?, "2"));
    try expect(suspense.get() == null);
    try expect(suspense.get() == null);
    try expect(suspense.get() == null);
}
