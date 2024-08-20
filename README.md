<h1 align="center">
  <img src="https://github-production-user-asset-6210df.s3.amazonaws.com/127856937/359537404-cf806741-1bfe-43da-972c-462a8718982a.svg?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAVCODYLSA53PQK4ZA%2F20240820%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20240820T151806Z&X-Amz-Expires=300&X-Amz-Signature=9e04b0148e520d51c87ffdea15b67f0951cf21472d3c25e517a6ffa726ad2d2f&X-Amz-SignedHeaders=host&actor_id=127856937&key_id=0&repo_id=841125766" alt="Markdownify" width="1007">
</h1>

<h4 align="center">Small and convenient <a href="https://en.wikipedia.org/wiki/YAML" target="_blank">YAML</a> parser</h4>

<p align="center">
  <a href="#key-features">Key Features</a> •
  <a href="#how-to-use">How To Use</a> •
  <a href="#support">Support</a> •
  <a href="#contributions">Contributions</a> •
  <a href="#license">License</a>
</p>

## Key Features

- Simple and straightforward to use thanks to built-in [reflections](https://ziglang.org/documentation/master/#Function-Reflection).
- Just define a struct and start using.
- Supports recursive struct.
- Automatically de-inits your arrays.

## How To Use

Easiest way to use ymlz is to fetch it via `zig fetch` and provide it the url of latest released version as the argument. See an example below.

```bash
$ zig fetch --save https://github.com/pwbh/ymlz/archive/refs/tags/0.0.1.tar.gz
```

Now in your `build.zig` we need to import ymlz as a module the following way:

```zig
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{ ... });

    const ymlz = b.dependency("ymlz", .{});
    exe.root_module.addImport("ymlz", ymlz.module("root"));
}
```

Now in your code you may import and use ymlz:

```zig
const std = @import("std");

const Ymlz = @import("ymlz").Ymlz;

const Tester = struct {
    first: i32,
    second: i64,
    name: []const u8,
    fourth: f32,
    foods: [][]const u8,
    inner: struct {
        sd: i32,
        k: u8,
        l: []const u8,
        another: struct {
            new: f32,
            stringed: []const u8,
        },
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
    var ymlz = try Ymlz(Tester).init(allocator);
    const result = try ymlz.load(yml_location);
    defer ymlz.deinit(result);

    std.debug.print("Tester: {any}\n", .{result});
}
```

## Contributions

Contributions are welcomed, while codebase is still small it should be relatively simple to get into it, if any questions or assist is needed an issue can be open and I will reach out.

## Support

If you find a bug please [submit new issue](https://github.com/pwbh/ymlz/issues/new) and I will try to address it in my free time. I do however want to not that this project is used in my bigger project, so any bugs I find, I fix them without reporting them as an issue, so some issues may just be fixed without need an issue opened.

## License

Apache License 2.0.

Can be found under the [LICENSE](https://github.com/pwbh/ymlz/blob/master/LICENSE).
