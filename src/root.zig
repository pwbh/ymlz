const std = @import("std");

const Suspense = @import("./Suspense.zig");

const Allocator = std.mem.Allocator;
const AnyReader = std.io.AnyReader;

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

const Suspensed = std.DoublyLinkedList([]const u8);

pub fn Ymlz(comptime Destination: type) type {
    return struct {
        allocator: Allocator,
        reader: ?AnyReader,
        allocations: std.ArrayList([]const u8),
        suspense: Suspense,

        const Self = @This();

        pub fn init(allocator: Allocator) !Self {
            return .{
                .allocator = allocator,
                .reader = null,
                .allocations = std.ArrayList([]const u8).init(allocator),
                .suspense = Suspense.init(allocator),
            };
        }

        pub fn deinit(self: *Self, st: anytype) void {
            defer self.allocations.deinit();

            for (self.allocations.items) |allocation| {
                self.allocator.free(allocation);
            }

            self.deinitRecursively(st, 0);

            self.suspense.deinit();
        }

        /// Uses absolute path for the yml file path. Can be used in conjunction
        /// such as `std.fs.cwd()` in order to create relative paths.
        /// See Github README for example.
        pub fn loadFile(self: *Self, yml_path: []const u8) !Destination {
            const file = try std.fs.openFileAbsolute(yml_path, .{ .mode = .read_only });
            defer file.close();
            const file_reader = file.reader();
            const any_reader: std.io.AnyReader = .{ .context = &file_reader.context, .readFn = fileRead };
            return self.loadReader(any_reader);
        }

        fn fileRead(context: *const anyopaque, buf: []u8) anyerror!usize {
            const file: *std.fs.File = @constCast(@alignCast(@ptrCast(context)));
            return std.fs.File.read(file.*, buf);
        }

        /// Allows passing a reader which will be used to parse your raw yml bytes.
        pub fn loadReader(self: *Self, reader: AnyReader) !Destination {
            if (@typeInfo(Destination) != .Struct) {
                @panic("ymlz only able to load yml files into structs");
            }

            self.reader = reader;

            return parse(self, Destination, 0);
        }

        fn deinitRecursively(self: *Self, st: anytype, depth: usize) void {
            const destination_reflaction = @typeInfo(@TypeOf(st));

            if (destination_reflaction == .Struct) {
                inline for (destination_reflaction.Struct.fields) |field| {
                    const typeInfo = @typeInfo(field.type);

                    switch (typeInfo) {
                        .Pointer => {
                            if (typeInfo.Pointer.size == .Slice and typeInfo.Pointer.child != u8) {
                                const child_type_info = @typeInfo(typeInfo.Pointer.child);

                                if (typeInfo.Pointer.size == .Slice and child_type_info == .Struct) {
                                    const inner = @field(st, field.name);

                                    for (inner) |inner_st| {
                                        self.deinitRecursively(inner_st, depth + 1);
                                    }
                                }

                                const container = @field(st, field.name);
                                self.allocator.free(container);
                            }
                        },
                        .Struct => {
                            const inner = @field(st, field.name);
                            self.deinitRecursively(inner, depth + 1);
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

        fn printFieldWithIdent(self: *Self, depth: usize, field_name: []const u8, raw_line: []const u8) void {
            _ = self;
            // std.debug.print("printFieldWithIdent:", .{});
            for (0..depth) |_| {
                std.debug.print(" ", .{});
            }

            std.debug.print("{s}\t{s}\n", .{ field_name, raw_line });
        }

        fn parse(self: *Self, comptime T: type, depth: usize) !T {
            var destination: T = undefined;

            const destination_reflaction = @typeInfo(@TypeOf(destination));

            inline for (destination_reflaction.Struct.fields) |field| {
                const typeInfo = @typeInfo(field.type);

                var raw_line: []const u8 = undefined;

                if (self.suspense.get()) |s| {
                    raw_line = s;
                } else {
                    raw_line = try self.readLine() orelse break;
                }

                if (raw_line.len == 0) break;

                // self.printFieldWithIdent(depth, field.name, raw_line);

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
                            @field(destination, field.name) = try self.parseStringArrayExpression(typeInfo.Pointer.child, depth + 1);
                        } else if (typeInfo.Pointer.size == .Slice and @typeInfo(typeInfo.Pointer.child) != .Pointer) {
                            @field(destination, field.name) = try self.parseArrayExpression(typeInfo.Pointer.child, depth + 1);
                        } else {
                            @panic("unexpected type recieved - " ++ @typeName(field.type) ++ "\n");
                        }
                    },
                    .Struct => {
                        @field(destination, field.name) = try self.parse(field.type, depth + 1);
                    },
                    else => {
                        @panic("unexpected type recieved - " ++ @typeName(field.type) ++ "\n");
                    },
                }
            }

            return destination;
        }

        fn ignoreComment(self: *Self, line: []const u8) []const u8 {
            _ = self;

            var comment_index: usize = 0;

            for (line, 0..line.len) |c, i| {
                if (c == '#') {
                    comment_index = i;
                    break;
                }
            }

            if (comment_index == 0) {
                return line;
            }

            for (1..comment_index) |i| {
                const from_end = comment_index - i;

                if (line[from_end] != ' ') {
                    return line[0 .. from_end + 1];
                }
            }

            return line;
        }

        fn readLine(self: *Self) !?[]const u8 {
            const reader = self.reader orelse return error.NoFileFound;
            const raw_line = try reader.readUntilDelimiterOrEofAlloc(
                self.allocator,
                '\n',
                MAX_READ_SIZE,
            );

            if (raw_line) |line| {
                try self.allocations.append(line);

                if (line[0] == '#') {
                    // Skipping comments
                    return self.readLine();
                }

                return self.ignoreComment(line);
            }

            return raw_line;
        }

        fn isNewExpression(self: *Self, raw_value_line: []const u8, depth: usize) bool {
            const indent_depth = self.getIndentDepth(depth);

            for (0..indent_depth) |d| {
                if (raw_value_line[d] != ' ') {
                    return true;
                }
            }

            return false;
        }

        fn parseStringArrayExpression(self: *Self, comptime T: type, depth: usize) ![]T {
            var list = std.ArrayList(T).init(self.allocator);
            defer list.deinit();

            while (true) {
                const raw_value_line = try self.readLine() orelse break;

                if (self.isNewExpression(raw_value_line, depth)) {
                    try self.suspense.set(raw_value_line);
                    break;
                }

                const result = try self.parseStringExpression(raw_value_line, depth);

                try list.append(result);
            }

            return try list.toOwnedSlice();
        }

        fn parseArrayExpression(self: *Self, comptime T: type, depth: usize) ![]T {
            var list = std.ArrayList(T).init(self.allocator);
            defer list.deinit();

            while (true) {
                const raw_value_line = try self.readLine() orelse break;

                try self.suspense.set(raw_value_line);

                if (self.isNewExpression(raw_value_line, depth)) {
                    break;
                }

                const result = try self.parse(T, depth + 1);

                try list.append(result);
            }

            return try list.toOwnedSlice();
        }

        fn parseStringExpression(self: *Self, raw_line: []const u8, depth: usize) ![]const u8 {
            const expression = try self.parseSimpleExpression(raw_line, depth);
            const value = self.getExpressionValue(expression);

            switch (value[0]) {
                '|' => {
                    return self.parseMultilineString(depth + 1, true);
                },
                '>' => {
                    return self.parseMultilineString(depth + 1, false);
                },
                else => return value,
            }
        }

        fn parseMultilineString(self: *Self, depth: usize, preserve_new_line: bool) ![]const u8 {
            var list = std.ArrayList(u8).init(self.allocator);
            defer list.deinit();

            while (true) {
                const raw_value_line = try self.readLine() orelse break;

                if (self.isNewExpression(raw_value_line, depth)) {
                    try self.suspense.set(raw_value_line);
                    if (preserve_new_line)
                        _ = list.pop();
                    break;
                }

                const expression = try self.parseSimpleExpression(raw_value_line, depth);
                const value = self.getExpressionValue(expression);

                try list.appendSlice(value);

                if (preserve_new_line)
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

        fn withoutQuotes(self: *Self, line: []const u8) []const u8 {
            _ = self;

            if (line[0] == '\'' or line[0] == '"' and line[line.len - 1] == '\'' or line[line.len - 1] == '"') {
                return line[1 .. line.len - 1];
            }

            return line;
        }

        fn parseSimpleExpression(self: *Self, raw_line: []const u8, depth: usize) !Expression {
            const indent_depth = self.getIndentDepth(depth);
            const line = raw_line[indent_depth..];

            if (line[0] == '-') {
                return .{
                    .value = .{ .Simple = self.withoutQuotes(line[2..]) },
                    .raw = raw_line,
                };
            }

            var tokens_iterator = std.mem.split(u8, line, ": ");

            const key = tokens_iterator.next() orelse return error.KeyNotFound;

            const value = tokens_iterator.next() orelse {
                return .{
                    .value = .{ .Simple = self.withoutQuotes(line) },
                    .raw = raw_line,
                };
            };

            return .{
                .value = .{ .KV = .{ .key = key, .value = self.withoutQuotes(value) } },
                .raw = raw_line,
            };
        }
    };
}

// test "should be able to parse simple types" {
//     const Subject = struct {
//         first: i32,
//         second: i64,
//         name: []const u8,
//         fourth: f32,
//     };

//     const yml_file_location = try std.fs.cwd().realpathAlloc(
//         std.testing.allocator,
//         "./resources/super_simple.yml",
//     );
//     defer std.testing.allocator.free(yml_file_location);

//     var ymlz = try Ymlz(Subject).init(std.testing.allocator);
//     const result = try ymlz.loadFile(yml_file_location);
//     defer ymlz.deinit(result);

//     try expect(result.first == 500);
//     try expect(result.second == -3);
//     try expect(std.mem.eql(u8, result.name, "just testing strings overhere"));
//     try expect(result.fourth == 142.241);
// }

// test "should be able to parse array types" {
//     const Subject = struct {
//         first: i32,
//         second: i64,
//         name: []const u8,
//         fourth: f32,
//         foods: [][]const u8,
//     };

//     const yml_file_location = try std.fs.cwd().realpathAlloc(
//         std.testing.allocator,
//         "./resources/super_simple.yml",
//     );
//     defer std.testing.allocator.free(yml_file_location);

//     var ymlz = try Ymlz(Subject).init(std.testing.allocator);
//     const result = try ymlz.loadFile(yml_file_location);
//     defer ymlz.deinit(result);

//     try expect(result.foods.len == 4);
//     try expect(std.mem.eql(u8, result.foods[0], "Apple"));
//     try expect(std.mem.eql(u8, result.foods[1], "Orange"));
//     try expect(std.mem.eql(u8, result.foods[2], "Strawberry"));
//     try expect(std.mem.eql(u8, result.foods[3], "Mango"));
// }

// test "should be able to parse deeps/recursive structs" {
//     const Subject = struct {
//         first: i32,
//         second: i64,
//         name: []const u8,
//         fourth: f32,
//         foods: [][]const u8,
//         inner: struct {
//             sd: i32,
//             k: u8,
//             l: []const u8,
//             another: struct {
//                 new: f32,
//                 stringed: []const u8,
//             },
//         },
//     };

//     const yml_file_location = try std.fs.cwd().realpathAlloc(
//         std.testing.allocator,
//         "./resources/super_simple.yml",
//     );
//     defer std.testing.allocator.free(yml_file_location);

//     var ymlz = try Ymlz(Subject).init(std.testing.allocator);
//     const result = try ymlz.loadFile(yml_file_location);
//     defer ymlz.deinit(result);

//     try expect(result.inner.sd == 12);
//     try expect(result.inner.k == 2);
//     try expect(std.mem.eql(u8, result.inner.l, "hello world"));
//     try expect(result.inner.another.new == 1);
//     try expect(std.mem.eql(u8, result.inner.another.stringed, "its just a string"));
// }

// test "should be able to parse booleans in all its forms" {
//     const Subject = struct {
//         first: bool,
//         second: bool,
//         third: bool,
//         fourth: bool,
//         fifth: bool,
//         sixth: bool,
//         seventh: bool,
//         eighth: bool,
//     };

//     const yml_file_location = try std.fs.cwd().realpathAlloc(
//         std.testing.allocator,
//         "./resources/booleans.yml",
//     );
//     defer std.testing.allocator.free(yml_file_location);

//     var ymlz = try Ymlz(Subject).init(std.testing.allocator);
//     const result = try ymlz.loadFile(yml_file_location);
//     defer ymlz.deinit(result);

//     try expect(result.first == true);
//     try expect(result.second == false);
//     try expect(result.third == true);
//     try expect(result.fourth == false);
//     try expect(result.fifth == true);
//     try expect(result.sixth == true);
//     try expect(result.seventh == false);
//     try expect(result.eighth == false);
// }

// test "should be able to parse multiline" {
//     const Subject = struct {
//         multiline: []const u8,
//         second_multiline: []const u8,
//     };

//     const yml_file_location = try std.fs.cwd().realpathAlloc(
//         std.testing.allocator,
//         "./resources/multilines.yml",
//     );
//     defer std.testing.allocator.free(yml_file_location);

//     var ymlz = try Ymlz(Subject).init(std.testing.allocator);
//     const result = try ymlz.loadFile(yml_file_location);
//     defer ymlz.deinit(result);

//     try expect(std.mem.containsAtLeast(u8, result.multiline, 1, "asdoksad\n"));
//     try expect(std.mem.containsAtLeast(u8, result.multiline, 1, "sdapdsadp\n"));
//     try expect(std.mem.containsAtLeast(u8, result.multiline, 1, "sodksaodasd\n"));
//     try expect(std.mem.containsAtLeast(u8, result.multiline, 1, "sdksdsodsokdsokd"));

//     try expect(std.mem.eql(u8, result.second_multiline, "adsasdasdad  sdasadasdadasd"));
// }

// test "should be able to ignore single quotes and double quotes" {
//     const Experiment = struct {
//         one: []const u8,
//         two: []const u8,
//         three: []const u8,
//     };

//     const yml_file_location = try std.fs.cwd().realpathAlloc(
//         std.testing.allocator,
//         "./resources/quotes.yml",
//     );
//     defer std.testing.allocator.free(yml_file_location);

//     var ymlz = try Ymlz(Experiment).init(std.testing.allocator);
//     const result = try ymlz.loadFile(yml_file_location);
//     defer ymlz.deinit(result);

//     try expect(std.mem.containsAtLeast(u8, result.one, 1, "testing without quotes"));
//     try expect(std.mem.containsAtLeast(u8, result.two, 1, "trying to see if it will break"));
//     try expect(std.mem.containsAtLeast(u8, result.three, 1, "hello world"));
// }

// test "should be able to parse arrays of T" {
//     const Tutorial = struct {
//         name: []const u8,
//         type: []const u8,
//         born: u64,
//     };

//     const Experiment = struct {
//         name: []const u8,
//         job: []const u8,
//         skill: []const u8,
//         employed: bool,
//         foods: [][]const u8,
//         languages: struct {
//             perl: []const u8,
//             python: []const u8,
//             pascal: []const u8,
//         },
//         education: []const u8,
//         tutorial: []Tutorial,
//     };

//     const yml_file_location = try std.fs.cwd().realpathAlloc(
//         std.testing.allocator,
//         "./resources/tutorial.yml",
//     );
//     defer std.testing.allocator.free(yml_file_location);

//     var ymlz = try Ymlz(Experiment).init(std.testing.allocator);
//     const result = try ymlz.loadFile(yml_file_location);
//     defer ymlz.deinit(result);

//     try expect(std.mem.eql(u8, result.name, "Martin D'vloper"));
//     try expect(std.mem.eql(u8, result.job, "Developer"));
//     try expect(std.mem.eql(u8, result.foods[0], "Apple"));
//     try expect(std.mem.eql(u8, result.foods[3], "Mango"));

//     try expect(std.mem.eql(u8, result.tutorial[0].name, "YAML Ain't Markup Language"));
//     try expect(std.mem.eql(u8, result.tutorial[0].type, "awesome"));
//     try expect(result.tutorial[0].born == 2001);

//     try expect(std.mem.eql(u8, result.tutorial[1].name, "JavaScript Object Notation"));
//     try expect(std.mem.eql(u8, result.tutorial[1].type, "great"));
//     try expect(result.tutorial[1].born == 2001);

//     try expect(std.mem.eql(u8, result.tutorial[2].name, "Extensible Markup Language"));
//     try expect(std.mem.eql(u8, result.tutorial[2].type, "good"));
//     try expect(result.tutorial[2].born == 1996);
// }

test "should be able to parse arrays and arrays in arrays" {
    const Uniform = struct {
        name: []const u8,
        type: []const u8,
        array_count: i32,
        offset: usize,
    };

    const UniformBlock = struct {
        slot: u64,
        size: u64,
        struct_name: []const u8,
        inst_name: []const u8,
        uniforms: []Uniform,
    };

    const Input = struct {
        slot: u64,
        name: []const u8,
        sem_name: []const u8,
        sem_index: usize,
    };

    const Details = struct {
        path: []const u8,
        is_binary: bool,
        entry_point: []const u8,
        inputs: []Input,
        outputs: []Input,
        uniform_blocks: []UniformBlock,
    };

    const Program = struct {
        name: []const u8,
        vs: Details,
        fs: Details,
    };

    const Shader = struct {
        slang: []const u8,
        programs: []Program,
    };

    const Experiment = struct {
        shaders: []Shader,
    };

    const yml_path = try std.fs.cwd().realpathAlloc(
        std.testing.allocator,
        "./resources/shader.yml",
    );
    defer std.testing.allocator.free(yml_path);

    var ymlz = try Ymlz(Experiment).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_path);
    defer ymlz.deinit(result);

    try expect(std.mem.eql(u8, result.shaders[0].programs[0].fs.uniform_blocks[0].uniforms[0].name, "u_color_override"));
}
