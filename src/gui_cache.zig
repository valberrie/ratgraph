const std = @import("std");

/// Options for StackCache
pub const StackCacheOpts = struct {
    /// Adds printing of logs using log_function in calls to begin() push() and pop()
    log_debug: bool = false,
    log_function: fn (comptime []const u8, anytype) void = std.debug.print,
};

/// A stack that determines if a stack frame's data or parent's data has changed since the last cycle.
/// To be used in a loop, starting with begin(), all push's must be popped before the next call to begin().
///
/// A frame/node is only cached when its data matches the previous cycle's data and its parent is cached.
///
/// Useful when you have a call stack you want to track. For instance calls to an instant mode gui's layout functions. This stack can be queried from frame to frame to determine if the layouts have changed and set a flag notifying child gui widget calls they need to re-emit draw commands.
///
/// Initialize with `init` and `deinit`
///
/// If NodeData needs to allocate memory, provide a pub fn deinit(*@This()) in NodeData, This is called when a node is destroyed
/// include a flag for tracking if it is initilized. Then after pushing call getCacheDataPtr and initilize.
///
pub fn StackCache(comptime NodeData: type, comptime eql_fn: fn (NodeData, NodeData) bool, comptime opts: StackCacheOpts) type {
    return struct {
        const Self = @This();
        const eqlFn = eql_fn;

        pub const Error = error{
            invalidState,
        };

        pub const Node = struct {
            next: ?*Node = null,
            depth: u32,
            data: NodeData,
        };

        alloc: std.mem.Allocator,
        alloc_count: u32 = 0,
        dealloc_count: u32 = 0,

        first: ?*Node = null,

        /// Flag indicating the last stack modification was a pop that reattached dangle.
        dangle_pushed: bool = false,
        /// Sub stack that is saved when encountering an uncached node. Reattached once stack returns to dangle depth.
        dangle: ?*Node = null,
        caret: ?*Node = null,
        depth: u32 = 0,
        cached: bool = false,

        pub fn init(alloc: std.mem.Allocator) !Self {
            return .{ .alloc = alloc };
        }

        pub fn deinit(self: *Self) void {
            self.dealloc();
        }

        pub fn clear(self: *Self) !void {
            try self.begin(); // to ensure clear is only called when stack is empty
            self.dealloc();
            self.first = null;
            if (self.first != null) return error.fucked;
        }

        pub fn begin(self: *Self) (error{ leftDangling, unmatchedPush } || Error)!void {
            logOut("\nBegin StackCache\n", .{});

            if (self.dangle != null) return error.leftDangling;
            if (self.depth != 0) return error.unmatchedPush;
            if (self.dangle_pushed) { //If our last push or pop was a pop reattaching dangle, the reattached dangle needs to be removed
                try self.revertDangleAttach();
            }
            self.caret = null;
        }

        pub fn dealloc(self: *Self) void {
            self.dealloc_till(self.first, null);
        }

        pub fn getCacheState(self: *const Self) bool {
            return self.cached;
        }

        //TODO please write this down and see if behavior is correct
        //
        //Returns the cache of the current layout
        //
        //Caret always points to last pushed node
        //depth is always what the next nodes depth will be
        //Possible states:
        //Node pushed:
        //  return caret because caret.depth == depth - 1
        //Node popped
        //  caret.depth > depth - 1
        //  traverse from first and find the last node with depth == depth - 1 before caret
        pub fn getCacheDataPtr(self: *const Self) ?*NodeData {
            if (self.depth == 0) return null;
            const d = self.depth - 1;
            //If caret has depth d return caret. else we just popped so traverse from first until the last node with same d
            if (self.caret) |caret| {
                if (caret.depth == d) return &caret.data;
                {
                    var it = self.first;
                    var last_parent: ?*Node = null;
                    while (it != null) : (it = it.?.next) {
                        if (it.? == caret) break;
                        if (it.?.depth == d)
                            last_parent = it;
                    }
                    if (last_parent) |lp| {
                        return &lp.data;
                    }
                }
            }

            //if (self.caret != null)
            //return &self.caret.?.data;
            return null;
        }

        //Caret always points to previous pushed node.
        //No branch should modify self.depth;
        pub fn push(self: *Self, new_data: NodeData) (Error || std.mem.Allocator.Error)!void {
            printNSpaces(self.depth, opts.log_function);
            logOut("{any} ", .{new_data});
            defer logOut("\n", .{});
            defer self.depth += 1;
            self.dangle_pushed = false;
            self.cached = false;
            if (self.caret) |caret| {
                if (caret.next) |next| { //List continues after this node
                    if (eqlFn(next.data, new_data) and next.depth == self.depth) { //Cache match
                        logOut("cached ", .{});
                        self.cached = true;
                        self.caret = next;
                    } else { //Cache mismatch
                        logOut("uncached ", .{});
                        if (self.dangle != null) return error.invalidState;

                        if (next.depth < self.depth) { //If the next node isn't at the same depth it is a sibling and we must allocate new nodes
                            self.dangle = next;
                            const new_node = try self.create_node();
                            new_node.* = .{ .data = new_data, .depth = self.depth };
                            caret.next = new_node;
                            self.caret = new_node;
                            //Set dangle to next
                            //Allocate a new node
                        } else {
                            //Regular

                            const cont_cache = findNextNonChildNode(next);
                            self.dangle = cont_cache;
                            self.dealloc_till(next.next, cont_cache);
                            self.destroy_node(next);
                            const new_node = try self.create_node();
                            new_node.* = .{ .data = new_data, .depth = self.depth };
                            //next.next = null;
                            self.caret.?.next = new_node;
                            self.caret = new_node;
                        }
                    }
                } else { //Appending to end of list
                    logOut("append ", .{});
                    const new_node = try self.create_node();
                    new_node.* = .{ .data = new_data, .depth = self.depth };
                    caret.next = new_node;
                    self.caret = new_node;
                }
            } else { //First node
                if (self.first) |first| { //List exists
                    if (eqlFn(first.data, new_data) and first.depth == self.depth) {
                        logOut("first cached ", .{});
                        self.cached = true;
                        self.caret = first;
                    } else { //Cache mismatch
                        logOut("first uncached ", .{});
                        if (self.dangle != null) return error.invalidState;
                        const cont_cache = findNextNonChildNode(first);
                        self.dangle = cont_cache;
                        self.dealloc_till(first.next, cont_cache);

                        self.destroy_node(first);
                        const new_node = try self.create_node();
                        new_node.* = .{ .data = new_data, .depth = self.depth };

                        self.first = new_node;
                        self.caret = self.first;

                        //first.next = null;
                        // first.data = new_data;
                        // first.depth = self.depth;
                        // self.caret = first;
                    }
                } else { //List empty
                    logOut("fresh list ", .{});
                    const new_node = try self.create_node();
                    new_node.* = .{ .data = new_data, .depth = self.depth };
                    self.first = new_node;
                    self.caret = self.first;
                }
            }
        }

        pub fn pop(self: *Self) Error!void {
            defer self.depth -= 1;

            printNSpaces(self.depth, opts.log_function);
            logOut("pop ", .{});
            defer logOut("\n", .{});

            if (self.caret.?.next) |next| {
                if (next.depth != self.depth) { //the next node is only valid if it has the next depth
                    logOut("dropping", .{});
                    const cont_cache = findNextNonChildNode(self.caret.?);
                    self.dealloc_till(next, cont_cache);
                    if (self.dangle != null) unreachable;
                    self.dangle = cont_cache;
                    self.caret.?.next = null;
                }
            }

            if (self.dangle) |d| {
                //Is dangle at the same level as this popped node or a level below. reattach
                //if (self.depth == d.depth or (self.depth - 1 == d.depth)) {
                if (self.depth - 1 == d.depth) {
                    if (self.caret.?.next != null) return error.invalidState;
                    self.cached = true;
                    self.caret.?.next = d;
                    self.dangle = null;
                    self.dangle_pushed = true;
                }
            } else {
                if (self.dangle_pushed) { //If our last push or pop was a pop reattaching dangle, the reattached dangle needs to be removed
                    try self.revertDangleAttach();
                    self.cached = false;
                }
            }
        }

        fn create_node(self: *Self) !*Node {
            self.alloc_count += 1;
            return try self.alloc.create(Node);
        }

        fn destroy_node(self: *Self, node: *Node) void {
            self.dealloc_count += 1;
            if (comptime std.meta.hasFn(NodeData, "deinit")) {
                @field(NodeData, "deinit")(&node.data);
            }
            self.alloc.destroy(node);
        }

        fn revertDangleAttach(self: *Self) Error!void {
            if (self.dangle != null) return error.invalidState;
            self.dangle_pushed = false;
            if (self.caret == null or self.caret.?.next == null) return error.invalidState;
            self.dealloc_till(self.caret.?.next, null);
            self.caret.?.next = null;
        }

        //Dealloc all nodes from start_node (inclusive) till end_node (exclusive)
        fn dealloc_till(self: *Self, start_node: ?*Node, end_node: ?*Node) void {
            var it = start_node;
            while (it != end_node) {
                const next = it.?.next;
                self.destroy_node(it.?);
                it = next;
            }
        }

        fn findNextNonChildNode(node: *Node) ?*Node {
            const depth = node.depth;
            var it_o: ?*Node = node.next;
            while (it_o != null) : (it_o = it_o.?.next) {
                const it = it_o.?;
                if (it.depth <= depth) {
                    //if (it.depth == depth or (depth > 0 and depth - 1 == it.depth)) {
                    return it;
                }
            }
            return null;
        }

        //Requires StackCache be created with a u8 as DataType.
        pub fn testingCompareLists(first: ?*Node, expected: []const struct { depth: u32, data: u8 }) error{
            expectedDifferent,
            listLongerThanExpected,
            listShorterThanExpected,
        }!void {
            var index: u32 = 0;
            var it_o = first;
            while (it_o != null) : (it_o = it_o.?.next) {
                const it = it_o.?;
                if (index >= expected.len) return error.listLongerThanExpected;
                const ex = expected[index];
                if (ex.depth != it.depth or ex.data != it.data)
                    return error.expectedDifferent;

                index += 1;
            }

            if (index != expected.len) return error.listShorterThanExpected;
        }

        fn logOut(comptime fmt: []const u8, args: anytype) void {
            if (opts.log_debug)
                opts.log_function(fmt, args);
        }

        fn printNSpaces(n: u32, print: fn (comptime []const u8, anytype) void) void {
            if (!opts.log_debug and print == opts.log_function)
                return;

            var i: u32 = 0;
            while (i < n) : (i += 1)
                print("  ", .{});
        }

        pub fn debugPrint(self: *Self) void {
            var it = self.first;
            while (it != null) : (it = it.?.next) {
                printNSpaces(it.?.depth, std.debug.print);
                std.debug.print("{c}\n", .{it.?.data});
            }
        }
    };
}

