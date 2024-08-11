const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn Ymlz(comptime Destination: type, yml_path: []const u8) type {
    return struct {
        allocator: Allocator,
        file_start_found: bool,
        file_reader: std.fs.File.Reader,
        is_expression_start: bool,
        current_index: usize,
        current_field: usize,

        const Self = @This();

        pub fn init(allocator: Allocator) !Self {
            const file_ds = try std.fs.openFileAbsolute(yml_path, .{ .mode = .read_only });
            const file_reader = file_ds.reader();

            return .{
                .allocator = allocator,
                .file_start_found = false,
                .file_reader = file_reader,
                .is_expression_start = false,
                .current_index = 0,
                .current_field = 0,
            };
        }

        pub fn load(self: *Self) !Destination {
            var destination: Destination = undefined;

            if (@typeInfo(Destination) != .Struct) {
                @panic("ymlz only able to load into structs");
            }

            const destination_reflaction = @typeInfo(@TypeOf(destination));

            inline for (destination_reflaction.Struct.fields) |field| {
                std.debug.print("Type: {any}\n", .{@typeInfo(@TypeOf(field.type))});

                switch (@typeInfo(field.type)) {
                    .Int => {
                        // + 1 for the double colons
                        try self.file_reader.skipBytes(field.name.len + 1, .{});

                        if (try self.getFieldValue()) |value| {
                            std.debug.print("getFieldValue():{s}\n", .{value});

                            @field(destination, field.name) = try std.fmt.parseInt(field.type, value, 10);
                        } else {
                            @panic("received null instead of value\n");
                        }
                    },

                    else => {
                        @panic("unhandled type paseed - " ++ @typeName(field.type) ++ "\n");
                    },
                }
            }

            // while (true) {
            //     const byte = try self.file_reader.readByte();

            //     switch (byte) {
            //         ' ' => {},
            //         '\n' => {},
            //         '-' => {
            //             try self.parseFileStart();
            //         },
            //         else => try self.parseText(),
            //     }

            //     self.current_index += 1;
            // }

            return destination;
        }

        fn getFieldValue(self: *Self) !?[]const u8 {
            var buf: [1024]u8 = undefined;

            while (true) {
                const byte = try self.file_reader.readByte();

                if (byte == ' ') {
                    std.debug.print("HEREREREREERERE {any}\n", .{byte});
                    continue;
                } else {
                    std.debug.print("DAMN: {}\n", .{byte});
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
