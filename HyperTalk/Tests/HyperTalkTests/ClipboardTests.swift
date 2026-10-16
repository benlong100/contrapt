//
//  ClipboardTests.swift
//  `the clipboard` as a container and expression — `put theList into the
//  clipboard` (HyperCard 10th Anniversary, budgetBoss, cs timers).
//

import Testing
@testable import HyperTalk

@Test func clipboardRoundTripsAsContainer() async throws {
    let host = try await run("""
    on p
      put "hello" into the clipboard
      put " world" after the clipboard
      put the clipboard
    end p
    """, handler: "p")
    #expect(host.messages.last == "hello world")
    #expect(host.clipboardText == "hello world")
}

@Test func clipboardChunkReads() async throws {
    let host = try await run("""
    on p
      put "alpha,beta" into the clipboard
      put item 2 of the clipboard
    end p
    """, handler: "p")
    #expect(host.messages.last == "beta")
}