fn testLcEqlFn(a: u8, b: u8) bool {
    return a == b;
}
const TestLc = StackCache(u8, testLcEqlFn, .{
    .log_debug = false,
});
test "StackCache init and same cache" {
    const alloc = std.testing.allocator;
    var lc: TestLc = .{ .alloc = alloc };
    defer lc.dealloc();

    // zig fmt: off
    try lc.begin();
    try lc.push('a');
        try lc.push('b');
        try lc.pop();
    try lc.pop();

    try TestLc.testingCompareLists(lc.first, &.{
        .{ .depth = 0, .data = 'a' },
        .{ .depth = 1, .data = 'b' },
    });

    try lc.begin();
    try lc.push('a');
        try lc.push('b');
        try lc.pop();
    try lc.pop();

    try TestLc.testingCompareLists(lc.first, &.{
        .{ .depth = 0, .data = 'a' },
        .{ .depth = 1, .data = 'b' },
    });
}

test "StackCache basic cache overwrite no dangle" {
    const alloc = std.testing.allocator;
    var lc: TestLc = .{ .alloc = alloc };
    defer lc.dealloc();

    // zig fmt: off
    try lc.begin();
    try lc.push('a');
        try lc.push('b');
        try lc.pop();
    try lc.pop();

    try TestLc.testingCompareLists(lc.first, &.{
        .{ .depth = 0, .data = 'a' },
        .{ .depth = 1, .data = 'b' },
    });

    try lc.begin();
    try lc.push('a');
        try lc.push('d');
        //if(layout.dirty) output Draw commands
        try lc.pop();
    try lc.pop();

    try TestLc.testingCompareLists(lc.first, &.{
        .{ .depth = 0, .data = 'a' },
        .{ .depth = 1, .data = 'd' },
    });
}

