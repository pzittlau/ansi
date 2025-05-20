//! This module provides a comprehensive toolkit for working with ANSI escape codes in Zig
//! applications. It allows for terminal text styling (SGR - Select Graphic Rendition), cursor
//! manipulation, screen erasing (CSI - Control Sequence Introducer), and other common C0 control
//! codes.
//!
//! # Features
//!
//! - **Rich SGR Support:** Includes codes for colors (standard, bright, 8-bit, RGB), text
//!   attributes (bold, italic, underline, etc.), and background colors.
//! - **CSI Commands:** Functions and constants for cursor movement, screen/line erasure, alternate
//!   screen buffer, cursor visibility, and more.
//! - **C0 Control Codes:** Common codes like BEL, TAB, LF, CR.
//! - **Flexible Usage:**
//!   1. **`format()` String (Compile-Time):** A powerful `comptime` function to embed ANSI
//!      sequences directly within a format string. Tags like `{red,bold}` or
//!      `{rgb;100;150;200;italic}` or `{cursorUp;5}` are resolved at compile time. An `ansi.reset`
//!      code is automatically appended by `format()`.
//!      Example: `const my_string = ansi.format("This is {red,underline}important{reset} info!");`
//!   2. **Direct Constants & Functions:** Exported `pub const` strings for fixed sequences (e.g.,
//!      `ansi.bold`, `ansi.erase_display_all`) and `pub fn` generators for parameterized codes
//!      (e.g., `ansi.rgb(r,g,b)`, `ansi.cursorUp(n)`). These functions return `[]const u8` and are
//!      safest when called with `comptime` (e.g., `comptime ansi.rgb(255,0,0)`) or when their
//!      result is immediately consumed (e.g., printed), as they use internal stack buffers for
//!      efficiency.
//!      Example: `const warning = ansi.yellow ++ "Warning:" ++ ansi.reset ++ " Be careful.";`
//!                `const move_up_5 = comptime ansi.cursorUp(5);`
//!
//! ================================================================================================
//!
//! Copyright © 2025 Pascal Zittlau
//!
//! Licensed under the Apache License, Version 2.0 (the "License");
//! you may not use this file except in compliance with the License.
//! You may obtain a copy of the License at
//!
//!     http://www.apache.org/licenses/LICENSE-2.0
//!
//! Unless required by applicable law or agreed to in writing, software
//! distributed under the License is distributed on an "AS IS" BASIS,
//! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//! See the License for the specific language governing permissions and
//! limitations under the License.

/// This function is used to format a string with ANSI escape codes. A reset code is added
/// automatically at the end of the string.
///
/// # Examples
/// ```zig
/// const ansi = @import("ansi");
/// const formatted1 = ansi.format("Hello, {green}{s}!{reset}");
/// const formatted2 = ansi.format("Hello, {green}{s}!");
/// // Both will print the same thing. But formatted1 will reset the formatting twice.
///
/// const formatted3 = ansi.format("Hello, {red,bold}{s}!");
/// const formatted4 = ansi.format("Hello, {bg_red,bold}{s}!");
/// const formatted5 = ansi.format("Hello, {red,bold,bg_blue}{s}!");
/// ```
pub fn format(comptime fmt: []const u8) []const u8 {
    @setEvalBranchQuota(2000000);
    comptime var out: []const u8 = "";
    comptime var i = 0;
    comptime var literal: []const u8 = "";
    comptime while (true) {
        const start_index = i;

        while (i < fmt.len) : (i += 1) {
            switch (fmt[i]) {
                '{', '}' => break,
                else => {},
            }
        }

        var end_index = i;
        var unescape_brace = false;

        // Handle {{ and }}, those are un-escaped as single braces
        if (i + 1 < fmt.len and fmt[i + 1] == fmt[i]) {
            unescape_brace = true;
            // Make the first brace part of the literal...
            end_index += 1;
            // ...and skip both
            i += 2;
        }

        literal = literal ++ fmt[start_index..end_index];

        // We've already skipped the other brace, restart the loop
        if (unescape_brace) continue;

        if (literal.len != 0) {
            out = out ++ literal;
            literal = "";
        }

        if (i >= fmt.len) break;

        if (fmt[i] == '}') {
            @compileError("missing opening {");
        }

        // Get past the {
        assert(fmt[i] == '{');
        i += 1;

        const fmt_begin = i;
        // Find the closing brace
        while (i < fmt.len and fmt[i] != '}') : (i += 1) {}
        const fmt_end = i;

        if (i >= fmt.len) {
            @compileError("missing closing }");
        }

        // Get past the }
        assert(fmt[i] == '}');
        i += 1;

        const args = "" ++ fmt[fmt_begin..fmt_end];
        var args_iter = std.mem.splitScalar(u8, args, ',');
        var had_non_ansi = false;
        var had_ansi = false;
        while (args_iter.next()) |arg| {
            if (fromText(arg)) |code| {
                out = out ++ code;
                had_ansi = true;
            } else {
                out = out ++ "{" ++ arg ++ "}";
                had_non_ansi = true;
            }
        }
        if (had_ansi and had_non_ansi) {
            @compileError(
                \\ Do not intermix ANSI formatting and non-ANSI formatting codes in one {}.
                \\ You may have a typo in your ANSI formatting.
            );
        }
    };

    // NOTE: Comment this line out if no reset is needed.
    out = out ++ comptime ansi.fromText("reset").?;
    return out;
}

