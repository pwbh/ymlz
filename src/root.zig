const std = @import("std");

const Allocator = std.mem.Allocator;

const expect = std.testing.expect;

/// Count of spaces for one depth level
const INDENT_SIZE = 2;
const MAX_READ_SIZE = std.math.maxInt(usize);

const Dictionary = struct {
    key: []const u8,
    values: [][]const u8,
};

const Value = union(enum) {
    Simple: []const u8,
    KV: struct { key: []const u8, value: []const u8 },
    Array: [][]const u8,
    Dictionary: Dictionary,
};

const Expression = struct {
    value: Value,
    raw: []const u8,
};

pub fn Ymlz(comptime Destination: type) type {
    return struct {
        allocator: Allocator,
        file: ?std.fs.File,
        seeked: usize,
        allocations: std.ArrayList([]const u8),

        const Self = @This();

        pub fn init(allocator: Allocator) !Self {
            return .{
                .allocator = allocator,
                .file = null,
                .seeked = 0,
                .allocations = std.ArrayList([]const u8).init(allocator),
            };
        }

        pub fn deinit(self: *Self, st: anytype) void {
            defer self.allocations.deinit();

            for (self.allocations.items) |allocation| {
                self.allocator.free(allocation);
            }

            self.deinitRecursively(st);
        }

        pub fn load(self: *Self, yml_path: []const u8) !Destination {
            if (@typeInfo(Destination) != .Struct) {
                @panic("ymlz only able to load yml files into structs");
            }

            self.file = try std.fs.openFileAbsolute(yml_path, .{ .mode = .read_only });

            return parse(self, Destination, 0);
        }

        fn deinitRecursively(self: *Self, st: anytype) void {
            const destination_reflaction = @typeInfo(@TypeOf(st));

            if (destination_reflaction == .Struct) {
                inline for (destination_reflaction.Struct.fields) |field| {
                    const typeInfo = @typeInfo(field.type);

                    switch (typeInfo) {
                        .Pointer => {
                            if (typeInfo.Pointer.size == .Slice and typeInfo.Pointer.child != u8) {
                                const child_type_info = @typeInfo(typeInfo.Pointer.child);

                                if (child_type_info == .Pointer and child_type_info.Pointer.size == .Slice) {
                                    const inner = @field(st, field.name);
                                    self.deinitRecursively(inner);
                                }

                                const container = @field(st, field.name);
                                self.allocator.free(container);
                            }
                        },
                        .Struct => {
                            const inner = @field(st, field.name);
                            self.deinitRecursively(inner);
                        },
                        else => continue,
                    }
                }
            }
        }

        fn getIndentDepth(self: *Self, depth: usize) usize {
            _ = self;
            return INDENT_SIZE * depth;
        }

        fn parse(self: *Self, comptime T: type, depth: usize) !T {
            var destination: T = undefined;

            const destination_reflaction = @typeInfo(@TypeOf(destination));

            inline for (destination_reflaction.Struct.fields) |field| {
                const typeInfo = @typeInfo(field.type);

                const raw_line = try self.readFileLine() orelse break;

                switch (typeInfo) {
                    .Bool => {
                        @field(destination, field.name) = try self.parseBooleanExpression(raw_line, depth);
                    },
                    .Int => {
                        @field(destination, field.name) = try self.parseNumericExpression(field.type, raw_line, depth);
                    },
                    .Float => {
                        @field(destination, field.name) = try self.parseNumericExpression(field.type, raw_line, depth);
                    },
                    .Pointer => {
                        if (typeInfo.Pointer.size == .Slice and typeInfo.Pointer.child == u8) {
                            @field(destination, field.name) = try self.parseStringExpression(raw_line, depth);
                        } else if (typeInfo.Pointer.size == .Slice and (typeInfo.Pointer.child == []const u8 or typeInfo.Pointer.child == []u8)) {
                            @field(destination, field.name) = try self.parseArrayExpression(
                                typeInfo.Pointer.child,
                                raw_line,
                                depth + 1,
                            );
                        } else {
                            std.debug.print("Type info: {any}\n", .{@typeInfo([]const u8)});
                            @panic("unexpeted type recieved - " ++ @typeName(field.type) ++ "\n");
                        }
                    },
                    .Struct => {
                        @field(destination, field.name) = try self.parse(field.type, depth);
                    },
                    else => {
                        std.debug.print("Type info: {any}\n", .{@typeInfo([]const u8)});
                        @panic("unexpeted type recieved - " ++ @typeName(field.type) ++ "\n");
                    },
                }
            }

            return destination;
        }

        fn readFileLine(self: *Self) !?[]const u8 {
            const file = self.file orelse return error.NoFileFound;

            const raw_line = try file.reader().readUntilDelimiterOrEofAlloc(
                self.allocator,
                '\n',
                MAX_READ_SIZE,
            );

            if (raw_line) |line| {
                try self.allocations.append(line);
                self.seeked += line.len + 1;
                try file.seekTo(self.seeked);
            }

            return raw_line;
        }

        fn isNewExpression(self: *Self, raw_value_line: []const u8, indent_depth: usize) bool {
            _ = self;

            for (0..indent_depth) |depth| {
                if (raw_value_line[depth] != ' ') {
                    return true;
                }
            }

            return false;
        }

        fn parseArrayExpression(self: *Self, comptime T: type, raw_line: []const u8, depth: usize) ![]T {
            _ = raw_line;

            const indent_depth = self.getIndentDepth(depth);

            var list = std.ArrayList(T).init(self.allocator);
            defer list.deinit();

            while (true) {
                const raw_value_line = try self.readFileLine() orelse break;

                if (self.isNewExpression(raw_value_line, indent_depth)) {
                    const file = self.file orelse return error.NoFileFound;
                    // We stumbled on new field, so we rewind this advancement and return our parsed type.
                    // - 2 -> For some reason we need to go back twice + the length of the sentence for the '\n'
                    try file.seekTo(self.seeked - raw_value_line.len - 2);
                    break;
                }

                // for now only arrays of strings
                const value = try self.parseStringExpression(raw_value_line[indent_depth..], depth);

                try list.append(value);
            }

            return try list.toOwnedSlice();
        }

        fn parseStringExpression(self: *Self, raw_line: []const u8, depth: usize) ![]const u8 {
            const expression = try self.parseSimpleExpression(raw_line, depth);
            const value = self.getExpressionValue(expression);

            switch (value[0]) {
                '|' => {
                    return self.parseMultilineString(depth);
                },
                else => return value,
            }
        }

        fn parseMultilineString(self: *Self, depth: usize) ![]const u8 {
            const indent_depth = self.getIndentDepth(depth);

            var list = std.ArrayList(u8).init(self.allocator);
            defer list.deinit();

            while (true) {
                const raw_value_line = try self.readFileLine() orelse break;

                if (self.isNewExpression(raw_value_line, indent_depth)) {
                    const file = self.file orelse return error.NoFileFound;
                    // We stumbled on new field, so we rewind this advancement and return our parsed type.
                    // - 2 -> For some reason we need to go back twice + the length of the sentence for the '\n'
                    try file.seekTo(self.seeked - raw_value_line.len - 2);
                    _ = list.pop();
                    break;
                }

                const expression = try self.parseSimpleExpression(raw_value_line[indent_depth..], depth);
                const value = self.getExpressionValue(expression);

                try list.appendSlice(value);
                try list.append('\n');
            }

            const str = try list.toOwnedSlice();

            try self.allocations.append(str);

            return str;
        }

        fn getExpressionValue(self: *Self, expression: Expression) []const u8 {
            _ = self;

            switch (expression.value) {
                .Simple => return expression.value.Simple,
                .KV => return expression.value.KV.value,
                else => @panic("Not implemeted for " ++ @typeName(@TypeOf(expression.value))),
            }
        }

        fn parseBooleanExpression(self: *Self, raw_line: []const u8, depth: usize) !bool {
            const expression = try self.parseSimpleExpression(raw_line, depth);
            const value = self.getExpressionValue(expression);

            const isBooleanTrue = std.mem.eql(u8, value, "True") or std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "On") or std.mem.eql(u8, value, "on");

            if (isBooleanTrue) {
                return true;
            }

            const isBooleanFalse = std.mem.eql(u8, value, "False") or std.mem.eql(u8, value, "false") or std.mem.eql(u8, value, "Off") or std.mem.eql(u8, value, "off");

            if (isBooleanFalse) {
                return false;
            }

            return error.NotBoolean;
        }

        fn parseNumericExpression(self: *Self, comptime T: type, raw_line: []const u8, depth: usize) !T {
            const expression = try self.parseSimpleExpression(raw_line, depth);
            const value = self.getExpressionValue(expression);

            switch (@typeInfo(T)) {
                .Int => {
                    return std.fmt.parseInt(T, value, 10);
                },
                .Float => {
                    return std.fmt.parseFloat(T, value);
                },
                else => {
                    return error.UnrecognizedSimpleType;
                },
            }
        }

        fn parseSimpleExpression(self: *Self, raw_line: []const u8, depth: usize) !Expression {
            const indent_depth = self.getIndentDepth(depth);

            if (raw_line[0] == '-') {
                return .{
                    .value = .{ .Simple = raw_line[2..] },
                    .raw = raw_line,
                };
            }

            var tokens_iterator = std.mem.split(u8, raw_line[indent_depth..], ": ");

            const key = tokens_iterator.next() orelse return error.KeyNotFound;

            const value = tokens_iterator.next() orelse {
                return .{
                    .value = .{ .Simple = raw_line },
                    .raw = raw_line,
                };
            };

            return .{
                .value = .{ .KV = .{ .key = key, .value = value } },
                .raw = raw_line,
            };
        }
    };
}

