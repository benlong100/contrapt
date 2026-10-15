//
//  TextMetricsTests.swift
//  HyperTalk
//
//  QuickDraw counted a centered/right line's trailing spaces; modern layout
//  hangs them. measuringTrailingSpaces converts each line's trailing run to
//  no-break spaces so they measure — same character count, offsets untouched.
//

import Testing
@testable import HyperTalk

private let nbsp = "\u{00A0}"

@Test func convertsTrailingSpacesPerLine() {
    let text = "pad:  \nnext   \nclean"
    let converted = TextMetrics.measuringTrailingSpaces(text)
    #expect(converted == "pad:\(nbsp)\(nbsp)\nnext\(nbsp)\(nbsp)\(nbsp)\nclean")
    #expect(converted.count == text.count)
}

@Test func tagFieldPadFullyConverts() {
    let padded = "Stacks let you move among cards:" + String(repeating: " ", count: 53) + "\n"
    let converted = TextMetrics.measuringTrailingSpaces(padded)
    #expect(converted == "Stacks let you move among cards:" + String(repeating: nbsp, count: 53) + "\n")
}

@Test func leadingAndInteriorSpacesSurvive() {
    #expect(TextMetrics.measuringTrailingSpaces("  a b \n c") == "  a b\(nbsp)\n c")
}

@Test func allSpaceLineConvertsWithoutCrossingLines() {
    #expect(TextMetrics.measuringTrailingSpaces("a\n   \nb") == "a\n\(nbsp)\(nbsp)\(nbsp)\nb")
}

@Test func untouchedTextRoundTrips() {
    let original = "no padding here\njust lines"
    #expect(TextMetrics.measuringTrailingSpaces(original) == original)
}
