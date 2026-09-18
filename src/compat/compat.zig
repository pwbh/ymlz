const std = @import("std");
const builtin = @import("builtin");

pub const isZig0_16 = builtin.zig_version.major == 0 and builtin.zig_version.minor >= 16;

pub const Io = if (isZig0_16)
    std.Io
else
    struct {
        pub const Dir = @import("Dir.zig");
    };
