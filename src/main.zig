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

const Tester = struct {
    first: i32,
    second: i64,
    name: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var ymlz = try Ymlz(Tester, "/Users/pwbh/Workspace/ymlz/super_simple.yml").init(allocator);
    const result = try ymlz.load();

    std.debug.print("Tester: {any}\n", .{result});
    std.debug.print("Tester.name: {s}\n", .{result.name});
}
