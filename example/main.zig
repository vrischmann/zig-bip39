const std = @import("std");

const bip39 = @import("bip39");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) {
        std.debug.panic("memory leaks\n", .{});
    };
    const allocator = gpa.allocator();

    const EncoderType = bip39.Mnemonic([20]u8);

    var encoder = try EncoderType.init(allocator, .English);
    defer encoder.deinit();

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        var entropy: [20]u8 = undefined;
        try std.os.getrandom(&entropy);

        const sentence = try encoder.encode(entropy);
        defer allocator.free(sentence);

        std.debug.print("entropy: {s}, sentence: {s}\n", .{ std.fmt.fmtSliceHexLower(&entropy), sentence });
    }
}
