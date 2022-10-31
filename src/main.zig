const builtin = @import("builtin");
const options = @import("build_options");
const std = @import("std");
const glfw = @import("glfw");
const fontconfig = @import("fontconfig");
const freetype = @import("freetype");
const harfbuzz = @import("harfbuzz");
const macos = @import("macos");
const tracy = @import("tracy");
const renderer = @import("renderer.zig");

const App = @import("App.zig");
const cli_args = @import("cli_args.zig");
const Config = @import("config.zig").Config;

pub fn main() !void {
    // Output some debug information right away
    std.log.info("dependency harfbuzz={s}", .{harfbuzz.versionString()});
    if (options.fontconfig) {
        std.log.info("dependency fontconfig={d}", .{fontconfig.version()});
    }
    std.log.info("renderer={}", .{renderer.Renderer});

    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa: ?GPA = gpa: {
        // Use the libc allocator if it is available beacuse it is WAY
        // faster than GPA. We only do this in release modes so that we
        // can get easy memory leak detection in debug modes.
        if (builtin.link_libc) {
            if (switch (builtin.mode) {
                .ReleaseSafe, .ReleaseFast => true,

                // We also use it if we can detect we're running under
                // Valgrind since Valgrind only instruments the C allocator
                else => std.valgrind.runningOnValgrind() > 0,
            }) break :gpa null;
        }

        break :gpa GPA{};
    };
    defer if (gpa) |*value| {
        // We want to ensure that we deinit the GPA because this is
        // the point at which it will output if there were safety violations.
        _ = value.deinit();
    };

    const alloc = alloc: {
        const base = if (gpa) |*value|
            value.allocator()
        else if (builtin.link_libc)
            std.heap.c_allocator
        else
            unreachable;

        // If we're tracing, wrap the allocator
        if (!tracy.enabled) break :alloc base;
        var tracy_alloc = tracy.allocator(base, null);
        break :alloc tracy_alloc.allocator();
    };

    // Parse the config from the CLI args
    var config = config: {
        var result = try Config.default(alloc);
        errdefer result.deinit();
        var iter = try std.process.argsWithAllocator(alloc);
        defer iter.deinit();
        try cli_args.parse(Config, alloc, &result, &iter);
        break :config result;
    };
    defer config.deinit();

    // Parse the config files
    // TODO(mitchellh): support nesting (config-file in a config file)
    // TODO(mitchellh): detect cycles when nesting
    if (config.@"config-file".list.items.len > 0) {
        const len = config.@"config-file".list.items.len;
        const cwd = std.fs.cwd();
        for (config.@"config-file".list.items) |path| {
            var file = try cwd.openFile(path, .{});
            defer file.close();

            var buf_reader = std.io.bufferedReader(file.reader());
            var iter = cli_args.lineIterator(buf_reader.reader());

            try cli_args.parse(Config, alloc, &config, &iter);

            // We don't currently support adding more config files to load
            // from within a loaded config file. This can be supported
            // later.
            if (config.@"config-file".list.items.len > len)
                return error.ConfigFileInConfigFile;
        }
    }
    std.log.info("config={}", .{config});

    // We want to log all our errors
    glfw.setErrorCallback(glfwErrorCallback);

    // Initialize glfw
    try glfw.init(.{});
    defer glfw.terminate();

    // Run our app
    var app = try App.init(alloc, &config);
    defer app.deinit();
    try app.run();
}

// Required by tracy/tracy.zig to enable/disable tracy support.
pub fn tracy_enabled() bool {
    return options.tracy_enabled;
}

// Our log level is always at least info in every build mode.
pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    else => .info,
};

// The function std.log will call.
pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // Stuff we can do before the lock
    const level_txt = comptime level.asText();
    const prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    // Lock so we are thread-safe
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();

    // On Mac, we use unified logging. To view this:
    //
    //   sudo log stream --level debug --predicate 'subsystem=="com.mitchellh.ghostty"'
    //
    if (builtin.os.tag == .macos) {
        // Convert our levels to Mac levels
        const mac_level: macos.os.LogType = switch (level) {
            .debug => .debug,
            .info => .info,
            .warn => .err,
            .err => .fault,
        };

        // Initialize a logger. This is slow to do on every operation
        // but we shouldn't be logging too much.
        const logger = macos.os.Log.create("com.mitchellh.ghostty", @tagName(scope));
        defer logger.release();
        logger.log(std.heap.c_allocator, mac_level, format, args);
    }

    // Always try default to send to stderr
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(level_txt ++ prefix ++ format ++ "\n", args) catch return;
}

fn glfwErrorCallback(code: glfw.Error, desc: [:0]const u8) void {
    std.log.warn("glfw error={} message={s}", .{ code, desc });
}

test {
    _ = @import("Atlas.zig");
    _ = @import("Pty.zig");
    _ = @import("Command.zig");
    _ = @import("TempDir.zig");
    _ = @import("font/main.zig");
    _ = @import("renderer.zig");
    _ = @import("terminal/Terminal.zig");
    _ = @import("input.zig");

    // Libraries
    _ = @import("segmented_pool.zig");
    _ = @import("terminal/main.zig");

    // TODO
    _ = @import("config.zig");
    _ = @import("cli_args.zig");
    _ = @import("lru.zig");
}
