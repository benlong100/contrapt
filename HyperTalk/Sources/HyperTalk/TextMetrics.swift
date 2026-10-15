//
//  TextMetrics.swift
//  HyperTalk
//
//  Classic-Mac text measurement rules that modern layout doesn't share.
//
//  QuickDraw's TextEdit measured a centered or right-aligned line INCLUDING its
//  trailing spaces, and authors leaned on that: What is HyperCard?'s Tag field
//  is "Stacks let you move among cards:" + 53 spaces, center-aligned — the pad
//  sized so the centered line lands flush LEFT (verified against real HyperCard
//  in Basilisk, 2026-10-15). TextKit and CSS instead "hang" trailing whitespace
//  (it doesn't shift alignment), which re-centers the bare words and moves them
//  ~half the pad's width. Converting the trailing run to NO-BREAK spaces makes
//  modern layout measure it like QuickDraw did — same glyph width, same
//  character count, so style-run and selection offsets are untouched.
//

public enum TextMetrics {

    /// `text` with each line's trailing spaces converted to no-break spaces
    /// (U+00A0), so centered/right-aligned layout measures them as QuickDraw
    /// did instead of hanging them. Character count is unchanged.
    public static func measuringTrailingSpaces(_ text: String) -> String {
        var characters = Array(text)
        // Walk backward; at each line end (string end or the char before a
        // newline) convert the run of plain spaces. A "\n" naturally stops the
        // inner walk, so an all-space line converts fully and no run crosses
        // line boundaries.
        func convertRun(endingAt lineEnd: Int) {
            var cursor = lineEnd
            while cursor >= 0, characters[cursor] == " " {
                characters[cursor] = "\u{00A0}"
                cursor -= 1
            }
        }
        convertRun(endingAt: characters.count - 1)
        for index in characters.indices where characters[index] == "\n" {
            convertRun(endingAt: index - 1)
        }
        return String(characters)
    }
}