/// Parses the text and returns the ANSI escape code if it's a valid name of an ANSI escape code.
/// Valid names are the names of the fields in the ansi struct, that are escape sequences and
/// the functions in the `color_functions` array.
/// Color functions expect u8 arguments. If they are out of range, the function will error.
pub fn fromText(text: []const u8) ?[]const u8 {
    inline for (std.meta.declarations(ansi)) |decl| {
        // We need to use startsWith because the name might be color_8bit, color_rgb, etc. and
        // after that come the arguments.
        if (!std.mem.startsWith(u8, text, decl.name)) {
            continue;
        }

        if (isEscapeSequence(decl)) {
            // If it's an escape sequence the name must be exactly the same.
            if (std.mem.eql(u8, text, decl.name)) {
                return @field(ansi, decl.name);
            }
        } else if (isEscapeFunction(decl)) {
            // If it's an escape function, parse and check the arguments.
            var args = std.mem.splitScalar(u8, text, ';');

            // The part before the first semicolon must be the same.
            if (!std.mem.eql(u8, args.next().?, decl.name)) {
                continue;
            }
            const F = @field(ansi, decl.name); // The function to call.
            const F_info = @typeInfo(@TypeOf(F)).@"fn";
            var F_args: std.meta.ArgsTuple(@TypeOf(F)) = undefined;

            for (F_info.params, 0..) |param, i| {
                const arg = args.next();
                if (arg == null) {
                    args.reset();
                    @compileError("Got not enough arguments after `" ++
                        decl.name ++ "`: " ++ args.rest());
                }

                const parsed = std.fmt.parseInt(param.type.?, arg.?, 10) catch |err| {
                    args.reset();
                    @compileError(@errorName(err) ++ ": Expected arguments of type `u8` after " ++
                        decl.name ++ ", got: " ++ args.rest());
                };

                F_args[i] = parsed;
            }
            if (args.peek() != null) {
                args.reset();
                @compileError("Got more arguments after `" ++
                    decl.name ++ "` than expexted: " ++ args.rest());
            }

            return @call(.auto, F, F_args);
        } else {
            // If it's not an escape sequence or a function, return null.
            return null;
        }
    }
    return null;
}

// ANSI escape codes for formatting.
pub const reset = "\x1b[0m";
pub const bold = "\x1b[1m";
pub const dim = "\x1b[2m";
pub const italic = "\x1b[3m";
pub const underline = "\x1b[4m";
pub const blink_slow = "\x1b[5m";
pub const blink_rapid = "\x1b[6m"; // not widely supported
pub const reverse = "\x1b[7m"; // not widely supported, same as invert
pub const invert = "\x1b[7m"; // not widely supported, same as reverse
pub const conceal = "\x1b[8m"; // not widely supported, same as hide
pub const hide = "\x1b[8m"; // not widely supported, same as conceal
pub const strike = "\x1b[9m";

pub const font_primary = "\x1b[10m";
pub const font_alt_1 = "\x1b[11m";
pub const font_alt_2 = "\x1b[12m";
pub const font_alt_3 = "\x1b[13m";
pub const font_alt_4 = "\x1b[14m";
pub const font_alt_5 = "\x1b[15m";
pub const font_alt_6 = "\x1b[16m";
pub const font_alt_7 = "\x1b[17m";
pub const font_alt_8 = "\x1b[18m";
pub const font_alt_9 = "\x1b[19m";

