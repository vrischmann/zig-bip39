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

/// A Mnemonic can encode a byte array called entropy into a "mnemonic sentence", a group of easy to remember words.
/// See https://en.bitcoin.it/wiki/BIP_0039
///
/// The type T must an array of u8, of either length 16, 20, 24, 28, 32.
/// Initialize with `init`.
pub fn Mnemonic(comptime T: type) type {
    comptime assert(std.meta.trait.isIndexable(T));

    // Compute the entropy bits at comptime since we know the type slices we're getting.
    comptime const entropy_bits = T.len * 8;
    comptime const checksum_mask: u8 = switch (entropy_bits) {
        128 => 0xF0, // 4 bits
        160 => 0xF8, // 5 bits
        192 => 0xFC, // 6 bits
        224 => 0xFE, // 7 bits
        256 => 0xFF, // 8 bits
        else => {
            @compileError("Expected array of u8 of either length [16, 20, 24, 28, 32], found " ++ @typeName(T));
        },
    };

    comptime const checksum_length = entropy_bits / 32;
    comptime const nb_words = (entropy_bits + checksum_length) / WORD_BITS;

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

        /// Encodes entropy into a mnemonic sentence.
        pub fn encode(self: *Self, entropy: T) ![]const u8 {
            // compute sha256 checksum
            //
            var checksum_buf: [256]u8 = undefined;
            std.crypto.Sha256.hash(&entropy, &checksum_buf);

            const checksum = @truncate(u8, checksum_buf[0] & checksum_mask);

            // append checksum to entropy

            const new_entropy = try std.mem.concat(self.allocator, u8, &[_][]const u8{
                &entropy,
                &[_]u8{checksum},
            });
            defer self.allocator.free(new_entropy);

            // generate the mnemonic sentence
            //

            var buffer = try std.Buffer.init(self.allocator, "");
            defer buffer.deinit();

            var i: usize = 0;
            while (i < nb_words) {
                if (i > 0) {
                    try buffer.append(" ");
                }

                const idx = extractIndex(new_entropy, i);

                try buffer.append(self.words[idx]);

                i += 1;
            }

            return buffer.toOwnedSlice();
        }
    };
}

/// Returns the index into the word list for the word at word_pos.
fn extractIndex(data: []const u8, word_pos: usize) usize {
    var pos: usize = 0;
    var end: usize = 0;
    var value: usize = 0;

    pos = word_pos * WORD_BITS;
    end = pos + WORD_BITS;

    // This function works by iterating over the bits in the range applicable for the word at word_pos.
    //
    // For example, the second word (index 1) will need these bits:
    //  - start = 1 * 11
    //  - end   = start + 11
    //
    // For each position in this range, we fetch the corresponding bit value and write the value to the
    // output value integer.
    //
    // To follow up the example above, the loop would iterate other two bytes:
    //  data[1] and data[2]
    //
    // These are the iterations this loop would perform:
    //  pos = 11, b = data[1], mask = 16  = 0b00010000
    //  pos = 12, b = data[1], mask = 8   = 0b00001000
    //  pos = 13, b = data[1], mask = 4   = 0b00000100
    //  pos = 14, b = data[1], mask = 2   = 0b00000010
    //  pos = 15, b = data[1], mask = 0   = 0b00000001
    //  pos = 16, b = data[2], mask = 128 = 0b10000000
    //  pos = 17, b = data[2], mask = 64  = 0b01000000
    //  pos = 18, b = data[2], mask = 32  = 0b00100000
    //  pos = 19, b = data[2], mask = 16  = 0b00010000
    //  pos = 20, b = data[2], mask = 8   = 0b00001000
    //  pos = 21, b = data[2], mask = 4   = 0b00000100

    while (pos < end) {
        // fetch the byte needed for the current position
        const b = data[pos / 8];

        // compute the mask of the bit we need
        const mask = @as(usize, 1) << @truncate(u6, 7 - @mod(pos, 8));

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

    var encoder = try Mnemonic([16]u8).init(testing.allocator, .English);
    defer encoder.deinit();

    const result = try encoder.encode(entropy);
    defer testing.allocator.free(result);

    testing.expectEqualSlices(u8, "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", result);
}

fn testMnemonic(comptime T: type, hex_entropy: []const u8, exp: []const u8) !void {
    var entropy: T = undefined;
    try std.fmt.hexToBytes(&entropy, hex_entropy);

    var encoder = try Mnemonic(T).init(testing.allocator, .English);
    defer encoder.deinit();

    // compute the mnemonic

    const result = try encoder.encode(entropy);
    defer testing.allocator.free(result);

    // check it

    testing.expectEqualSlices(u8, exp, result);
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
