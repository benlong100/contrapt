//
//  FunctionTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

// MARK: - Globals

@Test func globalPersistsAcrossHandlerCalls() throws {
    let host = MockHost(fields: ["out": ""])
    try run("""
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

@Test func globalPersistsAcrossSeparateRuns() throws {
    let host = MockHost(fields: ["out": ""])
    let script = """
    on mouseUp
      global counter
      put counter + 1 into counter
      put counter into field "out"
    end mouseUp
    """
    try run(script, host: host)
    #expect(host.fields["out"] == "1")
    try run(script, host: host)
    #expect(host.fields["out"] == "2")
}

@Test func nonGlobalsStayLocal() throws {
    let host = MockHost(fields: ["out": ""])
    try run("""
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

@Test func userFunctionReturnsValue() throws {
    let host = MockHost(fields: ["out": ""])
    try run("""
    on mouseUp
      put double(21) into field "out"
    end mouseUp

    function double n
      return n * 2
    end double
    """, host: host)
    #expect(host.fields["out"] == "42")
}

@Test func functionWithMultipleArgs() throws {
    let host = MockHost(fields: ["out": ""])
    try run("""
    on mouseUp
      put add(3, 4) into field "out"
    end mouseUp

    function add a, b
      return a + b
    end add
    """, host: host)
    #expect(host.fields["out"] == "7")
}

@Test func functionsCanCallFunctions() throws {
    let host = MockHost(fields: ["out": ""])
    try run("""
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

@Test func functionWithNoReturnYieldsEmpty() throws {
    let host = MockHost(fields: ["out": ""])
    try run("""
    on mouseUp
      if silent() is empty then put "empty" into field "out"
    end mouseUp

    function silent
      put "side effect" into ignored
    end silent
    """, host: host)
    #expect(host.fields["out"] == "empty")
}

@Test func unknownFunctionIsAFriendlyError() throws {
    do {
        try run("""
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

@Test func theResultHoldsAHandlersReturn() throws {
    let host = MockHost(fields: ["out": ""])
    try run("""
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

@Test func returnExitsTheHandlerEarly() throws {
    let host = MockHost(fields: ["out": ""])
    try run("""
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

@Test func lengthCountsCharacters() throws {
    let host = MockHost(fields: ["out": ""])
    try run("""
    on mouseUp
      put length("HyperTalk") into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "9")
}

@Test func randomIsInRange() throws {
    let host = MockHost(fields: ["out": ""])
    for _ in 0..<50 {
        try run("""
        on mouseUp
          put random(6) into field "out"
        end mouseUp
        """, host: host)
        let value = Int(host.fields["out"] ?? "") ?? 0
        #expect((1...6).contains(value))
    }
}
