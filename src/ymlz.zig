const std = @import("std");

const Allocator = std.mem.Allocator;

/// Count of spaces for one depth level
const INDENT_SIZE = 2;

const Dictionary = struct {
    key: []const u8,
    values: [][]const u8,
};

const Value = union(enum) {
    Simple: []const u8,
    Array: [][]const u8,
    Dictionary: Dictionary,
};

const Expression = struct {
    key: []const u8,
    value: Value,
    raw_representation: []const u8,
};

pub fn Ymlz(comptime Destination: type) type {
    return struct {
        allocator: Allocator,
        file: std.fs.File,
        current_parsed_expression: Expression,

        const Self = @This();

        pub fn init(allocator: Allocator, yml_path: []const u8) !Self {
            const file = try std.fs.openFileAbsolute(yml_path, .{ .mode = .read_only });

            return .{
                .allocator = allocator,
                .file = file,
                .current_parsed_expression = undefined,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
            // TODO: Need to save all references to where I allocate memory and make sure to deinit recursively from the end.
        }

        pub fn load(self: *Self) !Destination {
            var destination: Destination = undefined;

            if (@typeInfo(@TypeOf(destination)) != .Struct) {
                @panic("ymlz only able to load yml files into structs");
            }

            const destination_reflaction = @typeInfo(@TypeOf(destination));

            inline for (destination_reflaction.Struct.fields) |field| {
                std.debug.print("Field name: {s}\n", .{field.name});

                // TODO: Need to use the file descriptor and dynamically open the reader everyime, and when
                // new line is available, seek back and re-reade to new expression.
                const raw_line = try self.file.reader().readUntilDelimiterOrEofAlloc(
                    self.allocator,
                    '\n',
                    std.math.maxInt(usize),
                );

                if (self.isNewExpression(raw_line)) {
                    self.current_parsed_expression = try self.parseExpression(raw_line);
                } else {
                    self.continueExpressionParse();
                }

                const expression = try self.parseExpression(raw_line);
                const typeInfo = @typeInfo(field.type);

                switch (typeInfo) {
                    .Int => {
                        @field(destination, field.name) = try self.parseIntExpression(field.type, expression);
                    },
                    .Float => {
                        @field(destination, field.name) = try self.parseFloatExpression(field.type, expression);
                    },
                    .Pointer => {
                        if (typeInfo.Pointer.size == .Slice and typeInfo.Pointer.child == u8) {
                            @field(destination, field.name) = try self.parseStringExpression(expression);
                        } else if (typeInfo.Pointer.size == .Slice and typeInfo.Pointer.child == []const u8) {
                            std.debug.print("Need to handle this case\n", .{});
                        } else {
                            std.debug.print("Type info: {any}\n", .{@typeInfo([]const u8)});
                            @panic("unexpeted type recieved - " ++ @typeName(field.type) ++ "\n");
                        }
                    },
                    else => {
                        std.debug.print("Type info: {any}\n", .{@typeInfo([]const u8)});
                        @panic("unexpeted type recieved - " ++ @typeName(field.type) ++ "\n");
                    },
                }
            }

            return destination;
        }

        fn isNewExpression(self: *Self, raw_line: ?[]const u8) bool {
            _ = self;
            return raw_line != null and raw_line.?[0] != ' ';
        }

        fn parseStringExpression(self: *Self, expression: Expression) ![]const u8 {
            _ = self;

            if (expression.value != .Simple) {
                return error.ExpectedSimpleRecivedOther;
            }

            return expression.value.Simple;
        }

        fn parseFloatExpression(self: *Self, comptime T: type, expression: Expression) !T {
            _ = self;

            if (expression.value != .Simple) {
                return error.ExpectedSimpleRecivedOther;
            }

            return std.fmt.parseFloat(T, expression.value.Simple);
        }

        fn parseIntExpression(self: *Self, comptime T: type, expression: Expression) !T {
            _ = self;

            if (expression.value != .Simple) {
                return error.ExpectedSimpleRecivedOther;
            }

            return std.fmt.parseInt(T, expression.value.Simple, 10);
        }

        fn parseComplexExpression(self: *Self, expression: *Expression, depth: usize) !Expression {
            const indenth_depth = INDENT_SIZE * (depth + 1);

            expression.value = .{ .Array = &.{} };

            const raw_line = try self.file_reader.readUntilDelimiterOrEofAlloc(
                self.allocator,
                '\n',
                std.math.maxInt(usize),
            );

            if (raw_line) |line| {
                // making sure we are still in the correct depth, e.g. we are still trying to parse the same object
                // if we got here it means that the
                if (line[0..indenth_depth] != "  " ** depth) {
                    return self.parseExpression(raw_line);
                }

                switch (line[indenth_depth + 1]) {
                    '-' => {},
                    else => return error.UnknownComplexValue,
                }
            }

            return error.EOF;
        }

        fn parseExpression(self: *Self, raw_line: ?[]const u8) !Expression {
            var expression: Expression = undefined;

            // const possible_line = try self.file_reader.readUntilDelimiterOrEofAlloc(
            //     self.allocator,
            //     '\n',
            //     std.math.maxInt(usize),
            // );

            if (raw_line) |line| {
                expression.raw_representation = line;

                var tokens_iterator = std.mem.split(u8, line, ":");
                const key = tokens_iterator.next();

                if (key) |k| {
                    const value = tokens_iterator.next();

                    expression.key = k;

                    if (value) |v| {
                        // 0 - is a space
                        expression.value = .{ .Simple = v[1..v.len] };
                    } else {
                        self.parseComplexExpression(&expression, 0);
                        return expression;
                    }
                } else {
                    return error.ExpressionNoKey;
                }

                return expression;
            }

            return error.EOF;
        }

        fn getFieldValue(self: *Self) !?[]const u8 {
            var buf: [1024]u8 = undefined;

            while (true) {
                const byte = try self.file_reader.readByte();

                if (byte == ' ') {
                    continue;
                } else {
                    buf[0] = byte;
                    const total = try self.file_reader.readUntilDelimiterOrEof(buf[1..], '\n');

                    if (total) |t| {
                        return buf[0 .. t.len + 1];
                    }

                    return null;
                }
            }

            return null;
        }

        fn parseFileStart(self: *Self) !void {
            var buf: [2]u8 = undefined;
            _ = try self.file_reader.read(&buf);

            if (!std.mem.eql(u8, "--", &buf)) {
                return error.NotYaml;
            }
        }
    };
}
