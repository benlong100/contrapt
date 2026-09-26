//
//  PropertyTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func setWritesAProperty() async throws {
    let host = try await run("""
    on mouseUp
      set the width of button "OK" to 300
    end mouseUp
    """)
    #expect(host.properties["button OK.width"] == "300")
}

@Test func theOfReadsAProperty() async throws {
    let host = MockHost(fields: ["out": ""])
    host.properties["button OK.width"] = "120"
    try await run("""
    on mouseUp
      put the width of button "OK" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "120")
}

@Test func bareOfReadsAProperty() async throws {
    // HyperTalk lets you drop the leading `the`: `loc of field "x"`.
    let host = MockHost(fields: ["out": ""])
    host.properties["field Month1.loc"] = "40,60"
    try await run("""
    on mouseUp
      put loc of field "Month1" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "40,60")
}

@Test func shortAndLongNameResolveToTheName() async throws {
    // `short name of X` / `the long name of X` → the `name` property.
    let host = MockHost(fields: ["out": ""])
    host.properties["button OK.name"] = "OK"
    try await run("""
    on mouseUp
      put short name of button "OK" into field "out"
      put char 1 of the long name of button "OK" after field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "OKO")
}

@Test func theNumberOfCountsPartsAndCards() async throws {
    let host = MockHost(fields: ["a": "", "b": "", "out": ""])
    host.cardCount = 7
    try await run("""
    on mouseUp
      put the number of fields & "/" & the number of cards into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "3/7")
}

@Test func bareBackgroundAndCardObjects() async throws {
    // `the short name of bkgnd` → the current background; `btn` abbreviation.
    let host = MockHost(fields: ["out": ""])
    host.properties["this background.name"] = "Weekly"
    host.properties["button OK.width"] = "50"
    try await run("""
    on mouseUp
      put the short name of bkgnd into field "out"
      put the width of btn "OK" after field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "Weekly50")
}

@Test func setAcceptsACommaListValue() async throws {
    // `set rect of btn "X" to 10,20,110,60` — a point/rect value.
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      set rect of btn "Extend" to 351,238,431,255
    end mouseUp
    """, host: host)
    #expect(host.properties["button Extend.rect"] == "351,238,431,255")
}

@Test func fieldOfAnotherCard() async throws {
    // `field "WeekSecs" of prev card` reads a field on another card.
    let host = MockHost(fields: ["prev card.weeksecs": "12345", "out": ""])
    try await run("""
    on mouseUp
      get field "WeekSecs" of prev card
      put it into field "out"
    end mouseUp
    """, host: host)
    // Reading the "prev card." key proves the `of prev card` owner was used.
    #expect(host.fields["out"] == "12345")
}

@Test func inlineIfThenElseOnOneLine() async throws {
    // `if C then S1 else S2` on a single line, both branches inline.
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      put 5 into n
      if n > 3 then put "big" into field "out" else put "small" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "big")
}

@Test func inlineIfElseNestedInABlockElse() async throws {
    // A single-line if/else that is the last statement of an outer block
    // else — the trailing `end if` must close the OUTER if.
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      put 1 into n
      if n is 0 then
        put "zero" into field "out"
      else
        put "start" into field "out"
        if n is 1 then put "one" into field "out" else put "many" into field "out"
      end if
      put "!" after field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "one!")
}

@Test func fieldOfCardScopedToBackground() async throws {
    // `field "X" of last card of bkgnd "Weekly"` scopes the card to the
    // "Weekly" background (MockHost keys it "last card.weekly.").
    let host = MockHost(fields: ["last card.weekly.weeksecs": "999", "out": ""])
    try await run("""
    on mouseUp
      put field "WeekSecs" of last card of bkgnd "Weekly" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "999")
}

@Test func theUserLevelReadsAsScripting() async throws {
    // Contrapt has no access levels, so `the userLevel` is 5 (top); level
    // guards then pass, and setting it is a harmless no-op.
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put the userLevel into saveLevel
      if the userLevel < 3 then set userLevel to 3
      if the userLevel >= 5 then put "full" into field "out"
      set userLevel to saveLevel
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "full")
}

@Test func getPutsIntoIt() async throws {
    let host = MockHost(fields: ["out": ""])
    host.properties["this card.name"] = "Home"
    try await run("""
    on mouseUp
      get the name of this card
      put it into field "out"
      get 2 + 3
      put it after field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "Home5")
}

