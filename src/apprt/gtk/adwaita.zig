const std = @import("std");

// Until the gobject bindings are built at the same time we are building
// Ghostty, we need to import `adwaita.h` directly to ensure that the version
// macros match the version of `libadwaita` that we are building/linking
// against.
const c = @cImport({
    @cInclude("adwaita.h");
});

const adw = @import("adw");

const log = std.log.scoped(.gtk);

pub fn logVersion() void {
    log.info("libadwaita version build={s} runtime={}.{}.{}", .{
        c.ADW_VERSION_S,
        adw.getMajorVersion(),
        adw.getMinorVersion(),
        adw.getMicroVersion(),
    });
}

/// Verifies that the running libadwaita version is at least the given
/// version. This will return false if Ghostty is configured to not build with
/// libadwaita.
///
/// This can be run in both a comptime and runtime context. If it is run in a
/// comptime context, it will only check the version in the headers. If it is
/// run in a runtime context, it will check the actual version of the library we
/// are linked against. So generally  you probably want to do both checks!
///
/// This is inlined so that the comptime checks will disable the runtime checks
/// if the comptime checks fail.
pub inline fn versionAtLeast(
    comptime major: u16,
    comptime minor: u16,
    comptime micro: u16,
) bool {
    // If our header has lower versions than the given version, we can return
    // false immediately. This prevents us from compiling against unknown
    // symbols and makes runtime checks very slightly faster.
    if (comptime c.ADW_MAJOR_VERSION < major or
        (c.ADW_MAJOR_VERSION == major and c.ADW_MINOR_VERSION < minor) or
        (c.ADW_MAJOR_VERSION == major and c.ADW_MINOR_VERSION == minor and c.ADW_MICRO_VERSION < micro))
        return false;

    // If we're in comptime then we can't check the runtime version.
    if (@inComptime()) return true;

    // We use the functions instead of the constants such as c.ADW_MINOR_VERSION
    // because the function gets the actual runtime version.
    if (adw.getMajorVersion() >= major) {
        if (adw.getMajorVersion() > major) return true;
        if (adw.getMinorVersion() >= minor) {
            if (adw.getMinorVersion() > minor) return true;
            return adw.getMicroVersion() >= micro;
        }
    }

    return false;
}

test "versionAtLeast" {
    const testing = std.testing;

    try testing.expect(versionAtLeast(c.ADW_MAJOR_VERSION, c.ADW_MINOR_VERSION, c.ADW_MICRO_VERSION));
    try testing.expect(!versionAtLeast(c.ADW_MAJOR_VERSION, c.ADW_MINOR_VERSION, c.ADW_MICRO_VERSION + 1));
    try testing.expect(!versionAtLeast(c.ADW_MAJOR_VERSION, c.ADW_MINOR_VERSION + 1, c.ADW_MICRO_VERSION));
    try testing.expect(!versionAtLeast(c.ADW_MAJOR_VERSION + 1, c.ADW_MINOR_VERSION, c.ADW_MICRO_VERSION));
    try testing.expect(versionAtLeast(c.ADW_MAJOR_VERSION - 1, c.ADW_MINOR_VERSION, c.ADW_MICRO_VERSION));
    try testing.expect(versionAtLeast(c.ADW_MAJOR_VERSION - 1, c.ADW_MINOR_VERSION + 1, c.ADW_MICRO_VERSION));
    try testing.expect(versionAtLeast(c.ADW_MAJOR_VERSION - 1, c.ADW_MINOR_VERSION, c.ADW_MICRO_VERSION + 1));
    try testing.expect(versionAtLeast(c.ADW_MAJOR_VERSION, c.ADW_MINOR_VERSION - 1, c.ADW_MICRO_VERSION + 1));
}

// Whether AdwDialog, AdwAlertDialog, etc. are supported (1.5+)
pub fn supportsDialogs() bool {
    return versionAtLeast(1, 5, 0);
}
