# Zig ANSI Escape Code Library

A lightweight, `comptime` Zig library for adding colors, styles, and other ANSI escape sequences to
your terminal output.

## Overview

This library provides a simple and efficient way to control terminal appearance and behavior using
ANSI escape codes. It offers:

* **SGR Codes:** For text styling like colors (16, 256, 24-bit RGB), bold, italic, underline, etc.
* **CSI Codes:** For cursor movement, screen clearing, alternate screen buffer, and more.
* **C0 Control Codes:** Basic terminal operations like bell, tab, etc.
* **Dual API:**
    1.  A `comptime` `format()` function for embedding ANSI codes within format strings, similar to
        `std.fmt.format`.
    2.  Direct access to `pub const` sequences and `pub fn` generator functions.

## Installation

Vendor the `src/ansi.zig` file or run
```
zig fetch --save git+https://github.com/pzittlau/ansi.git
```

Then add the module to your executable in `build.zig`:
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // ... standard target and optimize options ...

    const exe = b.addExecutable(.{
        .name = "your_exe_name",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ansi_dep = b.dependency("ansi", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("ansi", ansi_dep.module("ansi")); // Expose the library's module as "ansi"

    // ... other build steps ...
}
```

## Usage

Import and use in your Zig code:
```zig
const std = @import("std");
const ansi = @import("ansi"); // "ansi" matches the name given in addModule

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Hello, {s}world!{s}\n", .{ansi.bold, ansi.reset});
}
```

See `src/main.zig` for more examples.

This library offers two primary ways to apply ANSI escape codes:

### Method 1: Using `ansi.format()`

The `ansi.format()` function processes a format string at compile time, replacing `{tags}` with
corresponding ANSI sequences. It automatically appends `ansi.reset` at the end.
```zig
const std = @import("std");
const ansi = @import("ansi");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Basic styling
    try stdout.print(ansi.format("This is {red}red text{reset}, and this is {green,bold}bold green text.\n"), .{});
    try stdout.print(ansi.format("Combined: {blue,italic,underline}Blue, Italic, Underlined.\n"), .{});

    // Parameterized colors
    try stdout.print(ansi.format("8-bit color: {8bit;160}Deep Red\n"), .{});
    try stdout.print(ansi.format("RGB color: {rgb;100;150;200}Custom Blue\n"), .{});
    try stdout.print(ansi.format("Background RGB: {bgRgb;30;60;30,white}White on Dark Green\n"), .{});

    // Cursor movement within format (parameters are for the ANSI command)
    try stdout.print(ansi.format("Move right: {cursorForward;10}Ten columns right.\n"), .{});

    // Mixing with standard std.fmt specifiers
    const name = "Ziggy";
    try stdout.print(ansi.format("Hello, {yellow,bold}{s}!\n"), .{name});
}
```
Tags within `{...}` are comma-separated for multiple SGR codes. For parameterized codes like `rgb`
or `cursorForward`, use semicolons to separate parameters for that specific code from its name
(e.g., `{rgb;100;150;200}`).

### Method 2: Direct Usage (Constants and Functions)

You can directly use exported `pub const` string literals for simple codes or call `pub fn`
generator functions for parameterized codes.
```zig
const std = @import("std");
const ansi = @import("ansi");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Using constants
    try stdout.print(ansi.bold ++ ansi.magenta ++ "Bold Magenta Text" ++ ansi.reset ++ "\n", .{});
    try stdout.print(ansi.erase_display_all, .{});

    // Using generator functions
    const custom_bg = comptime ansi.bg8bit(228);
    try stdout.print(ansi.rgb(255, 100, 50) ++ "Orange text" ++ ansi.reset ++ "\n", .{});
    try stdout.print(custom_bg ++ ansi.black ++ "Black on Pale Yellow BG" ++ ansi.reset ++ "\n", .{});

    // Cursor movement
    try stdout.print(ansi.cursorPosition(10, 5) ++ "Now at 10,5" ++ ansi.reset ++ "\n", .{});

    // For compile-time string construction, ensure generator function calls are comptime
    const comptime_str = "Header: " ++ comptime ansi.underline ++ "Title" ++ ansi.reset;
    try stdout.print(comptime_str ++ "\n", .{});
}
```

## Available Codes

The library provides a wide range of:
- SGR codes: `reset`, `bold`, `italic`, `underline`, various colors (`red`, `bg_blue`), bright
  colors (`red_bright`), color functions (`rgb`, `8bit`, `bgRgb`, `underline8bit`, etc.), font
  styles.
- CSI codes (constants): `erase_display_all`, `erase_line_all`, `cursor_show`, `cursor_hide`,
  `alt_screen_buffer_enable`, etc.
- CSI codes (functions): `cursorUp(n)`, `cursorDown(n)`, `cursorPosition(col, row)`, `scrollUp(n)`,
  `scrollDown(n)`, etc.
- C0 codes: `bell`, `tab`, `line_feed`, `carriage_return`.

Please refer to `src/ansi.zig` for a complete list of available constants and functions.

## License

This library is licensed under the Apache License, Version 2.0. See the LICENSE file or the header
in src/ansi.zig for details.

Copyright © 2025 Pascal Zittlau
