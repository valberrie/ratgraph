const std = @import("std");

const graph = @import("graphics.zig");

const Rec = graph.Rec;
const Vec2f = graph.Vec2f;
const Rect = graph.Rect;

const Color = graph.CharColor;
const intToColor = graph.intToColor;
const itc = intToColor;
const WHITE = intToColor(0xffffffff);
const BLACK = intToColor(0x000000ff);
const GRAY = intToColor(0x222222ff);
const GREEN = intToColor(0x00ff00ff);

pub fn restrictFloat(num: f32, min: f32, max: f32) f32 {
    if (num > max)
        return max;
    if (num < min)
        return min;
    return num;
}

pub fn rectContainsPoint(r: Rect, x: f32, y: f32) bool {
    return (x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h);
}

pub const DrawCommand = struct {
    pub const DRect = struct {
        rect: Rect,
        z: f32,
        col: Color,
    };

    pub const DTexRect = struct {
        rect: Rect,
        uv: Rect,
        col: Color,
        texture: graph.Texture,
    };

    pub const DText = struct {
        text: []const u8,
        x: f32,
        y: f32,
        z: f32,
        size: f32,
        col: Color,
    };

    pub const Types = enum {
        rect,
        text,
        texRect,
    };

    pub const Command = union(Types) {
        rect: DRect,
        text: DText,
        texRect: DTexRect,
    };

    pub fn drawRect(cmd_buf: *CmdBuf, rect: Rect, z: f32, col: Color) void {
        cmd_buf.append(.{ .rect = .{ .rect = rect, .z = z, .col = col } }) catch return;
    }

    pub fn drawTexRect(cmd_buf: *CmdBuf, rect: Rect, uv: Rect, texture: graph.Texture, col: Color) void {
        cmd_buf.append(.{ .texRect = .{ .rect = rect, .uv = uv, .col = col, .texture = texture } }) catch return;
    }

    pub fn drawText(cmd_buf: *CmdBuf, str_buf_stream: *StrBufStream, text: []const u8, x: f32, y: f32, z: f32, size: f32, col: Color) void {
        const pos = str_buf_stream.pos;
        _ = str_buf_stream.writer().write(text) catch return;
        //str_buf_stream.writer().writeByte(0) catch return;

        cmd_buf.append(.{ .text = .{
            .text = str_buf_stream.buffer[pos..str_buf_stream.pos],
            .x = x,
            .y = y,
            .z = z,
            .size = size,
            .col = col,
        } }) catch return;
    }

    pub fn drawTextFmt(cmd_buf: *CmdBuf, str_buf_stream: *StrBufStream, x: f32, y: f32, fsize: f32, comptime fmt_str: []const u8, fmt_data: anytype) void {
        const pos = str_buf_stream.pos;
        str_buf_stream.writer().print(fmt_str, fmt_data) catch return;
        //str_buf_stream.writer().writeByte(0) catch return;
        cmd_buf.append(.{ .text = .{
            .text = str_buf_stream.buffer[pos..str_buf_stream.pos],
            .x = x,
            .y = y,
            .z = -10,
            .size = fsize,
            .col = itc(0xeeeeeeff),
        } }) catch return;
    }
};

pub const CmdBuf = std.ArrayList(DrawCommand.Command);
pub const StrBufStream = std.io.FixedBufferStream([]u8);

pub fn drawCommands(cmds: []DrawCommand.Command, ctx: *graph.GraphicsContext, font: *graph.Font) void {
    for (cmds) |cmd| {
        switch (cmd) {
            .rect => |r| {
                //drawRect(r.rect, r.col);
                ctx.drawRect(r.rect, r.col);
            },
            .text => |t| {
                ctx.drawText(t.x, t.y, t.text, font, t.size, t.col);
            },
            .texRect => |tr| {
                ctx.drawRectTex(tr.rect, tr.uv, tr.col, tr.texture) catch return;
            },
        }
    }
}

const BRect = struct {
    const Self = @This();

    top: f32,
    bottom: f32,
    left: f32,
    right: f32,

    pub fn single(item: f32) Self {
        return .{ .top = item, .bottom = item, .left = item, .right = item };
    }
};

