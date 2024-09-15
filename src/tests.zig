const std = @import("std");

const expect = std.testing.expect;

const Ymlz = @import("root.zig").Ymlz;

test "Multiple elements in yaml file" {
    const MultiElement = struct {
        name: []const u8,
        bool_val: bool,
        int_val: u8,
        float_val: f64,
    };

    const Elements = struct { elements: []MultiElement };

    const yml_file_location = try std.fs.cwd().realpathAlloc(
        std.testing.allocator,
        "./resources/multiple_elements.yml",
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Elements).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
    defer ymlz.deinit(result);

    // Ensure both elements are parsed as expected and we have 2
    try expect(result.elements.len == 2);

    // Test 1st element
    try expect(result.elements[0].bool_val == true);
    try expect(std.mem.eql(u8, result.elements[0].name, "Example Name"));

    // Test 2nd element
    try expect(result.elements[1].bool_val == false);
    try expect(std.mem.eql(u8, result.elements[1].name, "Example Name 2"));

    // Test Ints
    try expect(result.elements[0].int_val == 0);
    try expect(result.elements[1].int_val == 120);

    // Test floats
    try expect(result.elements[0].float_val == 3.14);
    try expect(result.elements[1].float_val == 56.123);
}

test "98YD with bools" {
    const Element = struct {
        name: []const u8,
        from: []const u8,
        tags: []const u8,
        yaml: []const u8,
        tree: []const u8,
        json: []const u8,
        dump: []const u8,
        bool_val: bool,
        bool_val_2: bool,
        bool_val_with_spaces: bool,
    };

    const Experiment = struct {
        elements: []Element,
    };

    const yml_file_location = try std.fs.cwd().realpathAlloc(
        std.testing.allocator,
        "./resources/yaml-test-suite/98YD-mixed.yml",
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Experiment).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
    defer ymlz.deinit(result);

    const element = result.elements[0];

    // Test booleans
    try expect(element.bool_val == true);
    try expect(element.bool_val_2 == false);
    try expect(element.bool_val_with_spaces == true);

    try expect(std.mem.eql(u8, element.name, "Spec Example 5.5. Comment Indicator"));
    try expect(element.dump.len == 0);
}

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

test "QT73" {
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
        "./resources/yaml-test-suite/QT73.yml",
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Experiment).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
    defer ymlz.deinit(result);

    const element = result.elements[0];

    try expect(std.mem.eql(u8, element.name, "Comment and document-end marker"));
    try expect(std.mem.eql(u8, element.from, "@perlpunk"));
}
