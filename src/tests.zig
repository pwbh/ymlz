const std = @import("std");

const expect = std.testing.expect;

const Ymlz = @import("root.zig").Ymlz;

test "98YD" {
    const Element = struct {
        name: []const u8,
        from: []const u8,
        tags: []const u8,
        yaml: []const u8,
        tree: []const u8,
        json: []const u8,
        dump: []const u8,
    };

    const Experiment = struct {
        elements: []Element,
    };

    const yml_file_location = try std.fs.cwd().realpathAlloc(
        std.testing.allocator,
        "./resources/yaml-test-suite/98YD.yml",
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Experiment).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
    defer ymlz.deinit(result);

    try expect(std.mem.eql(u8, result.elements[0].name, "Spec Example 5.5. Comment Indicator"));
}

test "CC74" {
    const Element = struct {
        name: []const u8,
        from: []const u8,
        tags: []const u8,
        yaml: []const u8,
        tree: []const u8,
        json: []const u8,
        dump: []const u8,
    };

    const Experiment = struct {
        elements: []Element,
    };

    const yml_file_location = try std.fs.cwd().realpathAlloc(
        std.testing.allocator,
        "./resources/yaml-test-suite/CC74.yml",
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Experiment).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
    defer ymlz.deinit(result);

    try expect(std.mem.eql(u8, result.elements[0].name, "Spec Example 6.20. Tag Handles"));
}

test "F6MC" {
    const Element = struct {
        name: []const u8,
        from: []const u8,
        tags: []const u8,
        yaml: []const u8,
        tree: []const u8,
        json: []const u8,
        emit: []const u8,
    };

    const Experiment = struct {
        elements: []Element,
    };

    const yml_file_location = try std.fs.cwd().realpathAlloc(
        std.testing.allocator,
        "./resources/yaml-test-suite/F6MC.yml",
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Experiment).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
    defer ymlz.deinit(result);

    try expect(std.mem.eql(u8, result.elements[0].name, "More indented lines at the beginning of folded block scalars"));
}
