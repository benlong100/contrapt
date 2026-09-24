//
//  ConstantsTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func numberWordConstants() async throws {
    let host = try await run("""
    on mouseUp
      put one + two + three into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "6")
}

@Test func piConstant() async throws {
    let host = try await run("""
    on mouseUp
      put trunc(pi * 100) into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "314")
}

@Test func colonAndTenConstants() async throws {
    let host = try await run("""
    on mouseUp
      put ten & colon & zero & zero into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "10:00")
}
