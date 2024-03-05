const builtin = @import("builtin");

pub const kitty = @import("kitty.zig");
pub const page = @import("page.zig");
pub const point = @import("point.zig");
pub const PageList = @import("PageList.zig");
pub const Terminal = @import("Terminal.zig");
pub const Screen = @import("Screen.zig");
pub const Page = page.Page;

test {
    @import("std").testing.refAllDecls(@This());

    // todo: make top-level imports
    _ = @import("bitmap_allocator.zig");
    _ = @import("hash_map.zig");
    _ = @import("size.zig");
    _ = @import("style.zig");
}
