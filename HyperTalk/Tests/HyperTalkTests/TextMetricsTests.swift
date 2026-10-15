//
//  TextMetricsTests.swift
//  HyperTalk
//
//  QuickDraw-style trailing-whitespace stripping for centered/right-aligned
//  field text (the "'text:' + 53 spaces, centered" idiom — What is HyperCard?'s
//  Stacks card), including the offset remap style runs and selections ride.
//

import Testing
@testable import HyperTalk

@Test func stripsTrailingSpacesFromEachLine() {
    let (text, _) = TextMetrics.strippingTrailingLineWhitespace("text:   \nnext  \t \nclean")
    #expect(text == "text:\nnext\nclean")
}

@Test func spacePaddedCenteredFieldKeepsOnlyTheWords() {
    let padded = "text:" + String(repeating: " ", count: 53)
    let (text, remap) = TextMetrics.strippingTrailingLineWhitespace(padded)
    #expect(text == "text:")
    // An offset inside the removed pad clamps to the new line end.
    #expect(remap(30) == 5)
    #expect(remap(padded.count) == 5)
}

@Test func leadingAndInteriorWhitespaceSurvive() {
    let (text, _) = TextMetrics.strippingTrailingLineWhitespace("  a b \n\tc\t")
    #expect(text == "  a b\n\tc")
}

@Test func offsetsRemapAcrossLines() {
    //          0123456 789        (original)   ->  "ab\ncd"
    let (text, remap) = TextMetrics.strippingTrailingLineWhitespace("ab    \ncd  ")
    #expect(text == "ab\ncd")
    #expect(remap(0) == 0)   // 'a'
    #expect(remap(1) == 1)   // 'b'
    #expect(remap(4) == 2)   // inside first pad -> first line's new end
    #expect(remap(6) == 2)   // the newline keeps its place...
    #expect(remap(7) == 3)   // 'c' right after it
    #expect(remap(8) == 4)   // 'd'
    #expect(remap(11) == 5)  // past the end clamps to the stripped length
}

@Test func blankAndWhitespaceOnlyLinesCollapseButRemain() {
    let (text, _) = TextMetrics.strippingTrailingLineWhitespace("a\n   \nb")
    #expect(text == "a\n\nb")
}

@Test func untouchedTextRoundTrips() {
    let original = "no padding here\njust lines"
    let (text, remap) = TextMetrics.strippingTrailingLineWhitespace(original)
    #expect(text == original)
    #expect(remap(10) == 10)
}
