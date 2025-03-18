/// The OpenGL program for rendering terminal cells.
const CellProgram = @This();

const std = @import("std");
const gl = @import("opengl");

program: gl.Program,
vao: gl.VertexArray,
ebo: gl.Buffer,
vbo: gl.Buffer,

/// The raw structure that maps directly to the buffer sent to the vertex shader.
/// This must be "extern" so that the field order is not reordered by the
/// Zig compiler.
pub const Cell = extern struct {
    /// vec2 grid_coord
    grid_col: u16,
    grid_row: u16,

    /// vec2 glyph_pos
    glyph_x: u32 = 0,
    glyph_y: u32 = 0,

    /// vec2 glyph_size
    glyph_width: u32 = 0,
    glyph_height: u32 = 0,

    /// vec2 glyph_offset
    glyph_offset_x: i32 = 0,
    glyph_offset_y: i32 = 0,

    /// vec4 color_in
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    /// vec4 bg_color_in
    bg_r: u8,
    bg_g: u8,
    bg_b: u8,
    bg_a: u8,

    /// uint mode
    mode: CellMode,

    /// The width in grid cells that a rendering takes.
    grid_width: u8,
};

pub const CellMode = enum(u8) {
    bg = 1,
    fg = 2,
    fg_constrained = 3,
    fg_color = 7,
    fg_powerline = 15,

    // Non-exhaustive because masks change it
    _,

    /// Apply a mask to the mode.
    pub fn mask(self: CellMode, m: CellMode) CellMode {
        return @enumFromInt(@intFromEnum(self) | @intFromEnum(m));
    }

    pub fn isFg(self: CellMode) bool {
        // Since we use bit tricks below, we want to ensure the enum
        // doesn't change without us looking at this logic again.
        comptime {
            const info = @typeInfo(CellMode).@"enum";
            std.debug.assert(info.fields.len == 5);
        }

        return @intFromEnum(self) & @intFromEnum(@as(CellMode, .fg)) != 0;
    }
};

pub fn init() !CellProgram {
    // Load and compile our shaders.
    const program = try gl.Program.createVF(
        @embedFile("../shaders/cell.v.glsl"),
        @embedFile("../shaders/cell.f.glsl"),
    );
    errdefer program.destroy();

    // Set our cell dimensions
    const pbind = try program.use();
    defer pbind.unbind();

    // Set all of our texture indexes
    try program.setUniform("text", 0);
    try program.setUniform("text_color", 1);

    // Setup our VAO
    const vao = try gl.VertexArray.create();
    errdefer vao.destroy();
    const vaobind = try vao.bind();
    defer vaobind.unbind();

    // Element buffer (EBO)
    const ebo = try gl.Buffer.create();
    errdefer ebo.destroy();
    var ebobind = try ebo.bind(.element_array);
    defer ebobind.unbind();
    try ebobind.setData([6]u8{
        0, 1, 3, // Top-left triangle
        1, 2, 3, // Bottom-right triangle
    }, .static_draw);

    // Vertex buffer (VBO)
    const vbo = try gl.Buffer.create();
    errdefer vbo.destroy();
    var vbobind = try vbo.bind(.array);
    defer vbobind.unbind();
    var offset: usize = 0;
    try vbobind.attributeAdvanced(0, 2, gl.c.GL_UNSIGNED_SHORT, false, @sizeOf(Cell), offset);
    offset += 2 * @sizeOf(u16);
    try vbobind.attributeAdvanced(1, 2, gl.c.GL_UNSIGNED_INT, false, @sizeOf(Cell), offset);
    offset += 2 * @sizeOf(u32);
    try vbobind.attributeAdvanced(2, 2, gl.c.GL_UNSIGNED_INT, false, @sizeOf(Cell), offset);
    offset += 2 * @sizeOf(u32);
    try vbobind.attributeAdvanced(3, 2, gl.c.GL_INT, false, @sizeOf(Cell), offset);
    offset += 2 * @sizeOf(i32);
    try vbobind.attributeAdvanced(4, 4, gl.c.GL_UNSIGNED_BYTE, false, @sizeOf(Cell), offset);
    offset += 4 * @sizeOf(u8);
    try vbobind.attributeAdvanced(5, 4, gl.c.GL_UNSIGNED_BYTE, false, @sizeOf(Cell), offset);
    offset += 4 * @sizeOf(u8);
    try vbobind.attributeIAdvanced(6, 1, gl.c.GL_UNSIGNED_BYTE, @sizeOf(Cell), offset);
    offset += 1 * @sizeOf(u8);
    try vbobind.attributeIAdvanced(7, 1, gl.c.GL_UNSIGNED_BYTE, @sizeOf(Cell), offset);
    try vbobind.enableAttribArray(0);
    try vbobind.enableAttribArray(1);
    try vbobind.enableAttribArray(2);
    try vbobind.enableAttribArray(3);
    try vbobind.enableAttribArray(4);
    try vbobind.enableAttribArray(5);
    try vbobind.enableAttribArray(6);
    try vbobind.enableAttribArray(7);
    try vbobind.attributeDivisor(0, 1);
    try vbobind.attributeDivisor(1, 1);
    try vbobind.attributeDivisor(2, 1);
    try vbobind.attributeDivisor(3, 1);
    try vbobind.attributeDivisor(4, 1);
    try vbobind.attributeDivisor(5, 1);
    try vbobind.attributeDivisor(6, 1);
    try vbobind.attributeDivisor(7, 1);

    return .{
        .program = program,
        .vao = vao,
        .ebo = ebo,
        .vbo = vbo,
    };
}

pub fn bind(self: CellProgram) !Binding {
    const program = try self.program.use();
    errdefer program.unbind();

    const vao = try self.vao.bind();
    errdefer vao.unbind();

    const ebo = try self.ebo.bind(.element_array);
    errdefer ebo.unbind();

    const vbo = try self.vbo.bind(.array);
    errdefer vbo.unbind();

    return .{
        .program = program,
        .vao = vao,
        .ebo = ebo,
        .vbo = vbo,
    };
}

pub fn deinit(self: CellProgram) void {
    self.vbo.destroy();
    self.ebo.destroy();
    self.vao.destroy();
    self.program.destroy();
}

pub const Binding = struct {
    program: gl.Program.Binding,
    vao: gl.VertexArray.Binding,
    ebo: gl.Buffer.Binding,
    vbo: gl.Buffer.Binding,

    pub fn unbind(self: Binding) void {
        self.vbo.unbind();
        self.ebo.unbind();
        self.vao.unbind();
        self.program.unbind();
    }
};
