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

//GUI interface design
//functions that add elements should except generic args for numbers etc
//
//The functions themselves should call a getBoundRect() that calculates where items can be placed
//
//Problems:
//better mouse and/or keyboard abstractions

pub fn drawSlider(
    x: f32,
    y: f32,
    l: f32,
    h: f32,
    handle: f32,
    bg: Color,
    fg: Color,
    cbuf: *CmdBuf,
) void {
    cbuf.append(.{ .rect = .{ .z = -1, .rect = Rec(x, y, l, h), .col = bg } }) catch return;
    const di = 5;
    if (handle < l)
        cbuf.append(.{ .rect = .{ .z = -1, .rect = Rec(handle + x, y + di, h, h - (di * 2)), .col = fg } }) catch return;
}

pub fn rectContainsPoint(r: Rect, x: f32, y: f32) bool {
    return (x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h);
}

//Commands:
//Rect x y w h col
//Text *str x y fsize col
//

const Border1 = [3]Color{
    //intToColor(0x404040ff),
    intToColor(0xff4040ff),
    intToColor(0xd4d0c8ff),
    intToColor(0xffffffff),
};

const Border2 = [3]Color{
    intToColor(0xd4d0c8ff),
    intToColor(0x000000ff),
    intToColor(0x404040ff),
};

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

    pub fn drawOutsetBorder(cmd_buf: *CmdBuf, rect: Rect, w: f32, cols: [3]Color) void {
        const colors = [_]Color{ cols[0], cols[0], cols[1], cols[1], cols[2], cols[2] };

        const borders = genBorderRects(rect, w);
        for (borders) |border, i| {
            cmd_buf.append(.{ .rect = .{ .z = -10, .rect = border, .col = colors[i] } }) catch return;
        }
    }

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
//TODO
//Cool json seriel and deserial for arbitrary objects
//you provide a default struct
//specify what fields you want to load and write
//any missing fields get taken from the default
//
//eaisly allow persistant change through gui of things like styling etc.
//
//Multi window support
//How to ensure mouse clicks get sent to correct window?
//Basic window managment?
//how are overlapping windows handled
//is there own gctx context with multiple windows that are all drawn at once?
//This makes it simple

//DElete lol
pub const TextEditor = struct {
    const Self = @This();

    x: f32 = 400,
    y: f32 = 500,

    rows: u32 = 100,
    cols: u32 = 140,
    lines: std.ArrayList(std.ArrayList(u8)),

    cy: u32 = 0,

    pub fn init(alloc: *const std.mem.Allocator, str: []const u8) !Self {
        var ret = Self{ .lines = std.ArrayList(std.ArrayList(u8)).init(alloc.*) };
        var it = std.mem.SplitIterator(u8){ .buffer = str, .index = 0, .delimiter = "\n" };
        while (it.next()) |line| {
            try ret.lines.append(std.ArrayList(u8).init(alloc.*));
            try ret.lines.items[ret.lines.items.len - 1].appendSlice(line);
        }
        return ret;
    }

    pub fn deinit(self: *Self) void {
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.deinit();
    }

    pub fn draw(self: *Self, ctx: *graph.GraphicsContext, font: *graph.Font, point_size: f32) !void {
        const sf = point_size / font.font_size;
        const lines = self.lines.items[self.cy..];

        ctx.drawRect(Rec(self.x, self.y, font.max_advance * @intToFloat(f32, self.cols) * sf, font.line_gap * @intToFloat(f32, self.rows) * sf), itc(0x111111ff));

        for (lines) |line, i| {
            const slice = if (line.items.len > self.cols) line.items[0..self.cols] else line.items[0..];
            ctx.drawText(self.x, sf * font.ascent + self.y + (font.line_gap * sf) * @intToFloat(f32, i), slice, font, point_size, itc(0xffffffff));
            if (i >= self.rows)
                break;
        }
    }
};