test "StackCache basic cache overwrite append with same depth dangle reattach" {
    const alloc = std.testing.allocator;
    var lc: TestLc = .{ .alloc = alloc };
    defer lc.dealloc();

    // zig fmt: off
    try lc.begin();
    try lc.push('a');
        try lc.push('b');
        try lc.pop();
        try lc.push('j');//This is dangle 
            try lc.push('h');
            try lc.pop();
        try lc.pop();

    try lc.pop();

    try TestLc.testingCompareLists(lc.first, &.{
        .{ .depth = 0, .data = 'a' },
        .{ .depth = 1, .data = 'b' },
        .{ .depth = 1, .data = 'j' },
        .{ .depth = 2, .data = 'h' },
    });

    try lc.begin();
    try lc.push('a');
        try lc.push('d'); //Diff from init
            try lc.push('k');
                try lc.push('d');
                try lc.pop();
            try lc.pop();
        try lc.pop();
        try lc.push('j');//Same dangle as before, should reattch
            try lc.push('h');
            try lc.pop();
        try lc.pop();
    try lc.pop();

    try TestLc.testingCompareLists(lc.first, &.{
        .{ .depth = 0, .data = 'a' },
        .{ .depth = 1, .data = 'd' },
        .{ .depth = 2, .data = 'k' },
        .{ .depth = 3, .data = 'd' },

        .{ .depth = 1, .data = 'j' },
        .{ .depth = 2, .data = 'h' },

    });
}

