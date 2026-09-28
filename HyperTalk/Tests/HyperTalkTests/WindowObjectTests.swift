//
//  WindowObjectTests.swift
//  HyperTalk
//
//  Old stacks (e.g. Apple's Color Tools) save, restore, and reposition
//  HyperCard's palette and document windows. Contrapt has no window objects,
//  but the references must parse and run harmlessly so those stacks import.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func windowVisibleReadsFalseAndParses() async throws {
    // The line from Color Tools' AC_start that first hit the wall:
    // `put the visible of window "Tools" & "," & …`
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put the visible of window "Tools" & "," & the visible of window "Message" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "false,false")
}

@Test func setWindowPropertyIsANoOp() async throws {
    // `set the loc of window "AddColor" to …` and `set the mode of window …`
    // must run without error (and touch nothing).
    let host = try await run("""
    on mouseUp
      set the loc of window "AddColor" to "10,20"
      set the mode of window "AddColor" to 3
    end mouseUp
    """)
    #expect(host.properties["window AddColor.loc"] == nil)
}

@Test func cardWindowParsesAsAWindow() async throws {
    // `the top of card window` / `the left of card window` — a qualified
    // window, not a card named "window".
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put the top of card window & the left of card window into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "")
}

@Test func thereIsAWindowIsFalse() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      if there is not a window "AddColor" then put "gone" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "gone")
}
