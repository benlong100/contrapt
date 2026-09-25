//
//  ShowHidePushPopTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func showAndHideSetVisibility() async throws {
    let host = MockHost()
    host.properties["field Notes.visible"] = "true"
    host.properties["button OK.visible"] = "false"
    _ = try await run("""
    on mouseUp
      hide field "Notes"
      show button "OK"
    end mouseUp
    """, host: host)
    #expect(host.properties["field Notes.visible"] == "false")
    #expect(host.properties["button OK.visible"] == "true")
}

@Test func hideAtLocationStillHides() async throws {
    let host = MockHost()
    host.properties["button Secret.visible"] = "true"
    _ = try await run("""
    on mouseUp
      hide button "Secret" at 10,20
    end mouseUp
    """, host: host)
    #expect(host.properties["button Secret.visible"] == "false")
}

@Test func ignorableShowTargetsDoNotError() async throws {
    // Common old-stack lines Contrapt has no concept of — must parse cleanly.
    _ = try await run("""
    on mouseUp
      hide menuBar
      show message box
      hide card picture
    end mouseUp
    """)
}

@Test func goHomeAsksToOpenHome() async throws {
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      go home
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .home)
}

@Test func goCardOfBackgroundIgnoresTheQualifier() async throws {
    // `go card 1 of bkgnd "X"` parses; the background qualifier is ignored.
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      go card 1 of bkgnd "Weekly"
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .number(1))
}

@Test func goBackIsADestination() async throws {
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      go back
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .back)
}

@Test func pushThenPopNavigates() async throws {
    let host = MockHost()
    host.currentCardID = "42"
    _ = try await run("""
    on mouseUp
      push card
      pop card
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .id("42"))
}

@Test func pushNamedCardIsAcceptedAsCurrentCard() async throws {
    // `push card "X"` / `push myCard` parse; Contrapt remembers the
    // current card regardless of the descriptor.
    let host = MockHost()
    host.currentCardID = "9"
    _ = try await run("""
    on mouseUp
      push card "About"
      pop card
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .id("9"))
}

@Test func popCardIntoContainerReadsReference() async throws {
    let host = MockHost(fields: ["out": ""])
    host.currentCardID = "7"
    _ = try await run("""
    on mouseUp
      push card
      pop card into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "card id 7")
    #expect(host.destinations.isEmpty) // "into" doesn't navigate
}
