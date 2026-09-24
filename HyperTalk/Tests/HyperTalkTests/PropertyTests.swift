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

// MARK: - IDs

@Test func partsCanBeAddressedByID() throws {
    let host = try run("""
    on mouseUp
      set the title of button id 6 to "Renamed"
    end mouseUp
    """)
    #expect(host.properties["button id 6.title"] == "Renamed")
}

@Test func cardsCanBeAddressedByID() throws {
    let host = MockHost(fields: ["out": ""])
    host.properties["card id 12.name"] = "Home"
    try run("""
    on mouseUp
      put the name of card id 12 into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "Home")
}

@Test func theIDOfReadsAnID() throws {
    let host = MockHost(fields: ["out": ""])
    host.properties["button OK.id"] = "6"
    try run("""
    on mouseUp
      get the id of button "OK"
      set the visible of button id it to false
    end mouseUp
    """, host: host)
    #expect(host.properties["button id 6.visible"] == "false")
}

@Test func idExpressionsCanBeComputed() throws {
    let host = try run("""
    on mouseUp
      put 4 into n
      set the width of button id (n + 2) to 100
    end mouseUp
    """)
    #expect(host.properties["button id 6.width"] == "100")
}

@Test func goToCardByID() throws {
    let host = try run("""
    on mouseUp
      go to card id 12
    end mouseUp
    """)
    #expect(host.destinations == [.id("12")])
}

// MARK: - Ordinals and domains

@Test func partsCanBeAddressedByOrdinal() throws {
    let host = try run("""
    on mouseUp
      set the name of field 1 to "First Field"
      set the width of button 2 to 90
    end mouseUp
    """)
    #expect(host.properties["field 1.name"] == "First Field")
    #expect(host.properties["button 2.width"] == "90")
}

@Test func domainQualifiersReachTheRightLayer() throws {
    let host = try run("""
    on mouseUp
      set the name of card field 1 to "blah"
      set the text of background field 1 to "shared"
      set the title of bg button "Next" to "Onward"
    end mouseUp
    """)
    #expect(host.properties["card field 1.name"] == "blah")
    #expect(host.properties["background field 1.text"] == "shared")
    #expect(host.properties["background button Next.title"] == "Onward")
}

@Test func ordinalsCanBeComputed() throws {
    let host = try run("""
    on mouseUp
      put 1 into n
      set the visible of field (n + 1) to false
    end mouseUp
    """)
    #expect(host.properties["field 2.visible"] == "false")
}

// MARK: - Field contents with domains, ordinals, and ids

@Test func fieldContentsRespectDomainQualifiers() throws {
    let host = MockHost(fields: ["card 1": "on the card", "background 1": "on the bg"])
    try run("""
    on mouseUp
      put " (card)" after card field 1
      put " (bg)" after background field 1
    end mouseUp
    """, host: host)
    #expect(host.fields["card 1"] == "on the card (card)")
    #expect(host.fields["background 1"] == "on the bg (bg)")
}

@Test func fieldContentsByOrdinalAndID() throws {
    let host = MockHost(fields: ["2": "second", "id 9": "by id"])
    try run("""
    on mouseUp
      put field 2 into a
      put field id 9 into b
      put a && b into field 2
    end mouseUp
    """, host: host)
    #expect(host.fields["2"] == "second by id")
}

@Test func fieldContentsByNameStillWork() throws {
    let host = try run("""
    on mouseUp
      put "hello" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "hello")
}