test "should be able to parse simple types" {
    const Subject = struct {
        first: i32,
        second: i64,
        name: []const u8,
        fourth: f32,
    };

    const yml_file_location = try std.fs.cwd().realpathAlloc(
        std.testing.allocator,
        "./resources/super_simple.yml",
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Subject).init(std.testing.allocator);
    const result = try ymlz.load(yml_file_location);
    defer ymlz.deinit(result);

    try expect(result.first == 500);
    try expect(result.second == -3);
    try expect(std.mem.eql(u8, result.name, "just testing strings overhere"));
    try expect(result.fourth == 142.241);
}

test "should be able to parse array types" {
    const Subject = struct {
        first: i32,
        second: i64,
        name: []const u8,
        fourth: f32,
        foods: [][]const u8,
    };

    const yml_file_location = try std.fs.cwd().realpathAlloc(
        std.testing.allocator,
        "./resources/super_simple.yml",
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Subject).init(std.testing.allocator);
    const result = try ymlz.load(yml_file_location);
    defer ymlz.deinit(result);

    try expect(result.foods.len == 4);
    try expect(std.mem.eql(u8, result.foods[0], "Apple"));
    try expect(std.mem.eql(u8, result.foods[1], "Orange"));
    try expect(std.mem.eql(u8, result.foods[2], "Strawberry"));
    try expect(std.mem.eql(u8, result.foods[3], "Mango"));
}

