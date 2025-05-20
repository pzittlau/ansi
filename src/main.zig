pub fn main() !void {
    const stdout_writer = std.io.getStdOut().writer();

    try stdout_writer.print(ansi.erase_display_all ++ ansi.cursorPosition(1, 1), .{});

    try stdout_writer.print("\n=== ANSI Escape Code Library Demo ===\n\n", .{});

    // --- 1. Using ansi.format() (Compile-Time String Formatting) ---
    try stdout_writer.print("--- 1. `ansi.format()` Examples ---\n", .{});

    // Basic SGR styles (colors, attributes)
    try stdout_writer.print(ansi.format("This is {red}red{reset}, this is {green,bold}green and bold.\n"), .{});
    try stdout_writer.print(ansi.format("Combined: {blue,italic,underline}Blue, Italic, Underlined{reset}.\n"), .{});
    try stdout_writer.print(ansi.format("Background: {bg_yellow,black}Black text on Yellow BG.\n"), .{});

    // Parameterized colors via format()
    try stdout_writer.print(ansi.format("8-bit color: {8bit;160}Deep Red (8-bit)\n"), .{});
    try stdout_writer.print(ansi.format("RGB color: {rgb;100;150;255}Light Periwinkle (RGB)\n"), .{});
    try stdout_writer.print(ansi.format("Background 8-bit: {bg8bit;228}Pale Yellow BG\n"), .{});
    try stdout_writer.print(ansi.format("Background RGB: {bgRgb;30;60;30,white}White text on Dark Green BG\n"), .{});
    try stdout_writer.print(ansi.format("Underline color: {underline,underline8bit;198}Text with Pink Underline (Support varies)\n"), .{});
    try stdout_writer.print(ansi.format("Bright colors: {red_bright}Bright Red{reset}, {bg_cyan_bright,black}Black on Bright Cyan BG\n"), .{});

    // Mixing standard format specifiers ({s}, {d}, etc.)
    const user_name = "Ziggy";
    const count: u32 = 42;
    try stdout_writer.print(ansi.format("Hello, {yellow,bold}{s}{reset}! Your number is {blue}{d}.\n"), .{ user_name, count });

    // --- 2. Direct Usage of Constants and Functions ---
    try stdout_writer.print("\n--- 2. Direct Usage Examples ---\n", .{});

    // Concatenating constants
    try stdout_writer.print(ansi.magenta ++ ansi.blink_slow ++ "Magenta text" ++ ansi.reset ++ " and " ++ ansi.cyan_bright ++ "Bright Cyan text.\n", .{});
    // Intermixing constands and format function
    // You may need to double escape the {{}} to get the correct number of braces.
    try stdout_writer.print(ansi.format("This continues because no {reset,red}{{{{reset}}}} " ++ ansi.reset ++ "was used.\n"), .{});

    // Using generator functions
    const orange_color = comptime ansi.rgb(255, 165, 0);
    const dark_bg = comptime ansi.bgRgb(20, 20, 75);
    try stdout_writer.print(orange_color ++ "This is orange." ++ ansi.reset ++ "\n", .{});
    try stdout_writer.print(dark_bg ++ ansi.green_bright ++ "Bright green text on a custom dark blue background." ++ ansi.reset ++ "\n", .{});

    // --- 3. C0 and Parameterized CSI Command Examples (No Clearing) ---
    try stdout_writer.print("\n--- 3. C0 and CSI Command Examples ---\n", .{});

    // Bell character (might make a sound)
    try stdout_writer.print("Listen for the bell: " ++ ansi.bell ++ "(if your terminal supports it)\n", .{});

    // Cursor movement examples
    try stdout_writer.print("Line 1: Starting point.\n", .{});
    try stdout_writer.print("Line 2: 123456789\n", .{});
    try stdout_writer.print("Line 3: " ++ comptime ansi.cursorForward(9) ++ "Indented by 9 columns on Line 3.\n" ++ ansi.reset, .{});

    try stdout_writer.print("Line 4: TextAB", .{});
    try stdout_writer.print(comptime ansi.cursorBack(1) ++ "C", .{}); // Overwrites 'B' with 'C' -> TextAC
    try stdout_writer.print(comptime ansi.cursorForward(1) ++ "D\n", .{}); // Moves after C, prints D -> TextAC D
    try stdout_writer.print("          (Above line should be 'TextAC D')\n", .{});

    // For cursorPosition, it's relative to the screen. To make it somewhat predictable in a demo:
    // We'll print some newlines to "scroll" a bit, then position.
    const target_row: u8 = 32; // Example row
    const target_col: u8 = 25; // Example col
    try stdout_writer.print(comptime ansi.cursorPosition(target_row, target_col) ++
        ansi.italic ++ "Positioned at Row " ++ std.fmt.comptimePrint("{}", .{target_row}) ++
        ", Col " ++ std.fmt.comptimePrint("{}", .{target_col}) ++ " (screen relative).\n\n", .{});

    // Cursor visibility (effect is terminal-dependent and brief in scripts)
    try stdout_writer.print("Cursor hide/show demo:\n", .{});
    try stdout_writer.print("  Sequence to hide: {}\n", .{std.zig.fmtEscapes(ansi.cursor_hide)});
    try stdout_writer.print("  Sequence to show: {}\n", .{std.zig.fmtEscapes(ansi.cursor_show)});

    // --- 4. Font Styles (Terminal Support Varies Greatly) ---
    try stdout_writer.print("\n--- 4. Font Style Examples (Support Varies) ---\n", .{});
    try stdout_writer.print(ansi.format("This is {font_alt_1}Alternative Font 1{reset} (if supported).\n"), .{});
    try stdout_writer.print(ansi.format("This is {fraktur}Fraktur/Gothic{reset} (rarely supported).\n"), .{});
    try stdout_writer.print(ansi.format("This is {underline_double}Double Underline{reset} (sometimes bold off).\n"), .{});

    try stdout_writer.print("\nDemo complete. Styles should be reset." ++ ansi.reset ++ "\n\n", .{});
}

const std = @import("std");
const ansi = @import("ansi");
