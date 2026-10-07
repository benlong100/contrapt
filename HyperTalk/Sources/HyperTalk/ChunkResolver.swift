//
//  ChunkResolver.swift
//  HyperTalk
//

import Foundation

/// Extracts chunks of text — HyperCard's `char`/`word`/`item`/`line`
/// addressing. Splits the source into units, selects by index / range /
/// last / middle (1-based, like HyperTalk), and rejoins with the unit's
/// delimiter. Out-of-range selections yield empty string, as in HyperCard.
enum ChunkResolver {
    /// `evaluateIndex` resolves a position expression (e.g. the `2` in
    /// `word 2`) to an Int, deferring to the interpreter so indices can be
    /// arbitrary expressions.
    static func resolve(
        kind: ChunkKind,
        selector: ChunkSelector,
        in source: String,
        itemDelimiter: String = ",",
        evaluateIndex: (Expr) async throws -> Int
    ) async throws -> String {
        // Characters operate on the raw string; other kinds split into units.
        if kind == .character {
            let characters = Array(source)
            let (start, end) = try await bounds(selector, count: characters.count, evaluateIndex: evaluateIndex)
            guard start <= end, start >= 1, start <= characters.count else { return "" }
            let lo = max(1, start) - 1
            let hi = min(characters.count, end)
            return String(characters[lo..<hi])
        }

        let units = split(source, kind: kind, itemDelimiter: itemDelimiter)
        let (start, end) = try await bounds(selector, count: units.count, evaluateIndex: evaluateIndex)
        guard start <= end, start >= 1, start <= units.count else { return "" }
        let lo = max(1, start) - 1
        let hi = min(units.count, end)
        return units[lo..<hi].joined(separator: delimiter(kind, itemDelimiter: itemDelimiter))
    }

    /// Returns `source` with the selected chunk replaced by `replacement`.
    /// Extends the text (padding with empty units) when the selection lies
    /// past the end, so `put X into line 5 of Y` can grow Y.
    static func replacing(
        kind: ChunkKind,
        selector: ChunkSelector,
        in source: String,
        with replacement: String,
        itemDelimiter: String = ",",
        evaluateIndex: (Expr) async throws -> Int
    ) async throws -> String {
        if kind == .character {
            var characters = Array(source)
            let (start, end) = try await bounds(selector, count: characters.count, evaluateIndex: evaluateIndex)
            guard start >= 1 else { return source }
            let lo = min(start - 1, characters.count)
            let hi = min(max(end, start - 1), characters.count)
            characters.replaceSubrange(lo..<hi, with: Array(replacement))
            return String(characters)
        }

        var units = split(source, kind: kind, itemDelimiter: itemDelimiter)
        let (start, end) = try await bounds(selector, count: units.count, evaluateIndex: evaluateIndex)
        guard start >= 1 else { return source }
        while units.count < start { units.append("") }
        let lo = start - 1
        let hi = min(max(end, start), units.count)
        units.replaceSubrange(lo..<hi, with: [replacement])
        return units.joined(separator: delimiter(kind, itemDelimiter: itemDelimiter))
    }

    /// How many units of `kind` are in `source` (empty text has none).
    static func count(kind: ChunkKind, in source: String, itemDelimiter: String = ",") -> Int {
        guard !source.isEmpty else { return 0 }
        return kind == .character ? source.count : split(source, kind: kind, itemDelimiter: itemDelimiter).count
    }

    /// The character-offset range a chunk occupies in `source` — the position
    /// half of `resolve` (which returns the text), for `select` and its
    /// selected* descriptors. Nil when the selector lies outside the text.
    static func range(
        kind: ChunkKind,
        selector: ChunkSelector,
        in source: String,
        itemDelimiter: String = ",",
        evaluateIndex: (Expr) async throws -> Int
    ) async throws -> Range<Int>? {
        if kind == .character {
            let count = source.count
            let (start, end) = try await bounds(selector, count: count, evaluateIndex: evaluateIndex)
            guard start <= end, start >= 1, start <= count else { return nil }
            return (start - 1)..<min(count, end)
        }
        let spans = unitSpans(source, kind: kind, itemDelimiter: itemDelimiter)
        let (start, end) = try await bounds(selector, count: spans.count, evaluateIndex: evaluateIndex)
        guard start <= end, start >= 1, start <= spans.count else { return nil }
        let hi = min(spans.count, end)
        return spans[start - 1].lowerBound..<spans[hi - 1].upperBound
    }

