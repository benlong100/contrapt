//
//  FieldClickHitTest.swift
//  Contrapt
//
//  Which hard line (and word) of a locked field's text a click landed on —
//  the `clickLine`/`clickText` behind HyperCard's classic list-field
//  navigation (click a line, the script goes there). Lays the text out with
//  CoreText the way the field renders it (same font, width, wrapping), finds
//  the visual line under the click, and maps it back to the return-delimited
//  HyperTalk line number.
//

import Foundation
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum FieldClickHitTest {
    /// The 1-based hard-line number and the word under `location` (a point in
    /// the field's inner text box). `wraps` is false for preformatted text
    /// (the field renders it unwrapped and clips, so the layout must too).
    static func hit(in text: String, at location: CGPoint, textWidth: CGFloat,
                    format: TextFormat, wraps: Bool, textHeight: Double? = nil,
                    styleRuns: [StyleRun] = []) -> (line: Int, text: String) {
        guard !text.isEmpty else { return (1, "") }
        let (lines, origins, layoutWidth, pathHeight) = layout(text, textWidth: textWidth, format: format, wraps: wraps, textHeight: textHeight)
        guard !lines.isEmpty else { return (1, "") }

        // Find the visual line whose band contains the click's y (top-down;
        // clicks past the last line clamp to it, as HyperCard does).
        var lineIndex = lines.count - 1
        for (index, line) in lines.enumerated() {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let baselineFromTop = pathHeight - origins[index].y
            if location.y <= baselineFromTop + descent + leading {
                lineIndex = index
                break
            }
        }
        let line = lines[lineIndex]
        let range = CTLineGetStringRange(line)

        // Visual line → hard (return-delimited) line: count the newlines
        // before this line's first character.
        let nsText = text as NSString
        var hardLine = 1
        for i in 0..<range.location where nsText.character(at: i) == 0x0A { hardLine += 1 }

        // The word under the click's x, honoring the line's flush (alignment).
        let flush: CGFloat = switch format.align {
        case .center: 0.5
        case .right: 1
        default: 0
        }
        let penOffset = CGFloat(CTLineGetPenOffsetForFlush(line, flush, Double(layoutWidth)))
        let index = CTLineGetStringIndexForPosition(line, CGPoint(x: location.x - penOffset, y: 0))
        let grouped = groupedMask(text: nsText, format: format, styleRuns: styleRuns)
        return (hardLine, clickedText(in: nsText, around: index, lineRange: range, grouped: grouped))
    }

    /// Lays `text` out the way the field renders it (same font, width,
    /// wrapping, line-height grid) — the shared machinery behind click
    /// hit-testing and the find box.
    private static func layout(_ text: String, textWidth: CGFloat, format: TextFormat,
                               wraps: Bool, textHeight: Double?) -> (lines: [CTLine], origins: [CGPoint], layoutWidth: CGFloat, pathHeight: CGFloat) {
        let font = platformFont(for: format)
        let paragraph = NSMutableParagraphStyle()
        if let textHeight {
            paragraph.minimumLineHeight = textHeight
            paragraph.maximumLineHeight = textHeight
        }
        paragraph.alignment = switch format.align {
        case .center: .center
        case .right: .right
        default: .left
        }
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: paragraph,
        ])
        let layoutWidth = wraps ? max(10, textWidth) : 100_000
        let pathHeight: CGFloat = 1_000_000
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: layoutWidth, height: pathHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else {
            return ([], [], layoutWidth, pathHeight)
        }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        return (lines, origins, layoutWidth, pathHeight)
    }

    /// The bounding box of a character range in the laid-out text — the find
    /// box around the exact matched substring, in the field's inner text-box
    /// coordinates (top-left origin). A match spanning a soft wrap boxes its
    /// first line's segment. Nil when the range is empty or out of bounds.
    static func matchRect(of range: Range<Int>, in text: String, textWidth: CGFloat,
                          format: TextFormat, wraps: Bool, textHeight: Double? = nil) -> CGRect? {
        let characters = Array(text)
        guard range.lowerBound >= 0, range.lowerBound < range.upperBound,
              range.upperBound <= characters.count else { return nil }
        // Character offsets (FindMatcher's coin) → utf16 (CoreText's).
        let startUTF16 = String(characters[0..<range.lowerBound]).utf16.count
        let endUTF16 = startUTF16 + String(characters[range.lowerBound..<range.upperBound]).utf16.count

        let (lines, origins, layoutWidth, pathHeight) = layout(text, textWidth: textWidth, format: format, wraps: wraps, textHeight: textHeight)
        guard let lineIndex = lines.firstIndex(where: { line in
            let lineRange = CTLineGetStringRange(line)
            return startUTF16 >= lineRange.location && startUTF16 < lineRange.location + max(1, lineRange.length)
        }) else { return nil }

        let line = lines[lineIndex]
        let lineRange = CTLineGetStringRange(line)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let flush: CGFloat = switch format.align {
        case .center: 0.5
        case .right: 1
        default: 0
        }
        let penOffset = CGFloat(CTLineGetPenOffsetForFlush(line, flush, Double(layoutWidth)))
        let clampedEnd = min(endUTF16, lineRange.location + lineRange.length)
        let xStart = CTLineGetOffsetForStringIndex(line, startUTF16, nil) + penOffset
        let xEnd = CTLineGetOffsetForStringIndex(line, clampedEnd, nil) + penOffset
        let baselineFromTop = pathHeight - origins[lineIndex].y
        return CGRect(x: min(xStart, xEnd),
                      y: baselineFromTop - ascent,
                      width: max(1, abs(xEnd - xStart)),
                      height: ascent + descent)
    }

    /// A per-UTF-16-index flag of whether each character is in a grouped run
    /// (HyperCard's group text style). Built from the style runs — each char
    /// takes the group state of the run covering it, falling back to the
    /// field's base format where no run does. Empty style runs + ungrouped base
    /// yield an all-false mask, so ungrouped fields cost nothing.
    private static func groupedMask(text: NSString, format: TextFormat, styleRuns: [StyleRun]) -> [Bool] {
        let characters = Array(text as String)
        guard !characters.isEmpty else { return [] }
        // Group state per Character, seeded from the base format.
        var charGrouped = [Bool](repeating: format.isGroup, count: characters.count)
        for (index, run) in styleRuns.enumerated() {
            let lo = max(0, min(run.start, characters.count))
            let hi = index + 1 < styleRuns.count ? min(styleRuns[index + 1].start, characters.count) : characters.count
            guard hi > lo else { continue }
            for c in lo..<hi { charGrouped[c] = run.format.isGroup }
        }
        // Expand to UTF-16 indices (CoreText's coin), since a Character can be
        // more than one UTF-16 unit.
        var mask = [Bool]()
        mask.reserveCapacity(text.length)
        for (c, character) in characters.enumerated() {
            for _ in 0..<String(character).utf16.count { mask.append(charGrouped[c]) }
        }
        return mask
    }

    /// The text `the clickText` reports for a click at utf16 `index`: the whole
    /// contiguous grouped run when the click lands on grouped text (stopping at
    /// a line break or the first ungrouped character), otherwise the single
    /// word. The grouped run may span soft wraps, so it isn't confined to the
    /// clicked visual line the way the word fallback is.
    private static func clickedText(in text: NSString, around index: Int, lineRange: CFRange, grouped: [Bool]) -> String {
        guard lineRange.length > 0 else { return "" }
        let lineEnd = lineRange.location + lineRange.length
        let i = min(max(index, lineRange.location), lineEnd - 1)
        func isNewline(_ at: Int) -> Bool { text.character(at: at) == 0x0A }
        if i < grouped.count, grouped[i], !isNewline(i) {
            var start = i, end = i + 1
            while start > 0, grouped[start - 1], !isNewline(start - 1) { start -= 1 }
            while end < text.length, end < grouped.count, grouped[end], !isNewline(end) { end += 1 }
            return text.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return word(in: text, around: index, lineRange: lineRange)
    }

    /// The whitespace-delimited word containing utf16 `index` (clamped into
    /// the clicked line, so a click past a line's end yields its last word).
    private static func word(in text: NSString, around index: Int, lineRange: CFRange) -> String {
        guard lineRange.length > 0 else { return "" }
        let lineEnd = lineRange.location + lineRange.length
        var i = min(max(index, lineRange.location), lineEnd - 1)
        func isSpace(_ at: Int) -> Bool {
            let c = text.character(at: at)
            return c == 0x20 || c == 0x0A || c == 0x09 || c == 0x0D
        }
        // A click on whitespace binds to the word before it.
        while i > lineRange.location, isSpace(i) { i -= 1 }
        if isSpace(i) { return "" }
        var start = i, end = i + 1
        while start > lineRange.location, !isSpace(start - 1) { start -= 1 }
        while end < lineEnd, !isSpace(end) { end += 1 }
        return text.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The platform font matching how the field's SwiftUI Text renders.
    static func platformFont(for format: TextFormat) -> PlatformFont {
        let size = CGFloat(format.size)
        // An embedded outline font (the stack's own TrueType) renders its real
        // glyphs — lay the same text out with it, matching TextFormat.font.
        if let name = format.embeddedFontName, let embedded = PlatformFont(name: name, size: size) {
            return embedded
        }
        // Serif is real Palatino (see TextFormat.font) — classic-stack line
        // breaks depend on its metrics; the system serif runs wider.
        if format.fontDesign == .serif, let palatino = palatinoFont(size: size, bold: format.isBold, italic: format.isItalic) {
            return palatino
        }
        let base = PlatformFont.systemFont(ofSize: size, weight: format.isBold ? .bold : .regular)
        let design: PlatformFontDescriptor.SystemDesign = switch format.fontDesign {
        case .serif: .serif
        case .monospaced: .monospaced
        case .rounded: .rounded
        default: .default
        }
        #if canImport(UIKit)
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
        #else
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
        #endif
    }

    /// Palatino with the requested traits, or nil if the family is missing
    /// (then the system serif stands in).
    private static func palatinoFont(size: CGFloat, bold: Bool, italic: Bool) -> PlatformFont? {
        #if canImport(UIKit)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        var descriptor = UIFontDescriptor(fontAttributes: [.family: "Palatino"])
        if !traits.isEmpty, let adjusted = descriptor.withSymbolicTraits(traits) {
            descriptor = adjusted
        }
        let font = UIFont(descriptor: descriptor, size: size)
        return font.familyName.hasPrefix("Palatino") ? font : nil
        #else
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        var descriptor = NSFontDescriptor(fontAttributes: [.family: "Palatino"])
        if !traits.isEmpty { descriptor = descriptor.withSymbolicTraits(traits) }
        guard let font = NSFont(descriptor: descriptor, size: size),
              font.familyName?.hasPrefix("Palatino") == true else { return nil }
        return font
        #endif
    }
}

#if canImport(UIKit)
typealias PlatformFont = UIFont
typealias PlatformFontDescriptor = UIFontDescriptor
#else
typealias PlatformFont = NSFont
typealias PlatformFontDescriptor = NSFontDescriptor
#endif
