// Heavily based on the fuzzy example from libvaxis:
// https://github.com/rockorager/libvaxis/blob/5a8112b78be7f8c52d7404a28d997f0638d1c665/examples/fuzzy.zig

const std = @import("std");
const kf = @import("known-folders");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const zf = @import("zf");

pub const known_folders_config: kf.KnownFolderConfig = .{
    .xdg_on_mac = true,
};

const Candidate = struct {
    str: []const u8,
    rank: f64,
};

const HighlightSlicer = struct {
    matches: []const usize,
    highlight: bool,
    str: []const u8,
    index: usize = 0,

    const Slice = struct {
        str: []const u8,
        highlight: bool,
    };

    pub fn init(str: []const u8, matches: []const usize) HighlightSlicer {
        const highlight = std.mem.indexOfScalar(usize, matches, 0) != null;
        return .{ .str = str, .matches = matches, .highlight = highlight };
    }

    pub fn next(slicer: *HighlightSlicer) ?Slice {
        if (slicer.index >= slicer.str.len) return null;

        const start_state = slicer.highlight;
        var index: usize = slicer.index;
        while (index < slicer.str.len) : (index += 1) {
            const highlight = std.mem.indexOfScalar(usize, slicer.matches, index) != null;
            if (start_state != highlight) break;
        }

        const slice = Slice{ .str = slicer.str[slicer.index..index], .highlight = slicer.highlight };
        slicer.highlight = !slicer.highlight;
        slicer.index = index;
        return slice;
    }
};

