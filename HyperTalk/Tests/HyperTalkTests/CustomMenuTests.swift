//
//  CustomMenuTests.swift
//  Scripted custom menus: create/delete/put-into/enable/disable/reset,
//  property reads and sets, existence, counts, and doMenu menuMessage routing.
//

import Testing
@testable import HyperTalk

@Test func createPopulateAndReadMenu() async throws {
    let host = try await run("""
    on p
      create menu "Games"
      put "Chess,Checkers,-,Quit Games" into menu "Games"
      put the number of menus & "|" & the number of menuItems of menu "Games" ¬
        & "|" & the name of menuItem 2 of menu "Games" ¬
        & "|" & (there is a menu "Games") & (there is a menu "Nope")
    end p
    """, handler: "p")
    #expect(host.messages.last == "1|4|Checkers|truefalse")
}

@Test func menuTextAndLastItem() async throws {
    let host = try await run("""
    on p
      create menu "M"
      put "a,b,c" into menu "M"
      put the name of last menuItem of menu "M" & "|" & the number of lines in (the text of menu "M")
    end p
    """, handler: "p")
    #expect(host.messages.last == "c|3")
}

@Test func enableDisableAndCheckmark() async throws {
    let host = try await run("""
    on p
      create menu "M"
      put "one,two" into menu "M"
      disable menuItem 1 of menu "M"
      set the checkMark of menuItem 2 of menu "M" to true
      disable menu "M"
      put the enabled of menuItem 1 of menu "M" & the checkMark of menuItem 2 of menu "M" & the enabled of menu "M"
      enable menu "M"
      put the enabled of menu "M"
    end p
    """, handler: "p")
    #expect(host.messages.dropLast().last == "falsetruefalse")
    #expect(host.messages.last == "true")
}

@Test func deleteItemMenuAndReset() async throws {
    let host = try await run("""
    on p
      create menu "A"
      put "x,y,z" into menu "A"
      delete menuItem 2 of menu "A"
      put the number of menuItems of menu "A" into n1
      create menu "B"
      delete menu "B"
      put n1 & "|" & the number of menus into r
      reset menubar
      put r & "|" & the number of menus
    end p
    """, handler: "p")
    #expect(host.messages.last == "2|1|0")
}

@Test func doMenuSendsTheItemsMenuMessage() async throws {
    let host = try await run("""
    on p
      create menu "Go"
      put "Home,Away" into menu "Go" with menuMessages "goHomeNow,goAway"
      doMenu "Home"
      put "after " & the result
    end p

    on goHomeNow
      put "message routed"
    end goHomeNow
    """, handler: "p")
    #expect(host.messages.contains("message routed"))
}

@Test func putAfterAppendsToMenu() async throws {
    let host = try await run("""
    on p
      create menu "M"
      put "a,b" into menu "M"
      put "c" after menu "M"
      put the number of menuItems of menu "M" & the name of menuItem 3 of menu "M"
    end p
    """, handler: "p")
    #expect(host.messages.last == "3c")
}

@Test func theMenusListsNamesAndModifiersReadUp() async throws {
    // `the menus` is the return-separated name list; modifier keys read
    // through the host ("up" on a host without a keyboard).
    let host = try await run("""
    on p
      create menu "A"
      create menu "B"
      put the number of lines in (the menus) & "|" & line 2 of the menus ¬
        & "|" & the optionKey & the shiftKey & the commandKey
    end p
    """, handler: "p")
    #expect(host.messages.last == "2|B|upupup")
}
