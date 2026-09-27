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
            guard !itemDelimiter.isEmpty else { return [source] }
            return source.components(separatedBy: itemDelimiter)
        case .line:
            return source.components(separatedBy: "\n")
        }
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
        }
    }
}