pub const Window = struct {
    const Self = @This();
    const DRect = DrawCommand.drawRect;

    //Private variables
    //Describe the top left corner of current element outside of all padding and margin
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,

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

    //Style vars
    slider_h: f32 = 25,
    label_fsize: f32 = 40,
    padding: f32 = 15,
    bg: Color = itc(0x5b595aff),

    //default_style: ElementStyle = .{ .margin = BRect.single(2), .padding = BRect.single(0) },

    //User provided constants
    y_init: f32,
    x_init: f32,
    width: f32,
    title: []const u8,
    font_size: f32,

    cmd_buf: *CmdBuf = undefined,
    str_buf_stream: std.io.FixedBufferStream([]u8) = undefined,

    mouse_state: graph.SDL.MouseState = undefined,

    style: Style,

    font: *graph.Font,

    //PRIVATES
    line_gap: f32,
    scale_factor: f32,

    last_active_drop_down: ?usize = null,

    pub fn drawText(self: *Self, x: f32, y: f32, text: []const u8, pt_size: f32, col: Color) void {
        DrawCommand.drawText(self.cmd_buf, &self.str_buf_stream, text, x, y, 0, pt_size, col);
    }

    pub const Style = struct {
        const Margin = struct {
            left: f32,
            right: f32,
            bottom: f32,
            top: f32,

            pub fn initEqual(val: f32) Margin {
                return Margin{ .left = val, .right = val, .bottom = val, .top = val };
            }
        };

        const BoxStyle = struct {
            margin: Margin,
            text_size_pt: f32,
            border_w_pt: f32,
            border_color: Color,
        };

        title_style: BoxStyle = BoxStyle{ .margin = Margin.initEqual(12), .text_size_pt = 12, .border_w_pt = 1, .border_color = itc(0x000000ff) },

        title_bg: Color = itc(0x2f52a2ff),
        title_fg: Color = itc(0xd5dcecff),
        title_sep: Color = itc(0x242933ff),
        item_border: Color = itc(0x1e1e1eff),
        item_bg: Color = itc(0x323232ff),
        item_fg: Color = itc(0xd5dcecff),
        bg: Color = itc(0x2d3548ff),
        toggled_on_bg: Color = itc(0xffb532ff),
        toggled_off_bg: Color = itc(0x2d2d2dff),
        toggled_on_fg: Color = itc(0x111111ff),
        toggled_off_fg: Color = itc(0xd5dcecff),

        title_size_pt: f32 = 8,
        title_margin_pt: Margin = Margin.initEqual(1),
        title_spacing_pt: f32 = 2,

        checkbox_size_pt: f32 = 12,
        checkbox_margin_pt: Margin = Margin.initEqual(1),
        checkbox_spacing_pt: f32 = 2,

        title_size: f32 = 12,
        border_w: f32 = 3,
    };

    pub fn init(font: *graph.Font, style: Style, window_x: f32, window_y: f32, width: f32, title: []const u8) Self {
        const sf = style.title_size / font.font_size;
        return Self{
            .scale_factor = sf,
            .line_gap = (font.ascent - font.descent) * sf,
            .style = style,
            .font = font,
            .x_init = window_x,
            .y_init = window_y,
            .width = width,
            .title = title,
            .font_size = style.title_size,
        };
    }

    pub fn requestItemIndex(self: *Self) usize {
        self.item_index += 1;
        return self.item_index - 1;
    }

    pub fn begin(self: *Self, cmd_buf: *CmdBuf, str_buf: []u8, new_pos: Vec2f, m_delta: Vec2f, m_down: bool, mouse_state: graph.SDL.MouseState) void {
        defer self.x += self.font.ptToPixel(2);
        self.mouse_state = mouse_state;
        self.item_index = 0;
        const this_item = self.requestItemIndex();
        self.y = self.y_init;
        self.x = self.x_init;
        self.w = self.width - self.padding * 2;

        self.cmd_buf = cmd_buf;
        self.str_buf_stream = std.io.FixedBufferStream([]u8){ .buffer = str_buf, .pos = 0 };

        self.m_delta = m_delta;
        self.m_old_x = new_pos.x - self.m_delta.x;
        self.m_old_y = new_pos.y - self.m_delta.y;
        self.m_down = m_down;
        if (!self.m_down)
            self.click_index = null;

        const scaled_vert_margin = self.font.ptToPixel(self.style.title_margin_pt.top + self.style.title_margin_pt.bottom);
        var title_rect: Rect = Rec(
            self.x,
            self.y,
            self.width,
            self.line_gap + scaled_vert_margin,
        );

        if (self.click_index) |cindex| {
            if (cindex == this_item) {
                self.y_init += self.m_delta.y;
                self.x_init += self.m_delta.x;
                self.x = self.x_init;
                self.y = self.y_init;
            }
        } else {
            if (self.m_down and rectContainsPoint(title_rect, self.m_old_x, self.m_old_y)) {
                self.click_index = this_item;
                self.y_init += self.m_delta.y;
                self.x_init += self.m_delta.x;
                self.x = self.x_init;
                self.y = self.y_init;
            }
        }

        //Update title position so it doesn't lag behind on window movement
        //title_rect = Rec(self.x, self.y, self.width - self.padding * 2, title_height);
        title_rect = Rec(self.x, self.y, self.width, self.line_gap + scaled_vert_margin);
        DRect(self.cmd_buf, .{ .x = self.x_init, .y = self.y_init, .w = self.width, .h = 0 }, -10, self.style.bg);

        DRect(
            self.cmd_buf,
            title_rect,
            -10,
            self.style.title_bg,
            //itc(0xc48214ff),
        );

        self.drawText(
            self.x + self.font.ptToPixel(self.style.title_margin_pt.left),
            self.y + self.font.ascent * self.scale_factor + self.font.ptToPixel(self.style.title_margin_pt.top),
            self.title,
            self.font_size,
            self.style.title_fg,
        );
        self.y += self.line_gap + scaled_vert_margin + self.font.ptToPixel(self.style.title_spacing_pt);
    }

    pub fn end(self: *Self) void {
        self.y += self.padding;
        self.cmd_buf.items[0].rect.rect.h = self.y - self.y_init;

        //DrawCommand.drawOutsetBorder(self.cmd_buf, Rec(self.x_init, self.y_init, self.width, self.y - self.y_init), 2, Border1);
    }

    pub fn listRadio(self: *Self, index: *usize, count: usize, labels: []std.ArrayList(u8)) void {
        self.y += self.default_style.getTop();
        defer self.y += self.default_style.getBottom();
        const adjx = self.x + self.default_style.getLeft();

        {
            var i: usize = 0;
            while (i < count) : (i += 1) {
                const rec = Rec(adjx, self.y, self.w / 2, self.slider_h);
                DrawCommand.drawRect(self.cmd_buf, rec, 0, if (index.* == i) WHITE else BLACK);
                self.drawText(adjx, self.y + self.font_size, labels[i].items, self.font_size, BLACK);
                if (self.m_down and rectContainsPoint(rec, self.m_old_x, self.m_old_y)) {
                    index.* = i;
                }
                self.y += self.slider_h * 1.2;
            }
        }
    }

    pub fn floatSlide(self: *Self, lab: ?[]const u8, item: *f32, min: f32, max: f32) void {
        const this_item = self.requestItemIndex();

        self.y += 0;
        defer self.y += 0;

        const adjx = self.x;
        const h = self.line_gap;
        defer self.y += h;
        const val = item.*;

        const perc = ((val - min) / (max - min));
        const handle_pos = perc * (self.w - h);

        var select = false;
        if (self.click_index) |cindex| {
            if (cindex == this_item) {
                if (self.m_old_x >= adjx + handle_pos and self.m_old_x <= adjx + handle_pos + self.slider_h) {
                    item.* = (self.m_delta.x + handle_pos) / (self.w - h) * (max - min) + min;
                    item.* = restrictFloat(item.*, min, max);
                }
                select = true;
            }
        } else {
            if (self.m_down and rectContainsPoint(Rec(adjx + handle_pos, self.y, h, h), self.m_old_x, self.m_old_y)) {
                self.click_index = this_item;
                self.focused_textbox = null;

                item.* = (self.m_delta.x + handle_pos) / (self.w - h) * (max - min) + min;
                item.* = restrictFloat(item.*, min, max);
                select = true;
            }
        }

        drawSlider(adjx, self.y, self.w, h, handle_pos, itc(0x1a1a1aff), if (select) GRAY else WHITE, self.cmd_buf);

        if (lab) |l| {
            DrawCommand.drawTextFmt(
                self.cmd_buf,
                &self.str_buf_stream,
                adjx,
                self.y + h - (h * 0.3),
                self.font_size,
                "{s}: {d}",
                .{ l, @intToFloat(f32, @floatToInt(i32, val * 1000)) / 1000 },
            );
        } else {
            DrawCommand.drawTextFmt(
                self.cmd_buf,
                &self.str_buf_stream,
                adjx,
                self.y + h,
                h,
                "{d}",
                .{@floatToInt(i32, val)},
            );
        }
    }

    pub fn dropDownEnum(self: *Self, comptime enum_type: type, enum_value: *enum_type) void {
        const id = self.requestItemIndex();
        _ = enum_value;

        const info = @typeInfo(enum_type);
        switch (info) {
            .Enum => {
                self.drawText(self.x, self.y + self.font.ascent * self.scale_factor, "Drop down", self.font_size, BLACK);
                if (rectContainsPoint(Rec(self.x, self.y, self.width, self.line_gap), self.m_old_x, self.m_old_y) and self.mouse_state.left_down) {
                    if (self.last_active_drop_down == null) {
                        self.last_active_drop_down = id;
                        //Display the drop down
                    }
                }

                if (self.last_active_drop_down == id) {
                    inline for (info.Enum.fields) |field, i| {
                        DrawCommand.drawRect(self.cmd_buf, Rec(self.x, self.y + @intToFloat(f32, i + 1) * self.line_gap, self.width, self.line_gap), 0, WHITE);
                        self.drawText(self.x, self.y + @intToFloat(f32, i + 1) * self.line_gap + self.font.ascent * self.scale_factor, field.name, self.font_size, BLACK);
                    }
                }
            },
            else => @compileError("Only enums supported"),
        }
        self.y += self.line_gap;
    }

    pub fn checkBox(self: *Self, val: *bool, lab: ?[]const u8) void {
        const w = if (lab != null) self.font.measureText(lab.?) * self.scale_factor + self.line_gap else self.line_gap;

        const r = Rec(self.x, self.y, w, self.line_gap + self.style.border_w * 2);

        if (rectContainsPoint(r, self.m_old_x, self.m_old_y)) {
            if (self.mouse_state.left_down) {
                val.* = !val.*;
            }
        }

        DrawCommand.drawRect(self.cmd_buf, r, 0, self.style.item_border);
        DrawCommand.drawRect(
            self.cmd_buf,
            .{
                .x = r.x + self.style.border_w,
                .y = r.y + self.style.border_w,
                .w = r.w - self.style.border_w * 2,
                .h = r.h - self.style.border_w * 2,
            },
            0,
            if (val.*) self.style.toggled_on_bg else self.style.toggled_off_bg,
        );

        if (lab) |l|
            self.drawText(
                self.x + self.line_gap / 2,
                self.y + self.style.border_w + self.font.ascent * self.scale_factor,
                l,
                self.font_size,
                if (val.*) self.style.toggled_on_fg else self.style.toggled_off_fg,
            );

        self.y += self.line_gap + self.style.border_w * 2 + self.font.ptToPixel(self.style.checkbox_spacing_pt);
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
        const adjx = self.x;
        //TODO ensure text doesn't overlap
        //const w = self.width - self.default_style.getWidth() - self.padding * 2;
        //self.y += self.default_style.getTop();
        //defer self.y += self.default_style.getBottom();

        DrawCommand.drawText(self.cmd_buf, &self.str_buf_stream, str, adjx, self.y + self.label_fsize, 0, self.label_fsize, BLACK);
        self.y += self.label_fsize;
    }

    pub fn textBox(self: *Self, str: *std.ArrayList(u8), pos: *usize) void {
        const init_y = self.y;
        const adjx = self.x;
        const w = self.width - self.padding * 2;
        //self.y += ;
        //defer self.y += self.default_style.getBottom();

        const this_item = self.requestItemIndex();
        const r = Rec(adjx, self.y, w, self.label_fsize);

        if (self.m_down and rectContainsPoint(r, self.m_old_x, self.m_old_y))
            self.focused_textbox = this_item;

        const focused = self.focused_textbox == this_item;
        _ = pos;
        //if (focused) {
        //    var key = ray.GetCharPressed();
        //    while (key != 0) : (key = ray.GetCharPressed()) {
        //        //TODO unicode support, the & 0xff converts any unicode into garbage
        //        str.insert(pos.*, @intCast(u8, key & 0xff)) catch return;
        //        pos.* += 1;
        //    }

        //    //TODO Raylib fucks the repeat
        //    if (ray.IsKeyPressed(ray.KEY_BACKSPACE)) {
        //        if (str.items.len > 0 and pos.* <= str.items.len and pos.* != 0) {
        //            _ = str.orderedRemove(pos.* - 1);
        //            pos.* -= 1;
        //        }
        //    }
        //}

        DRect(self.cmd_buf, r, if (focused) GRAY else WHITE);
        self.drawText(adjx, self.y + self.font_size, str.items, self.font_size, BLACK);
        //TODO how to measure text without font info?
        //TODO draw cursor
        //DRect(self.cmd_buf, Rec(self.x + @intToFloat(f32, pos) * self.label_fsize / 2, self.y, 2, self.label_fsize), ray.RED);
        self.y += self.label_fsize;
        DrawCommand.drawOutsetBorder(self.cmd_buf, Rec(
            self.x + self.default_style.margin.left,
            init_y + self.default_style.margin.top,
            self.width - self.default_style.margin.left - self.default_style.margin.right - self.padding * 2,
            self.y - init_y + self.default_style.padding.bottom,
        ), self.default_style.border_width, Border2);
    }
};

pub fn drawStruct(ctx: *Window, to_mod: anytype) void {
    const T = @TypeOf(to_mod);
    const pinfo = @typeInfo(T);
    const child = pinfo.Pointer.child;

    inline for (@typeInfo(child).Struct.fields) |Field| {
        switch (@typeInfo(Field.field_type)) {
            .Float => {
                ctx.floatSlide(null, &@field(to_mod, Field.name), 0, 1000);
            },
            .Int => {
                const ptr = &@field(to_mod, Field.name);
                var float: f32 = @intToFloat(f32, ptr.*);
                ctx.floatSlide(null, &float, 0, 255);
                ptr.* = @floatToInt(u8, float);
            },
            else => {},
        }
    }
}

pub fn genBorderRects(r: Rect, w: f32) [6]Rect {
    return .{
        Rec(r.x, r.y, r.w, w),
        Rec(r.x, r.y, w, r.h),
        Rec(r.x + r.w - w, r.y + w, w, r.h - w),
        Rec(r.x + w, r.y + r.h - w, r.w - w, w),
        Rec(r.x + w, r.y + w, r.w - w * 2, w),
        Rec(r.x + w, r.y + w * 2, w, r.h - w * 2),
    };
}