    /// Character-offset spans of each unit of `kind` in `source`, aligned
    /// with what `split` produces.
    private static func unitSpans(_ source: String, kind: ChunkKind, itemDelimiter: String) -> [Range<Int>] {
        let characters = Array(source)
        switch kind {
        case .character:
            return characters.indices.map { $0..<($0 + 1) }
        case .line:
            var spans: [Range<Int>] = []
            var start = 0
            for (offset, character) in characters.enumerated() where character == "\n" {
                spans.append(start..<offset)
                start = offset + 1
            }
            spans.append(start..<characters.count)
            return spans
        case .item:
            guard !itemDelimiter.isEmpty, let delimiter = itemDelimiter.first else { return [0..<characters.count] }
            var spans: [Range<Int>] = []
            var start = 0
            for (offset, character) in characters.enumerated() where character == delimiter {
                spans.append(start..<offset)
                start = offset + 1
            }
            spans.append(start..<characters.count)
            return spans
        case .word:
            // Mirror wordSplit: whitespace-separated, quoted spans one word.
            var spans: [Range<Int>] = []
            var start: Int? = nil
            var inQuotes = false
            for (offset, character) in characters.enumerated() {
                if character == "\"" {
                    inQuotes.toggle()
                    if start == nil { start = offset }
                } else if !inQuotes, character == " " || character == "\t" || character == "\n" {
                    if let s = start { spans.append(s..<offset); start = nil }
                } else if start == nil {
                    start = offset
                }
            }
            if let s = start { spans.append(s..<characters.count) }
            return spans
        }
    }

    // MARK: - Splitting

    private static func split(_ source: String, kind: ChunkKind, itemDelimiter: String) -> [String] {
        switch kind {
        case .character:
            return source.map(String.init)
        case .word:
            // Runs of whitespace separate words; empties dropped. As in
            // HyperCard, a double-quoted span is a single word (quotes kept):
            // word 2 of «stack "Graph Maker"» is «"Graph Maker"».
            return wordSplit(source)
        case .item:
            // Delimited by the itemDelimiter (comma by default); empties kept
            // (item 2 of "a,,c" is empty). An empty delimiter yields one item.
            // A TRAILING delimiter makes no final empty item — HyperCard counts
            // ",a,,b," as 4 items and `last item of "a,b,"` is b (oracle-
            // verified against HyperCard 2.3).
            guard !itemDelimiter.isEmpty else { return [source] }
            return dropTrailingEmpty(source.components(separatedBy: itemDelimiter))
        case .line:
            // Same trailing rule: `the number of lines in return` is 1.
            return dropTrailingEmpty(source.components(separatedBy: "\n"))
        }
    }

    /// HyperCard ignores the empty chunk a trailing delimiter would create
    /// (but keeps leading/middle empties, and "" still has zero chunks).
    private static func dropTrailingEmpty(_ parts: [String]) -> [String] {
        if parts.count > 1, parts.last == "" { return Array(parts.dropLast()) }
        return parts
    }

    /// Whitespace-separated words, where a double-quoted span (quotes
    /// included) is one word — HyperCard's word chunking.
    private static func wordSplit(_ source: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inQuotes = false
        for character in source {
            if character == "\"" {
                inQuotes.toggle()
                current.append(character)
            } else if !inQuotes, character == " " || character == "\t" || character == "\n" {
                if !current.isEmpty { words.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func delimiter(_ kind: ChunkKind, itemDelimiter: String) -> String {
        switch kind {
        case .character: ""
        case .word: " "
        case .item: itemDelimiter
        case .line: "\n"
        }
    }

    // MARK: - Selector → 1-based inclusive [start, end]

    private static func bounds(
        _ selector: ChunkSelector,
        count: Int,
        evaluateIndex: (Expr) async throws -> Int
    ) async throws -> (start: Int, end: Int) {
        switch selector {
        case .index(let expression):
            let i = try await evaluateIndex(expression)
            return (i, i)
        case .range(let startExpression, let endExpression):
            let a = try await evaluateIndex(startExpression)
            let b = try await evaluateIndex(endExpression)
            return (min(a, b), max(a, b))
        case .last:
            return (count, count)
        case .middle:
            let m = count == 0 ? 0 : (count + 1) / 2
            return (m, m)
        case .any:
            let i = count == 0 ? 0 : Int.random(in: 1...count)
            return (i, i)
        }
    }
}
