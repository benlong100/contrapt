import Foundation
import Testing
@testable import HyperTalk

@Test func langAddStackAllScriptsParse() throws {
    // Pull every script out of the regenerated stack and parse-check it.
    let url = URL(fileURLWithPath: "/Users/wanderer/Desktop/Homemade Apps/HyperPad/Contrapt/Language Additions.contrapt")
    let data = try Data(contentsOf: url)
    // Store-only zip: find the stack.json entry payload via the JSON itself —
    // simplest: scan for the first '{' and parse from there to the end minus
    // the central directory is fragile, so unzip properly is better. Instead,
    // rely on the file layout: stored entry at a fixed header offset.
    // Local file header is 30 bytes + name length (10, "stack.json").
    let payload = data.dropFirst(30 + 10)
    // The JSON ends where the central directory begins (PK\x01\x02).
    let marker = Data([0x50, 0x4B, 0x01, 0x02])
    guard let end = payload.range(of: marker)?.lowerBound else {
        Issue.record("couldn't find central directory"); return
    }
    let json = payload[payload.startIndex..<end]
    struct P: Decodable { let script: String }
    struct C: Decodable { let script: String; let parts: [P] }
    struct B: Decodable { let script: String; let parts: [P] }
    struct S: Decodable { let script: String; let cards: [C]; let backgrounds: [B] }
    let s = try JSONDecoder().decode(S.self, from: Data(json))
    var scripts = [s.script] + s.backgrounds.map(\.script) + s.cards.map(\.script)
    scripts += s.backgrounds.flatMap { $0.parts.map(\.script) }
    scripts += s.cards.flatMap { $0.parts.map(\.script) }
    for script in scripts where !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        try HyperTalk.check(script)
    }
}