pub const ElementStyle = struct {
    const Self = @This();
    margin: BRect,
    padding: BRect,

    border_width: f32 = 2,

    pub fn getWidth(self: *Self) f32 {
        return self.margin.left + self.margin.right + self.padding.left + self.padding.right + self.border_width * 2;
    }

    pub fn getTop(self: *Self) f32 {
        return self.margin.top + self.padding.top + self.border_width;
    }

    pub fn getBottom(self: *Self) f32 {
        return self.margin.bottom + self.padding.bottom + self.border_width;
    }

    pub fn getLeft(self: *Self) f32 {
        return self.margin.left + self.padding.left + self.border_width;
    }

    pub fn getRight(self: *Self) f32 {
        return self.margin.right + self.padding.right + self.border_width;
    }
};

pub const SaveData = struct {
    x: f32,
    y: f32,
};

const GUIDOC =
    \\How the gui system works:
    \\  Layouting and elements are seperate functions.
    \\  Everything is drawn through a Fat Cursor.
    \\  The layout is specified by the user and subsequent elements that are added "button, floatSlide etc" are drawn to fill the provide cursor.
    \\  For instance, the function button() will fill fully the current cursor with what a button. In order to not use the whole window, 
    \\  helper functions that divide up cursors into smaller cursors that can be iterated are helpful
;

pub const Layout = union(enum) {
    const Self = @This();
    column: struct {
        num_items: u32,
        item_height: f32,
        index: u32 = 0,
    },

    pub fn nextCursor(self: *Self, section_cursor: FatCursor) FatCursor {
        switch (self.*) {
            .column => |col| {
                defer self.column.index += 1;
                var co = section_cursor;
                co.co = graph.Rec(
                    co.co.x,
                    co.co.y + (@as(f32, @floatFromInt(col.index)) * col.item_height),
                    co.co.w,
                    col.item_height,
                );
                return co;
            },
        }
    }
};

pub const FatCursor = struct {
    const Self = @This();

    ctx: *graph.GraphicsContext,
    font: *graph.Font,

    co: graph.Rect,
    layout: Layout = .{ .column = .{ .num_items = 0, .item_height = 10 } },

    pub fn init(xin: f32, yin: f32, win: f32, hin: f32, ctx: *graph.GraphicsContext, font: *graph.Font) Self {
        return Self{
            .co = .{
                .x = 72 * xin,
                .y = 72 * yin,
                .w = 72 * win,
                .h = 72 * hin,
            },
            .ctx = ctx,
            .font = font,
        };
    }

    pub fn rect(self: *Self, col: Color) void {
        self.ctx.ptRect(self.co.x, self.co.y, self.co.w, self.co.h, col);
    }

    pub fn text(self: *Self, str: []const u8, col: Color) void {
        self.ctx.drawText(self.co.x, self.co.y, str, self.font, self.co.h, col);
    }

    pub fn margin(self: *Self, w: f32) void {
        self.co.x += w;
        self.co.y += w;
        self.co.w -= w * 2;
        self.co.h -= w * 2;
    }

    pub fn ymargin(self: *Self, h: f32) void {
        self.co.y += h;
        self.co.h -= h;
    }

    pub fn beginCursor(self: *Self, cursor: graph.Rect) graph.Rect {
        const old = self.co;
        self.co = cursor;
        return old;
    }
    pub fn endCursor(self: *Self, cursor: graph.Rect) void {
        self.co = cursor;
    }

    pub fn begin3D(self: *Self, param: struct { light: Color, dark: Color, bg: Color, border_w: f32 }) Rect {
        const old_co = self.co;
        self.rect(param.light);
        self.co.x += param.border_w;
        self.co.y += param.border_w;
        self.co.w -= param.border_w;
        self.co.h -= param.border_w;
        self.rect(param.dark);
        self.co.w -= param.border_w;
        self.co.h -= param.border_w;
        self.rect(param.bg);

        return old_co;
    }

    pub fn end3D(self: *Self, co: Rect) void {
        self.co = co;
    }
};

pub fn nColumns(cr: FatCursor, index: u32, n: u32) FatCursor {
    const w = cr.co.w / @as(f32, @floatFromInt(n));
    var co = cr;
    co.co.w = w;
    co.co.x += @as(f32, @floatFromInt(index)) * w;

    return co;
}

