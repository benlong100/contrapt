//
//  MarkdownHTML.swift
//  Contrapt
//

import Foundation

/// Converts a rich field's Markdown source into a self-contained HTML
/// document for display in a `WKWebView`.
///
/// Privacy/sandbox (D7): the output contains **only** text formatting and
/// `<a>` links — never `<img>`, `<script>`, `<iframe>`, or any remote
/// reference — so the web view has nothing to fetch. Image syntax renders as
/// its alt text. Links don't load in place; the navigation delegate opens
/// card links via `go` and web links in the system browser, on tap only.
enum MarkdownHTML {
    /// A full HTML document (styling inlined) rendering `markdown`, using the
    /// field's base font design and size. Headings and other elements scale
    /// relative to that base.
    /// `linkColor` is a CSS color (a #RRGGBB hex or a name) for `<a>` links —
    /// the card's highlight; nil keeps the system link blue.
    static func document(from markdown: String, fontDesign: FontDesign = .standard, size: Double = 17, linkColor: String? = nil) -> String {
        let body = renderBlocks(markdown)
        return """
        <!DOCTYPE html>
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css(fontFamily: fontFamily(fontDesign), size: size, linkColor: linkColor))</style></head>
        <body>\(body)</body></html>
        """
    }

    /// A CSS font-family stack for each design.
    private static func fontFamily(_ design: FontDesign) -> String {
        switch design {
        case .standard: "-apple-system, system-ui, sans-serif"
        case .serif: "ui-serif, Georgia, 'Times New Roman', serif"
        case .monospaced: "ui-monospace, 'SF Mono', Menlo, monospace"
        case .rounded: "ui-rounded, -apple-system, system-ui, sans-serif"
        }
    }

    // MARK: - Block structure

    private static func renderBlocks(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var html = ""
        var index = 0

        func isBlank(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).isEmpty }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if isBlank(line) { index += 1; continue }

