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

        pub fn deinit(self: *Self) void {
            for (self.allocations.items) |allocation| {
                self.allocator.free(allocation);
            }
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

            inline for (destination_reflaction.Struct.fields) |field| {
                const typeInfo = @typeInfo(field.type);

                switch (typeInfo) {
                    .Pointer => {
                        if (typeInfo.Pointer.size == .Slice and typeInfo.Pointer.child == u8) {
                            const child_type_info = @typeInfo(typeInfo.Pointer.child);

                            if (child_type_info == .Pointer and child_type_info.Pointer.size == .Slice) {
                                self.deinitRecursively(@field(st, field.name));
                            }

                            const array = @field(st, field.name);
                            std.debug.print("Freeing: {any}\n", .{array});
                            self.allocator.free(array);
                        } else {
                            std.debug.print("Type info: {any}\n", .{@typeInfo([]const u8)});
                            @panic("unexpeted type recieved - " ++ @typeName(field.type) ++ "\n");
                        }
                    },
                    .Struct => {
                        self.deinitRecursively(st);
                    },
                    else => continue,
                }
            }
        }

        fn parse(self: *Self, comptime T: type, depth: usize) !T {
            const indent_depth: usize = INDENT_SIZE * depth;

            var destination: T = undefined;

            const destination_reflaction = @typeInfo(@TypeOf(destination));

            inline for (destination_reflaction.Struct.fields) |field| {
                const typeInfo = @typeInfo(field.type);

                const raw_line = try self.readFileLine();

                switch (typeInfo) {
                    .Int => {
                        @field(destination, field.name) = try self.parseNumericExpression(field.type, raw_line, indent_depth);
                    },
                    .Float => {
                        @field(destination, field.name) = try self.parseNumericExpression(field.type, raw_line, indent_depth);
                    },
                    .Pointer => {
                        if (typeInfo.Pointer.size == .Slice and typeInfo.Pointer.child == u8) {
                            @field(destination, field.name) = try self.parseStringExpression(raw_line, indent_depth);
                        } else if (typeInfo.Pointer.size == .Slice and (typeInfo.Pointer.child == []const u8 or typeInfo.Pointer.child == []u8)) {
                            @field(destination, field.name) = try self.parseArrayExpression(
                                typeInfo.Pointer.child,
                                raw_line,
                                indent_depth,
                            );
                        } else {
                            std.debug.print("Type info: {any}\n", .{@typeInfo([]const u8)});
                            @panic("unexpeted type recieved - " ++ @typeName(field.type) ++ "\n");
                        }
                    },
                    .Struct => {
                        @field(destination, field.name) = try self.parseStruct(field.type, indent_depth);
                    },
                    else => {
                        std.debug.print("Type info: {any}\n", .{@typeInfo([]const u8)});
                        @panic("unexpeted type recieved - " ++ @typeName(field.type) ++ "\n");
                    },
                }
            }

            return destination;
        }

        fn parseStruct(self: *Self, comptime T: type, indent_depth: usize) !T {
            _ = try self.readFileLine();
            return self.parse(T, indent_depth + 1);
        }

        fn readFileLine(self: *Self) !?[]const u8 {
            const file = self.file orelse return error.NoFileFound;

            const raw_line = try file.reader().readUntilDelimiterOrEofAlloc(
                self.allocator,
                '\n',
                std.math.maxInt(usize),
            );

            if (raw_line) |line| {
                try self.allocations.append(line);

                self.seeked += line.len + 1;
                try file.seekTo(self.seeked);
            }

            return raw_line;
        }

        fn parseArrayExpression(self: *Self, comptime T: type, raw_line: ?[]const u8, indent_depth: usize) ![]T {
            var list = std.ArrayList(T).init(self.allocator);
            defer list.deinit();

            const line = raw_line orelse return error.EOF;

            var split = std.mem.split(u8, line, ":");
            _ = split.next() orelse return error.NoKeyParsed;

            while (true) {
                const raw_value_line = try self.readFileLine() orelse break;

                if (raw_value_line[indent_depth] != ' ') {
                    const file = self.file orelse return error.NoFileFound;

                    // We stumbled on new field, so we rewind this advancement and return our parsed type.
                    // - 2 -> For some reason we need to go back twice + the length of the sentence for the '\n'
                    try file.seekTo(self.seeked - raw_value_line.len - 2);
                    break;
                }

                // for now only arrays of strings
                const value = try self.parseStringExpression(raw_value_line[indent_depth..], indent_depth);

                try list.append(value);
            }

            return try list.toOwnedSlice();
        }

        fn parseStringExpression(self: *Self, raw_line: ?[]const u8, indent_depth: usize) ![]const u8 {
            const expression = try self.parseSimpleExpression(raw_line, indent_depth);

            if (expression.value != .Simple) {
                return error.ExpectedSimpleRecivedOther;
            }

            return expression.value.Simple;
        }

        fn getExpressionValue(self: *Self, expression: Expression) []const u8 {
            _ = self;

            switch (expression.value) {
                .Simple => return expression.value.Simple,
                .KV => return expression.value.KV.value,
                else => @panic("Not implemeted for " ++ @typeName(@TypeOf(expression.value))),
            }
        }

        fn parseNumericExpression(self: *Self, comptime T: type, raw_line: ?[]const u8, indent_depth: usize) !T {
            const expression = try self.parseSimpleExpression(raw_line, indent_depth);
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

        fn parseSimpleExpression(self: *Self, raw_line: ?[]const u8, indent_depth: usize) !Expression {
            _ = self;

            if (raw_line) |line| {
                if (line[0] == '-') {
                    return .{
                        .value = .{ .Simple = line[2..] },
                        .raw = line,
                    };
                }

                var tokens_iterator = std.mem.split(u8, line[indent_depth..], ": ");

                const key = tokens_iterator.next() orelse return error.KeyNotFound;
                const value = tokens_iterator.next() orelse return error.ValueNotFound;

                return .{
                    .value = .{ .KV = .{ .key = key, .value = value } },
                    .raw = line,
                };
            }

            return error.EOF;
        }
    };
}
