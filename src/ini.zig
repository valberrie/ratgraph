const std = @import("std");

const indexOfSentinel = std.mem.indexOfSentinel;
const indexOfScalar = std.mem.indexOfScalar;
const trim = std.mem.trim;

const EXAMPLE =
    \\; last modified 1 April 2001 by John Doe
    \\[owner] 
    \\name = John Doe
    \\organization = Acme Widgets Inc.
    \\
    \\[database] ; This is what a database is 
    \\; use IP address in case network name resolution is not working
    \\server = 192.0.2.62     
    \\port = 143
    \\file = "payroll.dat"
    \\tits = 
;

const whitespace = " \t\r\x00";

pub const EntryType = enum {
    section,
    comment,
    kv,
    empty,
};

pub const KeyValue = struct {
    key: []const u8 = "",
    val: []const u8 = "",

    e_type: EntryType = .empty,
};

pub const Error = error{
    InvalidIdentifier,
    TrailingGarbage,
    NoMatching,
    NoEquals,
    NotImpelmented,
};

//Numbers not allowed to begin
fn isValidStartingChar(ch: u8) bool {
    return ((ch > 64 and ch < 91) or (ch > 96 and ch < 123) or ch == '_');
}

pub fn isValidIdentifier(name: []const u8) bool {
    if (name.len < 1 or !isValidStartingChar(name[0]))
        return false;

    var valid = true;
    for (name[1..]) |ch|
        valid = valid and ((ch > 47 and ch < 58) or (ch > 64 and ch < 91) or (ch > 96 and ch < 123) or ch == '_');

    return valid;
}

//pub fn assertStartingChar(ch:u8)!void{
//    if(!isValidStartingChar())
//}

fn assertIdentifier(identifier: []const u8) !void {
    if (!isValidIdentifier(identifier))
        return Error.InvalidIdentifier;
}

fn assertNoTrailingGarbage(trail: []const u8) !void {
    for (trail) |ch| {
        if (indexOfScalar(u8, whitespace, ch) == null) {
            if (ch == ';' or ch == '#')
                return;
            return Error.TrailingGarbage;
        }
    }
}

pub fn parseLine(str: []const u8) Error!KeyValue {
    if (str.len < 1)
        return KeyValue{}; //Empty

    const first = str[0];
    switch (first) {
        '[' => {
            if (indexOfScalar(u8, str, ']')) |end| {
                try assertIdentifier(trim(u8, str[1..end], whitespace));
                try assertNoTrailingGarbage(str[end + 1 ..]);

                return KeyValue{ .e_type = .section, .key = trim(u8, str[1..end], whitespace), .val = "" };
            } else {
                return Error.NoMatching;
            }
        },
        ';', '#' => {
            return KeyValue{ .e_type = .comment, .key = trim(u8, str[1..], whitespace), .val = "" };
        },
        else => {
            const comment = trim(u8, str[0..], whitespace);
            //ugly hack to deal to allow comments to be idented
            if (comment.len > 0 and (comment[0] == ';' or comment[0] == '#')) {
                return KeyValue{ .e_type = .comment, .key = comment, .val = "" };
            }

            if (indexOfScalar(u8, str, '=')) |eql_pos| {
                const key = trim(u8, str[0..eql_pos], whitespace);
                try assertIdentifier(key);

                const val = trim(u8, str[eql_pos + 1 ..], whitespace);

                return KeyValue{ .e_type = .kv, .key = key, .val = val };
            } else {
                return Error.NoEquals;
            }
        },
    }

    return Error.NotImplemented;
    //return KeyValue{};
}

pub const Parser = struct {
    const Self = @This();
    const PrintFnType = *const fn ([]const u8, anytype) void;

    it: std.mem.SplitIterator(u8),
    line: usize = 0,
    item: []const u8 = "",

    did_error: bool = false,

    pub fn init(file_str: []const u8) Self {
        return .{
            .it = std.mem.split(u8, file_str, "\n"),
            .line = 0,
        };
    }

    pub fn next(self: *Self, comptime printfn: PrintFnType) ?KeyValue {
        while (self.it.next()) |item| {
            if (parseLine(item)) |kv| {
                if (kv.e_type == .empty)
                    continue;
                return kv;
            } else |err| {
                self.did_error = true;
                self.errMsg(err, printfn);
            }
        }
        return null;
    }

    pub fn nextWithErr(self: *Self) ?Error!KeyValue {
        while (self.it.next()) |item| {
            return parseLine(item);
        }
        return null;
    }

    pub fn errMsg(self: *Self, err: Error, comptime printfn: PrintFnType) void {
        const INI = "Ini Error: \n\t";
        const fmt = .{ INI, self.line, self.item };
        switch (err) {
            Error.InvalidIdentifier => printfn.*("{s}Invalid identifier on line {d}: \"{s}\"\n", fmt),
            Error.TrailingGarbage => printfn.*("{s}Trailing chars on line {d}: \"{s}\"\n", fmt),
            Error.NoMatching => printfn.*("{s}Missing closing character on line {d}: \"{s}\"\n", fmt),
            Error.NoEquals => printfn.*("{s}No \"=\" found on line {d}: \"{s}\"\n", fmt),
            Error.NotImpelmented => printfn.*("{s}This means a bug occured while parsing line {d}: \"{s}\"\n", fmt),
        }
    }
};

