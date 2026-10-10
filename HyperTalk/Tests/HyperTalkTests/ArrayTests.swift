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

@Test func jsonDecodeReadsNestedValues() async throws {
    // HyperTalk string literals have no \" escape, so assemble the JSON with
    // the `quote` constant: {"main":{"temp":72},"ok":true}
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put "{" & quote & "main" & quote & ":{" & quote & "temp" & quote & ":72}," & quote & "ok" & quote & ":true}" into j
      put JSONDecode(j) into data
      put data["main"]["temp"] & "," & data["ok"] into msg
    end p
    """, host: host)
    #expect(host.messages.last == "72,true")
}

@Test func jsonDecodeArrayUsesNumericKeys() async throws {
    // JSON array ["a","b","c"] → numeric keys "1".."3".
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put "[" & quote & "a" & quote & "," & quote & "b" & quote & "," & quote & "c" & quote & "]" into j
      put JSONDecode(j) into list
      put list["2"] & "/" & the number of elements of list into msg
    end p
    """, host: host)
    #expect(host.messages.last == "b/3")
}

@Test func jsonEncodeRoundTrips() async throws {
    // Build an array, encode to JSON, decode back, read a value.
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put 72 into data["temp"]
      put "sf" into data["city"]
      put JSONDecode(JSONEncode(data))["temp"] into msg
    end p
    """, host: host)
    #expect(host.messages.last == "72")
}

@Test func repeatForEachKeyAndElement() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put 10 into scores["a"]
      put 20 into scores["b"]
      put 0 into total
      repeat for each element e in scores
        add e to total
      end repeat
      put "" into klist
      repeat for each key k in scores
        put k after klist
      end repeat
      put total & "/" & klist into msg
    end p
    """, host: host)
    #expect(host.messages.last == "30/ab")
}

@Test func splitAndCombineRoundTrip() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put "a,b,c" into list
      split list
      put list["2"] into picked
      combine list by "-"
      put picked & "/" & list into msg
    end p
    """, host: host)
    #expect(host.messages.last == "b/a-b-c")
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
