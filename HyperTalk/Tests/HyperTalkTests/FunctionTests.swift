//
//  FunctionTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

// MARK: - Globals

@Test func globalPersistsAcrossHandlerCalls() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      global tally
      put 0 into tally
      bump
      bump
      put tally into field "out"
    end mouseUp

    on bump
      global tally
      put tally + 1 into tally
    end bump
    """, host: host)
    #expect(host.fields["out"] == "2")
}

@Test func globalPersistsAcrossSeparateRuns() async throws {
    let host = MockHost(fields: ["out": ""])
    let script = """
    on mouseUp
      global counter
      put counter + 1 into counter
      put counter into field "out"
    end mouseUp
    """
    try await run(script, host: host)
    #expect(host.fields["out"] == "1")
    try await run(script, host: host)
    #expect(host.fields["out"] == "2")
}

@Test func nonGlobalsStayLocal() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put "mine" into x
      helper
      put x into field "out"
    end mouseUp

    on helper
      put "theirs" into x
    end helper
    """, host: host)
    #expect(host.fields["out"] == "mine")
}

// MARK: - Functions

@Test func userFunctionReturnsValue() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put double(21) into field "out"
    end mouseUp

    function double n
      return n * 2
    end double
    """, host: host)
    #expect(host.fields["out"] == "42")
}

@Test func functionWithMultipleArgs() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put add(3, 4) into field "out"
    end mouseUp

    function add a, b
      return a + b
    end add
    """, host: host)
    #expect(host.fields["out"] == "7")
}

@Test func functionsCanCallFunctions() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put quad(5) into field "out"
    end mouseUp

    function quad n
      return double(double(n))
    end quad

    function double n
      return n * 2
    end double
    """, host: host)
    #expect(host.fields["out"] == "20")
}

@Test func functionWithNoReturnYieldsEmpty() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      if silent() is empty then put "empty" into field "out"
    end mouseUp

    function silent
      put "side effect" into ignored
    end silent
    """, host: host)
    #expect(host.fields["out"] == "empty")
}

@Test func unknownFunctionIsAFriendlyError() async throws {
    do {
        try await run("""
        on mouseUp
          put mystery(1) into x
        end mouseUp
        """, host: MockHost())
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.message.contains("mystery"))
    }
}

// MARK: - return and the result

@Test func theResultHoldsAHandlersReturn() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      validate
      put the result into field "out"
    end mouseUp

    on validate
      return "ok"
    end validate
    """, host: host)
    #expect(host.fields["out"] == "ok")
}

@Test func returnExitsTheHandlerEarly() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put grade(95) into field "out"
    end mouseUp

    function grade score
      if score >= 90 then return "A"
      if score >= 80 then return "B"
      return "C"
    end grade
    """, host: host)
    #expect(host.fields["out"] == "A")
}

// MARK: - Built-in functions

@Test func lengthCountsCharacters() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put length("HyperTalk") into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "9")
}

@Test func randomIsInRange() async throws {
    let host = MockHost(fields: ["out": ""])
    for _ in 0..<50 {
        try await run("""
        on mouseUp
          put random(6) into field "out"
        end mouseUp
        """, host: host)
        let value = Int(host.fields["out"] ?? "") ?? 0
        #expect((1...6).contains(value))
    }
}

// MARK: - Counts and more built-ins

@Test func numberOfLinesOfAField() async throws {
    let host = MockHost(fields: ["out": "", "src": "one\ntwo\nthree"])
    try await run("""
    on mouseUp
      put the number of lines of field "src" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "3")
}

@Test func numberOfWordsAndItems() async throws {
    let host = MockHost(fields: ["a": "", "b": "", "c": ""])
    try await run("""
    on mouseUp
      put the number of words of "the quick brown fox" into field "a"
      put the number of items of "a,b,c" into field "b"
      put the number of chars of "hello" into field "c"
    end mouseUp
    """, host: host)
    #expect(host.fields["a"] == "4")
    #expect(host.fields["b"] == "3")
    #expect(host.fields["c"] == "5")
}

@Test func theNumberOfThisCardStillWorks() async throws {
    // Ensure the count parse doesn't shadow the card `number` property.
    let host = MockHost(fields: ["out": ""])
    host.properties["this card.number"] = "3"
    try await run("""
    on mouseUp
      put the number of this card into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "3")
}

@Test func theLengthOf() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put the length of "HyperTalk" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "9")
}

@Test func mathBuiltins() async throws {
    let host = MockHost(fields: ["a": "", "b": "", "c": "", "d": "", "e": ""])
    try await run("""
    on mouseUp
      put round(2.6) into field "a"
      put trunc(2.9) into field "b"
      put abs(0 - 5) into field "c"
      put min(3, 1, 2) into field "d"
      put max(3, 1, 2) into field "e"
    end mouseUp
    """, host: host)
    #expect(host.fields["a"] == "3")
    #expect(host.fields["b"] == "2")
    #expect(host.fields["c"] == "5")
    #expect(host.fields["d"] == "1")
    #expect(host.fields["e"] == "3")
}

@Test func offsetAndCharConversions() async throws {
    let host = MockHost(fields: ["a": "", "b": "", "c": "", "d": ""])
    try await run("""
    on mouseUp
      put offset("brown", "the quick brown fox") into field "a"
      put offset("zzz", "hello") into field "b"
      put charToNum("A") into field "c"
      put numToChar(66) into field "d"
    end mouseUp
    """, host: host)
    #expect(host.fields["a"] == "11")
    #expect(host.fields["b"] == "0")
    #expect(host.fields["c"] == "65")
    #expect(host.fields["d"] == "B")
}

// MARK: - Date and time

@Test func dateAndTimeForms() async throws {
    let host = MockHost(fields: ["a": "", "b": "", "c": "", "d": "", "e": ""])
    try await run("""
    on mouseUp
      put the date into field "a"
      put the long date into field "b"
      put the abbreviated date into field "c"
      put the time into field "d"
      put the long time into field "e"
    end mouseUp
    """, host: host)
    #expect(host.fields["a"] == "1/2/34")
    #expect(host.fields["b"] == "Monday, January 2, 2034")
    #expect(host.fields["c"] == "Jan 2, 2034")
    #expect(host.fields["d"] == "3:45 PM")
    #expect(host.fields["e"] == "3:45:07 PM")
}

@Test func secondsAndTicks() async throws {
    let host = MockHost(fields: ["a": "", "b": ""])
    try await run("""
    on mouseUp
      put the seconds into field "a"
      put the ticks into field "b"
    end mouseUp
    """, host: host)
    #expect(host.fields["a"] == "2019686400")
    #expect(host.fields["b"] == "121181184000")
}
