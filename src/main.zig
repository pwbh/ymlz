const std = @import("std");

const Ymlz = @import("root.zig").Ymlz;

const Tutorial = struct {
    name: []const u8,
    type: []const u8,
    born: u16,
};

const Tester = struct {
    first: i32,
    second: i64,
    name: []const u8,
    fourth: f32,
    foods: [][]const u8,
    inner: struct {
        sd: i32,
        k: u8,
        l: []const u8,
        another: struct {
            new: f32,
            stringed: []const u8,
        },
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        return error.NoPathArgument;
    }

    const yml_location = args[1];
    var ymlz = try Ymlz(Tester).init(allocator);
    const result = try ymlz.load(yml_location);
    defer ymlz.deinit(result);

    std.debug.print("Tester: {any}\n", .{result});
    std.debug.print("Tester.name: {s}\n", .{result.name});
    std.debug.print("Tester.forth: {}\n", .{result.fourth});
    std.debug.print("Tester.foods: {any}\n", .{result.foods});
    std.debug.print("Tester.inner: {any}\n", .{result.inner});
}