test "StackCache basic cache overwrite append with parent depth dangle reattach" {
    const alloc = std.testing.allocator;
    var lc: TestLc = .{ .alloc = alloc };
    defer lc.dealloc();

    // zig fmt: off
    try lc.begin();
    try lc.push('a');
        try lc.push('b');
        try lc.pop();
    try lc.pop();
    try lc.push('j');//This is dangle 
        try lc.push('h');
        try lc.pop();
    try lc.pop();


    try TestLc.testingCompareLists(lc.first, &.{
        .{ .depth = 0, .data = 'a' },
        .{ .depth = 1, .data = 'b' },
        .{ .depth = 0, .data = 'j' },
        .{ .depth = 1, .data = 'h' },
    });

    try lc.begin();
    try lc.push('a');
        try lc.push('d'); //Diff from init
            try lc.push('k');
                try lc.push('d');
                try lc.pop();
            try lc.pop();
        try lc.pop();
    try lc.pop();
    try lc.push('j');//Same dangle as before, should reattch
        try lc.push('h');
        try lc.pop();
    try lc.pop();

    try TestLc.testingCompareLists(lc.first, &.{
        .{ .depth = 0, .data = 'a' },
        .{ .depth = 1, .data = 'd' },
        .{ .depth = 2, .data = 'k' },
        .{ .depth = 3, .data = 'd' },

        .{ .depth = 0, .data = 'j' },
        .{ .depth = 1, .data = 'h' },

    });
}


