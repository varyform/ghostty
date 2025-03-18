const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const terminal = @import("../main.zig");
const point = @import("../point.zig");
const size = @import("../size.zig");
const command = @import("graphics_command.zig");
const PageList = @import("../PageList.zig");
const Screen = @import("../Screen.zig");
const LoadingImage = @import("graphics_image.zig").LoadingImage;
const Image = @import("graphics_image.zig").Image;
const Rect = @import("graphics_image.zig").Rect;
const Command = command.Command;

const log = std.log.scoped(.kitty_gfx);

/// An image storage is associated with a terminal screen (i.e. main
/// screen, alt screen) and contains all the transmitted images and
/// placements.
pub const ImageStorage = struct {
    const ImageMap = std.AutoHashMapUnmanaged(u32, Image);
    const PlacementMap = std.AutoHashMapUnmanaged(PlacementKey, Placement);

    /// Dirty is set to true if placements or images change. This is
    /// purely informational for the renderer and doesn't affect the
    /// correctness of the program. The renderer must set this to false
    /// if it cares about this value.
    dirty: bool = false,

    /// This is the next automatically assigned image ID. We start mid-way
    /// through the u32 range to avoid collisions with buggy programs.
    /// TODO: This isn't good enough, it's perfectly legal for programs
    ///       to use IDs in the latter half of the range and collisions
    ///       are not gracefully handled.
    next_image_id: u32 = 2147483647,

    /// This is the next automatically assigned placement ID. This is never
    /// user-facing so we can start at 0. This is 32-bits because we use
    /// the same space for external placement IDs. We can start at zero
    /// because any number is valid.
    next_internal_placement_id: u32 = 0,

    /// The set of images that are currently known.
    images: ImageMap = .{},

    /// The set of placements for loaded images.
    placements: PlacementMap = .{},

    /// Non-null if there is an in-progress loading image.
    loading: ?*LoadingImage = null,

    /// The total bytes of image data that have been loaded and the limit.
    /// If the limit is reached, the oldest images will be evicted to make
    /// space. Unused images take priority.
    total_bytes: usize = 0,
    total_limit: usize = 320 * 1000 * 1000, // 320MB

    pub fn deinit(
        self: *ImageStorage,
        alloc: Allocator,
        s: *terminal.Screen,
    ) void {
        if (self.loading) |loading| loading.destroy(alloc);

        var it = self.images.iterator();
        while (it.next()) |kv| kv.value_ptr.deinit(alloc);
        self.images.deinit(alloc);

        self.clearPlacements(s);
        self.placements.deinit(alloc);
    }

    /// Kitty image protocol is enabled if we have a non-zero limit.
    pub fn enabled(self: *const ImageStorage) bool {
        return self.total_limit != 0;
    }

    /// Sets the limit in bytes for the total amount of image data that
    /// can be loaded. If this limit is lower, this will do an eviction
    /// if necessary. If the value is zero, then Kitty image protocol will
    /// be disabled.
    pub fn setLimit(
        self: *ImageStorage,
        alloc: Allocator,
        s: *terminal.Screen,
        limit: usize,
    ) !void {
        // Special case disabling by quickly deleting all
        if (limit == 0) {
            self.deinit(alloc, s);
            self.* = .{};
        }

        // If we re lowering our limit, check if we need to evict.
        if (limit < self.total_bytes) {
            const req_bytes = self.total_bytes - limit;
            log.info("evicting images to lower limit, evicting={}", .{req_bytes});
            if (!try self.evictImage(alloc, req_bytes)) {
                log.warn("failed to evict enough images for required bytes", .{});
            }
        }

        self.total_limit = limit;
    }

    /// Add an already-loaded image to the storage. This will automatically
    /// free any existing image with the same ID.
    pub fn addImage(self: *ImageStorage, alloc: Allocator, img: Image) Allocator.Error!void {
        // If the image itself is over the limit, then error immediately
        if (img.data.len > self.total_limit) return error.OutOfMemory;

        // If this would put us over the limit, then evict.
        const total_bytes = self.total_bytes + img.data.len;
        if (total_bytes > self.total_limit) {
            const req_bytes = total_bytes - self.total_limit;
            log.info("evicting images to make space for {} bytes", .{req_bytes});
            if (!try self.evictImage(alloc, req_bytes)) {
                log.warn("failed to evict enough images for required bytes", .{});
                return error.OutOfMemory;
            }
        }

        // Do the gop op first so if it fails we don't get a partial state
        const gop = try self.images.getOrPut(alloc, img.id);

        log.debug("addImage image={}", .{img: {
            var copy = img;
            copy.data = "";
            break :img copy;
        }});

        // Write our new image
        if (gop.found_existing) {
            self.total_bytes -= gop.value_ptr.data.len;
            gop.value_ptr.deinit(alloc);
        }

        gop.value_ptr.* = img;
        self.total_bytes += img.data.len;

        self.dirty = true;
    }

    /// Add a placement for a given image. The caller must verify in advance
    /// the image exists to prevent memory corruption.
    pub fn addPlacement(
        self: *ImageStorage,
        alloc: Allocator,
        image_id: u32,
        placement_id: u32,
        p: Placement,
    ) !void {
        assert(self.images.get(image_id) != null);
        log.debug("placement image_id={} placement_id={} placement={}\n", .{
            image_id,
            placement_id,
            p,
        });

        // The important piece here is that the placement ID needs to
        // be marked internal if it is zero. This allows multiple placements
        // to be added for the same image. If it is non-zero, then it is
        // an external placement ID and we can only have one placement
        // per (image id, placement id) pair.
        const key: PlacementKey = .{
            .image_id = image_id,
            .placement_id = if (placement_id == 0) .{
                .tag = .internal,
                .id = id: {
                    defer self.next_internal_placement_id +%= 1;
                    break :id self.next_internal_placement_id;
                },
            } else .{
                .tag = .external,
                .id = placement_id,
            },
        };

        const gop = try self.placements.getOrPut(alloc, key);
        gop.value_ptr.* = p;

        self.dirty = true;
    }

    fn clearPlacements(self: *ImageStorage, s: *terminal.Screen) void {
        var it = self.placements.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(s);
        self.placements.clearRetainingCapacity();
    }

    /// Get an image by its ID. If the image doesn't exist, null is returned.
    pub fn imageById(self: *const ImageStorage, image_id: u32) ?Image {
        return self.images.get(image_id);
    }

    /// Get an image by its number. If the image doesn't exist, return null.
    pub fn imageByNumber(self: *const ImageStorage, image_number: u32) ?Image {
        var newest: ?Image = null;

        var it = self.images.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.number == image_number) {
                if (newest == null or
                    kv.value_ptr.transmit_time.order(newest.?.transmit_time) == .gt)
                {
                    newest = kv.value_ptr.*;
                }
            }
        }

        return newest;
    }

    /// Delete placements, images.
    pub fn delete(
        self: *ImageStorage,
        alloc: Allocator,
        t: *terminal.Terminal,
        cmd: command.Delete,
    ) void {
        switch (cmd) {
            .all => |delete_images| {
                var it = self.placements.iterator();
                while (it.next()) |entry| {
                    // Skip virtual placements
                    switch (entry.value_ptr.location) {
                        .pin => {},
                        .virtual => continue,
                    }

                    // Deinit the placement and remove it
                    const image_id = entry.key_ptr.image_id;
                    entry.value_ptr.deinit(&t.screen);
                    self.placements.removeByPtr(entry.key_ptr);
                    if (delete_images) self.deleteIfUnused(alloc, image_id);
                }

                if (delete_images) {
                    var image_it = self.images.iterator();
                    while (image_it.next()) |kv| self.deleteIfUnused(alloc, kv.key_ptr.*);
                }

                self.dirty = true;
            },

            .id => |v| self.deleteById(
                alloc,
                &t.screen,
                v.image_id,
                v.placement_id,
                v.delete,
            ),

            .newest => |v| newest: {
                const img = self.imageByNumber(v.image_number) orelse break :newest;
                self.deleteById(
                    alloc,
                    &t.screen,
                    img.id,
                    v.placement_id,
                    v.delete,
                );
            },

            .intersect_cursor => |delete_images| {
                self.deleteIntersecting(
                    alloc,
                    t,
                    .{ .active = .{
                        .x = t.screen.cursor.x,
                        .y = t.screen.cursor.y,
                    } },
                    delete_images,
                    {},
                    null,
                );
            },

            .intersect_cell => |v| intersect_cell: {
                if (v.x <= 0 or v.y <= 0) {
                    log.warn("delete intersect cell coords must be at least 1", .{});
                    break :intersect_cell;
                }

                self.deleteIntersecting(
                    alloc,
                    t,
                    .{ .active = .{
                        .x = std.math.cast(size.CellCountInt, v.x - 1) orelse break :intersect_cell,
                        .y = std.math.cast(size.CellCountInt, v.y - 1) orelse break :intersect_cell,
                    } },
                    v.delete,
                    {},
                    null,
                );
            },

            .intersect_cell_z => |v| intersect_cell_z: {
                if (v.x <= 0 or v.y <= 0) {
                    log.warn("delete intersect cell coords must be at least 1", .{});
                    break :intersect_cell_z;
                }

                self.deleteIntersecting(
                    alloc,
                    t,
                    .{ .active = .{
                        .x = std.math.cast(size.CellCountInt, v.x - 1) orelse break :intersect_cell_z,
                        .y = std.math.cast(size.CellCountInt, v.y - 1) orelse break :intersect_cell_z,
                    } },
                    v.delete,
                    v.z,
                    struct {
                        fn filter(ctx: i32, p: Placement) bool {
                            return p.z == ctx;
                        }
                    }.filter,
                );
            },

            .column => |v| column: {
                if (v.x <= 0) {
                    log.warn("delete column must be greater than zero", .{});
                    break :column;
                }

                const x = v.x - 1;
                var it = self.placements.iterator();
                while (it.next()) |entry| {
                    const img = self.imageById(entry.key_ptr.image_id) orelse continue;
                    const rect = entry.value_ptr.rect(img, t) orelse continue;
                    if (rect.top_left.x <= x and rect.bottom_right.x >= x) {
                        entry.value_ptr.deinit(&t.screen);
                        self.placements.removeByPtr(entry.key_ptr);
                        if (v.delete) self.deleteIfUnused(alloc, img.id);
                    }
                }

                // Mark dirty to force redraw
                self.dirty = true;
            },

            .row => |v| row: {
                if (v.y <= 0) {
                    log.warn("delete row must be greater than zero", .{});
                    break :row;
                }

                // v.y is in active coords so we want to convert it to a pin
                // so we can compare by page offsets.
                const target_pin = t.screen.pages.pin(.{ .active = .{
                    .y = std.math.cast(size.CellCountInt, v.y - 1) orelse break :row,
                } }) orelse break :row;

                var it = self.placements.iterator();
                while (it.next()) |entry| {
                    const img = self.imageById(entry.key_ptr.image_id) orelse continue;
                    const rect = entry.value_ptr.rect(img, t) orelse continue;

                    // We need to copy our pin to ensure we are at least at
                    // the top-left x.
                    var target_pin_copy = target_pin;
                    target_pin_copy.x = rect.top_left.x;
                    if (target_pin_copy.isBetween(rect.top_left, rect.bottom_right)) {
                        entry.value_ptr.deinit(&t.screen);
                        self.placements.removeByPtr(entry.key_ptr);
                        if (v.delete) self.deleteIfUnused(alloc, img.id);
                    }
                }

                // Mark dirty to force redraw
                self.dirty = true;
            },

            .z => |v| {
                var it = self.placements.iterator();
                while (it.next()) |entry| {
                    switch (entry.value_ptr.location) {
                        .pin => {},

                        // Virtual placeholders cannot delete by z according
                        // to the spec.
                        .virtual => continue,
                    }

                    if (entry.value_ptr.z == v.z) {
                        const image_id = entry.key_ptr.image_id;
                        entry.value_ptr.deinit(&t.screen);
                        self.placements.removeByPtr(entry.key_ptr);
                        if (v.delete) self.deleteIfUnused(alloc, image_id);
                    }
                }

                // Mark dirty to force redraw
                self.dirty = true;
            },

            .range => |v| range: {
                if (v.first <= 0 or v.last <= 0) {
                    log.warn("delete range values must be greater than zero", .{});
                    break :range;
                }
                if (v.first > v.last) {
                    log.warn("delete range 'x' ({}) must be less than or equal to 'y' ({})", .{ v.first, v.last });
                    break :range;
                }

                var it = self.placements.iterator();
                while (it.next()) |entry| {
                    if (entry.key_ptr.image_id >= v.first or entry.key_ptr.image_id <= v.last) {
                        const image_id = entry.key_ptr.image_id;
                        entry.value_ptr.deinit(&t.screen);
                        self.placements.removeByPtr(entry.key_ptr);
                        if (v.delete) self.deleteIfUnused(alloc, image_id);
                    }
                }

                // Mark dirty to force redraw
                self.dirty = true;
            },

            // We don't support animation frames yet so they are successfully
            // deleted!
            .animation_frames => {},
        }
    }

    fn deleteById(
        self: *ImageStorage,
        alloc: Allocator,
        s: *terminal.Screen,
        image_id: u32,
        placement_id: u32,
        delete_unused: bool,
    ) void {
        // If no placement, we delete all placements with the ID
        if (placement_id == 0) {
            var it = self.placements.iterator();
            while (it.next()) |entry| {
                if (entry.key_ptr.image_id == image_id) {
                    entry.value_ptr.deinit(s);
                    self.placements.removeByPtr(entry.key_ptr);
                }
            }
        } else {
            if (self.placements.getEntry(.{
                .image_id = image_id,
                .placement_id = .{ .tag = .external, .id = placement_id },
            })) |entry| {
                entry.value_ptr.deinit(s);
                self.placements.removeByPtr(entry.key_ptr);
            }
        }

        // If this is specified, then we also delete the image
        // if it is no longer in use.
        if (delete_unused) self.deleteIfUnused(alloc, image_id);

        // Mark dirty to force redraw
        self.dirty = true;
    }

    /// Delete an image if it is unused.
    fn deleteIfUnused(self: *ImageStorage, alloc: Allocator, image_id: u32) void {
        var it = self.placements.iterator();
        while (it.next()) |kv| {
            if (kv.key_ptr.image_id == image_id) {
                return;
            }
        }

        // If we get here, we can delete the image.
        if (self.images.getEntry(image_id)) |entry| {
            self.total_bytes -= entry.value_ptr.data.len;
            entry.value_ptr.deinit(alloc);
            self.images.removeByPtr(entry.key_ptr);
        }
    }

    /// Deletes all placements intersecting a screen point.
    fn deleteIntersecting(
        self: *ImageStorage,
        alloc: Allocator,
        t: *terminal.Terminal,
        p: point.Point,
        delete_unused: bool,
        filter_ctx: anytype,
        comptime filter: ?fn (@TypeOf(filter_ctx), Placement) bool,
    ) void {
        // Convert our target point to a pin for comparison.
        const target_pin = t.screen.pages.pin(p) orelse return;

        var it = self.placements.iterator();
        while (it.next()) |entry| {
            const img = self.imageById(entry.key_ptr.image_id) orelse continue;
            const rect = entry.value_ptr.rect(img, t) orelse continue;
            if (target_pin.isBetween(rect.top_left, rect.bottom_right)) {
                if (filter) |f| if (!f(filter_ctx, entry.value_ptr.*)) continue;
                entry.value_ptr.deinit(&t.screen);
                self.placements.removeByPtr(entry.key_ptr);
                if (delete_unused) self.deleteIfUnused(alloc, img.id);
            }
        }

        // Mark dirty to force redraw
        self.dirty = true;
    }

    /// Evict image to make space. This will evict the oldest image,
    /// prioritizing unused images first, as recommended by the published
    /// Kitty spec.
    ///
    /// This will evict as many images as necessary to make space for
    /// req bytes.
    fn evictImage(self: *ImageStorage, alloc: Allocator, req: usize) !bool {
        assert(req <= self.total_limit);

        // Ironically we allocate to evict. We should probably redesign the
        // data structures to avoid this but for now allocating a little
        // bit is fine compared to the megabytes we're looking to save.
        const Candidate = struct {
            id: u32,
            time: std.time.Instant,
            used: bool,
        };

        var candidates = std.ArrayList(Candidate).init(alloc);
        defer candidates.deinit();

        var it = self.images.iterator();
        while (it.next()) |kv| {
            const img = kv.value_ptr;

            // This is a huge waste. See comment above about redesigning
            // our data structures to avoid this. Eviction should be very
            // rare though and we never have that many images/placements
            // so hopefully this will last a long time.
            const used = used: {
                var p_it = self.placements.iterator();
                while (p_it.next()) |p_kv| {
                    if (p_kv.key_ptr.image_id == img.id) {
                        break :used true;
                    }
                }

                break :used false;
            };

            try candidates.append(.{
                .id = img.id,
                .time = img.transmit_time,
                .used = used,
            });
        }

        // Sort
        std.mem.sortUnstable(
            Candidate,
            candidates.items,
            {},
            struct {
                fn lessThan(
                    ctx: void,
                    lhs: Candidate,
                    rhs: Candidate,
                ) bool {
                    _ = ctx;

                    // If they're usage matches, then its based on time.
                    if (lhs.used == rhs.used) return switch (lhs.time.order(rhs.time)) {
                        .lt => true,
                        .gt => false,
                        .eq => lhs.id < rhs.id,
                    };

                    // If not used, then its a better candidate
                    return !lhs.used;
                }
            }.lessThan,
        );

        // They're in order of best to evict.
        var evicted: usize = 0;
        for (candidates.items) |c| {
            // Delete all the placements for this image and the image.
            var p_it = self.placements.iterator();
            while (p_it.next()) |entry| {
                if (entry.key_ptr.image_id == c.id) {
                    self.placements.removeByPtr(entry.key_ptr);
                }
            }

            if (self.images.getEntry(c.id)) |entry| {
                log.info("evicting image id={} bytes={}", .{ c.id, entry.value_ptr.data.len });

                evicted += entry.value_ptr.data.len;
                self.total_bytes -= entry.value_ptr.data.len;

                entry.value_ptr.deinit(alloc);
                self.images.removeByPtr(entry.key_ptr);

                if (evicted > req) return true;
            }
        }

        return false;
    }

    /// Every placement is uniquely identified by the image ID and the
    /// placement ID. If an image ID isn't specified it is assumed to be 0.
    /// Likewise, if a placement ID isn't specified it is assumed to be 0.
    pub const PlacementKey = struct {
        image_id: u32,
        placement_id: packed struct {
            tag: enum(u1) { internal, external },
            id: u32,
        },
    };

    pub const Placement = struct {
        /// The location where this placement should be drawn.
        location: Location,

        /// Offset of the x/y from the top-left of the cell.
        x_offset: u32 = 0,
        y_offset: u32 = 0,

        /// Source rectangle for the image to pull from
        source_x: u32 = 0,
        source_y: u32 = 0,
        source_width: u32 = 0,
        source_height: u32 = 0,

        /// The columns/rows this image occupies.
        columns: u32 = 0,
        rows: u32 = 0,

        /// The z-index for this placement.
        z: i32 = 0,

        pub const Location = union(enum) {
            /// Exactly placed on a screen pin.
            pin: *PageList.Pin,

            /// Virtual placement (U=1) for unicode placeholders.
            virtual: void,
        };

        pub fn deinit(
            self: *const Placement,
            s: *terminal.Screen,
        ) void {
            switch (self.location) {
                .pin => |p| s.pages.untrackPin(p),
                .virtual => {},
            }
        }

        /// Returns the size in grid cells that this placement takes up.
        pub fn gridSize(
            self: Placement,
            image: Image,
            t: *const terminal.Terminal,
        ) struct {
            cols: u32,
            rows: u32,
        } {
            if (self.columns > 0 and self.rows > 0) return .{
                .cols = self.columns,
                .rows = self.rows,
            };

            // Calculate our cell size.
            const terminal_width_f64: f64 = @floatFromInt(t.width_px);
            const terminal_height_f64: f64 = @floatFromInt(t.height_px);
            const grid_columns_f64: f64 = @floatFromInt(t.cols);
            const grid_rows_f64: f64 = @floatFromInt(t.rows);
            const cell_width_f64 = terminal_width_f64 / grid_columns_f64;
            const cell_height_f64 = terminal_height_f64 / grid_rows_f64;

            // Our image width
            const width_px = if (self.source_width > 0) self.source_width else image.width;
            const height_px = if (self.source_height > 0) self.source_height else image.height;

            // Calculate our image size in grid cells
            const width_f64: f64 = @floatFromInt(width_px);
            const height_f64: f64 = @floatFromInt(height_px);

            // If only columns is specified, calculate rows based on aspect ratio
            if (self.columns > 0 and self.rows == 0) {
                const cols_f64: f64 = @floatFromInt(self.columns);
                const cols_px = cols_f64 * cell_width_f64;
                const aspect_ratio = height_f64 / width_f64;
                const rows_px = cols_px * aspect_ratio;
                const rows_cells = rows_px / cell_height_f64;
                return .{
                    .cols = self.columns,
                    .rows = @intFromFloat(@ceil(rows_cells)),
                };
            }

            // If only rows is specified, calculate columns based on aspect ratio
            if (self.rows > 0 and self.columns == 0) {
                const rows_f64: f64 = @floatFromInt(self.rows);
                const rows_px = rows_f64 * cell_height_f64;
                const aspect_ratio = width_f64 / height_f64;
                const cols_px = rows_px * aspect_ratio;
                const cols_cells = cols_px / cell_width_f64;
                return .{
                    .cols = @intFromFloat(@ceil(cols_cells)),
                    .rows = self.rows,
                };
            }

            const width_cells: u32 = @intFromFloat(@ceil(width_f64 / cell_width_f64));
            const height_cells: u32 = @intFromFloat(@ceil(height_f64 / cell_height_f64));

            return .{
                .cols = width_cells,
                .rows = height_cells,
            };
        }

        /// Returns a selection of the entire rectangle this placement
        /// occupies within the screen. This can return null if the placement
        /// doesn't have an associated rect (i.e. a virtual placement).
        pub fn rect(
            self: Placement,
            image: Image,
            t: *const terminal.Terminal,
        ) ?Rect {
            const grid_size = self.gridSize(image, t);
            const pin = switch (self.location) {
                .pin => |p| p,
                .virtual => return null,
            };

            var br = switch (pin.downOverflow(grid_size.rows - 1)) {
                .offset => |v| v,
                .overflow => |v| v.end,
            };
            br.x = @min(
                // We need to sub one here because the x value is
                // one width already. So if the image is width "1"
                // then we add zero to X because X itself is width 1.
                pin.x + (grid_size.cols - 1),
                t.cols - 1,
            );

            return .{
                .top_left = pin.*,
                .bottom_right = br,
            };
        }
    };
};

