const std = @import("std");
const constants = @import("constants.zig");

const Suspense = @import("Suspense.zig");

const Allocator = std.mem.Allocator;

const compat = @import("compat/compat.zig");
const isZig0_16 = compat.isZig0_16;
const Dir = if (isZig0_16)
    std.Io.Dir
else
    compat.Io.Dir;
const File = if (isZig0_16)
    std.Io.File
else
    std.fs.File;
const Io = if (isZig0_16)
    std.Io
else
    compat.Io;
const Writer = if (isZig0_16)
    std.Io.Writer
else
    std.io.Writer;
const trimStart = if (isZig0_16)
    std.mem.trimStart
else
    std.mem.trimLeft;
const trimEnd = if (isZig0_16)
    std.mem.trimEnd
else
    std.mem.trimRight;

const expect = std.testing.expect;

const RawReader = struct {
    const Self = @This();

    raw: []const u8,
    index: usize = 0,

    pub fn readLine(
        self: *Self,
        allocator: Allocator,
    ) !?[]const u8 {
        if (self.index >= self.raw.len) {
            return null;
        }
        const remaining = self.raw[self.index..];
        const end = std.mem.indexOfScalar(u8, remaining, '\n') orelse remaining.len;
        if (end > constants.MAX_READ_SIZE) {
            return error.StreamTooLong;
        }
        const line = try allocator.dupe(u8, remaining[0..end]);
        self.index += if (end < remaining.len) end + 1 else end;
        return line;
    }
};

