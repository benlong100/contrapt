//
//  CreateMenuTests.swift
//  HyperTalk
//
//  `create menu "X"` / `create stack …` — Contrapt models neither custom menus
//  nor runtime stack creation, so these are accepted and ignored (like `delete
//  menu`), and execution continues rather than erroring (Adventures of Sean 2's
//  setUpMenus rebuilds the menu bar with create/delete/put-into-menu).
//

import Foundation
import Testing
@testable import HyperTalk

@Test func createMenuIsANoOpAndContinues() async throws {
    let host = try await run("""
    on mouseUp
      create menu "File"
      put "About,Quit" into menu "File"
      beep
    end mouseUp
    """)
    #expect(host.beeps == 1)
}

@Test func createStackParsesAsNoOp() throws {
    _ = try Parser.parse("""
    on mouseUp
      create stack "Scratch"
    end mouseUp
    """)
}

@Test func enableDisableSetTheEnabledProperty() async throws {
    // `enable`/`disable <button>` set the part's `enabled` property, readable
    // via `the enabled of` — a get/set round-trip.
    let host = try await run("""
    on mouseUp
      disable bg button "prior"
      put the enabled of bg button "prior" into field "a"
      enable bg button "prior"
      put the enabled of bg button "prior" into field "b"
    end mouseUp
    """, host: MockHost(fields: ["a": "", "b": ""]))
    #expect(host.fields["a"] == "false")
    #expect(host.fields["b"] == "true")
}

@Test func disableMenuIsANoOp() async throws {
    let host = try await run("""
    on mouseUp
      disable menu "File"
      beep
    end mouseUp
    """)
    #expect(host.beeps == 1)
}