// Our pin for the placement
fn trackPin(
    t: *terminal.Terminal,
    pt: point.Coordinate,
) !*PageList.Pin {
    return try t.screen.pages.trackPin(t.screen.pages.pin(.{
        .active = pt,
    }).?);
}

test "storage: add placement with zero placement id" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .cols = 100, .rows = 100 });
    defer t.deinit(alloc);
    t.width_px = 100;
    t.height_px = 100;

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1, .width = 50, .height = 50 });
    try s.addImage(alloc, .{ .id = 2, .width = 25, .height = 25 });
    try s.addPlacement(alloc, 1, 0, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 25, .y = 25 }) } });
    try s.addPlacement(alloc, 1, 0, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 25, .y = 25 }) } });

    try testing.expectEqual(@as(usize, 2), s.placements.count());
    try testing.expectEqual(@as(usize, 2), s.images.count());

    // verify the placement is what we expect
    try testing.expect(s.placements.get(.{
        .image_id = 1,
        .placement_id = .{ .tag = .internal, .id = 0 },
    }) != null);
    try testing.expect(s.placements.get(.{
        .image_id = 1,
        .placement_id = .{ .tag = .internal, .id = 1 },
    }) != null);
}

test "storage: delete all placements and images" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 3, .cols = 3 });
    defer t.deinit(alloc);
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1 });
    try s.addImage(alloc, .{ .id = 2 });
    try s.addImage(alloc, .{ .id = 3 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try s.addPlacement(alloc, 2, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });

    s.dirty = false;
    s.delete(alloc, &t, .{ .all = true });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 0), s.images.count());
    try testing.expectEqual(@as(usize, 0), s.placements.count());
    try testing.expectEqual(tracked, t.screen.pages.countTrackedPins());
}

