//
//  MarkdownLinks.swift
//  HyperTalk
//
//  The logic behind `the link of <chunk> of field …` on RICH fields, whose
//  text is Markdown source. Setting a link wraps the chunk's characters as
//  [label](target); a chunk already inside a link retargets that link; an
//  empty target unwraps it. Pure text — shared by the app and web hosts.
//

import Foundation

nonisolated public enum MarkdownLinks {

    /// The link target covering `range` (character offsets), or "" when the
    /// range doesn't touch a [label](target) span.
    public static func link(in source: String, at range: Range<Int>) -> String {
        let clamped = clamp(range, to: source)
        return spans(in: source).first { overlaps($0.full, clamped) }?.target ?? ""
    }

    /// `source` with the link over `range` set to `target`:
    /// - range inside an existing [label](target) → that link retargets
    ///   (empty target unwraps it, keeping the label text);
    /// - otherwise the range's characters become [them](target)
    ///   (empty target, or an empty range, changes nothing).
    public static func settingLink(in source: String, range: Range<Int>, to target: String) -> String {
        let clamped = clamp(range, to: source)
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if let span = spans(in: source).first(where: { overlaps($0.full, clamped) }) {
            let replacement = trimmed.isEmpty ? span.label : "[\(span.label)](\(trimmed))"
            return replacing(source, span.full, with: replacement)
        }
        guard !trimmed.isEmpty, clamped.lowerBound < clamped.upperBound else { return source }
        let label = substring(source, clamped)
        return replacing(source, clamped, with: "[\(label)](\(trimmed))")
    }

    // MARK: - Spans

    /// Every [label](target) in `source`, as character-offset ranges.
    static func spans(in source: String) -> [(full: Range<Int>, label: String, target: String)] {
        guard let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)") else { return [] }
        let nsRange = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: nsRange).compactMap { match in
            guard let full = Range(match.range, in: source),
                  let label = Range(match.range(at: 1), in: source),
                  let target = Range(match.range(at: 2), in: source) else { return nil }
            let lo = source.distance(from: source.startIndex, to: full.lowerBound)
            let hi = source.distance(from: source.startIndex, to: full.upperBound)
            return (full: lo..<hi, label: String(source[label]), target: String(source[target]))
        }
    }

    // MARK: - Character-offset helpers

    private static func clamp(_ range: Range<Int>, to source: String) -> Range<Int> {
        let count = source.count
        let lo = max(0, min(range.lowerBound, count))
        return lo..<max(lo, min(range.upperBound, count))
    }

    private static func overlaps(_ a: Range<Int>, _ b: Range<Int>) -> Bool {
        a.lowerBound < b.upperBound && b.lowerBound < a.upperBound
    }

    private static func substring(_ source: String, _ range: Range<Int>) -> String {
        let lo = source.index(source.startIndex, offsetBy: range.lowerBound)
        let hi = source.index(source.startIndex, offsetBy: range.upperBound)
        return String(source[lo..<hi])
    }

    private static func replacing(_ source: String, _ range: Range<Int>, with text: String) -> String {
        let lo = source.index(source.startIndex, offsetBy: range.lowerBound)
        let hi = source.index(source.startIndex, offsetBy: range.upperBound)
        return source.replacingCharacters(in: lo..<hi, with: text)
    }
}
