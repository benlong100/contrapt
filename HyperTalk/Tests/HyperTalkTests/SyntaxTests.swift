//
//  SyntaxTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func checkAcceptsAWellFormedScript() throws {
    try HyperTalk.check("""
    on mouseUp
      go to next card
    end mouseUp
    """)
}

@Test func checkAcceptsAnEmptyScript() throws {
    try HyperTalk.check("")
}

@Test func checkReportsProblemsWithLineNumbers() {
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

@Test func syntaxSpansClassifyASample() {
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

@Test func syntaxSpansTolerateUnterminatedStrings() {
    let source = "put \"oops\nput 1 into x"
    let spans = HyperTalk.syntaxSpans(in: source)
    let strings = spans.filter { $0.kind == .string }.map { String(source[$0.range]) }
    #expect(strings == ["\"oops"])
}

@Test func syntaxSpansKeywordsAreCaseInsensitive() {
    let source = "ON MOUSEUP"
    let spans = HyperTalk.syntaxSpans(in: source)
    #expect(spans.first?.kind == .keyword)
}
