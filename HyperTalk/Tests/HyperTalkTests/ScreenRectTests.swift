//
//  ScreenRectTests.swift
//  HyperTalk
//
//  `the screenRect` — HyperCard's display rectangle. Contrapt shows one card
//  (effectively the screen), so it reports "0,0,<stackWidth>,<stackHeight>"
//  rather than echoing the bare word and failing when used numerically.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func theScreenRectReportsStackBounds() async throws {
    let host = MockHost(fields: ["out": ""])
    host.properties["this stack.width"] = "640"
    host.properties["this stack.height"] = "480"
    _ = try await run("""
    on mouseUp
      put the screenRect into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "0,0,640,480")
}

@Test func screenRectItemIsNumeric() async throws {
    // The whole point: items of the screenRect coerce to numbers.
    let host = MockHost(fields: ["out": ""])
    host.properties["this stack.width"] = "512"
    host.properties["this stack.height"] = "342"
    _ = try await run("""
    on mouseUp
      put (item 3 of the screenRect) - 12 into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "500")
}
