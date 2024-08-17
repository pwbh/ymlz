const std = @import("std");

const Ymlz = @import("ymlz.zig").Ymlz;

pub fn StructTag(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Struct => |st| {
            var enum_fields: [st.fields.len]std.builtin.Type.EnumField = undefined;
            inline for (st.fields, 0..) |field, index| {
                enum_fields[index] = .{
                    .name = field.name,
                    .value = index,
                };
            }
            return @Type(.{
                .Enum = .{
                    .tag_type = u16,
                    .fields = &enum_fields,
                    .decls = &.{},
                    .is_exhaustive = true,
                },
            });
        },
        else => @compileError("Not a struct"),
    }
}

pub fn setField(ptr: anytype, tag: StructTag(@TypeOf(ptr.*)), value: anytype) void {
    const T = @TypeOf(value);
    const st = @typeInfo(@TypeOf(ptr.*)).Struct;
    inline for (st.fields, 0..) |field, index| {
        if (tag == @as(@TypeOf(tag), @enumFromInt(index))) {
            if (field.type == T) {
                @field(ptr.*, field.name) = value;
            } else {
                @panic("Type mismatch: " ++ @typeName(field.type) ++ " != " ++ @typeName(T));
            }
        }
    }
}

const Tutorial = struct {
    name: []const u8,
    type: []const u8,
    born: u16,
};

const Tester = struct {
    first: i32,
    second: i64,
    name: []const u8,
    fourth: f32,
    foods: [][]const u8,
    testerino: struct {
        sd: i32,
        k: u8,
        l: []const u8,
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        return error.NoPathArgument;
    }

    const yml_location = args[1];
    var ymlz = try Ymlz(Tester).init(allocator, yml_location);
    const result = try ymlz.load();

    std.debug.print("Tester: {any}\n", .{result});
    std.debug.print("Tester.name: {s}\n", .{result.name});
    std.debug.print("Tester.forth: {}\n", .{result.fourth});
    std.debug.print("Tester.foods: {any}\n", .{result.foods});

    // const file = try std.fs.openFileAbsolute(yml_location, .{ .mode = .read_only });
    // defer file.close();
    // try file.seekBy(15);
    // var buf: [5]u8 = undefined;
    // _ = try file.reader().read(&buf);
    // std.debug.print("buf: {s}\n", .{buf});
    // try file.seekTo(0);
    // _ = try file.reader().read(&buf);
    // std.debug.print("buf: {s}\n", .{buf});
}
