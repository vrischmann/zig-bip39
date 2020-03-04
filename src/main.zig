const std = @import("std");
const testing = std.testing;

const WordList = struct {
    language: []const u8,
    words: [2047][]const u8,
};

fn readWordList(comptime language: []const u8, comptime data: []const u8) anyerror!WordList {
    var words: [2047][]const u8 = undefined;

    var iter = std.mem.tokenize(data, "\n");
    var i: usize = 0;
    while (iter.next()) |line| {
        words[i] = line;
        i += 1;
    }

    return WordList{
        .language = language,
        .words = words,
    };
}

const data_english = @embedFile("wordlist_english.txt");

test "read all words" {
    const english = try readWordList("english", data_english);

    for (english.words[0..2]) |word| {
        std.debug.warn("word: {}\n", .{word});
    }
}