            // Fenced code block: ``` … ```
            if trimmed.hasPrefix("```") {
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(escape(lines[index]))
                    index += 1
                }
                if index < lines.count { index += 1 } // closing fence
                html += "<pre><code>\(code.joined(separator: "\n"))</code></pre>"
                continue
            }

            // Horizontal rule.
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                html += "<hr>"
                index += 1
                continue
            }

            // ATX heading: #… ######
            if let heading = headingLevel(trimmed) {
                let content = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                html += "<h\(heading)>\(inline(content))</h\(heading)>"
                index += 1
                continue
            }

            // Blockquote: consecutive `> …` lines.
            if trimmed.hasPrefix(">") {
                var quote: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let stripped = lines[index].trimmingCharacters(in: .whitespaces).dropFirst()
                    quote.append(inline(stripped.trimmingCharacters(in: .whitespaces)))
                    index += 1
                }
                html += "<blockquote>\(quote.joined(separator: "<br>"))</blockquote>"
                continue
            }

            // Unordered list: -, *, + markers.
            if isUnorderedItem(trimmed) {
                var items: [String] = []
                while index < lines.count, isUnorderedItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    let content = String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst(2))
                    items.append("<li>\(inline(content))</li>")
                    index += 1
                }
                html += "<ul>\(items.joined())</ul>"
                continue
            }

            // Ordered list: 1. 2. …
            if isOrderedItem(trimmed) {
                var items: [String] = []
                while index < lines.count, isOrderedItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    let itemLine = lines[index].trimmingCharacters(in: .whitespaces)
                    let content = String(itemLine[(itemLine.firstIndex(of: ".")!)...].dropFirst()).trimmingCharacters(in: .whitespaces)
                    items.append("<li>\(inline(content))</li>")
                    index += 1
                }
                html += "<ol>\(items.joined())</ol>"
                continue
            }

            // Paragraph: consecutive non-blank, non-block lines.
            var paragraph: [String] = []
            while index < lines.count, !isBlank(lines[index]),
                  headingLevel(lines[index].trimmingCharacters(in: .whitespaces)) == nil,
                  !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">"),
                  !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```"),
                  !isUnorderedItem(lines[index].trimmingCharacters(in: .whitespaces)),
                  !isOrderedItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                paragraph.append(inline(lines[index].trimmingCharacters(in: .whitespaces)))
                index += 1
            }
            if !paragraph.isEmpty {
                html += "<p>\(paragraph.joined(separator: "<br>"))</p>"
            }
        }
        return html
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func isUnorderedItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func isOrderedItem(_ line: String) -> Bool {
        guard let dot = line.firstIndex(of: ".") else { return false }
        let digits = line[line.startIndex..<dot]
        return !digits.isEmpty && digits.allSatisfy(\.isNumber) && line[dot...].dropFirst().first == " "
    }

    // MARK: - Inline

    /// Inline formatting: code spans, links, bold, italic. Images render as
    /// their alt text (no `<img>`; nothing to fetch).
    private static func inline(_ text: String) -> String {
        var result = escape(text)

        // Protect code spans so their contents aren't further formatted.
        var codeSpans: [String] = []
        result = replace(result, #"`([^`]+)`"#) { groups in
            codeSpans.append(groups[1])
            return "\u{0}CODE\(codeSpans.count - 1)\u{0}"
        }

        // Images -> alt text (drop the remote reference entirely).
        result = replace(result, #"!\[([^\]]*)\]\([^)]*\)"#) { groups in groups[1] }

        // Links [text](url).
        result = replace(result, #"\[([^\]]+)\]\(([^)]+)\)"#) { groups in
            "<a href=\"\(attribute(groups[2]))\">\(groups[1])</a>"
        }

        // Bold then italic (bold first so ** isn't eaten by *).
        result = replace(result, #"\*\*(.+?)\*\*"#) { "<strong>\($0[1])</strong>" }
        result = replace(result, #"__(.+?)__"#) { "<strong>\($0[1])</strong>" }
        result = replace(result, #"\*(.+?)\*"#) { "<em>\($0[1])</em>" }
        result = replace(result, #"(?<![A-Za-z0-9])_(.+?)_(?![A-Za-z0-9])"#) { "<em>\($0[1])</em>" }

        // Restore code spans.
        for (i, span) in codeSpans.enumerated() {
            result = result.replacingOccurrences(of: "\u{0}CODE\(i)\u{0}", with: "<code>\(span)</code>")
        }
        return result
    }

    /// Applies `transform` to every match of `pattern`; groups[0] is the whole
    /// match, groups[1...] the captures.
    private static func replace(_ text: String, _ pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                let r = match.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            result += transform(groups)
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Escapes a string for use inside a double-quoted HTML attribute.
    private static func attribute(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func css(fontFamily: String, size: Double, linkColor: String? = nil) -> String {
        let link = linkColor ?? "-apple-system-blue"
        return """
    :root { color-scheme: light dark; }
    body {
        font-family: \(fontFamily);
        font-size: \(Int(size.rounded()))px;
        margin: 12px; line-height: 1.45;
        -webkit-text-size-adjust: 100%;
    }
    h1, h2, h3, h4, h5, h6 { line-height: 1.2; margin: 0.6em 0 0.3em; }
    h1 { font-size: 1.7em; } h2 { font-size: 1.4em; } h3 { font-size: 1.2em; }
    p { margin: 0.5em 0; }
    a { color: \(link); }
    code { font-family: ui-monospace, monospace; font-size: 0.9em; background: rgba(127,127,127,0.15); padding: 0.1em 0.3em; border-radius: 4px; }
    pre { background: rgba(127,127,127,0.12); padding: 10px; border-radius: 8px; overflow-x: auto; }
    pre code { background: none; padding: 0; }
    blockquote { margin: 0.5em 0; padding-left: 12px; border-left: 3px solid rgba(127,127,127,0.4); color: rgba(127,127,127,1); }
    ul, ol { margin: 0.5em 0; padding-left: 1.4em; }
    hr { border: none; border-top: 1px solid rgba(127,127,127,0.3); margin: 1em 0; }
    """
    }
}
