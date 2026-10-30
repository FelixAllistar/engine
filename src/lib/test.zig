comptime {
    _ = @import("common/test.zig");
    _ = @import("gen1/test.zig");
    // Single player (trainer AI) only exists in cartridge mode
    if (!@import("pkmn.zig").options.showdown) _ = @import("gen1/single_player_test.zig");
    _ = @import("gen2/test.zig");
}
