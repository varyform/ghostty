const options = @import("build_options");
const std = @import("std");
const glfw = @import("glfw");

const App = @import("App.zig");
const tracy = @import("tracy/tracy.zig");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    defer _ = general_purpose_allocator.deinit();

    // If we're tracing, then wrap memory so we can trace allocations
    const alloc = if (!tracy.enabled) gpa else tracy.allocator(gpa, null).allocator();

    // Initialize glfw
    try glfw.init(.{});
    defer glfw.terminate();

    // Run our app
    var app = try App.init(alloc);
    defer app.deinit();
    try app.run();
}

// Required by tracy/tracy.zig to enable/disable tracy support.
pub fn tracy_enabled() bool {
    return options.tracy_enabled;
}

test {
    _ = @import("Atlas.zig");
    _ = @import("FontAtlas.zig");
    _ = @import("Grid.zig");
    _ = @import("Pty.zig");
    _ = @import("Command.zig");
    _ = @import("TempDir.zig");
    _ = @import("terminal/Terminal.zig");

    // Libraries
    _ = @import("segmented_pool.zig");
    _ = @import("libuv/main.zig");
    _ = @import("terminal/main.zig");
}