test "storage: delete all placements and images preserves limit" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 3, .cols = 3 });
    defer t.deinit(alloc);
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    s.total_limit = 5000;
    try s.addImage(alloc, .{ .id = 1 });
    try s.addImage(alloc, .{ .id = 2 });
    try s.addImage(alloc, .{ .id = 3 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try s.addPlacement(alloc, 2, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });

    s.dirty = false;
    s.delete(alloc, &t, .{ .all = true });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 0), s.images.count());
    try testing.expectEqual(@as(usize, 0), s.placements.count());
    try testing.expectEqual(@as(usize, 5000), s.total_limit);
    try testing.expectEqual(tracked, t.screen.pages.countTrackedPins());
}

test "storage: delete all placements" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 3, .cols = 3 });
    defer t.deinit(alloc);
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1 });
    try s.addImage(alloc, .{ .id = 2 });
    try s.addImage(alloc, .{ .id = 3 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try s.addPlacement(alloc, 2, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });

    s.dirty = false;
    s.delete(alloc, &t, .{ .all = false });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 0), s.placements.count());
    try testing.expectEqual(@as(usize, 3), s.images.count());
    try testing.expectEqual(tracked, t.screen.pages.countTrackedPins());
}

test "storage: delete all placements by image id" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 3, .cols = 3 });
    defer t.deinit(alloc);
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1 });
    try s.addImage(alloc, .{ .id = 2 });
    try s.addImage(alloc, .{ .id = 3 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try s.addPlacement(alloc, 2, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });

    s.dirty = false;
    s.delete(alloc, &t, .{ .id = .{ .image_id = 2 } });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 1), s.placements.count());
    try testing.expectEqual(@as(usize, 3), s.images.count());
    try testing.expectEqual(tracked + 1, t.screen.pages.countTrackedPins());
}

