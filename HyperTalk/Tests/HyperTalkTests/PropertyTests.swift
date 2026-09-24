//
//  PropertyTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func setWritesAProperty() throws {
    let host = try run("""
    on mouseUp
      set the width of button "OK" to 300
    end mouseUp
    """)
    #expect(host.properties["button OK.width"] == "300")
}

@Test func theOfReadsAProperty() throws {
    let host = MockHost(fields: ["out": ""])
    host.properties["button OK.width"] = "120"
    try run("""
    on mouseUp
      put the width of button "OK" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "120")
}

@Test func getPutsIntoIt() throws {
    let host = MockHost(fields: ["out": ""])
    host.properties["this card.name"] = "Home"
    try run("""
    on mouseUp
      get the name of this card
      put it into field "out"
      get 2 + 3
      put it after field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "Home5")
}

@Test func propertiesWorkInConditions() throws {
    let host = MockHost(fields: ["out": ""])
    host.properties["button Big.width"] = "400"
    try run("""
    on mouseUp
      if the width of button "Big" > 300 then
        put "wide" into field "out"
      end if
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "wide")
}

@Test func objectNamesCanBeExpressions() throws {
    let host = try run("""
    on mouseUp
      put "OK" into which
      set the visible of button which to false
    end mouseUp
    """)
    #expect(host.properties["button OK.visible"] == "false")
}

@Test func setWithoutOfIsAFriendlyError() {
    #expect(throws: ScriptError.self) {
        try run("""
        on mouseUp
          set the width to 300
        end mouseUp
        """)
    }
}

@Test func unknownObjectIsAFriendlyError() throws {
    do {
        try run("""
        on mouseUp
          set the width of the moon to 300
        end mouseUp
        """)
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.message.contains("object"))
    }
}

@Test func theWithoutOfIsStillANoiseWord() throws {
    let host = try run("""
    on mouseUp
      put the date into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    // No date function yet: falls back to the unquoted literal.
    #expect(host.fields["out"] == "date")
}

@Test func setPropertyOnCards() throws {
    let host = try run("""
    on mouseUp
      set the name of this card to "Home"
      set the name of card 2 to "Second"
    end mouseUp
    """)
    #expect(host.properties["this card.name"] == "Home")
    #expect(host.properties["card 2.name"] == "Second")
}
