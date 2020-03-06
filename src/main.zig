const std = @import("std");
const testing = std.testing;

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

pub const EncodingError = error{InvalidDataSize};

pub const MIN_ENTROPY_SIZE = 16 * 8;
pub const MAX_ENTROPY_SIZE = 32 * 8;
const WORD_BITS = 11;

pub fn mnemonic(allocator: *std.mem.Allocator, language: Language, entropy: []const u8) ![][]const u8 {
    const entropy_bits = entropy.len * 8;

    // some sanity checks
    if (entropy_bits < MIN_ENTROPY_SIZE or entropy_bits > MAX_ENTROPY_SIZE) {
        return EncodingError.InvalidDataSize;
    }
    // TODO(vincent): can we check this via an annotation to the slice ?
    if (@mod(entropy_bits, 32) != 0) {
        return EncodingError.InvalidDataSize;
    }

    // compute sha256 checksum
    //
    var checksum_buf: [256]u8 = undefined;
    std.crypto.Sha256.hash(entropy, &checksum_buf);

    const checksum: u8 = @truncate(u8, checksum_buf[0] & checksumMask(entropy_bits));

    // append checksum to entropy

    const new_entropy = try allocator.alloc(u8, entropy.len + 1);

    std.mem.copy(u8, new_entropy, entropy);
    new_entropy[entropy.len] = checksum;

    // generate the mnemonic sentence
    //

    const words = switch (language) {
        // TODO(vincent): need to fix this so we don't recompute the word list
        // every time, but doing it at comptime is way too long.
        .English => readWordList(data_english),
    };

    const checksum_length = entropy_bits / 32;
    const nb_words = (entropy_bits + checksum_length) / WORD_BITS;

    var result = std.ArrayList([]const u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < nb_words) {
        const idx = extractIndex(new_entropy, i);

        try result.append(words[idx]);

        i += 1;
    }

    return result.toSlice();
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

        const in_byte_pos = 7 - @mod(pos, 8);
        const full_mask = @as(i64, 1) << @truncate(u6, in_byte_pos);
        const mask = @truncate(u8, @bitCast(u64, full_mask));

        // Shift the current value by one to the left since we're adding a single bit.
        value <<= 1;

        // Append a 1 if the bit for the current position is set, 0 otherwise.
        value |= b & mask;

        pos += 1;
    }

    return value;
}

fn checksumMask(bits: usize) usize {
    std.debug.warn("bits: {}\n", .{bits});
    return switch (bits) {
        128 => 0xF0, // 4 bits
        160 => 0xF8, // 5 bits
        192 => 0xFC, // 6 bits
        224 => 0xFE, // 7 bits
        256 => 0xFF, // 8 bits
        else => unreachable,
    };
}

test "check the english wordlist" {
    const wordlist = readWordList(data_english);
    testing.expect(wordlist.len == 2048);
}

test "mnemonic all zeroes" {
    var entropy: [32]u8 = undefined;
    std.mem.set(u8, &entropy, 0);

    const result = try mnemonic(testing.allocator, .English, &entropy);
}