const FileReader = struct {
    const Self = @This();

    allocator: Allocator,
    io: Io,
    file: File,
    buffer: []u8,
    reader: File.Reader,

    pub fn init(allocator: Allocator, io: Io, yml_path: []const u8) !Self {
        const file = try Dir.openFileAbsolute(io, yml_path, .{ .mode = .read_only });
        if (isZig0_16) {
            errdefer file.close(io);
        } else {
            errdefer file.close();
        }
        const buffer = try allocator.alloc(u8, 4096);
        errdefer allocator.free(buffer);
        return .{
            .allocator = allocator,
            .io = io,
            .file = file,
            .buffer = buffer,
            .reader = if (isZig0_16)
                file.reader(io, buffer)
            else
                file.reader(buffer),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
        if (isZig0_16) {
            self.file.close(self.io);
        } else {
            self.file.close();
        }
    }

    pub fn readLine(
        self: *Self,
        allocator: std.mem.Allocator,
    ) !?[]const u8 {
        var line = Writer.Allocating.init(allocator);
        defer line.deinit();
        _ = self.reader.interface.streamDelimiter(
            &line.writer,
            '\n',
        ) catch |err| switch (err) {
            error.EndOfStream => {
                if (line.written().len == 0)
                    return null;
                return try allocator.dupe(u8, line.written());
            },
            else => return err,
        };
        // consume '\n'
        _ = try self.reader.interface.takeByte();
        return try allocator.dupe(u8, line.written());
    }
};

pub fn Ymlz(comptime Destination: type) type {
    const Value = union(enum) {
        Simple: []const u8,
        KV: struct { key: []const u8, value: []const u8 },
    };

    const Expression = struct {
        value: Value,
        raw: []const u8,
    };

    return struct {
        allocator: Allocator,
        allocations: std.ArrayList([]const u8),
        suspense: Suspense,

        const Self = @This();

        pub fn init(allocator: Allocator) !Self {
            return .{
                .allocator = allocator,
                .allocations = try std.ArrayList([]const u8).initCapacity(allocator, 0),
                .suspense = Suspense.init(allocator),
            };
        }

        pub fn deinit(self: *Self, st: anytype) void {
            defer self.allocations.deinit(self.allocator);

            for (self.allocations.items) |allocation| {
                self.allocator.free(allocation);
            }

            self.deinitRecursively(st, 0);

            self.suspense.deinit();
        }

        /// Uses absolute path for the yml file path. Can be used in conjunction
        /// such as `std.io.Dir.cwd()` in order to create relative paths.
        /// See Github README for example.
        pub fn loadFile(self: *Self, yml_path: []const u8) !Destination {
            if (isZig0_16) {
                var threaded: std.Io.Threaded = .init_single_threaded;
                const io = threaded.io();
                var reader: FileReader = try .init(self.allocator, io, yml_path);
                defer reader.deinit();
                return self.loadReader(&reader);
            } else {
                const io: Io = .{};
                var reader: FileReader = try .init(self.allocator, io, yml_path);
                defer reader.deinit();
                return self.loadReader(&reader);
            }
        }

        pub fn loadRaw(self: *Self, raw: []const u8) !Destination {
            var reader: RawReader = .{ .raw = raw };
            return self.loadReader(&reader);
        }

        /// Allows passing a reader which will be used to parse your raw yml bytes.
        pub fn loadReader(self: *Self, reader: anytype) !Destination {
            if (@typeInfo(Destination) != .@"struct") {
                @panic("ymlz only able to load yml files into structs");
            }

            return self.parse(reader, Destination, 0);
        }

        fn deinitRecursively(self: *Self, st: anytype, depth: usize) void {
            const destination_reflaction = @typeInfo(@TypeOf(st));

            if (destination_reflaction == .@"struct") {
                inline for (destination_reflaction.@"struct".fields) |field| {
                    const typeInfo = @typeInfo(field.type);
                    const actualTypeInfo = if (typeInfo == .optional) @typeInfo(typeInfo.optional.child) else typeInfo;

                    switch (actualTypeInfo) {
                        .pointer => {
                            if (actualTypeInfo.pointer.size == .slice and actualTypeInfo.pointer.child != u8) {
                                const child_type_info = @typeInfo(actualTypeInfo.pointer.child);

                                if (actualTypeInfo.pointer.size == .slice and child_type_info == .@"struct") {
                                    const inner = @field(st, field.name);

                                    if (typeInfo == .optional) {
                                        if (inner) |n| {
                                            for (n) |inner_st| {
                                                self.deinitRecursively(inner_st, depth + 1);
                                            }
                                        }
                                    } else {
                                        for (inner) |inner_st| {
                                            self.deinitRecursively(inner_st, depth + 1);
                                        }
                                    }
                                }

                                const container = @field(st, field.name);

                                if (typeInfo == .optional) {
                                    if (container) |c| {
                                        self.allocator.free(c);
                                    }
                                } else {
                                    self.allocator.free(container);
                                }
                            }
                        },
                        .@"struct" => {
                            const inner = @field(st, field.name);
                            self.deinitRecursively(inner, depth + 1);
                        },
                        else => continue,
                    }
                }
            }
        }

        fn isComment(line: []const u8) bool {
            for (line) |char| {
                if (char == '#') {
                    return true;
                }

                if (char != ' ') {
                    return false;
                }
            }

            return false;
        }

        fn getIndentDepth(depth: usize) usize {
            return constants.INDENT_SIZE * depth;
        }

        fn printFieldWithIdent(depth: usize, field_name: []const u8, raw_line: []const u8) void {
            // std.debug.print("printFieldWithIdent:", .{});
            for (0..depth) |_| {
                std.debug.print(" ", .{});
            }

            std.debug.print("{s}\t{s}\n", .{ field_name, raw_line });
        }

        fn trimLeadingSpaces(s: ?[]const u8) ?[]const u8 {
            const str = s orelse return null;
            var i: usize = 0;
            while (i < str.len and str[i] == ' ') : (i += 1) {}
            return str[i..];
        }

        fn getFieldName(raw_line: []const u8, depth: usize) ?[]const u8 {
            const indent = getIndentDepth(depth);
            const line = raw_line[indent..];
            var splitted = std.mem.splitSequence(u8, line, ":");
            // when running on linux, what gets returned here for a non-zero indent is a value prefixed with a space
            // getFieldName() - indent: 2 line: ' abcd: 12'
            // for example, when running the example, the inner struct field abcd is set to ' abcd' which causes issues
            // as it will crash because @panic("No such field in given yml file."). this occurs because when it does the comparison
            // on line 221 below, the compare looks like this: 'abcd' == ' abcd'
            return trimLeadingSpaces(splitted.next());
        }

        fn parse(self: *Self, reader: anytype, comptime T: type, depth: usize) !T {
            var destination: T = undefined;
            const destination_reflaction = @typeInfo(@TypeOf(destination));
            var totalFieldsParsed: usize = 0;

            // Make sure nullify all optional fields first
            inline for (destination_reflaction.@"struct".fields) |field| {
                if (@typeInfo(field.type) == .optional) {
                    @field(destination, field.name) = null;
                }
            }

            while (totalFieldsParsed < destination_reflaction.@"struct".fields.len) {
                const raw_line = try self.readLine(reader) orelse {
                    break;
                };

                if (raw_line.len == 0) {
                    continue;
                }

                if (totalFieldsParsed != 0 and newArrrayIndexPresent(raw_line)) {
                    try self.suspense.set(raw_line);
                    break;
                }

                const field_name = getFieldName(raw_line, depth) orelse {
                    @panic(("Failed to get field name from yml file."));
                };

                var is_field_parsed = false;

                inline for (destination_reflaction.@"struct".fields, 0..) |field, index| {
                    const type_info = @typeInfo(field.type);
                    const is_optional_field = type_info == .optional;

                    if (std.mem.eql(u8, field.name, field_name)) {
                        const actual_type_info = if (is_optional_field) @typeInfo(type_info.optional.child) else type_info;

                        try self.parseField(
                            actual_type_info,
                            reader,
                            &destination,
                            field,
                            raw_line,
                            depth,
                        );

                        is_field_parsed = true;
                    }

                    if (index == destination_reflaction.@"struct".fields.len - 1 and !is_field_parsed and is_optional_field) {
                        is_field_parsed = true;
                        try self.suspense.set(raw_line);
                    }
                }

                if (!is_field_parsed) {
                    @panic("No such field in given yml file.");
                } else {
                    totalFieldsParsed += 1;
                }
            }

            return destination;
        }

        inline fn parseField(
            self: *Self,
            actual_type_info: std.builtin.Type,
            reader: anytype,
            destination: anytype,
            field: std.builtin.Type.StructField,
            raw_line: []const u8,
            depth: usize,
        ) !void {
            switch (actual_type_info) {
                .bool => {
                    @field(destination, field.name) = try parseBooleanExpression(raw_line, depth);
                },
                .int => {
                    @field(destination, field.name) = try parseNumericExpression(field.type, raw_line, depth);
                },
                .float => {
                    @field(destination, field.name) = try parseNumericExpression(field.type, raw_line, depth);
                },
                .pointer => {
                    if (actual_type_info.pointer.size == .slice and actual_type_info.pointer.child == u8) {
                        @field(destination, field.name) = try self.parseStringExpression(reader, raw_line, depth, false);
                    } else if (actual_type_info.pointer.size == .slice and (actual_type_info.pointer.child == []const u8 or actual_type_info.pointer.child == []u8)) {
                        @field(destination, field.name) = try self.parseStringArrayExpression(reader, actual_type_info.pointer.child, depth + 1);
                    } else if (actual_type_info.pointer.size == .slice and @typeInfo(actual_type_info.pointer.child) != .pointer) {
                        @field(destination, field.name) = try self.parseArrayExpression(reader, actual_type_info.pointer.child, depth + 1);
                    } else {
                        @panic("unexpected pointer type recieved - " ++ @typeName(field.type) ++ "\n");
                    }
                },
                .@"struct" => {
                    @field(destination, field.name) = try self.parse(reader, field.type, depth + 1);
                },
                else => {
                    @panic("unexpected type recieved - " ++ @typeName(field.type) ++ "\n");
                },
            }
        }

        fn isOptionalFieldExists(lookup_key: []const u8, raw_line: []const u8, depth: usize) !bool {
            const indent_depth = getIndentDepth(depth);
            var split_iterator = std.mem.splitSequence(u8, raw_line[indent_depth..], ":");
            const key = split_iterator.next() orelse return false;
            return std.mem.eql(u8, key, lookup_key);
        }

        fn ignoreComment(line: []const u8) []const u8 {
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

        fn readRawLine(self: *Self, reader: anytype) !?[]const u8 {
            if (self.suspense.get()) |s| {
                return s;
            }
            const raw_line = try reader.readLine(self.allocator);
            if (raw_line) |line| {
                try self.allocations.append(self.allocator, line);
            }
            return raw_line;
        }

        fn readLine(self: *Self, reader: anytype) !?[]const u8 {
            const raw_line = try self.readRawLine(reader);

            if (raw_line) |line| {
                // TODO: What shoud really happen if a file has '---' which means a new document in the same file.
                if (isComment(line) or std.mem.eql(u8, "---", line)) {
                    // Skipping comments
                    return self.readLine(reader);
                }

                return ignoreComment(line);
            }

            return null;
        }

        fn newArrrayIndexPresent(raw_line: []const u8) bool {
            // Trim whitespace
            const trimmed_line = std.mem.trim(u8, raw_line, " ");
            var iter = std.mem.tokenizeScalar(u8, trimmed_line, ' ');
            const first_token = if (iter.next()) |token| token else "";
            if (!std.mem.eql(u8, first_token, "-")) return false;

            // Check for next token this if the first token is '-' should now be a field,
            // if that's true it means that we start a new index in array.
            if (iter.next()) |token| {
                const double_quotes = std.mem.count(u8, token, "\"");
                const is_new_field = std.mem.count(u8, token, ":");
                if (double_quotes == 0 and is_new_field == 1) return true;
            }
            return false;
        }

        fn isArrayEntryOnlyChar(raw_line: []const u8) bool {
            // Trim whitespace to see if this is only the array start char
            var trimmed_line = trimStart(u8, raw_line, " ");
            trimmed_line = trimEnd(u8, trimmed_line, " ");
            return std.mem.eql(u8, trimmed_line, "-");
        }

        fn isNewExpression(raw_value_line: []const u8, depth: usize) bool {
            if (raw_value_line.len == 0) {
                return false;
            }

            const indent_depth = getIndentDepth(depth);

            for (0..indent_depth) |d| {
                if (raw_value_line[d] != ' ') {
                    return true;
                }
            }

            return false;
        }

        fn parseStringArrayExpression(self: *Self, reader: anytype, comptime T: type, depth: usize) ![]T {
            var list = try std.ArrayList(T).initCapacity(self.allocator, 0);
            defer list.deinit(self.allocator);

            while (true) {
                const raw_value_line = try self.readLine(reader) orelse break;

                if (isNewExpression(raw_value_line, depth)) {
                    try self.suspense.set(raw_value_line);
                    break;
                }

                const result = try self.parseStringExpression(reader, raw_value_line, depth, false);

                try list.append(self.allocator, result);
            }

            return try list.toOwnedSlice(self.allocator);
        }

        fn parseArrayExpression(self: *Self, reader: anytype, comptime T: type, depth: usize) ![]T {
            var list = try std.ArrayList(T).initCapacity(self.allocator, 0);
            defer list.deinit(self.allocator);

            while (true) {
                const raw_value_line = try self.readLine(reader) orelse break;

                // If this is only the array entry char '-', just eat this line
                if (isArrayEntryOnlyChar(raw_value_line)) {
                    continue;
                }

                try self.suspense.set(raw_value_line);

                if (isNewExpression(raw_value_line, depth)) {
                    break;
                }

                const result = try self.parse(reader, T, depth + 1);

                try list.append(self.allocator, result);
            }

            return try list.toOwnedSlice(self.allocator);
        }

        fn parseStringExpression(self: *Self, reader: anytype, raw_line: []const u8, depth: usize, is_multiline: bool) ![]const u8 {
            const expression = try parseSimpleExpression(raw_line, depth, is_multiline);
            const value = getExpressionValueWithTrim(expression);

            if (value.len == 0) return value;

            switch (value[0]) {
                '|' => {
                    return self.parseMultilineString(reader, depth + 1, true);
                },
                '>' => {
                    return self.parseMultilineString(reader, depth + 1, false);
                },
                else => return value,
            }
        }

        fn parseMultilineString(self: *Self, reader: anytype, depth: usize, preserve_new_line: bool) ![]const u8 {
            var list = try std.ArrayList(u8).initCapacity(self.allocator, 0);
            defer list.deinit(self.allocator);

            while (true) {
                const raw_value_line = try self.readRawLine(reader) orelse break;

                if (isNewExpression(raw_value_line, depth)) {
                    try self.suspense.set(raw_value_line);
                    if (preserve_new_line)
                        _ = list.pop();
                    break;
                }

                const expression = try parseSimpleExpression(raw_value_line, depth, true);
                const value = getExpressionValue(expression);

                try list.appendSlice(self.allocator, value);

                if (preserve_new_line)
                    try list.append(self.allocator, '\n');
            }

            const str = try list.toOwnedSlice(self.allocator);

            try self.allocations.append(self.allocator, str);

            return str;
        }

        fn getExpressionValueWithTrim(expression: Expression) []const u8 {
            return std.mem.trim(u8, getExpressionValue(expression), " ");
        }

        fn getExpressionValue(expression: Expression) []const u8 {
            switch (expression.value) {
                .Simple => return expression.value.Simple,
                .KV => return expression.value.KV.value,
            }
        }

        fn parseBooleanExpression(raw_line: []const u8, depth: usize) !bool {
            const expression = try parseSimpleExpression(raw_line, depth, false);
            const value = getExpressionValueWithTrim(expression);

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

        fn parseNumericExpression(comptime T: type, raw_line: []const u8, depth: usize) !T {
            const expression = try parseSimpleExpression(raw_line, depth, false);
            const value = getExpressionValueWithTrim(expression);

            switch (@typeInfo(T)) {
                .int => {
                    return std.fmt.parseInt(T, value, 10);
                },
                .float => {
                    return std.fmt.parseFloat(T, value);
                },
                else => {
                    return error.UnrecognizedSimpleType;
                },
            }
        }

        fn withoutQuotes(line: []const u8) []const u8 {
            if ((line[0] == '\'' or line[0] == '"') and (line[line.len - 1] == '\'' or line[line.len - 1] == '"')) {
                return line[1 .. line.len - 1];
            }

            return line;
        }

        fn parseSimpleExpression(raw_line: []const u8, depth: usize, is_multiline: bool) !Expression {
            const indent_depth = getIndentDepth(depth);

            if (raw_line.len < indent_depth) {
                return .{
                    .value = .{ .Simple = raw_line },
                    .raw = raw_line,
                };
            }

            // NOTE: Need to think about this a bit more, maybe there is a cleaner solution for this.
            if (is_multiline) {
                return .{
                    .value = .{ .Simple = raw_line[indent_depth..] },
                    .raw = raw_line,
                };
            }

            const line = raw_line[indent_depth..];

            if (line[0] == '-') {
                return .{
                    .value = .{ .Simple = withoutQuotes(line[2..]) },
                    .raw = raw_line,
                };
            }

            var tokens_iterator = std.mem.splitSequence(u8, line, ": ");

            const key = tokens_iterator.next() orelse return error.KeyNotFound;

            const value = tokens_iterator.next() orelse {
                return .{
                    .value = .{ .Simple = withoutQuotes(line) },
                    .raw = raw_line,
                };
            };

            return .{
                .value = .{ .KV = .{ .key = key, .value = withoutQuotes(value) } },
                .raw = raw_line,
            };
        }
    };
}

test {
    _ = Suspense;
    _ = @import("tests.zig");
}

const testing_io: Io = if (isZig0_16)
    std.testing.io
else
    .{};

test "should be able to parse simple types" {
    const Subject = struct {
        first: i32,
        second: i64,
        name: []const u8,
        fourth: f32,
    };

    const yml_file_location = try Dir.cwd().realPathFileAlloc(
        testing_io,
        "./resources/super_simple.yml",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Subject).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
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

    const yml_file_location = try Dir.cwd().realPathFileAlloc(
        testing_io,
        "./resources/super_simple.yml",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Subject).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
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

    const yml_file_location = try Dir.cwd().realPathFileAlloc(
        testing_io,
        "./resources/super_simple.yml",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Subject).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
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

    const yml_file_location = try Dir.cwd().realPathFileAlloc(
        testing_io,
        "./resources/booleans.yml",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Subject).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
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

test "should be able to parse multiline" {
    const Subject = struct {
        multiline: []const u8,
        second_multiline: []const u8,
    };

    const yml_file_location = try Dir.cwd().realPathFileAlloc(
        testing_io,
        "./resources/multilines.yml",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Subject).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
    defer ymlz.deinit(result);

    try expect(std.mem.containsAtLeast(u8, result.multiline, 1, "asdoksad\n"));
    try expect(std.mem.containsAtLeast(u8, result.multiline, 1, "sdapdsadp\n"));
    try expect(std.mem.containsAtLeast(u8, result.multiline, 1, "sodksaodasd\n"));
    try expect(std.mem.containsAtLeast(u8, result.multiline, 1, "sdksdsodsokdsokd"));

    try expect(std.mem.eql(u8, result.second_multiline, "adsasdasdad  sdasadasdadasd"));
}

test "should be able to ignore single quotes and double quotes" {
    const Experiment = struct {
        one: []const u8,
        second: []const u8,
        three: []const u8,
    };

    const yml_file_location = try Dir.cwd().realPathFileAlloc(
        testing_io,
        "./resources/quotes.yml",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Experiment).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
    defer ymlz.deinit(result);

    try expect(std.mem.containsAtLeast(u8, result.one, 1, "testing without quotes"));
    try expect(std.mem.containsAtLeast(u8, result.second, 1, "trying to see if it will break"));
    try expect(std.mem.containsAtLeast(u8, result.three, 1, "hello world"));
}

test "should be able to parse arrays of T" {
    const Tutorial = struct {
        name: []const u8,
        type: []const u8,
        born: u64,
    };

    const Experiment = struct {
        name: []const u8,
        job: []const u8,
        skill: []const u8,
        employed: bool,
        foods: [][]const u8,
        languages: struct {
            perl: []const u8,
            python: []const u8,
            pascal: []const u8,
        },
        education: []const u8,
        tutorial: []Tutorial,
    };

    const yml_file_location = try Dir.cwd().realPathFileAlloc(
        testing_io,
        "./resources/tutorial.yml",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Experiment).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
    defer ymlz.deinit(result);

    try expect(std.mem.eql(u8, result.name, "Martin D'vloper"));
    try expect(std.mem.eql(u8, result.job, "Developer"));
    try expect(std.mem.eql(u8, result.foods[0], "Apple"));
    try expect(std.mem.eql(u8, result.foods[3], "Mango"));

    try expect(std.mem.eql(u8, result.tutorial[0].name, "YAML Ain't Markup Language"));
    try expect(std.mem.eql(u8, result.tutorial[0].type, "awesome"));
    try expect(result.tutorial[0].born == 2001);

    try expect(std.mem.eql(u8, result.tutorial[1].name, "JavaScript Object Notation"));
    try expect(std.mem.eql(u8, result.tutorial[1].type, "great"));
    try expect(result.tutorial[1].born == 2001);

    try expect(std.mem.eql(u8, result.tutorial[2].name, "Extensible Markup Language"));
    try expect(std.mem.eql(u8, result.tutorial[2].type, "good"));
    try expect(result.tutorial[2].born == 1996);
}

test "should be able to parse arrays and arrays in arrays" {
    const ImageSamplerPairs = struct {
        slot: u32,
        name: []const u8,
        image_name: []const u8,
        sampler_name: []const u8,
    };

    const Sampler = struct {
        slot: u32,
        name: []const u8,
        sampler_type: []const u8,
    };

    const Image = struct {
        slot: u64,
        name: []const u8,
        multisampled: bool,
        type: []const u8,
        sample_type: []const u8,
    };

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
        images: ?[]Image,
        samplers: ?[]Sampler,
        image_sampler_pairs: ?[]ImageSamplerPairs,
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

    const yml_path = try Dir.cwd().realPathFileAlloc(
        testing_io,
        "./resources/shader.yml",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(yml_path);

    var ymlz = try Ymlz(Experiment).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_path);
    defer ymlz.deinit(result);

    try expect(std.mem.eql(u8, result.shaders[0].programs[0].fs.uniform_blocks[0].uniforms[0].name, "u_color_override"));
    try expect(std.mem.eql(u8, result.shaders[0].slang, "glsl430"));
    try expect(result.shaders[0].programs[0].vs.images == null);
    try expect(result.shaders[0].programs[0].fs.images != null);
    try expect(result.shaders[0].programs[0].fs.images.?[0].slot == 0);
    try expect(std.mem.eql(u8, result.shaders[0].programs[0].fs.images.?[0].sample_type, "float"));
    try expect(std.mem.eql(u8, result.shaders[6].slang, "wgsl"));
    try expect(std.mem.eql(u8, result.shaders[6].programs[0].name, "default"));
    try expect(result.shaders[6].programs[0].vs.image_sampler_pairs == null);
    try expect(result.shaders[6].programs[0].fs.image_sampler_pairs.?[0].slot == 0);
    try expect(result.shaders[6].programs[0].fs.image_sampler_pairs != null);
    try expect(std.mem.eql(u8, result.shaders[6].programs[0].fs.image_sampler_pairs.?[0].sampler_name, "smp"));
}

test "should be able to to skip optional fields if non-existent in the parsed file" {
    const Subject = struct {
        first: i32,
        second: ?i64,
        name: []const u8,
        fourth: f32,
        foods: ?[][]const u8,
        more_foods: ?[][]const u8,
        inner: struct {
            abcd: i32,
            k: u32,
            l: []const u8,
            another: struct {
                new: i8,
                stringed: []const u8,
            },
        },
    };

    const yml_file_location = try Dir.cwd().realPathFileAlloc(
        testing_io,
        "./resources/super_simple_with_optional.yml",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Subject).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
    defer ymlz.deinit(result);

    try expect(result.first == 500);
    try expect(result.second == null);
    try expect(std.mem.eql(u8, result.name, "just testing strings overhere"));
    try expect(result.fourth == 142.241);

    const foods = result.foods.?;
    try expect(foods.len == 4);
    try expect(std.mem.eql(u8, foods[0], "Apple"));
    try expect(std.mem.eql(u8, foods[1], "Orange"));
    try expect(std.mem.eql(u8, foods[2], "Strawberry"));
    try expect(std.mem.eql(u8, foods[3], "Mango"));

    try expect(result.more_foods == null);

    try expect(result.inner.abcd == 12);
    try expect(std.mem.eql(u8, result.inner.another.stringed, "its just a string"));
}

test "should handle optional for new array index" {
    const Subject = struct {
        products: []struct {
            name: []const u8,
            num_products: u16,
            price: f32,
            fresh: bool,
            extra_information: ?[]const u8,
        },
    };
    const yml_file_location = try Dir.cwd().realPathFileAlloc(
        testing_io,
        "./resources/optional_array.yml",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(yml_file_location);

    var ymlz = try Ymlz(Subject).init(std.testing.allocator);
    const result = try ymlz.loadFile(yml_file_location);
    defer ymlz.deinit(result);

    try expect(result.products.len == 3);

    const products = result.products;
    try expect(std.mem.eql(u8, products[0].name, "pear"));
    try expect(std.mem.eql(u8, products[1].name, "bread"));
    try expect(std.mem.eql(u8, products[2].name, "yogurt"));

    try expect(products[0].extra_information == null);
    try expect(products[1].extra_information != null);
    try expect(products[2].extra_information == null);

    try expect(products[0].fresh == true);
    try expect(products[1].fresh == false);
    try expect(products[2].fresh == true);
}
