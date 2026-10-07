//
//  UsingStackTests.swift
//  HyperTalk
//
//  `start using stack "X"` / `stop using stack "X"` — cross-stack messaging.
//  An in-use stack's handlers and functions join the message hierarchy after
//  the current stack, so a stack can call into a shared library (the H2G2
//  suite's `start using stack "The Library"` then `justOpened`).
//

import Foundation
import Testing
@testable import HyperTalk

@Test func startUsingMakesHandlerReachable() async throws {
    let host = MockHost(fields: ["out": ""])
    host.stackLibrary["Helper"] = "on greet\nput \"hi\" into field \"out\"\nend greet"
    try await run("""
    on mouseUp
      start using stack "Helper"
      greet
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "hi")
}

@Test func startUsingMakesFunctionReachable() async throws {
    let host = MockHost(fields: ["out": ""])
    host.stackLibrary["Lib"] = "function double n\nreturn n * 2\nend double"
    try await run("""
    on mouseUp
      start using stack "Lib"
      put double(21) into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "42")
}

@Test func stopUsingRemovesTheLibrary() async throws {
    let host = MockHost(fields: ["out": "untouched"])
    host.stackLibrary["Helper"] = "on greet\nput \"hi\" into field \"out\"\nend greet"
    host.beginUsingStack("Helper")
    // After `stop using`, `greet` is unhandled again — a genuine error.
    await #expect(throws: ScriptError.self) {
        _ = try await run("""
        on mouseUp
          stop using stack "Helper"
          greet
        end mouseUp
        """, host: host)
    }
}

@Test func currentStackTakesPrecedenceOverInUse() async throws {
    // A handler defined both locally and in an in-use stack: the local one wins
    // (the in-use stack is searched only after the current stack).
    let host = MockHost(fields: ["out": ""])
    host.stackLibrary["Helper"] = "on greet\nput \"aux\" into field \"out\"\nend greet"
    host.beginUsingStack("Helper")
    try await run("""
    on mouseUp
      greet
    end mouseUp
    on greet
      put "local" into field "out"
    end greet
    """, host: host)
    #expect(host.fields["out"] == "local")
}

@Test func inUseStackSkipsUnparseableHandlers() async throws {
    // A library handler that uses an unsupported construct doesn't disable the
    // rest of the library — the good handler is still reachable (per-handler
    // lenient parse, as HyperCard compiles handlers independently).
    let host = MockHost(fields: ["out": ""])
    host.stackLibrary["Lib"] = """
    on broken
      if
    end broken
    on greet
      put "hi" into field "out"
    end greet
    """
    try await run("""
    on mouseUp
      start using stack "Lib"
      greet
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "hi")
}

@Test func inUseStackPersistsAcrossDispatches() async throws {
    // `start using` is session state on the host, so a later, separate dispatch
    // still reaches the library (openStack registers it; a button uses it).
    let host = MockHost(fields: ["out": ""])
    host.stackLibrary["Helper"] = "on greet\nput \"hi\" into field \"out\"\nend greet"
    try await run("on mouseUp\nstart using stack \"Helper\"\nend mouseUp", host: host)
    try await run("on mouseUp\ngreet\nend mouseUp", host: host)
    #expect(host.fields["out"] == "hi")
}