test "storage: delete all placements by image id and unused images" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 3, .cols = 3 });
    defer t.deinit(alloc);
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1 });
    try s.addImage(alloc, .{ .id = 2 });
    try s.addImage(alloc, .{ .id = 3 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try s.addPlacement(alloc, 2, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });

    s.dirty = false;
    s.delete(alloc, &t, .{ .id = .{ .delete = true, .image_id = 2 } });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 1), s.placements.count());
    try testing.expectEqual(@as(usize, 2), s.images.count());
    try testing.expectEqual(tracked + 1, t.screen.pages.countTrackedPins());
}

test "storage: delete placement by specific id" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 3, .cols = 3 });
    defer t.deinit(alloc);
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1 });
    try s.addImage(alloc, .{ .id = 2 });
    try s.addImage(alloc, .{ .id = 3 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try s.addPlacement(alloc, 1, 2, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try s.addPlacement(alloc, 2, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });

    s.dirty = false;
    s.delete(alloc, &t, .{ .id = .{
        .delete = true,
        .image_id = 1,
        .placement_id = 2,
    } });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 2), s.placements.count());
    try testing.expectEqual(@as(usize, 3), s.images.count());
    try testing.expectEqual(tracked + 2, t.screen.pages.countTrackedPins());
}

test "storage: delete intersecting cursor" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 100, .cols = 100 });
    defer t.deinit(alloc);
    t.width_px = 100;
    t.height_px = 100;
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1, .width = 50, .height = 50 });
    try s.addImage(alloc, .{ .id = 2, .width = 25, .height = 25 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 0, .y = 0 }) } });
    try s.addPlacement(alloc, 1, 2, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 25, .y = 25 }) } });

    t.screen.cursorAbsolute(12, 12);

    s.dirty = false;
    s.delete(alloc, &t, .{ .intersect_cursor = false });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 1), s.placements.count());
    try testing.expectEqual(@as(usize, 2), s.images.count());
    try testing.expectEqual(tracked + 1, t.screen.pages.countTrackedPins());

    // verify the placement is what we expect
    try testing.expect(s.placements.get(.{
        .image_id = 1,
        .placement_id = .{ .tag = .external, .id = 2 },
    }) != null);
}

