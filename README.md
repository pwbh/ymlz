<h1 align="center">
  <img src="https://raw.githubusercontent.com/pwbh/ymlz/882bd9458b1a828a886b8a5e661706071944c8f3/imgs/logo.svg?token=A6PPCKPNZEG6CRWSUIJLFULGYTCGA" alt="ymlz" width="1007">
</h1>

<h4 align="center">Small and convenient <a href="https://en.wikipedia.org/wiki/YAML" target="_blank">YAML</a> parser</h4>

<p align="center">
  <a href="#key-features">Key Features</a> •
  <a href="#how-to-use">How To Use</a> •
  <a href="#support">Support</a> •
  <a href="#contribution">Contribution</a> •
  <a href="#license">License</a>
</p>

## Key Features

- Simple and straightforward to use thanks to built-in [reflections](https://ziglang.org/documentation/master/#Function-Reflection).
- Just define a struct and start using.
- Supports recursive struct.
- Deinitialization is handled for you, just call `deinit()` and you are done.
- Fields are automatically parsed based on field's type.

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

Now in your code you may import and use ymlz, I will be loading the following YAML file:

```yml
first: 500
second: -3
name: just testing strings overhere
fourth: 142.241
foods:
  - Apple
  - Orange
  - Strawberry
  - Mango
inner:
  sd: 12
  k: 2
  l: hello world
  another:
    new: 1
    stringed: its just a string
```

In your Zig codebase:

```zig
const std = @import("std");

const Ymlz = @import("ymlz").Ymlz;

// Notice how simple it is to define a struct that is one-to-one
// to the yaml file structure
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

    // We can print and see that all the fields have been loaded
    std.debug.print("Tester: {any}\n", .{result});
    // Lets try accessing the first field and printing it
    std.debug.print("First: {}\n", .{result.first});
}
```

## Contribution

You are more then welcomed to submit a PR, ymlz codebase is still pretty small and it should be relatively simple to get into it, if you have any questions regarding the project or you just need assist starting out, open an issue.

## Support

If you find a bug please [submit new issue](https://github.com/pwbh/ymlz/issues/new) and I will try to address it in my free time. I do however want to not that this project is used in my bigger project, so any bugs I find, I fix them without reporting them as an issue, so some issues may just be fixed without need an issue opened.

## License

Apache License 2.0.

Can be found under the [LICENSE](https://github.com/pwbh/ymlz/blob/master/LICENSE).
