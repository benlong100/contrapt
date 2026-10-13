//
//  HTMLPage.swift
//  HyperTalk
//
//  Readers behind `the title of url "…"`, `the text of url "…"`, and
//  `the links of url "…"` (Contrapt web gathering). A deliberately small
//  HTML reader, not a browser: enough to pull the title, the readable
//  text, and the link targets out of real-world pages. Pure Foundation,
//  shared by the app and the web export.
//

import Foundation

nonisolated enum HTMLPage {

    /// The `<title>` tag's text — entities decoded, whitespace collapsed.
    /// Empty when the page has no title.
    static func title(of html: String) -> String {
        guard let match = firstMatch("(?is)<title\\b[^>]*>(.*?)</title>", in: html, group: 1) else { return "" }
        return decodeEntities(match)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The page's readable text: scripts, styles, and head chrome removed;
    /// block elements become line breaks; tags stripped; entities decoded.
    static func text(of html: String) -> String {
        var work = html
        // Comments and the invisible machinery first, so their contents
        // never leak into the text.
        work = remove("(?s)<!--.*?-->", from: work)
        for container in ["script", "style", "head", "noscript", "template", "svg"] {
            work = remove("(?is)<\(container)\\b[^>]*>.*?</\(container)>", from: work)
        }
        // Block-level boundaries read as line breaks, so paragraphs and
        // list items stay separate once the tags are gone.
        work = work.replacingOccurrences(
            of: "(?i)</?(p|div|br|li|ul|ol|tr|td|th|table|h[1-6]|section|article|header|footer|blockquote|pre|figure|figcaption|dl|dt|dd|hr|nav|aside|main|form|option|select)\\b[^>]*>",
            with: "\n", options: .regularExpression)
        work = remove("(?s)<[^>]+>", from: work)
        work = decodeEntities(work)
        // Tidy: collapse runs of spaces, trim each line, drop runs of
        // blank lines to a single separator.
        let lines = work.components(separatedBy: "\n")
            .map { collapseSpaces($0).trimmingCharacters(in: .whitespaces) }
        var output: [String] = []
        for line in lines {
            if line.isEmpty {
                if output.last?.isEmpty == false { output.append("") }
            } else {
                output.append(line)
            }
        }
        while output.last?.isEmpty == true { output.removeLast() }
        return output.joined(separator: "\n")
    }

    /// The page's link targets in order — `<a href>` values resolved against
    /// `base`, http(s) only, duplicates dropped after the first.
    static func links(of html: String, base: String) -> [String] {
        let pattern = "(?is)<a\\b[^>]*?\\bhref\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let baseURL = URL(string: base)
        var seen = Set<String>()
        var found: [String] = []
        let range = NSRange(html.startIndex..., in: html)
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match else { return }
            var href = ""
            for group in [2, 3, 4] {
                if let r = Range(match.range(at: group), in: html) { href = String(html[r]); break }
            }
            href = decodeEntities(href).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, !href.hasPrefix("#") else { return }
            let lowered = href.lowercased()
            guard !lowered.hasPrefix("javascript:"), !lowered.hasPrefix("mailto:"), !lowered.hasPrefix("data:") else { return }
            let resolved = URL(string: href, relativeTo: baseURL)?.absoluteString ?? href
            guard resolved.lowercased().hasPrefix("http") else { return }
            if seen.insert(resolved).inserted { found.append(resolved) }
        }
        return found
    }

    // MARK: - Helpers

    private static func firstMatch(_ pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    private static func remove(_ pattern: String, from text: String) -> String {
        text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func collapseSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "[ \\t\\r\u{00A0}]+", with: " ", options: .regularExpression)
    }

    /// The HTML entities seen in practice — the common named set plus
    /// numeric forms (`&#233;`, `&#x1F389;`). Unknown names pass through.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&" else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            // An entity runs to the next ";" within a short window.
            guard let end = text[index...].prefix(12).firstIndex(of: ";") else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let name = String(text[text.index(after: index)..<end])
            if let decoded = decodeEntity(name) {
                result.append(decoded)
                index = text.index(after: end)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result
    }

    private static func decodeEntity(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return Self.namedEntities[name]
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "copy": "©", "reg": "®", "trade": "™",
        "mdash": "—", "ndash": "–", "hellip": "…", "middot": "·", "bull": "•",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
        "laquo": "«", "raquo": "»", "deg": "°", "times": "×", "divide": "÷",
        "frac12": "½", "frac14": "¼", "frac34": "¾", "plusmn": "±",
        "eacute": "é", "egrave": "è", "agrave": "à", "ccedil": "ç",
        "ouml": "ö", "uuml": "ü", "auml": "ä", "szlig": "ß", "ntilde": "ñ",
    ]
}