test "storage: delete intersecting cursor plus unused" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 100, .cols = 100 });
    defer t.deinit(alloc);
    t.width_px = 100;
    t.height_px = 100;
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1, .width = 50, .height = 50 });
    try s.addImage(alloc, .{ .id = 2, .width = 25, .height = 25 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 0, .y = 0 }) } });
    try s.addPlacement(alloc, 1, 2, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 25, .y = 25 }) } });

    t.screen.cursorAbsolute(12, 12);

    s.dirty = false;
    s.delete(alloc, &t, .{ .intersect_cursor = true });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 1), s.placements.count());
    try testing.expectEqual(@as(usize, 2), s.images.count());
    try testing.expectEqual(tracked + 1, t.screen.pages.countTrackedPins());

    // verify the placement is what we expect
    try testing.expect(s.placements.get(.{
        .image_id = 1,
        .placement_id = .{ .tag = .external, .id = 2 },
    }) != null);
}

test "storage: delete intersecting cursor hits multiple" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 100, .cols = 100 });
    defer t.deinit(alloc);
    t.width_px = 100;
    t.height_px = 100;
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1, .width = 50, .height = 50 });
    try s.addImage(alloc, .{ .id = 2, .width = 25, .height = 25 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 0, .y = 0 }) } });
    try s.addPlacement(alloc, 1, 2, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 25, .y = 25 }) } });

    t.screen.cursorAbsolute(26, 26);

    s.dirty = false;
    s.delete(alloc, &t, .{ .intersect_cursor = true });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 0), s.placements.count());
    try testing.expectEqual(@as(usize, 1), s.images.count());
    try testing.expectEqual(tracked, t.screen.pages.countTrackedPins());
}

