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
    raw: []const u8,
};

pub fn Ymlz(comptime Destination: type) type {
    return struct {
        allocator: Allocator,
        file: std.fs.File,
        current_parsed_expression: Expression,
        seeked: usize,

        const Self = @This();

        pub fn init(allocator: Allocator, yml_path: []const u8) !Self {
            const file = try std.fs.openFileAbsolute(yml_path, .{ .mode = .read_only });

            return .{
                .allocator = allocator,
                .file = file,
                .current_parsed_expression = undefined,
                .seeked = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
            // TODO: Need to save all references to where I allocate memory and make sure to deinit recursively from the end.
        }

        pub fn load(self: *Self) !Destination {
            if (@typeInfo(Destination) != .Struct) {
                @panic("ymlz only able to load yml files into structs");
            }

            return parse(self, Destination, 0);
        }

        fn parse(self: *Self, comptime T: type, depth: usize) !T {
            const indent_depth: usize = INDENT_SIZE * (depth + 1);

            var destination: T = undefined;

            const destination_reflaction = @typeInfo(@TypeOf(destination));

            inline for (destination_reflaction.Struct.fields) |field| {
                std.debug.print("Field name: {s}\n", .{field.name});

                const typeInfo = @typeInfo(field.type);

                switch (typeInfo) {
                    .Int => {
                        @field(destination, field.name) = try self.parseIntExpression(field.type, indent_depth);
                    },
                    .Float => {
                        @field(destination, field.name) = try self.parseFloatExpression(field.type, indent_depth);
                    },
                    .Pointer => {
                        if (typeInfo.Pointer.size == .Slice and typeInfo.Pointer.child == u8) {
                            @field(destination, field.name) = try self.parseStringExpression(indent_depth);
                        } else if (typeInfo.Pointer.size == .Slice and (typeInfo.Pointer.child == []const u8 or typeInfo.Pointer.child == []u8)) {
                            @field(destination, field.name) = try self.parseStringArrayExpression(
                                typeInfo.Pointer.child,
                                indent_depth,
                            );
                        } else {
                            std.debug.print("Type info: {any}\n", .{@typeInfo([]const u8)});
                            @panic("unexpeted type recieved - " ++ @typeName(field.type) ++ "\n");
                        }
                    },
                    .Struct => {
                        @field(destination, field.name) = try self.parse(field.type, indent_depth + 1);
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
            const raw_line = try self.file.reader().readUntilDelimiterOrEofAlloc(
                self.allocator,
                '\n',
                std.math.maxInt(usize),
            );

            if (raw_line) |line| {
                self.seeked += line.len + 1;
                // std.debug.print("Seeked by: {}\n", .{@as(i64, @intCast(line.len))});
                try self.file.seekTo(self.seeked);
            }

            return raw_line;
        }

        fn parseStringArrayExpression(self: *Self, comptime T: type, indent_depth: usize) ![]T {
            var list = std.ArrayList(T).init(self.allocator);
            defer list.deinit();

            const raw_line = try self.readFileLine() orelse return error.EOF;

            var split = std.mem.split(u8, raw_line, ":");
            _ = split.next() orelse return error.NoKeyParsed;

            while (true) {
                const raw_value_line = try self.readFileLine() orelse break;

                std.debug.print("Raw line: {s}\n", .{raw_value_line});

                if (raw_value_line[0] != ' ') {
                    // We stumbled on new field, so we rewind this advancement and return our parsed type.
                    try self.file.seekTo(self.seeked - raw_value_line.len - 1);
                    break;
                }

                try list.append(raw_value_line[indent_depth + 2 ..]);
            }

            return try list.toOwnedSlice();
        }

        fn parseStringExpression(self: *Self, indent_depth: usize) ![]const u8 {
            const expression = try self.parseSimpleExpression(indent_depth);

            if (expression.value != .Simple) {
                return error.ExpectedSimpleRecivedOther;
            }

            return expression.value.Simple;
        }

        fn parseFloatExpression(self: *Self, comptime T: type, indent_depth: usize) !T {
            const expression = try self.parseSimpleExpression(indent_depth);

            if (expression.value != .Simple) {
                return error.ExpectedSimpleRecivedOther;
            }

            return std.fmt.parseFloat(T, expression.value.Simple);
        }

        fn parseIntExpression(self: *Self, comptime T: type, indent_depth: usize) !T {
            const expression = try self.parseSimpleExpression(indent_depth);

            if (expression.value != .Simple) {
                return error.ExpectedSimpleRecivedOther;
            }

            return std.fmt.parseInt(T, expression.value.Simple, 10);
        }

        fn parseSimpleExpression(self: *Self, indent_depth: usize) !Expression {
            var expression: Expression = undefined;

            const raw_line = try self.readFileLine();

            if (raw_line) |line| {
                expression.raw = line[indent_depth..];

                std.debug.print("raw_line: {s}\n", .{expression.raw});

                var tokens_iterator = std.mem.split(u8, expression.raw, ":");

                const key = tokens_iterator.next() orelse return error.Whatever;
                // std.debug.print("key: {s}\n", .{key});
                const raw_value = tokens_iterator.next() orelse return error.NoValue;

                expression.key = key;
                expression.value = .{ .Simple = raw_value[1..] };
            } else {
                return error.EOF;
            }

            return expression;
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
