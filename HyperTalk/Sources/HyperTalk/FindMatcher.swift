//
//  FindMatcher.swift
//  HyperTalk
//

import Foundation

/// The text-matching core of `find`, split out so it's pure and testable:
/// given a field's text and a query, it returns the character range of the
/// first match under a `FindMode`. Card traversal lives in the host; this is
/// just "does this string contain the query, and where?". Case-insensitive,
/// as HyperCard's find always is.
public enum FindMatcher {
    /// The first matching character range in `text` at or after `from`
    /// (a character offset), or nil if there's no match.
    public static func firstRange(in text: String, query: String, mode: FindMode, from: Int = 0) -> Range<Int>? {
        let haystack = Array(text.lowercased())
        let start = min(max(0, from), haystack.count)
        switch mode {
        case .chars, .string:
            return substringRange(haystack, Array(trimmed(query)), from: start)
        case .wholeWord, .wholePhrase:
            return wordBoundaryRange(haystack, Array(trimmed(query)), from: start)
        case .wordPrefix:
            // Every search word must begin a word somewhere in the field; the
            // boxed match is the first search word's first matching word.
            let words = trimmed(query).split(whereSeparator: \.isWhitespace).map(Array.init)
            guard let first = words.first else { return nil }
            for word in words where wordPrefixRange(haystack, word, from: 0) == nil {
                return nil
            }
            return wordPrefixRange(haystack, first, from: start)
        }
    }

    private static func trimmed(_ query: String) -> String {
        query.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Whether a character is part of a word (for boundary tests).
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// The first contiguous occurrence of `needle` in `haystack` at or after
    /// `from`, or nil. An empty needle never matches.
    private static func substringRange(_ haystack: [Character], _ needle: [Character], from: Int) -> Range<Int>? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        let last = haystack.count - needle.count
        guard from <= last else { return nil }
        for offset in from...last where Array(haystack[offset..<offset + needle.count]) == needle {
            return offset..<(offset + needle.count)
        }
        return nil
    }

    /// Like `substringRange`, but the match must begin and end on word
    /// boundaries (so `find word "cat"` skips "category").
    private static func wordBoundaryRange(_ haystack: [Character], _ needle: [Character], from: Int) -> Range<Int>? {
        var searchFrom = from
        while let range = substringRange(haystack, needle, from: searchFrom) {
            let beforeOK = range.lowerBound == 0 || !isWordCharacter(haystack[range.lowerBound - 1])
            let afterOK = range.upperBound == haystack.count || !isWordCharacter(haystack[range.upperBound])
            if beforeOK && afterOK { return range }
            searchFrom = range.lowerBound + 1
        }
        return nil
    }

    /// The first word at or after `from` that begins with `needle` (so
    /// `find "cat"` boxes "category"). The range covers the whole word, as
    /// HyperCard boxes it and `the foundText` reports it.
    private static func wordPrefixRange(_ haystack: [Character], _ needle: [Character], from: Int) -> Range<Int>? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        let last = haystack.count - needle.count
        guard from <= last else { return nil }
        for offset in from...last {
            let atWordStart = offset == 0 || !isWordCharacter(haystack[offset - 1])
            guard atWordStart else { continue }
            if Array(haystack[offset..<offset + needle.count]) == needle {
                var end = offset + needle.count
                while end < haystack.count, isWordCharacter(haystack[end]) { end += 1 }
                return offset..<end
            }
        }
        return nil
    }
}
