//
//  WebFeed.swift
//  HyperTalk
//
//  The reader behind `FeedItems(url "…")` (Contrapt web gathering): RSS 2.0
//  and Atom feeds parsed into the associative-array form, one element per
//  item with the keys title / link / date / text — exactly the shape
//  `make a card for each element` fills fields from. A deliberately small
//  reader, like HTMLPage: enough for real-world feeds, not a validator.
//

import Foundation

nonisolated enum WebFeed {

    /// Parse feed XML into an encoded array: elements keyed 1…n in feed
    /// order, each an array with keys `title`, `link`, `date`, `text`
    /// (absent parts read as empty). Input that isn't a feed yields an
    /// array with no elements.
    static func items(_ xml: String) -> String {
        let blocks = itemBlocks(xml)
        let pairs = blocks.enumerated().map { index, block in
            (key: String(index + 1), value: item(block))
        }
        return HyperTalkArray.encode(pairs)
    }

    // MARK: - Pieces

    /// The `<item>` (RSS) or `<entry>` (Atom) blocks, in feed order.
    private static func itemBlocks(_ xml: String) -> [String] {
        let rss = allMatches("(?is)<item\\b[^>]*>(.*?)</item>", in: xml)
        if !rss.isEmpty { return rss }
        return allMatches("(?is)<entry\\b[^>]*>(.*?)</entry>", in: xml)
    }

    /// One item's fields as an encoded array.
    private static func item(_ block: String) -> String {
        let title = plainText(firstTag(["title"], in: block))
        let date = plainText(firstTag(["pubDate", "published", "updated", "dc:date"], in: block))
        // The body is often HTML (or HTML inside CDATA) — read it the same
        // way `the text of url` reads a page.
        let body = HTMLPage.text(of: unwrapCDATA(firstTag(
            ["description", "summary", "content:encoded", "content"], in: block)))
        return HyperTalkArray.encode([
            (key: "title", value: title),
            (key: "link", value: link(in: block)),
            (key: "date", value: date),
            (key: "text", value: body),
        ])
    }

    /// RSS puts the URL in `<link>…</link>`; Atom in `<link href="…"/>`
    /// (prefer the alternate/plain one over self/edit links).
    private static func link(in block: String) -> String {
        let inline = plainText(firstTag(["link"], in: block))
        if !inline.isEmpty { return inline }
        let tags = allMatches("(?is)(<link\\b[^>]*>)", in: block)
        func href(_ tag: String) -> String {
            guard let url = firstMatch("(?is)\\bhref\\s*=\\s*\"([^\"]*)\"", in: tag) else { return "" }
            return HTMLPage.decodeEntities(url).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let preferred = tags.first(where: { tag in
            guard let rel = firstMatch("(?is)\\brel\\s*=\\s*\"([^\"]*)\"", in: tag) else { return true }
            return rel.lowercased() == "alternate"
        }) {
            return href(preferred)
        }
        return tags.first.map(href) ?? ""
    }

    /// A tag's inner text — the first of `names` that appears. Namespaced
    /// names (`content:encoded`) match literally.
    private static func firstTag(_ names: [String], in block: String) -> String {
        for name in names {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            if let inner = firstMatch("(?is)<\(escaped)\\b[^>]*>(.*?)</\(escaped)>", in: block) {
                return inner
            }
        }
        return ""
    }

    private static func plainText(_ raw: String) -> String {
        HTMLPage.decodeEntities(unwrapCDATA(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unwrapCDATA(_ text: String) -> String {
        text.replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