@Test func propertiesWorkInConditions() async throws {
    let host = MockHost(fields: ["out": ""])
    host.properties["button Big.width"] = "400"
    try await run("""
    on mouseUp
      if the width of button "Big" > 300 then
        put "wide" into field "out"
      end if
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "wide")
}

@Test func objectNamesCanBeExpressions() async throws {
    let host = try await run("""
    on mouseUp
      put "OK" into which
      set the visible of button which to false
    end mouseUp
    """)
    #expect(host.properties["button OK.visible"] == "false")
}

@Test func setWithoutOfIsAFriendlyError() async {
    await #expect(throws: ScriptError.self) {
        try await run("""
        on mouseUp
          set the width to 300
        end mouseUp
        """)
    }
}

@Test func unknownObjectIsAFriendlyError() async throws {
    do {
        try await run("""
        on mouseUp
          set the width of the moon to 300
        end mouseUp
        """)
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.message.contains("object"))
    }
}

@Test func theWithoutOfIsStillANoiseWord() async throws {
    let host = try await run("""
    on mouseUp
      put the mango into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    // A non-special word after "the" falls back to the unquoted literal.
    #expect(host.fields["out"] == "mango")
}

@Test func setPropertyOnCards() async throws {
    let host = try await run("""
    on mouseUp
      set the name of this card to "Home"
      set the name of card 2 to "Second"
    end mouseUp
    """)
    #expect(host.properties["this card.name"] == "Home")
    #expect(host.properties["card 2.name"] == "Second")
}

// MARK: - IDs

@Test func partsCanBeAddressedByID() async throws {
    let host = try await run("""
    on mouseUp
      set the title of button id 6 to "Renamed"
    end mouseUp
    """)
    #expect(host.properties["button id 6.title"] == "Renamed")
}

@Test func cardsCanBeAddressedByID() async throws {
    let host = MockHost(fields: ["out": ""])
    host.properties["card id 12.name"] = "Home"
    try await run("""
    on mouseUp
      put the name of card id 12 into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "Home")
}

@Test func theIDOfReadsAnID() async throws {
    let host = MockHost(fields: ["out": ""])
    host.properties["button OK.id"] = "6"
    try await run("""
    on mouseUp
      get the id of button "OK"
      set the visible of button id it to false
    end mouseUp
    """, host: host)
    #expect(host.properties["button id 6.visible"] == "false")
}

@Test func idExpressionsCanBeComputed() async throws {
    let host = try await run("""
    on mouseUp
      put 4 into n
      set the width of button id (n + 2) to 100
    end mouseUp
    """)
    #expect(host.properties["button id 6.width"] == "100")
}

@Test func goToCardByID() async throws {
    let host = try await run("""
    on mouseUp
      go to card id 12
    end mouseUp
    """)
    #expect(host.destinations == [.id("12")])
}

// MARK: - Ordinals and domains

@Test func partsCanBeAddressedByOrdinal() async throws {
    let host = try await run("""
    on mouseUp
      set the name of field 1 to "First Field"
      set the width of button 2 to 90
    end mouseUp
    """)
    #expect(host.properties["field 1.name"] == "First Field")
    #expect(host.properties["button 2.width"] == "90")
}

@Test func domainQualifiersReachTheRightLayer() async throws {
    let host = try await run("""
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

@Test func ordinalsCanBeComputed() async throws {
    let host = try await run("""
    on mouseUp
      put 1 into n
      set the visible of field (n + 1) to false
    end mouseUp
    """)
    #expect(host.properties["field 2.visible"] == "false")
}

// MARK: - Field contents with domains, ordinals, and ids

@Test func fieldContentsRespectDomainQualifiers() async throws {
    let host = MockHost(fields: ["card 1": "on the card", "background 1": "on the bg"])
    try await run("""
    on mouseUp
      put " (card)" after card field 1
      put " (bg)" after background field 1
    end mouseUp
    """, host: host)
    #expect(host.fields["card 1"] == "on the card (card)")
    #expect(host.fields["background 1"] == "on the bg (bg)")
}

@Test func fieldContentsByOrdinalAndID() async throws {
    let host = MockHost(fields: ["2": "second", "id 9": "by id"])
    try await run("""
    on mouseUp
      put field 2 into a
      put field id 9 into b
      put a && b into field 2
    end mouseUp
    """, host: host)
    #expect(host.fields["2"] == "second by id")
}

@Test func fieldContentsByNameStillWork() async throws {
    let host = try await run("""
    on mouseUp
      put "hello" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "hello")
}
