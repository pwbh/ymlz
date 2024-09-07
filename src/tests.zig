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

    const element = result.elements[0];

    try expect(std.mem.eql(u8, element.name, "Spec Example 5.5. Comment Indicator"));
    // dump: ""
    try expect(element.dump.len == 0);
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

    const element = result.elements[0];

    try expect(std.mem.eql(u8, element.name, "Spec Example 6.20. Tag Handles"));
    try expect(std.mem.eql(u8, element.tree, "+STR\n +DOC ---\n  =VAL <tag:example.com,2000:app/foo> \"bar\n -DOC\n-STR"));
    try expect(std.mem.eql(u8, element.dump, "--- !<tag:example.com,2000:app/foo> \"bar\"\n"));
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

    const element = result.elements[0];

    try expect(std.mem.eql(u8, element.name, "More indented lines at the beginning of folded block scalars"));
    try expect(std.mem.eql(u8, element.json, "{\n  \"a\": \" more indented\\nregular\\n\",\n  \"b\": \"\\n\\n more indented\\nregular\\n\"\n}"));
}
