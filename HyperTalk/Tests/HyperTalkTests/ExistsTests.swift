//
//  ExistsTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func thereIsAFieldThatExists() async throws {
    let host = try await run("""
    on mouseUp
      if there is a field "Notes" then put "yes" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["Notes": "hi", "out": ""]))
    #expect(host.fields["out"] == "yes")
}

@Test func thereIsNoFieldThatIsAbsent() async throws {
    let host = try await run("""
    on mouseUp
      if there is no field "Missing" then put "absent" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "absent")
}

@Test func thereIsAnAbsentFieldIsFalse() async throws {
    let host = try await run("""
    on mouseUp
      if there is a field "Missing" then put "wrong" into field "out"
      put "done" after field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "done")
}

@Test func thereIsAButtonByProperty() async throws {
    let host = MockHost(fields: ["out": ""])
    host.properties["button OK.name"] = "OK"
    _ = try await run("""
    on mouseUp
      if there is a button "OK" then put "found" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "found")
}

@Test func thisCardAlwaysExists() async throws {
    let host = try await run("""
    on mouseUp
      if there is this card then put "yes" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "yes")
}
