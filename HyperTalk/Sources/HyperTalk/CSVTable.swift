//
//  CSVTable.swift
//  HyperTalk
//
//  The reader behind `CSVItems(url "…")` (Contrapt web gathering): comma-
//  separated tables parsed into the associative-array form — the header row
//  names the keys, every following row becomes one element. The same shape
//  `FeedItems` produces and `make a card for each element` fills fields from.
//

import Foundation

nonisolated enum CSVTable {

    /// Parse CSV text into an encoded array: elements keyed 1…n, one per data
    /// row, each keyed by the header row's column names (a blank header reads
    /// as "column N"). Quoted fields carry commas, newlines, and `""` quotes,
    /// per the usual CSV rules. A table with no data rows yields no elements.
    static func items(_ text: String) -> String {
        let rows = parse(text)
        guard rows.count > 1 else { return HyperTalkArray.encode([]) }
        var headers: [String] = []
        for (index, raw) in rows[0].enumerated() {
            let name = raw.trimmingCharacters(in: .whitespaces)
            var header = name.isEmpty ? "column \(index + 1)" : name
            // A duplicate header would shadow its twin as an array key.
            if headers.contains(where: { $0.caseInsensitiveCompare(header) == .orderedSame }) {
                header = "\(header) \(index + 1)"
            }
            headers.append(header)
        }
        let elements = rows.dropFirst().enumerated().map { index, row in
            (key: String(index + 1), value: HyperTalkArray.encode(
                headers.enumerated().map { column, header in
                    (key: header, value: column < row.count ? row[column] : "")
                }))
        }
        return HyperTalkArray.encode(elements)
    }

    /// The raw grid. Handles quoted fields (embedded commas/newlines/`""`),
    /// both LF and CRLF row ends, and ignores a trailing empty line.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex
        func endField() { row.append(field); field = "" }
        func endRow() { endField(); rows.append(row); row = [] }
        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"") // "" — an escaped quote
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"": inQuotes = true
                case ",": endField()
                // "\r\n" is ONE Character in Swift (a grapheme cluster), so
                // CRLF matches as itself, not as "\r" then "\n".
                case "\r\n", "\r", "\n": endRow()
                default: field.append(character)
                }
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
