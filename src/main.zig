const std = @import("std");

const Ymlz = @import("root.zig").Ymlz;

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

    const yml_path = try std.fs.cwd().realpathAlloc(
        allocator,
        yml_location,
    );
    defer allocator.free(yml_path);

    var ymlz = try Ymlz(Experiment).init(allocator);
    const result = try ymlz.loadFile(yml_path);
    defer ymlz.deinit(result);

    std.debug.print("Tester: {s}\n", .{result.shaders[0].programs[0].fs.uniform_blocks[0].uniforms[0].name});
}