pub const fraktur = "\x1b[20m"; // rarely supported, same as gothic
pub const gothic = "\x1b[20m"; // rarely supported, same as fraktur
pub const underline_double = "\x1b[21m"; // sometimes disabled bold instead
pub const intensity_normal = "\x1b[22m";
pub const italic_not = "\x1b[23m";
pub const underline_not = "\x1b[24m";
pub const blink_not = "\x1b[25m";
pub const proportional_spacing = "\x1b[26m"; // rarely supported
pub const invert_not = "\x1b[27m";
pub const hide_not = "\x1b[28m";
pub const strike_not = "\x1b[29m";

pub const black = "\x1b[30m";
pub const red = "\x1b[31m";
pub const green = "\x1b[32m";
pub const yellow = "\x1b[33m";
pub const blue = "\x1b[34m";
pub const magenta = "\x1b[35m";
pub const cyan = "\x1b[36m";
pub const white = "\x1b[37m";
// Use color_8bit() and color_rgb() instead
// color_set_256: []const u8 = "\x1b[38m",
pub const color_default = "\x1b[39m"; // implementation defined

pub const bg_black = "\x1b[40m";
pub const bg_red = "\x1b[41m";
pub const bg_green = "\x1b[42m";
pub const bg_yellow = "\x1b[43m";
pub const bg_blue = "\x1b[44m";
pub const bg_magenta = "\x1b[45m";
pub const bg_cyan = "\x1b[46m";
pub const bg_white = "\x1b[47m";
// Use bg_color_8bit() and bg_color_rgb() instead
// bg_color_set_256: []const u8 = "\x1b[48m",
pub const bg_color_default = "\x1b[49m"; // implementation defined

pub const proportional_spacing_not = "\x1b[50m";
pub const framed = "\x1b[51m";
pub const encircled = "\x1b[52m";
pub const overlined = "\x1b[53m";
pub const framed_encircled_not = "\x1b[54m";
pub const overlined_not = "\x1b[55m";
// Use underline_color_8bit() and underline_color_rgb() instead
// underline_color: []const u8 = "\x1b[58m",
pub const underline_color_default = "\x1b[59m";

pub const ideogram_underline = "\x1b[60m"; // rarely supported, same as right_side_line
pub const right_side_line = "\x1b[60m"; // rarely supported, same as ideogram_underline
pub const ideogram_underline_double = "\x1b[61m"; // rarely supported, same as right_side_line_double
pub const right_side_line_double = "\x1b[61m"; // rarely supported, same as ideogram_underline_double
pub const ideogram_overline = "\x1b[62m"; // rarely supported, same as left_side_line
pub const left_side_line = "\x1b[62m"; // rarely supported, same as ideogram_overline
pub const ideogram_overline_double = "\x1b[63m"; // rarely supported, same as left_side_line_double
pub const left_side_line_double = "\x1b[63m"; // rarely supported, same as ideogram_overline_double
pub const ideogram_stress = "\x1b[64m"; // rarely supported
pub const ideogram_not = "\x1b[65m"; // rarely supported

pub const superscript = "\x1b[73m"; // rarely supported
pub const subscript = "\x1b[74m"; // rarely supported
pub const superscript_subscript_not = "\x1b[75m"; // rarely supported

pub const black_bright = "\x1b[90m";
pub const red_bright = "\x1b[91m";
pub const green_bright = "\x1b[92m";
pub const yellow_bright = "\x1b[93m";
pub const blue_bright = "\x1b[94m";
pub const magenta_bright = "\x1b[95m";
pub const cyan_bright = "\x1b[96m";
pub const white_bright = "\x1b[97m";

pub const bg_black_bright = "\x1b[100m";
pub const bg_red_bright = "\x1b[101m";
pub const bg_green_bright = "\x1b[102m";
pub const bg_yellow_bright = "\x1b[103m";
pub const bg_blue_bright = "\x1b[104m";
pub const bg_magenta_bright = "\x1b[105m";
pub const bg_cyan_bright = "\x1b[106m";
pub const bg_white_bright = "\x1b[107m";

/// Returns the ANSI escape code for an 8-bit color.
pub fn color8bit(n: u8) []const u8 {
    return @"8bit"(n);
}

