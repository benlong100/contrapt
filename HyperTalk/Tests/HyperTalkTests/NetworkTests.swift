//
//  NetworkTests.swift
//  HyperTalk
//
//  HTTP verbs (Contrapt "HyperCard, forward" — the network unlock). The `url`
//  container: GET via read, PUT via write, `post … to url`, `delete url`.
//  Transport errors surface through `the result`; these run against MockHost's
//  canned responses so they stay fast and offline.
//

import Testing
@testable import HyperTalk

@Test func urlGetReadsBodyIntoContainer() async throws {
    let host = MockHost()
    host.httpResponses["GET https://example.com/hi"] = ("hello", 200, nil)
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put url "https://example.com/hi" into msg
    end p
    """, host: host)
    #expect(host.messages.last == "hello")
    #expect(host.httpRequests.last?.method == "GET")
    #expect(host.httpRequests.last?.url == "https://example.com/hi")
}

@Test func urlGetSuccessClearsResult() async throws {
    let host = MockHost()
    host.httpResponses["GET https://example.com/ok"] = ("data", 200, nil)
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put url "https://example.com/ok" into body
      put the result into msg
    end p
    """, host: host)
    #expect(host.messages.last == "")
}

@Test func urlGetErrorGoesToResult() async throws {
    let host = MockHost()
    host.httpResponses["GET https://nope.example/"] = ("", 0, "Can't reach the server.")
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put url "https://nope.example/" into body
      put the result into msg
    end p
    """, host: host)
    #expect(host.messages.last == "Can't reach the server.")
}

@Test func urlPutSendsBody() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put "payload" into url "https://example.com/doc"
    end p
    """, host: host)
    #expect(host.httpRequests.last?.method == "PUT")
    #expect(host.httpRequests.last?.url == "https://example.com/doc")
    #expect(host.httpRequests.last?.body == "payload")
}

@Test func postToURLRepliesInIt() async throws {
    let host = MockHost()
    host.httpResponses["POST https://example.com/api"] = ("created", 201, nil)
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      post "name=hi" to url "https://example.com/api"
      put it into msg
    end p
    """, host: host)
    #expect(host.messages.last == "created")
    #expect(host.httpRequests.last?.method == "POST")
    #expect(host.httpRequests.last?.body == "name=hi")
}

@Test func deleteURLSendsDelete() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      delete url "https://example.com/doc"
    end p
    """, host: host)
    #expect(host.httpRequests.last?.method == "DELETE")
    #expect(host.httpRequests.last?.url == "https://example.com/doc")
}

@Test func jsonDecodeOfURLBuildsArray() async throws {
    let host = MockHost()
    host.httpResponses["GET https://example.com/weather.json"] =
        ("{\"main\":{\"temp\":72}}", 200, nil)
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put JSONDecode(url "https://example.com/weather.json") into data
      put data["main"]["temp"] into msg
    end p
    """, host: host)
    #expect(host.messages.last == "72")
}

@Test func urlPutSendsArrayAsJSON() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put "hot" into data["temp"]
      put data into url "https://example.com/state"
    end p
    """, host: host)
    #expect(host.httpRequests.last?.method == "PUT")
    #expect(host.httpRequests.last?.body == "{\n  \"temp\": \"hot\"\n}")
}
