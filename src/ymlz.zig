const std = @import("std");

const Allocator = std.mem.Allocator;

const ExpressionType = enum {
    complex,
    simple,
};

const Expression = struct {
    key: []const u8,
    type: ExpressionType,
    value: []const u8 = undefined,
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
                const expression = try self.parseExpression();

                switch (@typeInfo(field.type)) {
                    .Int => {
                        std.debug.print("{any} key: {s} value: {s}\n", .{ expression, expression.key, expression.value });
                        @field(destination, field.name) = try self.parseIntExpression(field.type, expression);
                    },
                    .Pointer => {
                        const typeInfo = @typeInfo(field.type);

                        if (typeInfo.Pointer.size == .Slice and typeInfo.Pointer.is_const and typeInfo.Pointer.child == u8) {
                            @field(destination, field.name) = expression.value;
                        }
                    },
                    else => {
                        std.debug.print("Type info: {any}\n", .{@typeInfo([]const u8)});
                        @panic("unhandled type paseed - " ++ @typeName(field.type) ++ "\n");
                    },
                }
            }

            return destination;
        }

        fn parseIntExpression(_: *Self, comptime T: type, expression: Expression) !T {
            if (expression.type == .complex) {
                return error.NotIntButComplex;
            }

            return std.fmt.parseInt(T, expression.value, 10);
        }

        fn parseExpression(self: *Self) !Expression {
            var expression: Expression = undefined;

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
                    expression.type = if (value == null) .complex else .simple;

                    if (value) |v| {
                        expression.value = v;
                    } else {
                        return self.parseExpression();
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