const ProjectPicker = struct {
    /// The full list of available items.
    list: std.ArrayList(vxfw.Text),
    /// The filtered list of available items.
    filtered: std.ArrayList(vxfw.RichText),
    /// The ListView used to render the filtered list of items.
    list_view: vxfw.ListView,
    /// The input box to type in a search pattern.
    text_field: vxfw.TextField,

    /// Used to allocate RichText widgets in the ListView.
    arena: std.heap.ArenaAllocator,

    /// Stores the selected path.
    result: std.ArrayList(u8),

    pub fn widget(self: *ProjectPicker) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = ProjectPicker.typeErasedEventHandler,
            .drawFn = ProjectPicker.typeErasedDrawFn,
        };
    }

    pub fn eventHandler(
        self: *ProjectPicker,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        switch (event) {
            .init => {
                // Initialize the filtered list
                const allocator = self.arena.allocator();
                for (self.list.items) |line| {
                    var spans = std.ArrayList(vxfw.RichText.TextSpan).init(allocator);
                    const span: vxfw.RichText.TextSpan = .{ .text = line.text };
                    try spans.append(span);
                    try self.filtered.append(.{ .text = spans.items });
                }

                return ctx.requestFocus(self.text_field.widget());
            },
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }

                try self.list_view.handleEvent(ctx, event);
            },
            .focus_in => {
                return ctx.requestFocus(self.text_field.widget());
            },
            else => {},
        }
    }

    pub fn draw(
        self: *ProjectPicker,
        ctx: vxfw.DrawContext,
    ) std.mem.Allocator.Error!vxfw.Surface {
        const max = ctx.max.size();

        const list_view: vxfw.SubSurface = .{
            .origin = .{ .row = 2, .col = 0 },
            .surface = try self.list_view.draw(ctx.withConstraints(
                ctx.min,
                .{ .width = max.width, .height = max.height - 3 },
            )),
        };

        const text_field: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 2 },
            .surface = try self.text_field.draw(ctx.withConstraints(
                ctx.min,
                .{ .width = max.width, .height = 1 },
            )),
        };

        const prompt: vxfw.Text = .{ .text = "", .style = .{ .fg = .{ .index = 4 } } };

        const prompt_surface: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try prompt.draw(ctx.withConstraints(ctx.min, .{ .width = 2, .height = 1 })),
        };

        const children = try ctx.arena.alloc(vxfw.SubSurface, 3);
        children[0] = list_view;
        children[1] = text_field;
        children[2] = prompt_surface;

        return .{
            .size = max,
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }

    fn typeErasedEventHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        const self: *ProjectPicker = @ptrCast(@alignCast(ptr));
        try self.eventHandler(ctx, event);
    }

    fn typeErasedDrawFn(
        ptr: *anyopaque,
        ctx: vxfw.DrawContext,
    ) std.mem.Allocator.Error!vxfw.Surface {
        const self: *ProjectPicker = @ptrCast(@alignCast(ptr));
        return try self.draw(ctx);
    }

    pub fn widget_builder(ptr: *const anyopaque, idx: usize, _: usize) ?vxfw.Widget {
        const self: *const ProjectPicker = @ptrCast(@alignCast(ptr));
        if (idx >= self.filtered.items.len) return null;

        return self.filtered.items[idx].widget();
    }

    fn sort(_: void, a: Candidate, b: Candidate) bool {
        // first by rank
        if (a.rank < b.rank) return true;
        if (a.rank > b.rank) return false;

        // then by length
        if (a.str.len < b.str.len) return true;
        if (a.str.len > b.str.len) return false;

        // then alphabetically
        for (a.str, 0..) |c, i| {
            if (c < b.str[i]) return true;
            if (c > b.str[i]) return false;
        }
        return false;
    }

    pub fn on_change(maybe_ptr: ?*anyopaque, _: *vxfw.EventContext, str: []const u8) anyerror!void {
        const ptr = maybe_ptr orelse return;
        const self: *ProjectPicker = @ptrCast(@alignCast(ptr));

        // Clear the filtered list and the arena.
        self.filtered.clearAndFree();
        _ = self.arena.reset(.free_all);

        const arena = self.arena.allocator();

        // If there is text in the search box we only render items that contain the search string.
        // Otherwise we render all the items.
        if (str.len > 0) {
            var case_sensitive = false;
            for (str) |c| {
                if (std.ascii.isUpper(c)) {
                    case_sensitive = true;
                    break;
                }
            }

            var tokens: std.ArrayListUnmanaged([]const u8) = .empty;
            var it = std.mem.tokenizeScalar(u8, str, ' ');
            while (it.next()) |token| {
                try tokens.append(arena, token);
            }

            var fuzzy_ranked: std.ArrayListUnmanaged(Candidate) = .empty;

            for (self.list.items) |item| {
                if (zf.rank(item.text, tokens.items, .{ .to_lower = !case_sensitive })) |r| {
                    try fuzzy_ranked.append(arena, .{ .str = item.text, .rank = r });
                }
            }

            std.sort.block(Candidate, fuzzy_ranked.items, {}, sort);

            for (fuzzy_ranked.items) |item| {
                var matches_buf: [2048]usize = undefined;
                const matches = zf.highlight(
                    item.str,
                    tokens.items,
                    &matches_buf,
                    .{ .to_lower = !case_sensitive },
                );

                var spans = std.ArrayList(vxfw.RichText.TextSpan).init(arena);

                if (matches.len == 0) {
                    const span: vxfw.RichText.TextSpan = .{ .text = item.str };
                    try spans.append(span);
                    try self.filtered.append(.{ .text = spans.items });
                    continue;
                }

                var slicer: HighlightSlicer = .init(item.str, matches);

                while (slicer.next()) |slice| {
                    const span: vxfw.RichText.TextSpan = .{
                        .text = slice.str,
                        .style = .{ .reverse = slice.highlight },
                    };
                    try spans.append(span);
                }

                try self.filtered.append(.{ .text = spans.items });
            }
        } else {
            for (self.list.items) |line| {
                var spans = std.ArrayList(vxfw.RichText.TextSpan).init(arena);
                const span: vxfw.RichText.TextSpan = .{ .text = line.text };
                try spans.append(span);
                try self.filtered.append(.{ .text = spans.items });
            }
        }

        self.list_view.scroll.top = 0;
        self.list_view.scroll.offset = 0;
        self.list_view.cursor = 0;
    }

    pub fn on_submit(maybe_ptr: ?*anyopaque, ctx: *vxfw.EventContext, _: []const u8) anyerror!void {
        const ptr = maybe_ptr orelse return;
        const self: *ProjectPicker = @ptrCast(@alignCast(ptr));

        const arena = self.arena.allocator();
        self.result.clearAndFree();

        // 1. We want to quit on every submit, even ones that fail.

        ctx.quit = true;

        // 2. Get the selected item.

        if (self.list_view.cursor >= self.filtered.items.len) return;

        var selected_item = std.ArrayList(u8).init(arena);
        defer selected_item.deinit();

        for (self.filtered.items[self.list_view.cursor].text) |span| {
            try selected_item.appendSlice(span.text);
        }

        // 3. If we can find a home directory replace any `~` in the chosen path with the path to
        //    the home directory.

        const home_path = kf.getPath(arena, .home) catch null;
        if (home_path) |home| {
            const replace_len = std.mem.replacementSize(u8, selected_item.items, "~", home);
            const result = try arena.alloc(u8, replace_len);

            _ = std.mem.replace(
                u8,
                selected_item.items,
                "~",
                home,
                result,
            );

            try self.result.appendSlice(result);
            return;
        }

        // 4. Otherwise just return the chosen item unmodified.

        try self.result.appendSlice(selected_item.items);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var app = try vxfw.App.init(allocator);
    errdefer app.deinit();

    const picker = try allocator.create(ProjectPicker);
    defer allocator.destroy(picker);

    picker.* = .{
        .list = std.ArrayList(vxfw.Text).init(allocator),
        .filtered = std.ArrayList(vxfw.RichText).init(allocator),
        .list_view = .{
            .children = .{
                .builder = .{
                    .userdata = picker,
                    .buildFn = ProjectPicker.widget_builder,
                },
            },
        },
        .text_field = .{
            .buf = vxfw.TextField.Buffer.init(allocator),
            .unicode = &app.vx.unicode,
            .userdata = picker,
            .onChange = ProjectPicker.on_change,
            .onSubmit = ProjectPicker.on_submit,
        },
        .arena = std.heap.ArenaAllocator.init(allocator),
        .result = std.ArrayList(u8).init(allocator),
    };
    defer picker.text_field.deinit();
    defer picker.list.deinit();
    defer picker.filtered.deinit();
    defer picker.arena.deinit();
    defer picker.result.deinit();

    // 1. Open the ~/.config directory, or equivalent on Windows.

    const config_dir = kf.open(
        allocator,
        .local_configuration,
        .{ .access_sub_paths = true },
    ) catch |err| {
        std.log.err("failed to open config directory: {}", .{err});
        std.process.exit(74); // EX_IOERR from sysexits.h - I/O error on file.
    };

    if (config_dir) |config| {
        // 2. Read the contents of the ~/.config/project-picker/projects file.

        const pp_dir = config.makeOpenPath("project-picker", .{}) catch |err| {
            std.log.err("failed to open project-picker config directory: {}", .{err});
            std.process.exit(74); // EX_IOERR from sysexits.h - I/O error on file.
        };

        const projects_file = pp_dir.createFile(
            "projects",
            .{ .truncate = false, .read = true },
        ) catch |err| {
            std.log.err("failed to load project-picker project file: {}", .{err});
            std.process.exit(74); // EX_IOERR from sysexits.h - I/O error on file.
        };

        const projects = projects_file.reader().readAllAlloc(
            allocator,
            std.math.maxInt(usize),
        ) catch |err| {
            std.log.err("failed to read project-picker project file: {}", .{err});
            std.process.exit(74); // EX_IOERR from sysexits.h - I/O error on file.
        };
        defer allocator.free(projects);

        // 3. Parse the lines of the file and add them to the available items in the project picker.

        var arena_state: std.heap.ArenaAllocator = .init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        var it = std.mem.tokenizeScalar(u8, projects, '\n');
        while (it.next()) |token| {
            if (std.mem.endsWith(u8, token, "/*")) {
                const dir_path = dir_path: {
                    const dir_path = token[0 .. token.len - 2];

                    if (!std.mem.startsWith(u8, dir_path, "~/")) {
                        break :dir_path dir_path;
                    }

                    var env = try std.process.getEnvMap(arena);
                    defer env.deinit();
                    const home = env.get("HOME") orelse return error.NoHomeDirectoryFound;
                    break :dir_path try std.fs.path.join(arena, &.{ home, dir_path[1..] });
                };

                const dir = try std.fs.cwd().openDir(dir_path, .{});
                var dir_it = dir.iterate();

                while (try dir_it.next()) |f| {
                    if (f.kind == .directory) {
                        try picker.list.append(
                            .{ .text = try std.fs.path.join(arena, &.{ dir_path, f.name }) },
                        );
                    }
                }
            } else {
                try picker.list.append(.{ .text = token });
            }
        }

        // 4. Run the picker.

        try app.run(picker.widget(), .{});
        app.deinit();

        // 5. If no selection was made exit with $status == 1.

        if (picker.result.items.len == 0) {
            std.process.exit(1);
        }

        // 6. Print the chosen path to STDOUT.

        const stdout = std.io.getStdOut().writer();
        nosuspend stdout.print("{s}", .{picker.result.items}) catch |err| {
            std.log.err("{s}", .{@errorName(err)});
            std.process.exit(74); // EX_IOERR from sysexits.h - I/O error on file.
        };
    } else {
        std.log.err("failed to open config directory", .{});
        std.process.exit(74); // EX_IOERR from sysexits.h - I/O error on file.
    }
}
