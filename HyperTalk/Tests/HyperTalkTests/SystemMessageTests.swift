//
//  SystemMessageTests.swift
//  HyperTalk
//
//  HyperCard's auto-sent system messages (`openCard`, `idle`, `mouseUp`, …) are
//  recognized keywords: sending one that no handler catches is a silent no-op,
//  not "Can't understand". Home-provided utility handlers (e.g. `getHomeInfo`)
//  resolve through the built-in Home library at the bottom of the path. A
//  genuinely unknown command (not a system message, not a Home/library handler)
//  still errors.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func unhandledSystemMessageIsIgnored() async throws {
    // `openStack` explicitly sends `openCard`; no openCard handler exists, so
    // it no-ops and the following `beep` still runs.
    let host = try await run("""
    on openStack
      openCard
      beep
    end openStack
    """, handler: "openStack")
    #expect(host.beeps == 1)
}

@Test func severalSystemMessagesNoOp() async throws {
    let host = try await run("""
    on mouseUp
      idle
      closeCard
      newBackground
      beep
    end mouseUp
    """)
    #expect(host.beeps == 1)
}

@Test func genuinelyUnknownCommandStillErrors() async throws {
    // A non-system, non-Home, unhandled command is still a real error, so a
    // true typo or missing auxiliary-stack call surfaces rather than silently
    // vanishing.
    await #expect(throws: ScriptError.self) {
        try await run("""
        on mouseUp
          frobnicate
        end mouseUp
        """)
    }
}

@Test func homeLibraryHandlesGetHomeInfo() async throws {
    // `getHomeInfo` resolves through the built-in Home library (a no-op here),
    // so an imported stack's openStack keeps running past it.
    let host = try await run("""
    on mouseUp
      getHomeInfo
      beep
    end mouseUp
    """)
    #expect(host.beeps == 1)
}
