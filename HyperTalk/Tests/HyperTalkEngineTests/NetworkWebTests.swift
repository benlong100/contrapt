//
//  NetworkWebTests.swift
//  HyperTalkEngine
//
//  The exported page's `url`/`post`/`delete url` path: WebHost delegates to the
//  EngineInteraction.httpRequest bridge (a `fetch` call in the browser), and the
//  script's httpHeaders/httpTimeout flow through, with status/headers read back.
//  Run against a canned interaction so they stay offline. The modal-state
//  behaviour itself is covered by HyperTalk's MockHost NetworkTests; here we
//  exercise it through one handler to prove the web bridge carries it all.
//

import Foundation
import Testing
@testable import HyperTalkEngine

// One card whose script probes the network a few ways, reporting through the
// message box so a test can read the result via the drained effects.
private let netJSON = """
{
  "formatVersion": 1, "id": "11111111-1111-1111-1111-111111111111",
  "name": "Net", "cardSize": {"width": 400, "height": 300}, "script": "",
  "backgrounds": [
    { "id": "22222222-2222-2222-2222-222222222222", "name": "BG", "script": "", "parts": [] }
  ],
  "cards": [
    { "id": "33333333-3333-3333-3333-333333333333", "name": "C1",
      "backgroundID": "22222222-2222-2222-2222-222222222222", "parts": [],
      "script": "on probe\\nset the httpHeaders to \\"Accept: text/plain\\"\\nset the httpTimeout to 15\\nput url \\"https://example.com/x\\"\\nend probe\\n\\non probeStatus\\nput url \\"https://example.com/made\\" into it\\nput the httpStatus & \\",\\" & (line 1 of the keys of the httpResponseHeaders)\\nend probeStatus\\n\\non probeErr\\nput url \\"https://example.com/x\\" into it\\nput the result\\nend probeErr" }
  ]
}
""".data(using: .utf8)!

/// The last message-box text among drained effects.
private func lastMessage(_ effects: [HostEffect]) -> String? {
    for effect in effects.reversed() { if case .message(let text) = effect { return text } }
    return nil
}

@Test func webHostGetDelegatesToInteraction() async throws {
    let interaction = EngineInteraction(httpRequest: { method, url, _, _, _ in
        ("\(method):\(url)", 200, [:], nil)
    })
    let engine = try StackEngine(stackJSON: netJSON, interaction: interaction)
    let body = try await engine.runMessage("url \"https://example.com/ping\"")
    #expect(body == "GET:https://example.com/ping")
}

@Test func webHostCarriesHeadersAndTimeout() async throws {
    // Reflect the request's header + timeout back through the body so the test
    // can confirm they crossed the bridge.
    let interaction = EngineInteraction(httpRequest: { _, _, _, headers, timeout in
        ("\(headers["Accept"] ?? "none")|\(Int(timeout))", 200, [:], nil)
    })
    let engine = try StackEngine(stackJSON: netJSON, interaction: interaction)
    _ = try await engine.runMessage("probe")
    #expect(lastMessage(engine.drainEffects()) == "text/plain|15")
}

@Test func webHostStatusAndResponseHeadersReadBack() async throws {
    let interaction = EngineInteraction(httpRequest: { _, _, _, _, _ in
        ("body", 201, ["Content-Type": "application/json"], nil)
    })
    let engine = try StackEngine(stackJSON: netJSON, interaction: interaction)
    _ = try await engine.runMessage("probeStatus")
    #expect(lastMessage(engine.drainEffects()) == "201,Content-Type")
}

@Test func webHostDefaultInteractionReportsUnavailable() async throws {
    let engine = try StackEngine(stackJSON: netJSON)   // default interaction
    _ = try await engine.runMessage("probeErr")
    #expect(lastMessage(engine.drainEffects()) == "Networking isn't available here.")
}