test "storage: delete by column" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 100, .cols = 100 });
    defer t.deinit(alloc);
    t.width_px = 100;
    t.height_px = 100;
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1, .width = 50, .height = 50 });
    try s.addImage(alloc, .{ .id = 2, .width = 25, .height = 25 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 0, .y = 0 }) } });
    try s.addPlacement(alloc, 1, 2, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 25, .y = 25 }) } });

    s.dirty = false;
    s.delete(alloc, &t, .{ .column = .{
        .delete = false,
        .x = 60,
    } });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 1), s.placements.count());
    try testing.expectEqual(@as(usize, 2), s.images.count());
    try testing.expectEqual(tracked + 1, t.screen.pages.countTrackedPins());

    // verify the placement is what we expect
    try testing.expect(s.placements.get(.{
        .image_id = 1,
        .placement_id = .{ .tag = .external, .id = 1 },
    }) != null);
}

test "storage: delete by column 1x1" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 100, .cols = 100 });
    defer t.deinit(alloc);
    t.width_px = 100;
    t.height_px = 100;

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1, .width = 1, .height = 1 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 0, .y = 0 }) } });
    try s.addPlacement(alloc, 1, 2, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 0 }) } });
    try s.addPlacement(alloc, 1, 3, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 2, .y = 0 }) } });

    s.delete(alloc, &t, .{ .column = .{
        .delete = false,
        .x = 2,
    } });
    try testing.expectEqual(@as(usize, 2), s.placements.count());
    try testing.expectEqual(@as(usize, 1), s.images.count());

    // verify the placement is what we expect
    try testing.expect(s.placements.get(.{
        .image_id = 1,
        .placement_id = .{ .tag = .external, .id = 1 },
    }) != null);
    try testing.expect(s.placements.get(.{
        .image_id = 1,
        .placement_id = .{ .tag = .external, .id = 3 },
    }) != null);
}

