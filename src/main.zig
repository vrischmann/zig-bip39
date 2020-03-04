const std = @import("std");
const testing = std.testing;

const WordList = struct {
    language: []const u8,
    words: [2048][]const u8,
};

/// Creates a WordList from the input data for the language provided.
fn readWordList(comptime language: []const u8, comptime data: []const u8) anyerror!WordList {
    var words: [2048][]const u8 = undefined;

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

    testing.expect(std.mem.eql(u8, english.language, "english"));
    testing.expect(english.words.len == 2048);
}
