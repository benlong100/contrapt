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
      show message watcher
      show variable watcher
    end mouseUp
    """)
}

@Test func menuObjectIsAbsentAndDeleteIsNoOp() async throws {
    // Home stacks manage their own menus: `if there is a menu "X" then delete
    // menu "X"`. Contrapt has no menus, so the test is false and delete no-ops.
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      if there is a menu "Home" then delete menu "Home"
      if there is not a menu "Home" then put "no menu" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "no menu")
}

@Test func thisAcceptsCdAndBgAbbreviations() async throws {
    // The Home stack writes `short name of this cd` and `this bg` throughout.
    let host = MockHost(fields: ["out": ""])
    host.properties["this card.name"] = "Welcome"
    _ = try await run("""
    on mouseUp
      put short name of this cd into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "Welcome")
}

@Test func bareNumberOfCardsInBackgroundCounts() async throws {
    // The Home stack: `put number of cds in this bg into numBgCards`. Bare
    // `number of <plural>` is a count; the `in this bg` scope is consumed.
    let host = MockHost(fields: ["out": ""])
    host.cardCount = 7
    _ = try await run("""
    on mouseUp
      put number of cds in this bg into field "out"
      put number of cds of first bg into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "7")
}

@Test func bareNumberOfThisCardIsOrdinalProperty() async throws {
    // `number of this cd` (singular) is the card's position, not a count.
    let host = MockHost(fields: ["out": ""])
    host.properties["this card.number"] = "3"
    _ = try await run("""
    on mouseUp
      put number of this cd into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "3")
}

@Test func setPartPropertyScopedToACardParses() async throws {
    // The Home stack: `set name of bg btn (curCard-adjust) of cd curCard to …`.
    // The owning-card scope is parsed and ignored (bg parts are shared), and
    // the parenthesised index and `set … to …` still resolve.
    let host = MockHost()
    host.properties["background button 2.name"] = "old"
    _ = try await run("""
    on mouseUp
      put 3 into curCard
      put 1 into adjust
      set name of bg btn (curCard-adjust) of cd curCard to "Welcome"
      set hilite of bg btn (curCard-adjust) of cd curCard to true
    end mouseUp
    """, host: host)
    #expect(host.properties["background button 2.name"] == "Welcome")
    #expect(host.properties["background button 2.hilite"] == "true")
}

@Test func messageBoxVisibleReadsFalseAndSetIsNoOp() async throws {
    // The Home stack's newLink saves/restores the message box:
    // `put visible of msg box into saveVisMsgBox` … `set visible of msg box to …`.
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      put visible of msg box into saveVis
      set visible of message box to true
      put saveVis into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "false")
}

@Test func lastAndFirstPartOrdinalsResolve() async throws {
    // The Home stack's makeNewHCButton addresses the just-created button as
    // `last cd btn`: `set script of last cd btn to …`, `id of last cd btn`.
    let host = MockHost(fields: ["out": ""])
    host.buttonCount = 3
    host.properties["card button 3.name"] = "New"
    _ = try await run("""
    on mouseUp
      set name of last cd btn to "Renamed"
      set name of first cd btn to "Top"
      put name of last cd btn into field "out"
    end mouseUp
    """, host: host)
    #expect(host.properties["card button 3.name"] == "Renamed")
    #expect(host.properties["card button 1.name"] == "Top")
    #expect(host.fields["out"] == "Renamed")
}

@Test func indirectObjectReferenceThroughAVariable() async throws {
    // dragHCButton receives a descriptor in a variable and drives the part
    // through it: `set hilite of theButton to not hilite of theButton`.
    let host = MockHost()
    host.properties["card button id 34.hilite"] = "false"
    _ = try await run("""
    on mouseUp
      put "cd btn id 34" into theButton
      set hilite of theButton to not hilite of theButton
    end mouseUp
    """, host: host)
    #expect(host.properties["card button id 34.hilite"] == "true")
}

@Test func goCardOfBackgroundOfStackChains() async throws {
    // The Home stack's updateHCPaths:
    // `go cd fileType of bkgnd "Paths" of stack "Home"`.
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      put "Stacks" into fileType
      go cd fileType of bkgnd "Paths" of stack "Home"
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .stack(name: "Home", card: .inBackground(.named("Stacks"), background: "Paths")))
}