test "storage: delete by row" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 100, .cols = 100 });
    defer t.deinit(alloc);
    t.width_px = 100;
    t.height_px = 100;
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1, .width = 50, .height = 50 });
    try s.addImage(alloc, .{ .id = 2, .width = 25, .height = 25 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 0, .y = 0 }) } });
    try s.addPlacement(alloc, 1, 2, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 25, .y = 25 }) } });

    s.dirty = false;
    s.delete(alloc, &t, .{ .row = .{
        .delete = false,
        .y = 60,
    } });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 1), s.placements.count());
    try testing.expectEqual(@as(usize, 2), s.images.count());
    try testing.expectEqual(tracked + 1, t.screen.pages.countTrackedPins());

    // verify the placement is what we expect
    try testing.expect(s.placements.get(.{
        .image_id = 1,
        .placement_id = .{ .tag = .external, .id = 1 },
    }) != null);
}

test "storage: delete by row 1x1" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 100, .cols = 100 });
    defer t.deinit(alloc);
    t.width_px = 100;
    t.height_px = 100;

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1, .width = 1, .height = 1 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .y = 0 }) } });
    try s.addPlacement(alloc, 1, 2, .{ .location = .{ .pin = try trackPin(&t, .{ .y = 1 }) } });
    try s.addPlacement(alloc, 1, 3, .{ .location = .{ .pin = try trackPin(&t, .{ .y = 2 }) } });

    s.delete(alloc, &t, .{ .row = .{
        .delete = false,
        .y = 2,
    } });
    try testing.expectEqual(@as(usize, 2), s.placements.count());
    try testing.expectEqual(@as(usize, 1), s.images.count());

    // verify the placement is what we expect
    try testing.expect(s.placements.get(.{
        .image_id = 1,
        .placement_id = .{ .tag = .external, .id = 1 },
    }) != null);
    try testing.expect(s.placements.get(.{
        .image_id = 1,
        .placement_id = .{ .tag = .external, .id = 3 },
    }) != null);
}

