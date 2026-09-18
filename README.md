<h1 align="center">
  <img src="https://raw.githubusercontent.com/pwbh/ymlz/ea6e6bf43dbe40edd66b46fc32be714546d38c6b/imgs/logo.svg" alt="ymlz" width="1007">
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
- Just define a struct, load a yml into it, and access your fields.
- Supports recursive struct.
- Deinitialization is handled for you, just call `deinit()` and you are done.
- Fields are automatically parsed based on field type.
- Ability to parse fields optionally.

## How To Use

Easiest way to use ymlz is to fetch it via `zig fetch`, **make sure to provide it the url of latest released version as the argument**.

See an example below.

```bash
zig fetch --save https://github.com/pwbh/ymlz/archive/refs/tags/0.6.0.tar.gz
```

Now in your `build.zig` we need to import ymlz as a module the following way:

```zig
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{ ... });

    const ymlz = b.dependency("ymlz", .{});
    exe.root_module.addImport("ymlz", ymlz.module("root"));
}
```

### Parsing YAML from file

We can utilize `loadFile` which expects the absolute path to your YAML file, I will be loading the following YAML file located in the root of my project under the name `file.yml`:

```yml
first: 500
second: -3
name: just testing strings overhere # just a comment
fourth: 142.241
# comment in between lines
foods:
  - Apple
  - Orange
  - Strawberry
  - Mango
inner:
  abcd: 12
  k: 2
  l: hello world # comment somewhere
  another:
    new: 1
    stringed: its just a string
```

main.zig:

```zig
/// Usage
/// zig build run -- ./file.yml
const std = @import("std");

const Ymlz = @import("ymlz").Ymlz;

// Notice how simple it is to define a struct that is one-to-one
// to the yaml file structure
const Experiment = struct {
        first: i32,
        second: i64,
        name: []const u8,
        fourth: f32,
        foods: [][]const u8,
        inner: struct {
            abcd: i32,
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

    const yml_path = try std.fs.cwd().realpathAlloc(
        allocator,
        yml_location,
    );
    defer allocator.free(yml_path);

    var ymlz = try Ymlz(Experiment).init(allocator);
    const result = try ymlz.loadFile(yml_path);
    defer ymlz.deinit(result);

    // We can print and see that all the fields have been loaded
    std.debug.print("Experiment: {any}\n", .{result});
    // Lets try accessing the first field and printing it
    std.debug.print("First: {}\n", .{result.first});
    // same goes for the array that we've defined `foods`
    for (result.foods) |food| {
        std.debug.print("{s}", .{food});
    }
}
```

### Parsing YAML from bytes

Parsing YAML file using generic `u8` slice for the sake of our example, lets parse a small YAML inlined in to some variable that contains our YAML in `[]const u8`.

```zig
const std = @import("std");

const Ymlz = @import("root.zig").Ymlz;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const yaml_content =
        \\first: 500
        \\second: -3
        \\name: just testing strings overhere # just a comment
        \\fourth: 142.241
        \\# comment in between lines
        \\foods:
        \\  - Apple
        \\  - Orange
        \\  - Strawberry
        \\  - Mango
        \\inner:
        \\  abcd: 12
        \\  k: 2
        \\  l: hello world                 # comment somewhere
        \\  another:
        \\    new: 1
        \\    stringed: its just a string
    ;

    const Experiment = struct {
        first: i32,
        second: i64,
        name: []const u8,
        fourth: f32,
        foods: [][]const u8,
        inner: struct {
            abcd: i32,
            k: u8,
            l: []const u8,
            another: struct {
                new: f32,
                stringed: []const u8,
            },
        },
    };

    var ymlz = try Ymlz(Experiment).init(allocator);
    const result = try ymlz.loadRaw(yaml_content);
    defer ymlz.deinit(result);

    std.debug.print("Experiment.first: {}\n", .{result.first});
}

```

### Parsing by providing a custom reader

It's possible to pass your own implementation for the `readLine` function to ymlz using `loadReader` which is used internally for both `loadFile` and `loadRaw`. See [internal implementation](https://github.com/pwbh/ymlz/blob/master/src/root.zig#L64) for reference. An instance of a struct implementing
the following function can be passed as reader:

```Zig
pub fn readLine(
    self: *Self,
    allocator: Allocator,
) !?[]const u8 {
    // ...
}
```

## Migrate to newer Zig Compiler Version

For convenience to upgrade to newer Zig compiler versions,
YMLZ can be used with two different compiler versions.

YMLZ Version | Zig 0.15.x | Zig 0.16.x | Zig 0.17.x
-------------|------------|------------|----------
0.6.0        |      X     |            |
0.6.1        |      X     |      X     |
0.7.0        |            |      X     |
0.7.1        |            |      X     |       X

Example:
1. Assume: Compiling with YMLZ 0.6.0 and Zig 0.15.x works successfully.
2. Update dependency to YMLZ 0.6.1. Then compiling with Zig 0.15.x will
   work successfully, too.
3. Update compiler to Zig 0.16.x. Most likely you have to migrate other
   things in your application, but all functions from YMLZ have the same
   signature and can be used in the same way as before.
4. Update dependency to YMLZ 0.7.0. The signature of the loadFile function
   has changed regarding to new `Io` struct introduced by Zig 0.16.x. You
   must pass an instance of the `Io` struct as the first argument. Normally
   the instance comes from the `init` parameter of type `std.process.Init` with
   a field named `io` from your `main` function, i.e.

```Zig
pub fn main(init: std.process.Init) !void {
    // ...
    ymlz.loadFile(init.io, path);
}
```

## Contribution

You are more then welcomed to submit a PR, ymlz codebase is still pretty small and it should be relatively simple to get into it, if you have any questions regarding the project or you just need assist starting out, open an issue.

## Support

If you find a bug please [submit new issue](https://github.com/pwbh/ymlz/issues/new) and I will try to address it in my free time. I do however want to note that this project is used in my bigger project, so any bugs I find, I fix without reporting them as an issue, so some issues that may have been reported have beeen fixed without me seeing them.

## License

Apache License 2.0. Can be found under the [LICENSE](https://github.com/pwbh/ymlz/blob/master/LICENSE).
