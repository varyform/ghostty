/// A zig build step that compiles a set of ".metal" files into a
/// ".metallib" file.
const MetallibStep = @This();

const std = @import("std");
const Step = std.Build.Step;
const RunStep = std.Build.Step.Run;
const LazyPath = std.Build.LazyPath;

pub const Options = struct {
    /// The name of the xcframework to create.
    name: []const u8,

    /// The OS being targeted
    target: std.Build.ResolvedTarget,

    /// The Metal source files.
    sources: []const LazyPath,
};

step: *Step,
output: LazyPath,

pub fn create(b: *std.Build, opts: Options) ?*MetallibStep {
    const self = b.allocator.create(MetallibStep) catch @panic("OOM");

    const sdk = switch (opts.target.result.os.tag) {
        .macos => "macosx",
        .ios => "iphoneos",
        else => return null,
    };

    const min_version = if (opts.target.query.os_version_min) |v|
        b.fmt("{}", .{v.semver})
    else switch (opts.target.result.os.tag) {
        .macos => "10.14",
        .ios => "11.0",
        else => unreachable,
    };

    const run_ir = RunStep.create(
        b,
        b.fmt("metal {s}", .{opts.name}),
    );
    run_ir.addArgs(&.{ "/usr/bin/xcrun", "-sdk", sdk, "metal", "-o" });
    const output_ir = run_ir.addOutputFileArg(b.fmt("{s}.ir", .{opts.name}));
    run_ir.addArgs(&.{"-c"});
    for (opts.sources) |source| run_ir.addFileArg(source);
    switch (opts.target.result.os.tag) {
        .ios => run_ir.addArgs(&.{b.fmt(
            "-mios-version-min={s}",
            .{min_version},
        )}),
        .macos => run_ir.addArgs(&.{b.fmt(
            "-mmacos-version-min={s}",
            .{min_version},
        )}),
        else => {},
    }

    const run_lib = RunStep.create(
        b,
        b.fmt("metallib {s}", .{opts.name}),
    );
    run_lib.addArgs(&.{ "/usr/bin/xcrun", "-sdk", sdk, "metallib", "-o" });
    const output_lib = run_lib.addOutputFileArg(b.fmt("{s}.metallib", .{opts.name}));
    run_lib.addFileArg(output_ir);
    run_lib.step.dependOn(&run_ir.step);

    self.* = .{
        .step = &run_lib.step,
        .output = output_lib,
    };

    return self;
}
