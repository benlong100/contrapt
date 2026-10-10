//
//  PersistenceTests.swift
//  HyperTalk
//
//  `stackData` — the stack's persistent key-value store, modeled as an
//  associative array backed by the host. Reuses the array machinery: bracket
//  get/set, nesting, keys/count, JSON, iteration. The point of the feature is
//  surviving between runs, so several tests write in one handler run and read
//  in a separate run against the same host (which retains the store).
//

import Testing
@testable import HyperTalk

@Test func stackDataSetAndGetInOneRun() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put 500 into stackData["highScore"]
      put stackData["highScore"] into msg
    end p
    """, host: host)
    #expect(host.messages.last == "500")
}

@Test func stackDataSurvivesBetweenRuns() async throws {
    let host = MockHost()
    // First run writes; a separate run (fresh interpreter, same host) reads it
    // back — the between-runs guarantee the feature exists for.
    _ = try await HyperTalk.run(handler: "save", in: """
    on save
      put "Ada" into stackData["name"]
    end save
    """, host: host)
    _ = try await HyperTalk.run(handler: "load", in: """
    on load
      put stackData["name"] into msg
    end load
    """, host: host)
    #expect(host.messages.last == "Ada")
}

@Test func stackDataNests() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put "dark" into stackData["prefs"]["theme"]
      put stackData["prefs"]["theme"] into msg
    end p
    """, host: host)
    #expect(host.messages.last == "dark")
}

@Test func stackDataKeysAndCount() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put 1 into stackData["a"]
      put 2 into stackData["b"]
      put the number of elements of stackData into msg
    end p
    """, host: host)
    #expect(host.messages.last == "2")
}

@Test func stackDataIteratesWithRepeatForEachKey() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put 10 into stackData["x"]
      put 20 into stackData["y"]
      put 0 into total
      repeat for each key k in stackData
        add stackData[k] to total
      end repeat
      put total into msg
    end p
    """, host: host)
    #expect(host.messages.last == "30")
}

@Test func stackDataShowsReadableJSONAtSink() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put "hot" into stackData["temp"]
      put stackData into msg
    end p
    """, host: host)
    #expect(host.messages.last == "{\n  \"temp\": \"hot\"\n}")
}

@Test func stackDataRoundTripsThroughJSONEncode() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put 7 into stackData["n"]
      put JSONEncode(stackData) into msg
    end p
    """, host: host)
    #expect(host.messages.last == "{\"n\":7}")
}

@Test func stackDataStartsEmpty() async throws {
    // An untouched store reads empty (0 elements) — a stack that has never
    // saved simply has nothing, rather than erroring.
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put the number of elements of stackData into msg
    end p
    """, host: host)
    #expect(host.messages.last == "0")
}
