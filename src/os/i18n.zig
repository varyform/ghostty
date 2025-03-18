const std = @import("std");
const builtin = @import("builtin");
const build_config = @import("../build_config.zig");

const log = std.log.scoped(.i18n);

/// Supported locales for the application. This must be kept up to date
/// with the translations available in the `po/` directory; this is used
/// by our build process as well runtime libghostty APIs.
///
/// The order also matters. For incomplete locale information (i.e. only
/// a language code available), the first match is used. For example, if
/// we know the user requested `zh` but has no script code, then we'd pick
/// the first locale that matches `zh`.
///
/// For ordering, we prefer:
///
///   1. The most common locales first, since there are places in the code
///      where we do linear searches for a locale and we want to minimize
///      the number of iterations for the common case.
///
///   2. Alphabetical for otherwise equally common locales.
///
///   3. Most preferred locale for a language without a country code.
///
pub const locales = [_][:0]const u8{
    "de_DE.UTF-8",
    "zh_CN.UTF-8",
};

/// Set for faster membership lookup of locales.
pub const locales_map = map: {
    var kvs: [locales.len]struct { []const u8 } = undefined;
    for (locales, 0..) |locale, i| kvs[i] = .{locale};
    break :map std.StaticStringMap(void).initComptime(kvs);
};

pub const InitError = error{
    InvalidResourcesDir,
    OutOfMemory,
};

/// Initialize i18n support for the application. This should be
/// called automatically by the global state initialization
/// in global.zig.
///
/// This calls `bindtextdomain` for gettext with the proper directory
/// of translations. This does NOT call `textdomain` as we don't
/// want to set the domain for the entire application since this is also
/// used by libghostty.
pub fn init(resources_dir: []const u8) InitError!void {
    // i18n is unsupported on Windows
    if (builtin.os.tag == .windows) return;

    // Our resources dir is always nested below the share dir that
    // is standard for translations.
    const share_dir = std.fs.path.dirname(resources_dir) orelse
        return error.InvalidResourcesDir;

    // Build our locale path
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrintZ(&buf, "{s}/locale", .{share_dir}) catch
        return error.OutOfMemory;

    // Bind our bundle ID to the given locale path
    log.debug("binding domain={s} path={s}", .{ build_config.bundle_id, path });
    _ = bindtextdomain(build_config.bundle_id, path.ptr) orelse
        return error.OutOfMemory;
}

/// Set the global gettext domain to our bundle ID, allowing unqualified
/// `gettext` (`_`) calls to look up translations for our application.
///
/// This should only be called for apprts that are fully owning the
/// Ghostty application. This should not be called for libghostty users.
pub fn initGlobalDomain() error{OutOfMemory}!void {
    _ = textdomain(build_config.bundle_id) orelse return error.OutOfMemory;
}

/// Translate a message for the Ghostty domain.
pub fn _(msgid: [*:0]const u8) [*:0]const u8 {
    return dgettext(build_config.bundle_id, msgid);
}

/// Canonicalize a locale name from a platform-specific value to
/// a POSIX-compliant value. This is a thin layer over the unexported
/// gnulib-lib function in gettext that does this already.
///
/// The gnulib-lib function modifies the buffer in place but has
/// zero bounds checking, so we do a bit extra to ensure we don't
/// overflow the buffer. This is likely slightly more expensive but
/// this isn't a hot path so it should be fine.
///
/// The buffer must be at least 16 bytes long. This ensures we can
/// fit the longest possible hardcoded locale name. Additionally,
/// it should be at least as long as locale in case the locale
/// is unchanged.
///
/// Here is the logic for macOS, but other platforms also have
/// their own canonicalization logic:
///
/// https://github.com/coreutils/gnulib/blob/5b92dd0a45c8d27f13a21076b57095ea5e220870/lib/localename.c#L1171
pub fn canonicalizeLocale(
    buf: []u8,
    locale: []const u8,
) error{NoSpaceLeft}![:0]const u8 {
    // Buffer must be 16 or at least as long as the locale and null term
    if (buf.len < @max(16, locale.len + 1)) return error.NoSpaceLeft;

    // Copy our locale into the buffer since it modifies in place.
    // This must be null-terminated.
    @memcpy(buf[0..locale.len], locale);
    buf[locale.len] = 0;

    _libintl_locale_name_canonicalize(buf[0..locale.len :0]);

    // Convert the null-terminated result buffer into a slice. We
    // need to search for the null terminator and slice it back.
    // We have to use `buf` since `slice` len will exclude the
    // null.
    const slice = std.mem.sliceTo(buf, 0);
    return buf[0..slice.len :0];
}

/// This can be called at any point a compile-time-known locale is
/// available. This will use comptime to verify the locale is supported.
pub fn staticLocale(comptime v: [*:0]const u8) [*:0]const u8 {
    comptime {
        for (locales) |locale| {
            if (std.mem.eql(u8, locale, v)) {
                return locale;
            }
        }

        @compileError("unsupported locale");
    }
}

// Manually include function definitions for the gettext functions
// as libintl.h isn't always easily available (e.g. in musl)
extern fn bindtextdomain(domainname: [*:0]const u8, dirname: [*:0]const u8) ?[*:0]const u8;
extern fn textdomain(domainname: [*:0]const u8) ?[*:0]const u8;
extern fn dgettext(domainname: [*:0]const u8, msgid: [*:0]const u8) [*:0]const u8;

// This is only available if we're building libintl from source
// since its otherwise not exported. We only need it on macOS
// currently but probably will on Windows as well.
extern fn _libintl_locale_name_canonicalize(name: [*:0]u8) void;

test "canonicalizeLocale darwin" {
    if (!builtin.target.os.tag.isDarwin()) return error.SkipZigTest;

    const testing = std.testing;
    var buf: [256]u8 = undefined;
    try testing.expectEqualStrings("en_US", try canonicalizeLocale(&buf, "en_US"));
    try testing.expectEqualStrings("zh_CN", try canonicalizeLocale(&buf, "zh-Hans"));
    try testing.expectEqualStrings("zh_TW", try canonicalizeLocale(&buf, "zh-Hant"));

    // This is just an edge case I want to make sure we're aware of:
    // canonicalizeLocale does not handle encodings and will turn them into
    // underscores. We should parse them out before calling this function.
    try testing.expectEqualStrings("en_US.UTF_8", try canonicalizeLocale(&buf, "en_US.UTF-8"));
}
