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
                    format: TextFormat, wraps: Bool) -> (line: Int, text: String) {
        guard !text.isEmpty else { return (1, "") }

        let font = platformFont(for: format)
        let paragraph = NSMutableParagraphStyle()
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
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return (1, "") }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

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
        return (hardLine, word(in: nsText, around: index, lineRange: range))
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
    private static func platformFont(for format: TextFormat) -> PlatformFont {
        let size = CGFloat(format.size)
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
}

#if canImport(UIKit)
typealias PlatformFont = UIFont
typealias PlatformFontDescriptor = UIFontDescriptor
#else
typealias PlatformFont = NSFont
typealias PlatformFontDescriptor = NSFontDescriptor
#endif
