//
//  MeAsContentsTests.swift
//  HyperTalk
//
//  In a field's script, `me` is the field's contents (HyperCard 2.x): read
//  it, write it, chunk it. Any other object's `me` still reads as its name.
//

import Foundation
import Testing
@testable import HyperTalk

private func fieldLayer(_ script: String) -> [ScriptLayer] {
    [ScriptLayer(name: "field \"Name\" script", source: script,
                 object: .part(kind: "field", domain: .card, reference: .named("Name"), onCard: nil))]
}

@Test func meReadsAFieldsContents() async throws {
    let host = MockHost(fields: ["card name": "Marmot", "out": ""])
    _ = try await HyperTalk.send("closeField", along: fieldLayer("""
    on closeField
      put me into field "out"
    end closeField
    """), host: host)
    #expect(host.fields["out"] == "Marmot")
}

@Test func meWritesAFieldsContentsAndChunks() async throws {
    let host = MockHost(fields: ["card name": "Alpha\nBeta"])
    _ = try await HyperTalk.send("closeField", along: fieldLayer("""
    on closeField
      put "Gamma" into line 2 of me
      if line 1 of me is "Alpha" then put empty into me
    end closeField
    """), host: host)
    // Line 2 was rewritten, then the whole field cleared — both through `me`.
    #expect(host.fields["card name"] == "")
}

@Test func meOnAButtonStillReadsItsName() async throws {
    let host = MockHost(fields: ["out": ""])
    host.properties["card button OK.name"] = "OK"
    let layer = [ScriptLayer(name: "button \"OK\" script", source: """
    on mouseUp
      put me into field "out"
    end mouseUp
    """, object: .part(kind: "button", domain: .card, reference: .named("OK"), onCard: nil))]
    _ = try await HyperTalk.send("mouseUp", along: layer, host: host)
    #expect(host.fields["out"] == "OK")
}

@Test func selectLineOfMe() async throws {
    let host = MockHost(fields: ["card name": "Alpha\nBeta\nGamma"])
    _ = try await HyperTalk.send("mouseUp", along: fieldLayer("""
    on mouseUp
      select line 2 of me
    end mouseUp
    """), host: host)
    #expect(host.selections.first?.start == 6)
    #expect(host.selections.first?.end == 10)
}