test "Basic Parser usage" {
    {
        var parser = Parser.init(EXAMPLE);
        while (parser.next(&std.debug.print)) |kv| {
            switch (kv.e_type) {
                .comment => {},
                .section => {},
                .kv => {},
                .empty => {},
            }
        }

        if (parser.did_error) {
            //We errored and printed messages for user, we should probably throw away all data and report failure to user.
        }
    }

    var err_parser = Parser.init(EXAMPLE);
    while (err_parser.nextWithErr()) |kver| {
        if (kver) |kv| {
            switch (kv.e_type) {
                //SAME handling as above
                else => {},
            }
        } else |err| {
            switch (err) {
                else => {},
            }
        }
    }
}

test "Basic ini test" {
    const INI = "Ini Error:\n\t";

    var it = std.mem.split(u8, EXAMPLE, "\n");
    var line: usize = 0;
    while (it.next()) |item| {
        const v = parseLine(item) catch |err| blk: {
            switch (err) {
                Error.InvalidIdentifier => std.debug.print("{s}Invalid identifier on line {d}: \"{s}\"\n", .{ INI, line, item }),
                Error.TrailingGarbage => std.debug.print("{s}Trailing chars on line {d}: \"{s}\"\n", .{ INI, line, item }),
                Error.NoMatching => std.debug.print("{s}Missing closing character on line {d}: \"{s}\"\n", .{ INI, line, item }),
                Error.NoEquals => std.debug.print("{s}No \"=\" found on line {d}: \"{s}\"\n", .{ INI, line, item }),
                Error.NotImpelmented => std.debug.print("{s}This means a bug occured while parsing line {d}: \"{s}\"\n", .{ INI, line, item }),
            }
            break :blk KeyValue{};
        };
        _ = v;
        //std.debug.print("\t{any}, \"{s}\" VAL: \"{s}\"\n", .{ v.e_type, v.key, v.val });
        line += 1;
    }
}

test "Basic ini test" {
    const exErr = std.testing.expectError;
    _ = parseLine("[mysec]") catch unreachable;

    const lines = struct { err: Error, line: []const u8 };

    const invalid_sections = [_]lines{
        .{ .err = Error.TrailingGarbage, .line = "[ mysection] 8 " },
        .{ .err = Error.TrailingGarbage, .line = "[ mysection]]" },
        .{ .err = Error.NoMatching, .line = "[ mi" },
        .{ .err = Error.InvalidIdentifier, .line = "[ my section ]" },
        .{ .err = Error.NoEquals, .line = " [ my section ]" },
        .{ .err = Error.InvalidIdentifier, .line = "[ mysection ;comment ]" },
        .{ .err = Error.InvalidIdentifier, .line = " = " },
        .{ .err = Error.InvalidIdentifier, .line = "= " },
        .{ .err = Error.InvalidIdentifier, .line = "= myname" },
        .{ .err = Error.InvalidIdentifier, .line = "my-name = whatever" },
        .{ .err = Error.InvalidIdentifier, .line = "my name = whatever" },
        .{ .err = Error.InvalidIdentifier, .line = "my& name = whatever" },
        .{ .err = Error.InvalidIdentifier, .line = "@my$ name = whatever" },
        .{ .err = Error.NoEquals, .line = "myname  c" },
    };

    for (invalid_sections) |sec| {
        const s = parseLine(sec.line);
        try exErr(sec.err, s);
    }

    const valid_lines = [_][]const u8{
        "[ mysection         ]",
        "[mysection]",
        "[    mysection_with_long_name_and_white_space        ]  ; comment",
        "my_identifier_ =",
        "my_identifier = whatever",
        "ThisISMYident________383838 = 28",
        ";comment",
        "             ;comment",
        ";",
        "; ",
        " ; ",
    };
    for (valid_lines) |l| {
        _ = try parseLine(l);
    }
}
