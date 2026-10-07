//
//  HyperCardVersionTests.swift
//  HyperTalk
//
//  `the version` / `the version of HyperCard` — the HyperCard application
//  version. Stacks gate startup on it (Caper in the Castro's openStack does
//  `if the version of HyperCard < 1.2`), so Contrapt reports a late 2.x and
//  the modern branch runs.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func theVersionOfHyperCard() async throws {
    let host = try await run("""
    on mouseUp
      put the version of HyperCard into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "2.4.1")
}

@Test func theBareVersion() async throws {
    let host = try await run("""
    on mouseUp
      put the version into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "2.4.1")
}

@Test func theLongVersion() async throws {
    let host = try await run("""
    on mouseUp
      put the long version into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "2.4.1")
}

@Test func versionGateTakesModernBranch() async throws {
    let host = try await run("""
    on mouseUp
      if the version of HyperCard < 1.2 then
        put "old" into field "out"
      else
        put "modern" into field "out"
      end if
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "modern")
}
