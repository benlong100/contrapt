//
//  ArithmeticCommandsTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func addAndSubtractUpdateContainers() async throws {
    let host = try await run("""
    on mouseUp
      put 10 into x
      add 5 to x
      subtract 3 from x
      put x into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "12")
}

@Test func multiplyAndDivideUpdateContainers() async throws {
    let host = try await run("""
    on mouseUp
      put 6 into x
      multiply x by 4
      divide x by 3
      put x into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "8")
}

@Test func arithmeticWorksOnFields() async throws {
    let host = try await run("""
    on mouseUp
      put 100 into field "n"
      add 23 to field "n"
    end mouseUp
    """, host: MockHost(fields: ["n": ""]))
    #expect(host.fields["n"] == "123")
}

@Test func divideCommandByZeroIsAFriendlyError() async {
    await #expect(throws: ScriptError.self) {
        try await run("""
        on mouseUp
          put 5 into x
          divide x by 0
        end mouseUp
        """)
    }
}