/// Returns the ANSI escape code for an 8-bit color.
pub fn @"8bit"(n: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[38;5;{d}m", .{n}) catch unreachable;
    return out;
}

/// Returns the ANSI escape code for an 8-bit color.
pub fn bit8(n: u8) []const u8 {
    return @"8bit"(n);
}

/// Returns the ANSI escape code for an RGB color.
pub fn rgb(r: u8, g: u8, b: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[38;2;{d};{d};{d}m", .{ r, g, b }) catch unreachable;
    return out;
}

/// Returns the ANSI escape code for a background 8-bit color.
pub fn bg8bit(n: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[48;5;{d}m", .{n}) catch unreachable;
    return out;
}

/// Returns the ANSI escape code for a background RGB color.
pub fn bgRgb(r: u8, g: u8, b: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[48;2;{d};{d};{d}m", .{ r, g, b }) catch unreachable;
    return out;
}

/// Returns the ANSI escape code for an underline 8-bit color.
pub fn underline8bit(n: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[58;5;{d}m", .{n}) catch unreachable;
    return out;
}

/// Returns the ANSI escape code for an underline RGB color.
pub fn underlineRgb(r: u8, g: u8, b: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[58;2;{d};{d};{d}m", .{ r, g, b }) catch unreachable;
    return out;
}

// some C0 control codes
pub const bell = "\x07";
pub const backspace = "\x08";
pub const tab = "\x09";
pub const line_feed = "\x0a";
pub const form_feed = "\x0c";
pub const carriage_return = "\x0d";
pub const escape = "\x1b";

// some CSI (Control Sequence Introducer) control codes
pub const erase_display_to_end = "\x1b[0J"; // erase from cursor to end of display
pub const erase_display_to_start = "\x1b[1J"; // erase from cursor to start of display
pub const erase_display_all = "\x1b[2J"; // erase entire display
pub const erase_display_all_buf = "\x1b[3J"; // caution: also deletes the scrollback buffer
pub const erase_line_to_end = "\x1b[0K"; // erase from cursor to end of line
pub const erase_line_to_start = "\x1b[1K"; // erase from cursor to start of line
pub const erase_line_all = "\x1b[2K"; // erase entire line
pub const aux_on = "\x1b5i"; // enable auxiliary device
pub const aux_off = "\x1b4i"; // disable auxiliary device
pub const device_status_report = "\x1b6n"; // request device status
pub const cursor_position_save = "\x1bs"; // save cursor position
pub const cursor_position_restore = "\x1bu"; // restore cursor position
pub const cursor_show = "\x1b[?25h"; // show cursor
pub const cursor_hide = "\x1b[?25l"; // hide cursor
pub const focus_report_enable = "\x1b[?1004h"; // enable focus reporting
pub const focus_report_disable = "\x1b[?1004l"; // disable focus reporting
pub const alt_screen_buffer_enable = "\x1b[?1049h"; // enable alt screen buffer
pub const alt_screen_buffer_disable = "\x1b[?1049l"; // disable alt screen buffer
pub const bracketed_paste_mode_enable = "\x1b[200~"; // enable bracketed paste mode
pub const bracketed_paste_mode_disable = "\x1b[201~"; // disable bracketed paste mode

/// Moves the cursor up by `n` lines.
pub fn cursorUp(n: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[{d}A", .{n}) catch unreachable;
    return out;
}

/// Moves the cursor down by `n` lines.
pub fn cursorDown(n: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[{d}B", .{n}) catch unreachable;
    return out;
}

/// Moves the cursor forward by `n` characters.
pub fn cursorForward(n: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[{d}C", .{n}) catch unreachable;
    return out;
}

/// Moves the cursor backward by `n` characters.
pub fn cursorBack(n: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[{d}D", .{n}) catch unreachable;
    return out;
}

/// Moves the cursor to the beginning of line `n` lines down.
pub fn cursorNextLine(n: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[{d}E", .{n}) catch unreachable;
    return out;
}

/// Moves the cursor to the beginning of line `n` lines up.
pub fn cursorPreviousLine(n: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[{d}F", .{n}) catch unreachable;
    return out;
}

/// Moves the cursor to column `n`.
pub fn cursorHorizontalAbsolute(n: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[{d}G", .{n}) catch unreachable;
    return out;
}

/// Moves the cursor to column `n` and row `m`.
pub fn cursorPosition(n: u8, m: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ n, m }) catch unreachable;
    return out;
}

/// Scrolls the screen up by `n` lines.
pub fn scrollUp(n: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[{d}S", .{n}) catch unreachable;
    return out;
}

/// Scrolls the screen down by `n` lines.
pub fn scrollDown(n: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[{d}T", .{n}) catch unreachable;
    return out;
}

/// Moves the cursor to the beginning of line `n` and column `m`.
pub fn horizontalVerticalPosition(n: u8, m: u8) []const u8 {
    var buf: [25]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "\x1b[{d};{d}f", .{ n, m }) catch unreachable;
    return out;
}

/// Returns true if the declaration is an escape sequence.
/// NOTE: If other declarations are added, that are a string literals, this will need to be updated.
fn isEscapeSequence(comptime decl: std.builtin.Type.Declaration) bool {
    // An escape sequence is a pointer to an array with a sentinel pointer.
    var TI = @typeInfo(@TypeOf(@field(ansi, decl.name)));
    if (TI != .pointer) return false;
    TI = @typeInfo(TI.pointer.child);
    return TI == .array and TI.array.sentinel_ptr != null;
}

/// Returns true if the declaration is an escape function.
/// NOTE: If other declarations are added, that are a function, this may need to be updated.
/// Maybe in the future a black or white list of functions will be better.
fn isEscapeFunction(comptime decl: std.builtin.Type.Declaration) bool {
    // An escape function is a function that has only arguments of type u8 and returns a string.
    if (@typeInfo(@TypeOf(@field(ansi, decl.name))) != .@"fn") return false;

    const fn_info = @typeInfo(@TypeOf(@field(ansi, decl.name))).@"fn";
    if (fn_info.return_type.? != []const u8) return false;
    if (fn_info.params.len == 0) return false;
    inline for (fn_info.params) |param| {
        if (param.type.? != u8) return false;
    }
    return true;
}

test "bold" {
    const formatted = format("Hello, {bold}{s}!");
    const formatted2 = "Hello, " ++ ansi.bold ++ "{s}!" ++ ansi.reset;
    try testing.expectEqualStrings("Hello, \x1b[1m{s}!\x1b[0m", formatted);
    try testing.expectEqualStrings(formatted, formatted2);
}

test "red" {
    const formatted = format("Hello, {red}{s}!");
    const formatted2 = "Hello, " ++ ansi.red ++ "{s}!" ++ ansi.reset;
    try testing.expectEqualStrings("Hello, \x1b[31m{s}!\x1b[0m", formatted);
    try testing.expectEqualStrings(formatted, formatted2);
}

test "blink_slow" {
    const formatted = format("Hello, {blink_slow}{s}!");
    const formatted2 = "Hello, " ++ blink_slow ++ "{s}!" ++ reset;
    try testing.expectEqualStrings("Hello, \x1b[5m{s}!\x1b[0m", formatted);
    try testing.expectEqualStrings(formatted, formatted2);
}

test "bold_red" {
    const formatted = format("Hello, {bold,red}{s}!");
    const formatted2 = "Hello, " ++ bold ++ red ++ "{s}!" ++ reset;
    try testing.expectEqualStrings("Hello, \x1b[1m\x1b[31m{s}!\x1b[0m", formatted);
    try testing.expectEqualStrings(formatted, formatted2);
}

test "8bit" {
    const formatted = format("Hello, {8bit;255}{s}!");
    const formatted2 = "Hello, " ++ comptime @"8bit"(255) ++ "{s}!" ++ reset;
    try testing.expectEqualStrings("Hello, \x1b[38;5;255m{s}!\x1b[0m", formatted);
    try testing.expectEqualStrings(formatted, formatted2);
}

test "rgb" {
    const formatted = format("Hello, {rgb;255;0;0}{s}!");
    const formatted2 = "Hello, " ++ comptime rgb(255, 0, 0) ++ "{s}!" ++ reset;
    try testing.expectEqualStrings("Hello, \x1b[38;2;255;0;0m{s}!\x1b[0m", formatted);
    try testing.expectEqualStrings(formatted, formatted2);
}

test "rgb_bold" {
    const formatted = format("Hello, {rgb;255;0;255,bold}{s}!");
    const formatted2 = "Hello, " ++ comptime rgb(255, 0, 255) ++ bold ++ "{s}!" ++ reset;
    try testing.expectEqualStrings("Hello, \x1b[38;2;255;0;255m\x1b[1m{s}!\x1b[0m", formatted);
    try testing.expectEqualStrings(formatted, formatted2);
}

const std = @import("std");
const testing = std.testing;

const assert = std.debug.assert;

const ansi = @This();
