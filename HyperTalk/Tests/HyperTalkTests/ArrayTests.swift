//
//  ArrayTests.swift
//  HyperTalk
//
//  Associative arrays (Contrapt structured data) — bracket get/set, nesting,
//  keys/count, chunk composition, and readable JSON display at a visible sink.
//

import Testing
@testable import HyperTalk

@Test func arraySetAndGet() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put 5 into counts["apples"]
      put counts["apples"] into msg
    end p
    """, host: host)
    #expect(host.messages.last == "5")
}

@Test func arrayNestedSetAndGet() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put "hot" into data["main"]["temp"]
      put data["main"]["temp"] into msg
    end p
    """, host: host)
    #expect(host.messages.last == "hot")
}

@Test func arrayKeysAndCount() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put 1 into counts["apples"]
      put 2 into counts["bananas"]
      put the keys of counts into msg
    end p
    """, host: host)
    #expect(host.messages.last == "apples\nbananas")

    let host2 = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put 1 into counts["apples"]
      put 2 into counts["bananas"]
      put the number of elements of counts into msg
    end p
    """, host: host2)
    #expect(host2.messages.last == "2")
}

@Test func arrayElementComposesWithChunks() async throws {
    // A string element still supports HyperCard chunk expressions.
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put "a,b,c" into data["list"]
      put item 2 of data["list"] into msg
    end p
    """, host: host)
    #expect(host.messages.last == "b")
}

@Test func arrayDisplaysAsJSONAtVisibleSink() async throws {
    // Putting an array to the message box renders readable JSON (not the
    // internal encoding). A variable copy keeps the array (round-trips).
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put 5 into counts["apples"]
      put counts into other
      put counts into msg
    end p
    """, host: host)
    #expect(host.messages.last == "{\n  \"apples\": 5\n}")
}

@Test func unsetElementIsEmpty() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put ("[" & counts["missing"] & "]") into msg
    end p
    """, host: host)
    #expect(host.messages.last == "[]")
}
