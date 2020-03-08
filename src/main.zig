const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

/// The set of languages supported.
pub const Language = enum {
    English,
};

/// Creates a WordList from the input data for the language provided.
fn readWordList(data: []const u8) [2048][]const u8 {
    var words: [2048][]const u8 = undefined;

    var iter = std.mem.tokenize(data, "\n");
    var i: usize = 0;
    while (iter.next()) |line| {
        words[i] = line;
        i += 1;
    }

    return words;
}

const data_english = @embedFile("wordlist_english.txt");

const WORD_BITS = 11;

pub fn mnemonic(
    comptime T: type,
) type {
    comptime assert(std.meta.trait.isIndexable(T));

    // Compute the entropy bits at comptime since we know the type slices we're getting.
    comptime const entropy_bits = T.len * 8;
    comptime const mask: u8 = switch (entropy_bits) {
        128 => 0xF0, // 4 bits
        160 => 0xF8, // 5 bits
        192 => 0xFC, // 6 bits
        224 => 0xFE, // 7 bits
        256 => 0xFF, // 8 bits
        else => {
            @compileError("Expected array of u8 of either length [16, 20, 24, 28, 32], found " ++ @typeName(T));
        },
    };

    return struct {
        const Self = @This();

        allocator: *std.mem.Allocator,

        words: [2048][]const u8,

        pub fn init(allocator: *std.mem.Allocator, language: Language) !Self {
            return Self{
                .allocator = allocator,
                .words = switch (language) {
                    .English => readWordList(data_english),
                },
            };
        }

        pub fn deinit(self: *Self) void {}

        pub fn encode(self: *Self, entropy: T) ![][]const u8 {
            // compute sha256 checksum
            //
            var checksum_buf: [256]u8 = undefined;
            std.crypto.Sha256.hash(&entropy, &checksum_buf);

            const checksum: u8 = @truncate(u8, checksum_buf[0] & mask);

            // append checksum to entropy

            const new_entropy = try self.allocator.alloc(u8, entropy.len + 1);
            defer self.allocator.free(new_entropy);

            std.mem.copy(u8, new_entropy, &entropy);
            new_entropy[entropy.len] = checksum;

            // generate the mnemonic sentence
            //

            const checksum_length = entropy_bits / 32;
            const nb_words = (entropy_bits + checksum_length) / WORD_BITS;

            var result = std.ArrayList([]const u8).init(self.allocator);
            defer result.deinit();

            var i: usize = 0;
            while (i < nb_words) {
                const idx = extractIndex(new_entropy, i);

                try result.append(self.words[idx]);

                i += 1;
            }

            return result.toOwnedSlice();
        }
    };
}

fn extractIndex(data: []const u8, word_pos: usize) usize {
    var pos: usize = 0;
    var end: usize = 0;
    var value: usize = 0;

    pos = word_pos * WORD_BITS;
    end = pos + WORD_BITS;

    while (pos < end) {
        // fetch the byte needed for the current position
        const b = data[pos / 8];

        // compute the mask of the bits we need
        const in_byte_pos = 7 - @mod(pos, 8);
        const full_mask = @as(i64, 1) << @truncate(u6, in_byte_pos);
        const mask = @truncate(u8, @bitCast(u64, full_mask));

        // shift the current value by one to the left since we're adding a single bit.
        value <<= 1;

        // Append a 1 if the bit for the current position is set, 0 otherwise.
        value |= if (b & mask == mask) @as(u8, 1) else 0;

        pos += 1;
    }

    return value;
}

test "extract index" {
    var entropy: [16]u8 = undefined;
    try std.fmt.hexToBytes(&entropy, "18ab19a9f54a9274f03e5209a2ac8a91");

    const idx = extractIndex(&entropy, 10);
    testing.expectEqual(idx, 277);
}

test "check the english wordlist" {
    const wordlist = readWordList(data_english);
    testing.expectEqual(wordlist.len, 2048);
}

test "mnemonic all zeroes" {
    var entropy: [16]u8 = undefined;
    std.mem.set(u8, &entropy, 0);

    var encoder = try mnemonic([16]u8).init(testing.allocator, .English);
    defer encoder.deinit();

    const result = try encoder.encode(entropy);
    defer testing.allocator.free(result);

    testing.expectEqual(@as(usize, 12), result.len);
    var i: usize = 0;
    while (i < 11) {
        testing.expectEqualSlices(u8, "abandon", result[i]);
        i += 1;
    }
    testing.expectEqualSlices(u8, "about", result[11]);
}

fn testMnemonic(comptime T: type, hex_entropy: []const u8, exp: []const u8) !void {
    var entropy: T = undefined;
    try std.fmt.hexToBytes(&entropy, hex_entropy);

    var encoder = try mnemonic(T).init(testing.allocator, .English);
    defer encoder.deinit();

    // compute the mnemonic

    const result = try encoder.encode(entropy);
    defer testing.allocator.free(result);

    // check it

    const joined = try std.mem.join(testing.allocator, " ", result);
    defer testing.allocator.free(joined);

    testing.expectEqualSlices(u8, exp, joined);
}

test "all test vectors" {
    // create the test vectors
    const data = @embedFile("vectors.json");

    const testVector = struct {
        entropy: []const u8,
        mnemonic: []const u8,
    };

    const options = std.json.ParseOptions{ .allocator = testing.allocator };

    const vectors = try std.json.parse([]testVector, &std.json.TokenStream.init(data), options);
    defer std.json.parseFree([]testVector, vectors, options);

    for (vectors) |v| {
        if (v.entropy.len == 32) {
            try testMnemonic([16]u8, v.entropy, v.mnemonic);
        } else if (v.entropy.len == 40) {
            try testMnemonic([20]u8, v.entropy, v.mnemonic);
        } else if (v.entropy.len == 48) {
            try testMnemonic([24]u8, v.entropy, v.mnemonic);
        } else if (v.entropy.len == 56) {
            try testMnemonic([28]u8, v.entropy, v.mnemonic);
        } else if (v.entropy.len == 64) {
            try testMnemonic([32]u8, v.entropy, v.mnemonic);
        } else {
            @panic("unhandled vector size");
        }
    }
}
