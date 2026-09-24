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
        evaluateIndex: (Expr) throws -> Int
    ) rethrows -> String {
        // Characters operate on the raw string; other kinds split into units.
        if kind == .character {
            let characters = Array(source)
            let (start, end) = try bounds(selector, count: characters.count, evaluateIndex: evaluateIndex)
            guard start <= end, start >= 1, start <= characters.count else { return "" }
            let lo = max(1, start) - 1
            let hi = min(characters.count, end)
            return String(characters[lo..<hi])
        }

        let units = split(source, kind: kind)
        let (start, end) = try bounds(selector, count: units.count, evaluateIndex: evaluateIndex)
        guard start <= end, start >= 1, start <= units.count else { return "" }
        let lo = max(1, start) - 1
        let hi = min(units.count, end)
        return units[lo..<hi].joined(separator: delimiter(kind))
    }

    /// How many units of `kind` are in `source` (empty text has none).
    static func count(kind: ChunkKind, in source: String) -> Int {
        guard !source.isEmpty else { return 0 }
        return kind == .character ? source.count : split(source, kind: kind).count
    }

    // MARK: - Splitting

    private static func split(_ source: String, kind: ChunkKind) -> [String] {
        switch kind {
        case .character:
            return source.map(String.init)
        case .word:
            // Runs of whitespace separate words; empties dropped.
            return source.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        case .item:
            // Comma-delimited; empties kept (item 2 of "a,,c" is empty).
            return source.components(separatedBy: ",")
        case .line:
            return source.components(separatedBy: "\n")
        }
    }

    private static func delimiter(_ kind: ChunkKind) -> String {
        switch kind {
        case .character: ""
        case .word: " "
        case .item: ","
        case .line: "\n"
        }
    }

    // MARK: - Selector → 1-based inclusive [start, end]

    private static func bounds(
        _ selector: ChunkSelector,
        count: Int,
        evaluateIndex: (Expr) throws -> Int
    ) rethrows -> (start: Int, end: Int) {
        switch selector {
        case .index(let expression):
            let i = try evaluateIndex(expression)
            return (i, i)
        case .range(let startExpression, let endExpression):
            let a = try evaluateIndex(startExpression)
            let b = try evaluateIndex(endExpression)
            return (min(a, b), max(a, b))
        case .last:
            return (count, count)
        case .middle:
            let m = count == 0 ? 0 : (count + 1) / 2
            return (m, m)
        }
    }
}
