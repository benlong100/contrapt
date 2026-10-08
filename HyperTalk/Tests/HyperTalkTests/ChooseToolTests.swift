//
//  ChooseToolTests.swift
//  HyperTalk
//
//  `choose <name> tool` and `the tool` — the tool machinery behind HyperCard's
//  script-delete idiom (choose button tool / click at … / doMenu "Clear
//  Button" / choose browse tool). The selection behavior itself lives in the
//  app host; these pin the language plumbing.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func chooseToolReachesTheHost() async throws {
    let host = try await run("""
    on mouseUp
      choose button tool
      choose field tool
      choose browse tool
    end mouseUp
    """)
    #expect(host.chosenTools == ["button", "field", "browse"])
}

@Test func choosePaintToolsAlsoReachTheHost() async throws {
    // Paint tools parse to the same statement; the host decides they no-op.
    let host = try await run("""
    on mouseUp
      choose select tool
      choose text tool
    end mouseUp
    """)
    #expect(host.chosenTools == ["select", "text"])
}

@Test func otherChooseFormsAreIgnored() async throws {
    // `choose tool 3` (by number) isn't modeled — accepted and ignored.
    let host = try await run("""
    on mouseUp
      choose tool 3
      beep
    end mouseUp
    """)
    #expect(host.chosenTools.isEmpty)
    #expect(host.beeps == 1)
}

@Test func theToolReadsTheHostsName() async throws {
    let host = MockHost(fields: ["out": ""])
    host.toolName = "button tool"
    try await run("""
    on mouseUp
      put the tool into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "button tool")
}

@Test func theToolGuardIdiomWorks() async throws {
    // `if the tool is "browse tool"` — the common save/guard idiom.
    let host = try await run("""
    on mouseUp
      if the tool is "browse tool" then beep
    end mouseUp
    """)
    #expect(host.beeps == 1)
}

@Test func dragDispatchesToHostAndPaintGlobalsRead() async throws {
    // `drag from h,v to h,v` is a real statement now (scripted painting);
    // point pairs or single "h,v" values both work, `with <keys>` is ignored.
    // Paint globals read host-backed defaults and sets are accepted.
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      choose line tool
      set the lineSize to 4
      drag from 10,20 to 110,120 with shiftKey
      drag from the clickLoc to 5,6
      reset paint
      put the lineSize & "," & the pattern & "," & the filled
    end p
    """, host: host, maxSteps: 1000)
    #expect(host.drags.count == 2)
    #expect(host.drags.first! == Drag(fromX: 10, fromY: 20, toX: 110, toY: 120))
    // MockHost doesn't store paint settings — reads are the HC defaults.
    #expect(host.messages.last == "1,12,false")
}
