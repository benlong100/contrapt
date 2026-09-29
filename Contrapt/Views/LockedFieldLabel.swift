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

    fileprivate func attributedText() -> NSAttributedString {
        let font = FieldClickHitTest.platformFont(for: format)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = textHeight
        paragraph.maximumLineHeight = textHeight
        paragraph.lineBreakMode = preformatted ? .byClipping : .byWordWrapping
        paragraph.alignment = switch format.align {
        case .center: .center
        case .right: .right
        default: .left
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: PlatformColor.labelColor,
        ]
        if format.isUnderline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if format.isOutline {
            // HyperCard's outline style: white interiors, black stroke — how
            // the Tour draws white titles over its black paint bars.
            attributes[.foregroundColor] = PlatformColor.white
            attributes[.strokeColor] = PlatformColor.black
            attributes[.strokeWidth] = -2.5
        }
        let attributed = NSMutableAttributedString(string: text, attributes: attributes)
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
