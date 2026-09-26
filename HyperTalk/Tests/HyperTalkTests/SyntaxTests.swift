//
//  SyntaxTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func checkAcceptsAWellFormedScript() async throws {
    try HyperTalk.check("""
    on mouseUp
      go to next card
    end mouseUp
    """)
}

@Test func checkAcceptsAnEmptyScript() async throws {
    try HyperTalk.check("")
}

@Test func checkSkipsDecorativeBannersAndLooseText() async throws {
    // Apple's 2.x scripts open with ∞∞∞ banners and prose outside handlers,
    // and use stray glyphs/colons. HyperCard ignores non-handler text.
    try HyperTalk.check("""
    ∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞
    Script from background: Home Cards

    THE MESSAGE HANDLERS IN THIS SCRIPT:
    openStack,closeStack,openBackground
    ∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞∞

    -----  Open/Resume Scripts  --------

    on openStack
      put 1 into x
    end openStack
    """)
}

@Test func looseTextHandlerStillRuns() async throws {
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    ∞∞∞ banner ∞∞∞
    notes: openStack, foo
    on mouseUp
      put "ok" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "ok")
}

@Test func checkAcceptsThePlotsPieButtonScript() async throws {
    // The Plots stack's "Pie" button — exercises paint no-ops, arithmetic
    // chunk indices, `number of … in`, `.02`, and bare-name globals.
    try HyperTalk.check("""
    on mouseUp
      put the userLevel into saveLevel
      if the userLevel < 3 then set userLevel to 3
      if the userLevel < 3 then exit mouseUp
      put "Sample Pie Chart" into field "Title"
      put frameBottom()-frameHeight()+10 into pieTop
      put frameLeft()+5 into pieLeft
      clearScreen
      reset paint
      choose oval tool
      set lineSize to 2
      set dragSpeed to 0
      drag from pieLeft,pieTop to pieLeft+10, pieTop+10
      set centered to false
      put the number of lines in field "Data" into dataCount
      repeat with i = 1 to dataCount+1
        choose line tool
        drag from 1,2 to 3,4
        if change > .02 then
          set pattern to getPattern(i)
          choose bucket tool
          click at halfX, halfY
        end if
        get line i of field "data"
        put item (i mod 12)+1 of "2,13,11" into pat
      end repeat
      reset paint
      choose browse tool
      set userLevel to saveLevel
    end mouseUp

    function getPattern selector
      return item (selector mod 12)+1 of "2,13,11,3,14,6,21,17,31,18,4,32"
    end getPattern
    """)
}

@Test func checkReportsProblemsWithLineNumbers() async {
    do {
        try HyperTalk.check("""
        on mouseUp
          repeat 3 times
            put 1 into x
        end mouseUp
        """)
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.line == 2)
        #expect(error.message.contains("end repeat"))
    } catch {
        Issue.record("Expected a ScriptError, got \(error)")
    }
}

@Test func syntaxSpansClassifyASample() async {
    let source = """
    on mouseUp -- greet the user
      put "Hello" into greeting
      put 42 into answer
    end mouseUp
    """
    let spans = HyperTalk.syntaxSpans(in: source)

    func texts(of kind: SyntaxSpan.Kind) -> [String] {
        spans.filter { $0.kind == kind }.map { String(source[$0.range]) }
    }

    #expect(texts(of: .comment) == ["-- greet the user"])
    #expect(texts(of: .string) == ["\"Hello\""])
    #expect(texts(of: .number) == ["42"])
    #expect(texts(of: .keyword).contains("on"))
    #expect(texts(of: .keyword).contains("put"))
    #expect(texts(of: .keyword).contains("into"))
    #expect(texts(of: .identifier).contains("mouseUp"))
    #expect(texts(of: .identifier).contains("greeting"))
}

@Test func syntaxSpansTolerateUnterminatedStrings() async {
    let source = "put \"oops\nput 1 into x"
    let spans = HyperTalk.syntaxSpans(in: source)
    let strings = spans.filter { $0.kind == .string }.map { String(source[$0.range]) }
    #expect(strings == ["\"oops"])
}

@Test func syntaxSpansKeywordsAreCaseInsensitive() async {
    let source = "ON MOUSEUP"
    let spans = HyperTalk.syntaxSpans(in: source)
    #expect(spans.first?.kind == .keyword)
}

// MARK: - Smart punctuation tolerance

@Test func curlyQuotesDelimitStrings() async throws {
    let host = MockHost(fields: ["out": ""])
    // As typed on an iPad with smart quotes on.
    try await HyperTalk.run(handler: "mouseUp", in: """
    on mouseUp
      put \u{201C}Hello\u{201D} into field \u{201C}out\u{201D}
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "Hello")
}

@Test func mismatchedCurlyAndStraightQuotesStillDelimit() async throws {
    let host = MockHost(fields: ["out": ""])
    try await HyperTalk.run(handler: "mouseUp", in: """
    on mouseUp
      put \u{201C}mixed" into field "out\u{201D}
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "mixed")
}

@Test func smartDashesStartComments() async throws {
    let host = MockHost(fields: ["out": ""])
    // iOS smart dashes turn a typed `--` into an en dash.
    try await HyperTalk.run(handler: "mouseUp", in: """
    on mouseUp \u{2013} an en-dash comment
      put "ok" into field "out" \u{2014} an em-dash comment
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "ok")
}

@Test func syntaxSpansColorCurlyQuotedStringsAndDashComments() async {
    let source = "put \u{201C}Hello\u{201D} into x \u{2013} note"
    let spans = HyperTalk.syntaxSpans(in: source)
    let strings = spans.filter { $0.kind == .string }.map { String(source[$0.range]) }
    let comments = spans.filter { $0.kind == .comment }.map { String(source[$0.range]) }
    #expect(strings == ["\u{201C}Hello\u{201D}"])
    #expect(comments == ["\u{2013} note"])
}

@Test func thenOnNextLineParses() async throws {
    // HyperCard style: `if <cond>` newline `then <statement>`.
    let host = try await run("""
    on mouseUp
      repeat with i = 1 to 5
        if i > 2
        then exit repeat
      end repeat
      put i into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "3")
}

@Test func notSignContinuesLine() async throws {
    let host = try await run("on mouseUp\nput \"a\" & ¬\n\"b\" into field \"out\"\nend mouseUp",
                             host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "ab")
}
