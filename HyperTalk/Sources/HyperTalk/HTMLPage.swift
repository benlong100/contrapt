//
//  HTMLPage.swift
//  HyperTalk
//
//  Readers behind `the title of url "…"`, `the text of url "…"`, and
//  `the links of url "…"` (Contrapt web gathering). A deliberately small
//  HTML reader, not a browser: enough to pull the title, the readable
//  text, and the links out of real-world pages. Pure Foundation — and
//  stdlib Regex throughout, NOT NSRegularExpression: Foundation's regex
//  drags the ICU data blob into the wasm engine, doubling its size.
//

import Foundation

nonisolated enum HTMLPage {

    /// The `<title>` tag's text — entities decoded, whitespace collapsed.
    /// Empty when the page has no title.
    static func title(of html: String) -> String {
        guard let match = html.firstMatch(of: #/(?is)<title\b[^>]*>(.*?)</title>/#) else { return "" }
        return decodeEntities(String(match.output.1))
            .replacing(#/\s+/#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The page's readable text: scripts, styles, and head chrome removed;
    /// block elements become line breaks; tags stripped; entities decoded.
    static func text(of html: String) -> String {
        var work = html
        // Comments and the invisible machinery first, so their contents
        // never leak into the text.
        work = work.replacing(#/(?s)<!--.*?-->/#, with: "")
        for container in ["script", "style", "head", "noscript", "template", "svg"] {
            if let regex = try? Regex("(?is)<\(container)\\b[^>]*>.*?</\(container)>") {
                work = work.replacing(regex, with: "")
            }
        }
        // Block-level boundaries read as line breaks, so paragraphs and
        // list items stay separate once the tags are gone.
        work = work.replacing(
            #/(?i)</?(?:p|div|br|li|ul|ol|tr|td|th|table|h[1-6]|section|article|header|footer|blockquote|pre|figure|figcaption|dl|dt|dd|hr|nav|aside|main|form|option|select)\b[^>]*>/#,
            with: "\n")
        work = work.replacing(#/(?s)<[^>]+>/#, with: "")
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
        let anchor = #/(?is)<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/#
        let baseURL = URL(string: base)
        var seen = Set<String>()
        var found: [String] = []
        for match in html.matches(of: anchor) {
            let raw = match.output.1 ?? match.output.2 ?? match.output.3 ?? ""
            let href = decodeEntities(String(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, !href.hasPrefix("#") else { continue }
            let lowered = href.lowercased()
            guard !lowered.hasPrefix("javascript:"), !lowered.hasPrefix("mailto:"), !lowered.hasPrefix("data:") else { continue }
            let resolved = URL(string: href, relativeTo: baseURL)?.absoluteString ?? href
            guard resolved.lowercased().hasPrefix("http") else { continue }
            if seen.insert(resolved).inserted { found.append(resolved) }
        }
        return found
    }

    // MARK: - Helpers

    static func collapseSpaces(_ text: String) -> String {
        text.replacing(#/[ \t\r\u{00A0}]+/#, with: " ")
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
