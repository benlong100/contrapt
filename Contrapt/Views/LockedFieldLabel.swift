//
//  LockedFieldLabel.swift
//  Contrapt
//
//  A locked field's text at an exact line height — HyperCard's per-field
//  textHeight, which SwiftUI's Text can't honor (it never renders lines
//  shorter than the font's natural height, and .lineSpacing only adds).
//  Imported stacks depend on it: the Tour packs 12 lines of 18pt Palatino
//  into a 250px field at textHeight 20.
//
//  A plain label (never first responder), so the SwiftUI wrapper's gestures
//  and contentShape keep handling clicks.
//

import SwiftUI

struct LockedFieldLabel {
    var text: String
    var format: TextFormat
    /// Exact line height in points.
    var textHeight: Double
    /// Don't wrap (preformatted/tabular text) — long lines clip.
    var preformatted: Bool
    /// A character range to show inverted (find box / script selection).
    var highlightRange: Range<Int>?
    /// Per-run styling (HyperCard styled text); empty = uniform `format`.
    var styleRuns: [StyleRun] = []

    /// Font/underline/outline/foreground for one run's format — everything
    /// except the whole-string paragraph style and baseline lift.
    private func glyphAttributes(_ format: TextFormat) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: FieldClickHitTest.platformFont(for: format),
            .foregroundColor: PlatformColor.labelColor,
            .underlineStyle: format.isUnderline ? NSUnderlineStyle.single.rawValue : 0,
        ]
        if format.isOutline {
            // HyperCard's outline style: white interiors, black stroke — how
            // the Tour draws white titles over its black paint bars.
            attributes[.foregroundColor] = PlatformColor.white
            attributes[.strokeColor] = PlatformColor.black
            attributes[.strokeWidth] = -2.5
        }
        return attributes
    }

    fileprivate func attributedText() -> NSAttributedString {
        let font = FieldClickHitTest.platformFont(for: format)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = textHeight
        paragraph.maximumLineHeight = textHeight
        // TextKit seats glyphs at the BOTTOM of a fixed line box (baseline =
        // height - descent); QuickDraw seated them at the TOP (baseline =
        // ascent). When the box is taller than the font's natural height,
        // lift the text by the difference so titles sit like HyperCard's.
        let naturalHeight = font.ascender - font.descender + font.leading
        let baselineLift = max(0, textHeight - naturalHeight)
        paragraph.lineBreakMode = preformatted ? .byClipping : .byWordWrapping
        paragraph.alignment = switch format.align {
        case .center: .center
        case .right: .right
        default: .left
        }
        // Whole-string base: the field's format plus paragraph + baseline.
        var attributes = glyphAttributes(format)
        attributes[.paragraphStyle] = paragraph
        if baselineLift > 0 { attributes[.baselineOffset] = baselineLift }
        let attributed = NSMutableAttributedString(string: text, attributes: attributes)

        // Styled text: overlay each run's glyph attributes on its span. Stroke
        // keys are cleared first so a non-outline run drops the base's outline.
        if !styleRuns.isEmpty {
            let characters = Array(text)
            for (index, run) in styleRuns.enumerated() {
                let lo = max(0, min(run.start, characters.count))
                let hi = index + 1 < styleRuns.count ? min(styleRuns[index + 1].start, characters.count) : characters.count
                guard hi > lo else { continue }
                let utf16Start = String(characters[0..<lo]).utf16.count
                let utf16Length = String(characters[lo..<hi]).utf16.count
                let nsRange = NSRange(location: utf16Start, length: utf16Length)
                attributed.removeAttribute(.strokeColor, range: nsRange)
                attributed.removeAttribute(.strokeWidth, range: nsRange)
                attributed.addAttributes(glyphAttributes(run.format), range: nsRange)
            }
        }
        if let range = highlightRange {
            // Clamp character offsets into the string and invert the span.
            let characters = Array(text)
            let lo = max(0, min(range.lowerBound, characters.count))
            let hi = max(lo, min(range.upperBound, characters.count))
            if hi > lo {
                let utf16Start = String(characters[0..<lo]).utf16.count
                let utf16Length = String(characters[lo..<hi]).utf16.count
                let nsRange = NSRange(location: utf16Start, length: utf16Length)
                attributed.addAttribute(.backgroundColor, value: PlatformColor.labelColor, range: nsRange)
                attributed.addAttribute(.foregroundColor, value: PlatformColor.textBackground, range: nsRange)
            }
        }
        return attributed
    }
}

#if canImport(AppKit)
extension PlatformColor {
    static var textBackground: NSColor { .textBackgroundColor }
}

extension LockedFieldLabel: NSViewRepresentable {
    func makeNSView(context: Context) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.isSelectable = false
        label.drawsBackground = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return label
    }

    func updateNSView(_ label: NSTextField, context: Context) {
        label.attributedStringValue = attributedText()
        label.lineBreakMode = preformatted ? .byClipping : .byWordWrapping
    }
}

typealias PlatformColor = NSColor
#else
extension PlatformColor {
    static var labelColor: UIColor { .label }
    static var textBackground: UIColor { .systemBackground }
}

extension LockedFieldLabel: UIViewRepresentable {
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = attributedText()
        label.lineBreakMode = preformatted ? .byClipping : .byWordWrapping
    }
}

typealias PlatformColor = UIColor
#endif