pub const Window = struct {
    const Self = @This();
    const DRect = DrawCommand.drawRect;

    //Any function that needs to id itself for input must increment this value
    //If the set of context calls is constant it allows a function call to identify itself
    //This is usefull for determing if the same element was being clicked last frame
    item_index: usize = 0,
    click_index: ?usize = null,
    focused_textbox: ?usize = null,

    m_delta: Vec2f = undefined,
    m_old_x: f32 = undefined,
    m_old_y: f32 = undefined,
    m_down: bool = false,

    dpi: f32,

    mouse_state: graph.SDL.MouseState = undefined,

    font: *graph.Font,

    cr: FatCursor,
    init_cursor: Rect = graph.Rec(4 * 72, 4 * 72, 8 * 72, 5 * 72),

    pub fn init(font: *graph.Font, ctx: *graph.GraphicsContext, dpi: f32) Self {
        return Self{
            .font = font,
            .cr = FatCursor.init(4, 4, 5, 6, ctx, font),
            .dpi = dpi,
        };
    }

    pub fn requestItemIndex(self: *Self) usize {
        self.item_index += 1;
        return self.item_index - 1;
    }

    pub fn begin(self: *Self, new_pos: Vec2f, m_delta: Vec2f, m_down: bool, mouse_state: graph.SDL.MouseState) void {
        //defer self.x += self.font.ptToPixel(2);
        self.mouse_state = mouse_state;
        self.item_index = 0;
        const this_item = self.requestItemIndex();

        const sf = 72 / self.dpi;
        const new_p = new_pos.smul(sf);

        self.m_delta = m_delta.smul(sf);
        self.m_old_x = new_p.x - self.m_delta.x;
        self.m_old_y = new_p.y - self.m_delta.y;
        self.m_down = m_down;
        if (!self.m_down)
            self.click_index = null;

        const BG = itc(0x29809bff);
        const TITLEBG = itc(0xa1a1a1ff);

        const cri = &self.cr;

        cri.co = self.init_cursor;
        cri.layout = .{ .column = .{ .num_items = 10, .item_height = 20 } };

        var cr = self.cr.layout.nextCursor(self.cr);
        {
            if (self.click_index) |cindex| {
                if (cindex == this_item) {
                    self.init_cursor.x += self.m_delta.x;
                    self.init_cursor.y += self.m_delta.y;
                }
            } else {
                if (self.m_down and rectContainsPoint(cr.co, self.m_old_x, self.m_old_y)) {
                    self.click_index = this_item;
                    self.init_cursor.x += self.m_delta.x;
                    self.init_cursor.y += self.m_delta.y;
                }
            }
        }

        cr.co = self.init_cursor;
        cr.rect(BG);
        cri.layout = .{ .column = .{ .num_items = 10, .item_height = 20 } };
        cr = self.cr.layout.nextCursor(self.cr);

        cr.rect(itc(0x000000ff));
        cr.margin(2);
        cr.rect(TITLEBG);

        cr.co = self.init_cursor;
        cr.co.y += 20;
    }

    pub fn end(self: *Self) void {
        _ = self;
        //self.cmd_buf.items[0].rect.rect.h = self.y - self.y_init;

    }

    pub fn floatSlide(self: *Self, lab: ?[]const u8, item: *f32, min: f32, max: f32) void {
        const val = item.*;
        const perc = ((val - min) / (max - min));
        const this_item = self.requestItemIndex();

        //CALL
        //const co = nextCursor()
        //
        //GuiContext needs to hold some nextCursor() function
        //What data does nextCursor need?
        //Type
        //Are third party nextCursor types needed?
        //
        //User calls some kind of setLayout function
        //set layout: grid, column
        //
        //current_Layout: Layout
        //
        //Layout = tagged union
        //grid = struct {
        //

        var cr = self.cr.layout.nextCursor(self.cr);
        //const cr = self.layout.nextCursor(self.cr.co);
        //const cr = &self.cr;
        //const button_h: f32 = 15;
        //const sec1 = cr.beginRestrictHeight(button_h);
        {
            cr.margin(1);
            cr.rect(itc(0x330033ff));
            cr.margin(1);
            cr.rect(itc(0x334433ff));
            //cr.text(lab orelse "_", itc(0xffffffff));
            var buf: [128]u8 = undefined;
            var fbs = std.io.FixedBufferStream([]u8){ .buffer = &buf, .pos = 0 };
            var w = fbs.writer();
            w.print("{s}: {d}", .{ lab orelse " ", val }) catch unreachable;
            cr.text(fbs.getWritten(), itc(0x00ff00ff));

            const handle_sec = cr.beginCursor(graph.Rec((perc * cr.co.w) + cr.co.x, cr.co.y, 13, cr.co.h));
            {
                cr.rect(itc(0xff0000ff));
                if (self.click_index) |cindex| {
                    if (cindex == this_item) {
                        item.* = ((self.m_delta.x + (cr.co.x - handle_sec.x)) / (handle_sec.w)) * (max - min) + min;
                    }
                } else {
                    if (self.m_down and rectContainsPoint(cr.co, self.m_old_x, self.m_old_y)) {
                        self.click_index = this_item;
                        self.focused_textbox = null;

                        item.* = ((self.m_delta.x + (cr.co.x - handle_sec.x)) / (handle_sec.w)) * (max - min) + min;
                    }
                }

                cr.margin(1);
                cr.rect(itc(0x880000ff));
            }
            cr.endCursor(handle_sec);
        }
        //cr.endRestrictHeight(sec1);
    }

    pub fn checkBox(self: *Self, val: *bool, lab: ?[]const u8) void {
        //const cr = &self.cr;
        var cr = self.cr.layout.nextCursor(self.cr);

        //const button_h: f32 = 18;
        //const sec1 = cr.beginRestrictHeight(button_h);
        {
            if (rectContainsPoint(cr.co, self.m_old_x, self.m_old_y)) {
                if (self.mouse_state.left_down) {
                    val.* = !val.*;
                }
            }
            cr.margin(2);
            cr.rect(itc(0x333333ff));
            cr.ymargin(1);
            cr.text(lab orelse "fuck", if (val.*) itc(0x00ff00ff) else itc(0xff0000ff));
        }
        //cr.endRestrictHeight(sec1);
        //cr.rect()

    }

    pub fn modify(self: *Self, comptime T: type, itemptr: *T, lab: ?[]const u8) void {
        const info = @typeInfo(T);
        switch (info) {
            .Struct => {
                inline for (info.Struct.fields) |field| {
                    self.cr.co.x += 12;
                    self.cr.co.w -= 24;
                    defer self.cr.co.w += 24;
                    defer self.cr.co.x -= 12;
                    self.modify(field.field_type, &@field(itemptr.*, field.name), field.name);
                }
            },
            .Float => {
                self.floatSlide(lab orelse "", itemptr, 0, 100);
            },
            .Pointer => |p| {
                switch (p.size) {
                    .Slice => {
                        self.label("pointer: " ++ @typeName(p.child));
                    },
                    else => {},
                }
            },
            else => {
                self.label(@typeName(T));
                return;
                //@compileLog(@typeName(T)[0..]);
                //@compileError("Type not supported for gui.modify");
            },
        }
    }

    //progress bar
    //Text box
    //slide
    //slideRange
    //slideRangeLabel
    //Border box
    //Rows with multi items
    //Drop down
    //Text list radio / selection
    //Spinner?
    //
    //currently struct Context can be thought of as a window,
    //further objects to allow layouting of a window.
    //
    //Input handeling:
    //Provide all state at begin() call
    //Styling
    //
    //How to deal with orderd drawing?
    //We don't know how big the background of a window should be drawn until after end is called
    //With painters drawing this requires insertion and storing the index of a drawcmd for later modification.
    //
    //Text justification
    //left right center
    //Both sides are as flush as possible
    //Colors of elements
    //Borders
    //
    //Have global styling for a window and optional element level styling passed immediatly
    //Have a similar system to html box model for margin and padding calcualtion?

    pub fn button(self: *Self) bool {
        var cr = self.cr.layout.nextCursor(self.cr);
        {
            const sec2 = cr.begin3D(.{ .light = itc(0xffffffff), .dark = itc(0x000000ff), .bg = itc(0x222222ff), .border_w = 1 });

            cr.end3D(sec2);
        }

        if (true)
            return false;
        const this_item = self.requestItemIndex();
        const adjx = self.x;
        const w = self.width - self.padding * 2;
        //self.y += 0;
        //defer self.y += self.default_style.getBottom();

        const button_height: f32 = 30;
        const r = Rect{ .x = adjx, .y = self.y, .w = w, .h = button_height };
        var color = itc(0x202020ff);
        defer DrawCommand.drawRect(
            self.cmd_buf,
            r,
            0,
            color,
        );
        self.y += button_height;

        //if (self.click_index) |cindex| {
        //    if (cindex == this_item) {
        //        color = BLACK;
        //        return false;
        //    }
        //}

        if (self.mouse_state.left_down and rectContainsPoint(r, self.m_old_x, self.m_old_y)) {
            self.click_index = this_item;
            return true;
        }
        return false;
    }

    pub fn label(self: *Self, str: []const u8) void {
        var cr = self.cr.layout.nextCursor(self.cr);
        {
            cr.rect(itc(0x000000ff));
            cr.text(str, itc(0xffffffff));
        }
    }
};