@Test func namedStackIsAbsentAndNameEchoes() async throws {
    // The Home stack's startUp: `if there is a stack "Audio Help" then …`.
    // Absent, so the guarded audio-palette block is skipped; a named stack's
    // short name echoes back (menuReset compares long names).
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      if there is a stack "Audio Help" then put "has audio" into field "out"
      if there is not a stack "Audio Help" then put the short name of stack "Phone" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "Phone")
}

@Test func putIntoMenuIsANoOp() async throws {
    // createTheMenus builds the Home menu:
    // `put homeMenuItems() into menu "Home" with menuMsgs homeMenuMsgs()`.
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      put "New,Open,-,Quit" into menu "Home" with menuMsgs "a,b,c,d"
      put "ok" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "ok")
}

@Test func goStackInANewWindowIgnoresTheModifier() async throws {
    // The Home stack's help handler: `go to stack theStack in a new window`.
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      put "HyperCard Help" into theStack
      go to stack theStack in a new window
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .stack(name: "HyperCard Help", card: nil))
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

@Test func goCardScopedToBackground() async throws {
    // `go card 1 of bkgnd "X"` scopes the card to that background.
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      go card 1 of bkgnd "Weekly"
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .inBackground(.number(1), background: "Weekly"))
}

@Test func clickAtTwoNumbers() async throws {
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      click at 100,120
    end mouseUp
    """, host: host)
    #expect(host.clickedAt?.x == 100)
    #expect(host.clickedAt?.y == 120)
}

@Test func clickAtSinglePointValue() async throws {
    // `click at loc of ...` — a single "h,v" value.
    let host = MockHost()
    host.properties["button OK.loc"] = "40,55"
    _ = try await run("""
    on mouseUp
      click at the loc of button "OK"
    end mouseUp
    """, host: host)
    #expect(host.clickedAt?.x == 40)
    #expect(host.clickedAt?.y == 55)
}

@Test func chooseToolIsIgnored() async throws {
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      choose browse tool
      put "ok" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "ok")
}

@Test func goCardByVariableWithStackQualifier() async throws {
    // `go card whichSix of stack "X"` — the variable card number mustn't be
    // read as a bare property; it resolves to that card within the stack.
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      put 3 into whichSix
      go card whichSix of stack "DateBook"
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .stack(name: "DateBook", card: .number(3)))
}

@Test func goAcceptsCdAbbreviation() async throws {
    let host = MockHost()
    host.currentCardID = "1"
    _ = try await run("""
    on mouseUp
      put 2 into n
      go cd n
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .number(2))
}

@Test func goToStackByName() async throws {
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      go to stack "Phone"
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .stack(name: "Phone", card: nil))
}

@Test func goCardOfStack() async throws {
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      go card 3 of stack "DateBook"
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .stack(name: "DateBook", card: .number(3)))
}

@Test func goToBareNameIsACardDestination() async throws {
    // `go to "Phone"` — a bare name resolves as a card reference.
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      go to "Phone"
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .named("Phone"))
}

@Test func bareDoMenuAndNumberOfLinesIn() async throws {
    // `doMenu select all` (bare multi-word) parses; `the number of lines in X`
    // accepts `in` for `of`.
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      doMenu select all
      doMenu clear picture
      put "a" & return & "b" & return & "c" into what
      put the number of lines in what into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "3")
    #expect(host.performedMenu.contains("select all"))
}

@Test func paintToolCommandsAndGlobalsAreNoOps() async throws {
    // A paint-tool script must parse and run without erroring, even though
    // Contrapt doesn't script painting.
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      choose oval tool
      set filled to false
      set centered to false
      set lineSize to 1
      drag from 160,140 to 210,90
      type "hello"
      reset paint
      choose browse tool
      put "ok" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "ok")
}

@Test func settingEnvironmentGlobalsIsAcceptedAsNoOp() async throws {
    // `set cursor to 4`, `set lockScreen to true`, etc. must not error.
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      set cursor to 4
      set lockScreen to true
      set userLevel to 5
      put "ok" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "ok")
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
