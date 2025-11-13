const std = @import("std");

const Ymlz = @import("root.zig").Ymlz;

const Experiment = struct {
    first: i32,
    second: i64,
    name: []const u8,
    fourth: f32,
    foods: [][]const u8,
    inner: struct {
        abcd: i32,
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

    const yaml_content =
        \\first: 500
        \\second: -3
        \\name: just testing strings overhere # just a comment
        \\fourth: 142.241
        \\# comment in between lines
        \\foods:
        \\  - Apple
        \\  - Orange
        \\  - Strawberry
        \\  - Mango
        \\inner:
        \\  abcd: 12
        \\  k: 2
        \\  l: hello world                 # comment somewhere
        \\  another:
        \\    new: 1
        \\    stringed: its just a string
    ;

    var ymlz = try Ymlz(Experiment).init(allocator);
    const result = try ymlz.loadRaw(yaml_content);
    defer ymlz.deinit(result);

    std.debug.print("Experiment.first: {}\n", .{result.first});
}