test "storage: delete images by range 1" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 3, .cols = 3 });
    defer t.deinit(alloc);
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1 });
    try s.addImage(alloc, .{ .id = 2 });
    try s.addImage(alloc, .{ .id = 3 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try s.addPlacement(alloc, 2, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try testing.expectEqual(@as(usize, 3), s.images.count());
    try testing.expectEqual(@as(usize, 2), s.placements.count());

    s.dirty = false;
    s.delete(alloc, &t, .{ .range = .{ .delete = false, .first = 1, .last = 2 } });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 3), s.images.count());
    try testing.expectEqual(@as(usize, 0), s.placements.count());
    try testing.expectEqual(tracked, t.screen.pages.countTrackedPins());
}

test "storage: delete images by range 2" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 3, .cols = 3 });
    defer t.deinit(alloc);
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1 });
    try s.addImage(alloc, .{ .id = 2 });
    try s.addImage(alloc, .{ .id = 3 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try s.addPlacement(alloc, 2, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try testing.expectEqual(@as(usize, 3), s.images.count());
    try testing.expectEqual(@as(usize, 2), s.placements.count());

    s.dirty = false;
    s.delete(alloc, &t, .{ .range = .{ .delete = true, .first = 1, .last = 2 } });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 1), s.images.count());
    try testing.expectEqual(@as(usize, 0), s.placements.count());
    try testing.expectEqual(tracked, t.screen.pages.countTrackedPins());
}

test "storage: delete images by range 3" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 3, .cols = 3 });
    defer t.deinit(alloc);
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1 });
    try s.addImage(alloc, .{ .id = 2 });
    try s.addImage(alloc, .{ .id = 3 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try s.addPlacement(alloc, 2, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try testing.expectEqual(@as(usize, 3), s.images.count());
    try testing.expectEqual(@as(usize, 2), s.placements.count());

    s.dirty = false;
    s.delete(alloc, &t, .{ .range = .{ .delete = false, .first = 1, .last = 1 } });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 3), s.images.count());
    try testing.expectEqual(@as(usize, 0), s.placements.count());
    try testing.expectEqual(tracked, t.screen.pages.countTrackedPins());
}

test "storage: delete images by range 4" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .rows = 3, .cols = 3 });
    defer t.deinit(alloc);
    const tracked = t.screen.pages.countTrackedPins();

    var s: ImageStorage = .{};
    defer s.deinit(alloc, &t.screen);
    try s.addImage(alloc, .{ .id = 1 });
    try s.addImage(alloc, .{ .id = 2 });
    try s.addImage(alloc, .{ .id = 3 });
    try s.addPlacement(alloc, 1, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try s.addPlacement(alloc, 2, 1, .{ .location = .{ .pin = try trackPin(&t, .{ .x = 1, .y = 1 }) } });
    try testing.expectEqual(@as(usize, 3), s.images.count());
    try testing.expectEqual(@as(usize, 2), s.placements.count());

    s.dirty = false;
    s.delete(alloc, &t, .{ .range = .{ .delete = true, .first = 1, .last = 1 } });
    try testing.expect(s.dirty);
    try testing.expectEqual(@as(usize, 1), s.images.count());
    try testing.expectEqual(@as(usize, 0), s.placements.count());
    try testing.expectEqual(tracked, t.screen.pages.countTrackedPins());
}

test "storage: aspect ratio calculation when only columns or rows specified" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var t = try terminal.Terminal.init(alloc, .{ .cols = 100, .rows = 100 });
    defer t.deinit(alloc);
    t.width_px = 100;
    t.height_px = 100;

    // Case 1: Only columns specified
    {
        const image = Image{ .id = 1, .width = 4, .height = 2 };
        var placement = ImageStorage.Placement{
            .location = .{ .virtual = {} },
            .columns = 6,
            .rows = 0,
        };

        const grid_size = placement.gridSize(image, &t);
        // 6 columns * (2/4) = 3 rows
        try testing.expectEqual(@as(u32, 6), grid_size.cols);
        try testing.expectEqual(@as(u32, 3), grid_size.rows);
    }

    // Case 2: Only rows specified
    {
        const image = Image{ .id = 2, .width = 2, .height = 4 };
        var placement = ImageStorage.Placement{
            .location = .{ .virtual = {} },
            .columns = 0,
            .rows = 6,
        };

        const grid_size = placement.gridSize(image, &t);
        // 6 rows * (2/4) = 3 columns
        try testing.expectEqual(@as(u32, 3), grid_size.cols);
        try testing.expectEqual(@as(u32, 6), grid_size.rows);
    }
}
