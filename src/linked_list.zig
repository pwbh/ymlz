const std = @import("std");

const Allocator = std.mem.Allocator;

const expect = std.testing.expect;

pub fn LinkedList(comptime T: type) type {
    return struct {
        head: ?*Node = null,
        tail: ?*Node = null,
        len: usize,
        allocator: Allocator,

        const Self = @This();

        const Node = struct {
            next: ?*Node = null,
            prev: ?*Node = null,
            value: T,
        };

        pub fn init(allocator: Allocator) Self {
            return .{
                .len = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            while (self.popFront()) |_| {}
        }

        pub fn appendFront(self: *Self, value: T) !void {
            const node = try self.allocator.create(Node);

            if (self.head == null) {
                node.* = .{ .value = value };
                self.head = node;
                self.tail = node;
            } else {
                const current_head = self.head.?;
                node.* = .{ .value = value, .next = current_head };
                current_head.prev = node;
                self.head = node;
            }

            self.len += 1;
        }

        pub fn appendBack(self: *Self, value: T) !void {
            if (self.tail == null) {
                try self.appendFront(value);
            } else {
                const current_tail = self.tail.?;
                const node = try self.allocator.create(Node);
                node.* = .{ .value = value, .prev = current_tail };
                current_tail.next = node;
                self.tail = node;
                self.len += 1;
            }
        }

        pub fn popFront(self: *Self) ?T {
            if (self.head == null) {
                return null;
            }

            const current_head = self.head.?;
            self.head = current_head.next;

            if (self.len == 1) {
                self.tail = null;
            }

            const value = current_head.value;
            self.allocator.destroy(current_head);
            self.len -= 1;

            return value;
        }

        pub fn popBack(self: *Self) ?T {
            if (self.tail == null) {
                return null;
            }

            const current_tail = self.tail.?;
            self.tail = current_tail.prev;

            if (self.len == 1) {
                self.head = null;
            }

            const value = current_tail.value;
            self.allocator.destroy(current_tail);
            self.len -= 1;

            return value;
        }

        pub fn printChain(self: *Self) void {
            var cursor = self.head;

            if (cursor == null) {
                std.debug.print("\n[]\n", .{});
                return;
            }

            std.debug.print("\n[", .{});
            while (cursor) |current_node| {
                if (current_node.next != null) {
                    std.debug.print("{} -> ", .{current_node.value});
                    cursor = current_node.next;
                } else {
                    std.debug.print("{}]\n", .{current_node.value});
                    break;
                }
            }
        }
    };
}

test "creates a linked list with appending via front and pops via back" {
    const allocator = std.testing.allocator;

    const linked_list = LinkedList(u32);

    var list = linked_list.init(allocator);

    defer list.deinit();

    try list.appendFront(1);
    try list.appendFront(2);
    try list.appendFront(3);

    list.printChain();

    try expect(list.len == 3);

    try expect(list.popBack() == 1);
    try expect(list.popBack() == 2);
    try expect(list.popBack() == 3);
    try expect(list.popBack() == null);

    try expect(list.len == 0);
}

test "creates a linked list with appending via back and pops via front" {
    const allocator = std.testing.allocator;

    var list = LinkedList(u32).init(allocator);

    defer list.deinit();

    try list.appendBack(1);
    try list.appendBack(2);
    try list.appendBack(3);

    try expect(list.len == 3);

    try expect(list.popFront() == 1);
    try expect(list.popFront() == 2);
    try expect(list.popFront() == 3);
    try expect(list.popFront() == null);

    try expect(list.len == 0);

    list.printChain();
}

test "creates a linked list with appending via back and front and pops via front" {
    const allocator = std.testing.allocator;

    var list = LinkedList(u32).init(allocator);

    defer list.deinit();

    try list.appendFront(1);
    try list.appendFront(2);
    try list.appendFront(3);

    try list.appendBack(1);
    try list.appendBack(2);
    try list.appendBack(3);

    list.printChain();

    try expect(list.len == 6);

    try expect(list.popFront() == 3);
    try expect(list.popFront() == 2);
    try expect(list.popFront() == 1);
    try expect(list.popFront() == 1);
    try expect(list.popFront() == 2);
    try expect(list.popFront() == 3);
    try expect(list.popFront() == null);

    try expect(list.len == 0);
}

test "creates a linked list with appending via back and front and pops via back" {
    const allocator = std.testing.allocator;

    var list = LinkedList(u32).init(allocator);

    defer list.deinit();

    try list.appendFront(1);
    try list.appendFront(2);
    try list.appendFront(3);

    try list.appendBack(1);
    try list.appendBack(2);
    try list.appendBack(3);

    list.printChain();

    try expect(list.len == 6);

    try expect(list.popBack() == 3);
    try expect(list.popBack() == 2);
    try expect(list.popBack() == 1);
    try expect(list.popBack() == 1);
    try expect(list.popBack() == 2);
    try expect(list.popBack() == 3);
    try expect(list.popBack() == null);

    try expect(list.len == 0);
}

test "creates a linked list with appending via front and auto pops via deinit" {
    const allocator = std.testing.allocator;

    var list = LinkedList(u32).init(allocator);

    try list.appendFront(1);
    try list.appendFront(2);
    try list.appendFront(3);

    try list.appendBack(1);
    try list.appendBack(2);
    try list.appendBack(3);

    try expect(list.len == 6);

    list.printChain();
    list.deinit();

    try expect(list.len == 0);

    try expect(list.popFront() == null);
    try expect(list.popBack() == null);
}

test "creates a linked list with elements appended mixed and popped via deinit" {
    const allocator = std.testing.allocator;

    var list = LinkedList(u32).init(allocator);

    try list.appendFront(1);
    try list.appendBack(2);
    try list.appendFront(5);
    try list.appendBack(2);
    try list.appendBack(4);
    try list.appendFront(3);
    try list.appendFront(3);

    try expect(list.len == 7);

    list.printChain();
    list.deinit();

    try expect(list.len == 0);
}

test "creates a linked list with elements appended mixed and pop mixed" {
    const allocator = std.testing.allocator;

    const linked_list = LinkedList(u32);

    var list = linked_list.init(allocator);

    try list.appendFront(1);
    try list.appendBack(2);
    try list.appendFront(5);
    try list.appendBack(2);
    try list.appendBack(4);
    try list.appendFront(3);
    try list.appendFront(3);

    try expect(list.len == 7);

    list.printChain();

    try expect(list.len == 0);
}
