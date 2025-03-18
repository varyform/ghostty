// This is the main file for the C API. The C API is used to embed Ghostty
// within other applications. Depending on the build settings some APIs
// may not be available (i.e. embedding into macOS exposes various Metal
// support).
//
// This currently isn't supported as a general purpose embedding API.
// This is currently used only to embed ghostty within a macOS app. However,
// it could be expanded to be general purpose in the future.

const std = @import("std");
const assert = std.debug.assert;
const posix = std.posix;
const builtin = @import("builtin");
const build_config = @import("build_config.zig");
const main = @import("main_ghostty.zig");
const state = &@import("global.zig").state;
const apprt = @import("apprt.zig");
const internal_os = @import("os/main.zig");

// Some comptime assertions that our C API depends on.
comptime {
    assert(apprt.runtime == apprt.embedded);
}

/// Global options so we can log. This is identical to main.
pub const std_options = main.std_options;

comptime {
    // These structs need to be referenced so the `export` functions
    // are truly exported by the C API lib.
    _ = @import("config.zig").CAPI;
    _ = apprt.runtime.CAPI;
}

/// ghostty_info_s
const Info = extern struct {
    mode: BuildMode,
    version: [*]const u8,
    version_len: usize,

    const BuildMode = enum(c_int) {
        debug,
        release_safe,
        release_fast,
        release_small,
    };
};

/// Initialize ghostty global state. It is possible to have more than
/// one global state but it has zero practical benefit.
export fn ghostty_init() c_int {
    assert(builtin.link_libc);

    // Since in the lib we don't go through start.zig, we need
    // to populate argv so that inspecting std.os.argv doesn't
    // touch uninitialized memory.
    var argv: [0][*:0]u8 = .{};
    std.os.argv = &argv;

    state.init() catch |err| {
        std.log.err("failed to initialize ghostty error={}", .{err});
        return 1;
    };

    return 0;
}

/// This is the entrypoint for the CLI version of Ghostty. This
/// is mutually exclusive to ghostty_init. Do NOT run ghostty_init
/// if you are going to run this. This will not return.
export fn ghostty_cli_main(argc: usize, argv: [*][*:0]u8) noreturn {
    std.os.argv = argv[0..argc];
    main.main() catch |err| {
        std.log.err("failed to run ghostty error={}", .{err});
        posix.exit(1);
    };
}

/// Return metadata about Ghostty, such as version, build mode, etc.
export fn ghostty_info() Info {
    return .{
        .mode = switch (builtin.mode) {
            .Debug => .debug,
            .ReleaseSafe => .release_safe,
            .ReleaseFast => .release_fast,
            .ReleaseSmall => .release_small,
        },
        .version = build_config.version_string.ptr,
        .version_len = build_config.version_string.len,
    };
}

/// Translate a string maintained by libghostty into the current
/// application language. This will return the same string (same pointer)
/// if no translation is found, so the pointer must be stable through
/// the function call.
///
/// This should only be used for singular strings maintained by Ghostty.
export fn ghostty_translate(msgid: [*:0]const u8) [*:0]const u8 {
    return internal_os.i18n._(msgid);
}
