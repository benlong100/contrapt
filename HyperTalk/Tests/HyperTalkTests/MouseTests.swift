//
//  MouseTests.swift
//  HyperTalk
//
//  `the mouse` — the button state ("up"/"down") polled by the classic
//  press-and-hold idiom (the HyperCard Tour's Parrot card):
//    repeat until the mouse is up
//      show card field "mandibles"
//    end repeat
//

import Foundation
import Testing
@testable import HyperTalk

@Test func theMouseReadsUpWhenNotPressed() async throws {
    let host = try await run("""
    on mouseUp
      put the mouse into field "state"
    end mouseUp
    """, host: MockHost(fields: ["state": ""]))
    #expect(host.fields["state"] == "up")
}

@Test func theMouseReadsDownWhilePressed() async throws {
    let mock = MockHost(fields: ["state": ""])
    mock.mouseDownPolls = 1
    let host = try await run("""
    on mouseDown
      put the mouse into field "state"
    end mouseDown
    """, handler: "mouseDown", host: mock)
    #expect(host.fields["state"] == "down")
}

@Test func mouseLocReadsThePointerAsHV() async throws {
    let host = MockHost(fields: ["out": ""])
    host.mousePath = [(120, 45)]
    try await run("""
    on mouseDown
      put the mouseLoc into field "out"
    end mouseDown
    """, handler: "mouseDown", host: host)
    #expect(host.fields["out"] == "120,45")
}

@Test func mouseHAndMouseVReadComponents() async throws {
    let host = MockHost(fields: ["out": ""])
    host.mousePath = [(120, 45)]
    try await run("""
    on mouseDown
      put the mouseH & "/" & the mouseV into field "out"
    end mouseDown
    """, handler: "mouseDown", host: host)
    #expect(host.fields["out"] == "120/45")
}

@Test func mouseLocReadsZeroWhenUntracked() async throws {
    let host = try await run("""
    on mouseUp
      put the mouseLoc into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "0,0")
}

@Test func dragLoopTracksTheMovingPointer() async throws {
    // The mid-drag idiom: poll the mouseLoc while the button is down. Each
    // poll sees the pointer's next position (and pauses a tick).
    let mock = MockHost(fields: ["out": ""])
    mock.mouseDownPolls = 3
    mock.mousePath = [(10, 10), (20, 15), (30, 20)]
    let host = try await run("""
    on mouseDown
      repeat until the mouse is up
        put field "out" & the mouseLoc & ";" into field "out"
      end repeat
    end mouseDown
    """, handler: "mouseDown", host: mock)
    #expect(host.fields["out"] == "10,10;20,15;30,20;")
}

@Test func clickLocReadsTheLastPressPoint() async throws {
    // DateBook's month grid: `item 2 of the clickLoc` finds the clicked row.
    let host = MockHost(fields: ["out": ""])
    host.clickValues[.location] = "204,120"
    try await run("""
    on mouseUp
      put item 2 of the clickLoc into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "120")
}

@Test func theMouseClickReadsFalseUntilAClickLands() async throws {
    // deleteHCLine's list idiom: `repeat until the mouseClick` waits for the
    // user to click a line. The poll reads false twice, then true on the
    // click — and each poll pauses a tick, like `the mouse`.
    let mock = MockHost(fields: ["count": "0"])
    mock.mouseClickPolls = 2
    let host = try await run("""
    on mouseUp
      repeat until the mouseClick
        add 1 to field "count"
      end repeat
    end mouseUp
    """, host: mock)
    #expect(host.fields["count"] == "2")
    #expect(host.waits == [Double](repeating: 1.0 / 60.0, count: 3))
}

@Test func theMouseClickIsTrueOnlyOncePerClick() async throws {
    // Consumed on read: a second read after the click is false again.
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put the mouseClick & "," & the mouseClick into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "true,false")
}

@Test func repeatUntilTheMouseIsUpExitsOnRelease() async throws {
    // The loop polls `the mouse`, sees "down" three times, then the release —
    // and each poll pauses a tick so the poll runs at HyperCard's cadence
    // rather than spinning through the step budget.
    let mock = MockHost(fields: ["count": "0"])
    mock.mouseDownPolls = 3
    let host = try await run("""
    on mouseDown
      repeat until the mouse is up
        add 1 to field "count"
      end repeat
    end mouseDown
    """, handler: "mouseDown", host: mock)
    #expect(host.fields["count"] == "3")
    #expect(host.waits == [Double](repeating: 1.0 / 60.0, count: 4))
}
