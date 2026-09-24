//
//  TypeCheckTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func isANumber() throws {
    let host = try run("""
    on mouseUp
      if "3.14" is a number then put "yes" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "yes")
}

@Test func isNotANumber() throws {
    let host = try run("""
    on mouseUp
      if "hello" is not a number then put "not" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "not")
}

@Test func isAnInteger() throws {
    let host = try run("""
    on mouseUp
      if 42 is an integer then put "a" after field "out"
      if 4.5 is an integer then put "b" after field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "a")
}

@Test func isALogical() throws {
    let host = try run("""
    on mouseUp
      if (1 < 2) is a logical then put "yes" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "yes")
}

@Test func isAPointAndRect() throws {
    let host = try run("""
    on mouseUp
      if "10,20" is a point then put "p" after field "out"
      if "0,0,100,50" is a rect then put "r" after field "out"
      if "10,20,30" is a point then put "x" after field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "pr")
}
