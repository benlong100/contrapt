//
//  HyperTalkArray.swift
//  HyperTalk
//
//  Associative arrays (keys → values), Contrapt's modern-HyperTalk addition
//  for structured data and JSON. The interpreter is "everything is text", so
//  an array is carried AS text in a reserved encoding: a sentinel prefix plus
//  an order-preserving JSON serialization of its key/value pairs. A value is
//  either a scalar string or (for nesting) another encoded array, so
//  `data["a"]["b"]` composes by decoding one level at a time.
//
//  The sentinel uses control characters that effectively never appear in real
//  stack text, so a plain string is never mistaken for an array. Arrays are
//  rendered as readable JSON whenever they reach a user-visible sink (a field,
//  the message box); variables keep the encoded form so arrays round-trip.
//

import Foundation

enum HyperTalkArray {
    /// Marks a string as an encoded array. Two C0 control chars + a tag —
    /// vanishingly unlikely in authored text or imported field contents.
    static let sentinel = "\u{01}\u{02}HTArr:"

    /// Whether `text` is an encoded associative array.
    static func isArray(_ text: String) -> Bool { decode(text) != nil }

    /// Decode to ordered key/value pairs, or nil if `text` isn't an array.
    static func decode(_ text: String) -> [(key: String, value: String)]? {
        guard text.hasPrefix(sentinel) else { return nil }
        let json = String(text.dropFirst(sentinel.count))
        guard let data = json.data(using: .utf8),
              let rows = try? JSONDecoder().decode([[String]].self, from: data) else { return nil }
        return rows.compactMap { $0.count == 2 ? (key: $0[0], value: $0[1]) : nil }
    }

    /// Encode ordered pairs into an array string.
    static func encode(_ pairs: [(key: String, value: String)]) -> String {
        let rows = pairs.map { [$0.key, $0.value] }
        guard let data = try? JSONEncoder().encode(rows),
              let json = String(data: data, encoding: .utf8) else { return sentinel + "[]" }
        return sentinel + json
    }

    /// The value for `key` (empty string when absent or `text` isn't an array).
    static func value(forKey key: String, in text: String) -> String {
        decode(text)?.first { $0.key == key }?.value ?? ""
    }

    /// `text` with `key` set to `value` — appending if new, replacing in place
    /// if present. A non-array `text` starts a fresh array (auto-vivify), so
    /// `put x into a["k"]` just works on an unset variable.
    static func setting(key: String, to value: String, in text: String) -> String {
        var pairs = decode(text) ?? []
        if let i = pairs.firstIndex(where: { $0.key == key }) {
            pairs[i].value = value
        } else {
            pairs.append((key: key, value: value))
        }
        return encode(pairs)
    }

    /// The keys, one per line (HyperCard's return-delimited list form).
    static func keys(of text: String) -> [String] { decode(text)?.map(\.key) ?? [] }

    /// The number of top-level elements.
    static func count(of text: String) -> Int { decode(text)?.count ?? 0 }

    /// A readable JSON rendering, for display when an array reaches a field or
    /// the message box. Nested arrays render as nested objects; a scalar that
    /// looks like a number is emitted unquoted. Non-arrays pass through.
    static func displayJSON(_ text: String, indent: Int = 0) -> String {
        guard let pairs = decode(text) else { return text }
        let pad = String(repeating: "  ", count: indent + 1)
        let closePad = String(repeating: "  ", count: indent)
        if pairs.isEmpty { return "{}" }
        let body = pairs.map { pair -> String in
            let rendered = isArray(pair.value) ? displayJSON(pair.value, indent: indent + 1) : jsonScalar(pair.value)
            return "\(pad)\(jsonString(pair.key)): \(rendered)"
        }.joined(separator: ",\n")
        return "{\n\(body)\n\(closePad)}"
    }

    /// A scalar as JSON: a canonical number unquoted, otherwise a quoted string.
    private static func jsonScalar(_ text: String) -> String {
        if let n = Double(text), Value.string(from: n) == text { return text }
        return jsonString(text)
    }

    /// `text` as a JSON string literal (escaped and quoted).
    private static func jsonString(_ text: String) -> String {
        if let data = try? JSONEncoder().encode(text), let s = String(data: data, encoding: .utf8) { return s }
        return "\"\""
    }
}
