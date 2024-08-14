const std = @import("std");

const Allocator = std.mem.Allocator;

const Dictionary = struct {
    key: []const u8,
    values: [][]const u8,
};

const Value = union(enum) {
    Simple: []const u8,
    Dictionary: Dictionary,
};

const Expression = struct {
    key: []const u8,
    value: Value,
};

pub fn Ymlz(comptime Destination: type, yml_path: []const u8) type {
    return struct {
        allocator: Allocator,
        file_start_found: bool,
        file_reader: std.fs.File.Reader,
        is_expression_start: bool,

        const Self = @This();

        pub fn init(allocator: Allocator) !Self {
            const file_ds = try std.fs.openFileAbsolute(yml_path, .{ .mode = .read_only });
            const file_reader = file_ds.reader();

            return .{
                .allocator = allocator,
                .file_start_found = false,
                .file_reader = file_reader,
                .is_expression_start = false,
            };
        }

        pub fn load(self: *Self) !Destination {
            var destination: Destination = undefined;

            if (@typeInfo(@TypeOf(destination)) != .Struct) {
                @panic("ymlz only able to load yml files into structs");
            }

            const destination_reflaction = @typeInfo(@TypeOf(destination));

            inline for (destination_reflaction.Struct.fields) |field| {
                std.debug.print("Field name: {s}\n", .{field.name});
                const expression = try self.parseExpression(null);
                const typeInfo = @typeInfo(field.type);

                switch (typeInfo) {
                    .Int => {
                        @field(destination, field.name) = try self.parseIntExpression(field.type, expression);
                    },
                    .Float => {
                        @field(destination, field.name) = try self.parseFloatExpression(field.type, expression);
                    },
                    .Pointer => {
                        if (typeInfo.Pointer.size == .Slice and typeInfo.Pointer.is_const and typeInfo.Pointer.child == u8) {
                            @field(destination, field.name) = try self.parseStringExpression(expression);
                        } else {
                            @panic("unexpeted type received - " ++ @typeName(field.type) ++ " expected []const u8\n");
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

        // TODO: rename to parseComplexExpression
        fn parseChildExpression(self: *Self, parent: Expression, child: *Expression) !Expression {
            _ = self;
            _ = parent;
            return child.*;
        }

        fn parseExpression(self: *Self, parent: ?Expression) !Expression {
            var expression: Expression = undefined;

            if (parent) |p| {
                return self.parseChildExpression(p, &expression);
            }

            const possible_line = try self.file_reader.readUntilDelimiterOrEofAlloc(
                self.allocator,
                '\n',
                std.math.maxInt(usize),
            );

            if (possible_line) |line| {
                var tokens_iterator = std.mem.split(u8, line, ": ");
                const key = tokens_iterator.next();

                if (key) |k| {
                    const value = tokens_iterator.next();

                    expression.key = k;

                    if (value) |v| {
                        expression.value = .{ .Simple = v };
                    } else {
                        return self.parseExpression(expression);
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