test "should be able to parse deeps/recursive structs" {
    const Subject = struct {
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

    const yml_file_location = try std.fs.cwd().realpathAlloc(
        std.testing.allocator,
        "./resources/super_simple.yml",
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Subject).init(std.testing.allocator);
    const result = try ymlz.load(yml_file_location);
    defer ymlz.deinit(result);

    try expect(result.inner.sd == 12);
    try expect(result.inner.k == 2);
    try expect(std.mem.eql(u8, result.inner.l, "hello world"));
    try expect(result.inner.another.new == 1);
    try expect(std.mem.eql(u8, result.inner.another.stringed, "its just a string"));
}

test "should be able to parse booleans in all its forms" {
    const Subject = struct {
        first: bool,
        second: bool,
        third: bool,
        fourth: bool,
        fifth: bool,
        sixth: bool,
        seventh: bool,
        eighth: bool,
    };

    const yml_file_location = try std.fs.cwd().realpathAlloc(
        std.testing.allocator,
        "./resources/booleans.yml",
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Subject).init(std.testing.allocator);
    const result = try ymlz.load(yml_file_location);
    defer ymlz.deinit(result);

    try expect(result.first == true);
    try expect(result.second == false);
    try expect(result.third == true);
    try expect(result.fourth == false);
    try expect(result.fifth == true);
    try expect(result.sixth == true);
    try expect(result.seventh == false);
    try expect(result.eighth == false);
}

test "should be able to parse booleans multiline " {
    const Subject = struct { multiline: []const u8 };

    const yml_file_location = try std.fs.cwd().realpathAlloc(
        std.testing.allocator,
        "./resources/multilines.yml",
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Subject).init(std.testing.allocator);
    const result = try ymlz.load(yml_file_location);
    defer ymlz.deinit(result);

    try expect(std.mem.containsAtLeast(u8, result.multiline, 1, "asdoksad\n"));
    try expect(std.mem.containsAtLeast(u8, result.multiline, 1, "sdapdsadp\n"));
    try expect(std.mem.containsAtLeast(u8, result.multiline, 1, "sodksaodasd\n"));
    try expect(std.mem.containsAtLeast(u8, result.multiline, 1, "sdksdsodsokdsokd\n"));
}