//test "StackCache basic cache destroy child cache" {
//    const alloc = std.testing.allocator;
//    var lc: TestLc = .{ .alloc = alloc };
//    defer lc.dealloc();
//
//    // zig fmt: off
//    try lc.begin();
//    try lc.push('a');
//        try lc.push('b');
//        try lc.pop();
//    try lc.pop();
//
//    try TestLc.testingCompareLists(lc.first, &.{
//        .{ .depth = 0, .data = 'a' },
//        .{ .depth = 1, .data = 'b' },
//    });
//
//    try lc.begin();
//    try lc.push('a');
//    try lc.pop(); 
//
//    try TestLc.testingCompareLists(lc.first, &.{
//        .{ .depth = 0, .data = 'a' },
//    });
//}

test "StackCache basic cache overwrite append " {
    const alloc = std.testing.allocator;
    var lc: TestLc = .{ .alloc = alloc };
    defer lc.dealloc();

    // zig fmt: off
    try lc.begin();
    try lc.push('a');
        try lc.push('b');
        try lc.pop();
    try lc.pop();

    try TestLc.testingCompareLists(lc.first, &.{
        .{ .depth = 0, .data = 'a' },
        .{ .depth = 1, .data = 'b' },
    });

    try lc.begin();
    try lc.push('a');
        try lc.push('d'); //Diff from init
            try lc.push('g');
                try lc.push('h');
                try lc.pop();
            try lc.pop();
        try lc.pop();
    try lc.pop();

    try TestLc.testingCompareLists(lc.first, &.{
        .{ .depth = 0, .data = 'a' },
        .{ .depth = 1, .data = 'd' },
        .{ .depth = 2, .data = 'g' },
        .{ .depth = 3, .data = 'h' },
    });
}

test "StackCache usage test"{
    const alloc = std.testing.allocator;
    var lc: TestLc = .{ .alloc = alloc };
    defer lc.dealloc();

    try lc.begin();
    try lc.push('a');
        try lc.push('b');
        try lc.pop();
        try lc.push('c');
        try lc.pop();
        try lc.push('b');
        try lc.pop();
        try lc.push('g');
            try lc.push('b');
                try lc.push('g');
                try lc.pop();
            try lc.pop();
        try lc.pop();
        try lc.push('g');
            try lc.push('k');
                try lc.push('k');
                try lc.pop();
            try lc.pop();
        try lc.pop();
    try lc.pop();

    try TestLc.testingCompareLists(lc.first, &.{
        .{ .depth = 0, .data = 'a' },
        .{ .depth = 1, .data = 'b' },
        .{ .depth = 1, .data = 'c' },
        .{ .depth = 1, .data = 'b' },
        .{ .depth = 1, .data = 'g' },
        .{ .depth = 2, .data = 'b' },
        .{ .depth = 3, .data = 'g' },
        .{ .depth = 1, .data = 'g' },
        .{ .depth = 2, .data = 'k' },
        .{ .depth = 3, .data = 'k' },
    });

    try lc.begin();
    try lc.push('a');
        try lc.push('g');
        try lc.pop();
    try lc.pop();

    try TestLc.testingCompareLists(lc.first, &.{
        .{ .depth = 0, .data = 'a' },
        .{ .depth = 1, .data = 'g' },
    });

    try lc.begin();
    try lc.push('a');
        try lc.push('b');
        try lc.pop();
    try lc.pop();

    try TestLc.testingCompareLists(lc.first, &.{
        .{ .depth = 0, .data = 'a' },
        .{ .depth = 1, .data = 'b' },
    });

}
