//
//  TextMetrics.swift
//  HyperTalk
//
//  Classic-Mac text measurement rules that modern layout doesn't share.
//
//  QuickDraw's TextEdit measured a centered or right-aligned line WITHOUT its
//  trailing spaces, so HyperCard authors space-padded text freely ("text:" plus
//  a run of spaces, centered, still sits centered on the words). SwiftUI and
//  AppKit measure those spaces, shoving the visible words half the pad's width
//  out of the field. Renderers strip the trailing run before layout — and remap
//  style-run/selection offsets through the returned map, since characters moved.
//

public enum TextMetrics {

    /// `text` with trailing spaces/tabs stripped from every line, plus a map
    /// from original character offsets to offsets in the stripped text (offsets
    /// inside a removed run clamp to that line's new end). Offsets count
    /// `Character`s, matching the style-run convention.
    public static func strippingTrailingLineWhitespace(
        _ text: String
    ) -> (text: String, remap: (Int) -> Int) {
        let characters = Array(text)
        var kept: [Character] = []
        kept.reserveCapacity(characters.count)
        // removedBefore[i] = how many of the first i original characters were
        // dropped — the offset remap is a subtraction through this table.
        var removedBefore = [Int](repeating: 0, count: characters.count + 1)
        var removed = 0
        var lineStart = 0
        for boundary in 0...characters.count {
            let isLineEnd = boundary == characters.count || characters[boundary] == "\n"
            if isLineEnd {
                var visibleEnd = boundary
                while visibleEnd > lineStart,
                      characters[visibleEnd - 1] == " " || characters[visibleEnd - 1] == "\t" {
                    visibleEnd -= 1
                }
                for index in lineStart..<boundary {
                    removedBefore[index] = removed
                    if index < visibleEnd { kept.append(characters[index]) } else { removed += 1 }
                }
                if boundary < characters.count {   // the newline itself stays
                    removedBefore[boundary] = removed
                    kept.append(characters[boundary])
                }
                lineStart = boundary + 1
            }
        }
        removedBefore[characters.count] = removed
        let stripped = String(kept)
        return (stripped, { offset in
            let clamped = max(0, min(offset, characters.count))
            return clamped - removedBefore[clamped]
        })
    }
}
