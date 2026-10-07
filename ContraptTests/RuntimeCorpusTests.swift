//
//  RuntimeCorpusTests.swift
//  ContraptTests
//
//  Tool #4 (runtime coverage): imports classic corpus stacks through the real
//  app importer and runs their openStack/openCard handlers against the app's
//  own DocumentScriptHost, surfacing RUNTIME errors that parsing can't (the
//  class id-122 / missing-field / cantAbort belonged to).
//
//  Opt-in so normal runs stay fast:
//      CONTRAPT_RUNTIME=1 xcodebuild test -scheme ContraptTests -destination 'platform=macOS'
//  Writes a ranked report to corpus-runtime-audit.txt at the project root.
//

import Foundation
import SwiftUI
import Testing
import HyperTalk
@testable import Contrapt

@MainActor
@Test func importerRunsHeadlessly() throws {
    // Smoke test (always on): the headless app-test infrastructure works.
    // Imports the first classic stack found under the project root, so it
    // doesn't break when individual stacks are moved or renamed.
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad"
    guard let path = classicStackFiles(under: root).first else {
        Issue.record("No classic stack found under \(root) to smoke-test the importer.")
        return
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let imported = try LegacyStackImporter.stack(from: data, name: (path as NSString).lastPathComponent)
    #expect(!imported.stack.cards.isEmpty)
    #expect(!imported.stack.backgrounds.isEmpty)
}

@MainActor
@Test func usingStackResolvesClassicSibling() throws {
    // `start using stack "The Library"` must load a classic sibling STAK and
    // expose its stack script (which defines `justOpened`) for H2G2.
    let dir = "/Users/wanderer/Desktop/Homemade Apps/HyperPad/New Stacks - Oct 5/H2G2_HyperCard"
    guard FileManager.default.fileExists(atPath: dir + "/The Library") else { return }
    StackLibrary.shared.register(url: URL(fileURLWithPath: dir).appendingPathComponent("The Library"))
    UsingStackStore.shared.end("The Library")
    UsingStackStore.shared.begin("The Library")
    let scripts = UsingStackStore.shared.stacks
    // The classic sibling loads, and its stack script (which defines
    // `justOpened`) is exposed for the message hierarchy.
    #expect(!scripts.isEmpty)
    #expect(scripts.first?.source.lowercased().contains("on justopened") == true)
    UsingStackStore.shared.reset()
}

@MainActor
@Test func caperImportsCardFieldText() throws {
    // Caper in the Castro is a format-8 (1.x) stack whose card-field contents
    // are `[i16 partID][NUL text]` entries with negative card-field ids and no
    // leading size word. Regression: the text must land in the fields (not leak
    // into the card name). Skips gracefully when the corpus isn't present.
    let path = "/Users/wanderer/Desktop/Homemade Apps/HyperPad/New Stacks - Oct 5 2nd batch/hypercard_caper-in-the-castro/Caper in the Castro"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let stack = try LegacyStackImporter.importedStack(from: URL(fileURLWithPath: path)).stack
    let card0 = stack.cards[0]
    // The content no longer leaks into the name.
    #expect(card0.name == "Introduction")
    func fieldText(_ scriptID: Int) -> String? {
        for part in card0.parts where part.scriptID == scriptID {
            if case .field(let f) = part.kind { return f.text }
        }
        return nil
    }
    #expect(fieldText(4)?.contains("Caper in the Castro was written") == true)
    #expect(fieldText(6)?.contains("From the Author") == true)
}

@MainActor
@Test func manholeCrossFileSiblingsResolve() throws {
    // The Manhole is six classic stack files whose rooms link across them with
    // `go … of stack "the Manhole N"`. Import-time sibling registration must
    // make every file resolvable by name, and each must re-import in place
    // (the engine of single-window cross-stack navigation). Skips gracefully
    // when the corpus isn't present.
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad"
    let manhole = classicStackFiles(under: root).first {
        ($0 as NSString).lastPathComponent.lowercased() == "the manhole"
    }
    guard let manhole else { return }

    StackLibrary.shared.registerSiblings(of: URL(fileURLWithPath: manhole), actualSize: false)
    for name in ["the manhole", "the manhole 2", "the manhole 3",
                 "the manhole 4", "the manhole 5", "the manhole 6"] {
        #expect(StackLibrary.shared.url(forName: name) != nil, "sibling \(name) should resolve")
    }

    // A resolved classic sibling imports in place with real cards — what a
    // cross-stack `go` hands to `document.present(...)`.
    let sibling = try #require(StackLibrary.shared.url(forName: "the manhole 2"))
    let imported = try LegacyStackImporter.importedStack(from: sibling, presentAtActualSize: false)
    #expect(!imported.stack.cards.isEmpty)
}

@MainActor
@Test func buttonIconPropertyRoundTrips() throws {
    // `the icon of button` reads the icon resource id, and `set the icon … to
    // N` writes it back (round-trips) rather than erroring "no icon property".
    var stack = Stack.makeNew()
    guard let bIndex = stack.cards[0].parts.firstIndex(where: {
        if case .button = $0.kind { return true } else { return false }
    }) else { Issue.record("no button on card 0"); return }
    if case .button(var b) = stack.cards[0].parts[bIndex].kind {
        b.iconID = 1234
        stack.cards[0].parts[bIndex].kind = .button(b)
    }
    let scriptID = stack.cards[0].parts[bIndex].scriptID
    var index = 0
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i }
    )
    let button = HyperTalkObject.part(kind: "button", domain: .card,
                                      reference: .id(String(scriptID)), onCard: nil)
    #expect(try host.propertyValue("icon", of: button) == "1234")
    try host.setProperty("icon", of: button, to: "5678")
    #expect(try host.propertyValue("icon", of: button) == "5678")
    // Setting by icon NAME (HyperCard allows it) is accepted, not an error, and
    // leaves the current id in place (Contrapt can't resolve a name to a glyph).
    try host.setProperty("icon", of: button, to: "General Essay")
    #expect(try host.propertyValue("icon", of: button) == "5678")
}

@MainActor
@Test func xcmdShimRegistryRoutesExternals() async throws {
    // A recorded external with a native shim runs it (FontExists — headless-
    // safe); an unknown external stays accepted-and-ignored (empty value).
    var stack = Stack.makeNew()
    stack.externalCommands = ["FontExists", "MysteryXCMD"]
    var index = 0
    var shown: [String] = []
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { shown.append($0) },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i }
    )
    let layers = try #require(host.scriptLayers(for: .thisCard))
    try await HyperTalk.send("probeShims", along: [ScriptLayer(name: "t", source: """
    on probeShims
      put FontExists("Helvetica") & "|" & FontExists("NoSuchFontFace99") & "|" & MysteryXCMD("x")
    end probeShims
    """, object: .thisCard)] + layers, host: host)
    #expect(shown.last == "true|false|")
}

@MainActor
@Test func fileIORoundTripsOnDisk() async throws {
    // open/write/close then open/read/close against the REAL sandboxed disk
    // (Application Support/HyperTalk Files), classic colon path mapped to its
    // last component. Failures report via `the result`, not script errors.
    var stack = Stack.makeNew()
    var index = 0
    var shown: [String] = []
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { shown.append($0) },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i }
    )
    let layers = try #require(host.scriptLayers(for: .thisCard))
    try await HyperTalk.send("probeFileIO", along: [ScriptLayer(name: "t", source: """
    on probeFileIO
      open file "HD:Data:contrapt-test-file"
      write "hello" & return & "disk" to file "HD:Data:contrapt-test-file"
      close file "HD:Data:contrapt-test-file"
      open file "contrapt-test-file"
      read from file "contrapt-test-file" until return
      put it into one
      read from file "contrapt-test-file" for 99
      put one & it & "|" & the result
      close file "contrapt-test-file"
    end probeFileIO
    """, object: .thisCard)] + layers, host: host)
    #expect(shown.last == "hello\ndisk|eof")
    // Cleanup the real file.
    let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: false)
        .appendingPathComponent("HyperTalk Files/contrapt-test-file")
    try? FileManager.default.removeItem(at: url)
}

@MainActor
@Test func scrollOfFieldRoundTrips() throws {
    // `the scroll of field` is modeled: set stores the offset on the field,
    // get reads it back, negatives clamp to 0, and buttons have no scroll.
    var stack = Stack.makeNew()
    guard let fIndex = stack.cards[0].parts.firstIndex(where: {
        if case .field = $0.kind { return true } else { return false }
    }) else { Issue.record("no field on card 0"); return }
    let scriptID = stack.cards[0].parts[fIndex].scriptID
    var index = 0
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i }
    )
    let field = HyperTalkObject.part(kind: "field", domain: .card,
                                     reference: .id(String(scriptID)), onCard: nil)
    #expect(try host.propertyValue("scroll", of: field) == "0")
    try host.setProperty("scroll", of: field, to: "144")
    #expect(try host.propertyValue("scroll", of: field) == "144")
    if case .field(let f) = stack.cards[0].parts[fIndex].kind {
        #expect(f.scroll == 144)
    } else { Issue.record("field lost its kind") }
    try host.setProperty("scroll", of: field, to: "-20")
    #expect(try host.propertyValue("scroll", of: field) == "0")
    // Round-trips through the manifest (persisted like HyperCard persists it).
    let reloaded = try Stack(fileData: stack.fileData()).sanitized()
    var found = false
    for p in reloaded.cards[0].parts { if case .field(let f) = p.kind, f.scroll == 0 { found = true } }
    #expect(found)
}

@MainActor
@Test func setThinPartGeometryIsNotInflated() throws {
    // A script that sets a part's height or rect to a thin value (classic
    // stacks' 2px footer rules — The Hacker Crackdown's "divider") must keep
    // that height. An old max(16) floor in setProperty silently fattened them
    // into bars even though import stored the real 2px (the long divider saga).
    var stack = Stack.makeNew()
    guard let bIndex = stack.cards[0].parts.firstIndex(where: {
        if case .button = $0.kind { return true } else { return false }
    }) else { Issue.record("no button on card 0"); return }
    let scriptID = stack.cards[0].parts[bIndex].scriptID
    var index = 0
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i }
    )
    let button = HyperTalkObject.part(kind: "button", domain: .card,
                                      reference: .id(String(scriptID)), onCard: nil)
    try host.setProperty("height", of: button, to: "2")
    #expect(stack.cards[0].parts[bIndex].frame.height == 2)
    try host.setProperty("rect", of: button, to: "0,408,640,410")
    #expect(stack.cards[0].parts[bIndex].frame.height == 2)
    #expect(stack.cards[0].parts[bIndex].frame.width == 640)
}

@MainActor
@Test func closeCardReenablesPriorButton() async throws {
    // The Hacker Crackdown's title card disables bg button "Prior" in openCard
    // and re-enables it in closeCard (via its DisableOrEnable handler). Leaving
    // the title card must therefore send closeCard so Prior isn't stuck gray.
    // This exercises the script chain (bare-word enable/disable, the handler,
    // and `set the enabled`) end-to-end against the app host.
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad/New Stacks - Oct 5 3rd batch"
    guard let path = classicStackFiles(under: root).first(where: {
        ($0 as NSString).lastPathComponent.lowercased().contains("hacker crackdown")
    }) else { return }
    var stack = try LegacyStackImporter.importedStack(from: URL(fileURLWithPath: path)).stack
    var index = 0
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i }
    )
    func priorEnabled() -> Bool {
        for p in stack.backgrounds[0].parts where p.name.lowercased() == "prior" { return p.isEnabled }
        Issue.record("no bg button named Prior"); return true
    }
    let layers = try #require(host.scriptLayers(for: .thisCard))
    #expect(priorEnabled() == true)                               // imported enabled
    try await HyperTalk.send("openCard", along: layers, host: host)
    #expect(priorEnabled() == false)                              // title card disables it
    try await HyperTalk.send("closeCard", along: layers, host: host)
    #expect(priorEnabled() == true)                               // leaving re-enables it
}

@MainActor
@Test func hackerOpenStackCropsCardWindow() async throws {
    // The Hacker Crackdown's openStack sizes its card window one dimension at
    // a time (`set width/height of card window to …`). Running the REAL stack
    // script must yield a cropped viewport (600×440) — the big-card-small-
    // window idiom that hides the card's blank right/bottom margins.
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad/New Stacks - Oct 5 3rd batch"
    guard let path = classicStackFiles(under: root).first(where: {
        ($0 as NSString).lastPathComponent.lowercased().contains("hacker crackdown")
    }) else { return }
    var stack = try LegacyStackImporter.importedStack(from: URL(fileURLWithPath: path)).stack
    var index = 0
    var viewport: CGSize?
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i },
        cardWindowViewport: Binding(get: { viewport }, set: { viewport = $0 })
    )
    let layers = try #require(host.scriptLayers(for: .thisCard))
    try await HyperTalk.send("openStack", along: layers, host: host)
    let size = try #require(viewport)
    #expect(size.width < 640 && size.height < 480)
    #expect(size.width >= 500 && size.height >= 400) // a "Large"-ish page, not a sliver
}

@MainActor
@Test func cardWindowRectCropsViewport() async throws {
    // `set the rect of card window to 0,0,612,442` (The Hacker Crackdown's
    // resizable pages) crops the card viewport; reading it back reports the
    // viewport, and a full-size rect clears the crop.
    var stack = Stack.makeNew()
    var index = 0
    var viewport: CGSize?
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i },
        cardWindowViewport: Binding(get: { viewport }, set: { viewport = $0 })
    )
    try host.setWindowProperty("rect", window: "card", to: "0,0,612,442")
    #expect(viewport == CGSize(width: 612, height: 442))
    #expect(host.windowProperty("rect", window: "card") == "0,0,612,442")
    #expect(host.windowProperty("scroll", window: "card") == "0,0")
    // Restoring a rect at least the card size clears the crop.
    try host.setWindowProperty("rect", window: "card", to: "0,0,2000,2000")
    #expect(viewport == nil)
    // Other windows stay unmodeled (absent-object defaults).
    #expect(host.windowProperty("rect", window: "tool") == nil)
}

@MainActor
@Test func importsBodyTextForPartlessCards() throws {
    // The Hacker Crackdown's book pages (card 2+) have NO card-layer parts —
    // every field is a background template — so the 2.x content section starts
    // at a header-relative offset, not right after a (nonexistent) part list.
    // Regression: those pages must still import their per-card body text (the
    // scan that finds the real content start), not come through blank.
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad/New Stacks - Oct 5 3rd batch"
    guard let path = classicStackFiles(under: root).first(where: {
        ($0 as NSString).lastPathComponent.lowercased().contains("hacker crackdown")
    }) else { return }
    let stack = try LegacyStackImporter.importedStack(from: URL(fileURLWithPath: path)).stack
    #expect(stack.cards.count > 1)
    let page2 = stack.cards[1]
    func text(_ card: Card, _ name: String) -> String {
        for p in card.parts { if p.name == name, case .field(let f) = p.kind { return f.text } }
        return ""
    }
    // The preface body is thousands of characters; it was empty before the fix.
    #expect(text(page2, "Text").count > 2000)
    #expect(text(page2, "Text").contains("Austin"))
    #expect(text(page2, "Page Number") == "Page 2 of 52")
}

@MainActor
@Test func importsRealCardSizeAndThinParts() throws {
    // The Hacker Crackdown is a 640×480 (2.x) stack with a 2px-tall "divider"
    // rule. Regression: honor the real card size (not 512×342) and the thin
    // part height (no 8px floor) so the footer isn't squished. Skips if absent.
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad/New Stacks - Oct 5 3rd batch"
    guard let path = classicStackFiles(under: root).first(where: {
        ($0 as NSString).lastPathComponent.lowercased().contains("hacker crackdown")
    }) else { return }
    let stack = try LegacyStackImporter.importedStack(from: URL(fileURLWithPath: path)).stack
    #expect(stack.cardSize.width == 640)
    #expect(stack.cardSize.height == 480)
    let bg = try #require(stack.backgrounds.first)
    let divider = try #require(bg.parts.first { $0.name == "divider" })
    #expect(divider.frame.height < 8)   // the real rule is ~2px, not the old 16
    #expect(divider.frame.width == 640)

    // The APP path: importedContraptFile encodes this stack to JSON, then
    // StackDocument decodes + sanitizes it on open. Confirm the thin height
    // survives that round-trip (not re-inflated).
    let data = try stack.fileData()
    let reloaded = try Stack(fileData: data).sanitized()
    let rbg = try #require(reloaded.backgrounds.first)
    let rdivider = try #require(rbg.parts.first { $0.name == "divider" })
    #expect(rdivider.frame.height < 8)
}

@MainActor
@Test func appImportChainDividerHeight() throws {
    // Mirror the APP exactly: importedContraptFile writes a real .contrapt, then
    // StackDocument.load reads it back (the path Cmd-R uses). If the divider is
    // thin here, a thick render in the app is a stale binary, not this code.
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad/New Stacks - Oct 5 3rd batch"
    guard let path = classicStackFiles(under: root).first(where: {
        ($0 as NSString).lastPathComponent.lowercased().contains("hacker crackdown")
    }) else { return }
    let contrapt = try LegacyStackImporter.importedContraptFile(from: URL(fileURLWithPath: path))
    let doc = try #require(StackDocument.load(from: contrapt))
    let bg = try #require(doc.stack.backgrounds.first)
    let divider = try #require(bg.parts.first { $0.name == "divider" })
    #expect(divider.frame.height < 8)
}

@MainActor
@Test func lockedScreenDefersCrossWindowGo() async throws {
    // Under `lock screen`, a `go home` peek that pops back within the stack
    // must NOT open the Home window (the stack stays frontmost); a genuine
    // lock → go stack → unlock still lands on the stack.
    var stack = Stack.makeNew()
    var index = 0
    var homeCount = 0
    var stackOpens: [String] = []
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i },
        onGoHome: { homeCount += 1 },
        onGoStack: { name, _ in stackOpens.append(name) }
    )

    // Peek at Home under lock, then navigate back within the stack.
    host.setScreenLocked(true)
    try await host.goToCard(.home, effects: [])
    #expect(homeCount == 0) // deferred, not opened
    try await host.goToCard(.first, effects: []) // in-stack nav supersedes the peek
    host.setScreenLocked(false)
    #expect(homeCount == 0) // peek cancelled — stack stays front

    // A real lock → go stack → unlock lands on the target stack.
    host.setScreenLocked(true)
    try await host.goToCard(.stack(name: "Phone", card: nil), effects: [])
    #expect(stackOpens.isEmpty) // deferred
    host.setScreenLocked(false)
    #expect(stackOpens == ["Phone"])
}

@MainActor
@Test func buttonEnabledPropertyRoundTrips() throws {
    // `disable`/`enable` → `set the enabled` flips `Part.isEnabled`, and `the
    // enabled of button` reads it back.
    var stack = Stack.makeNew()
    guard let bIndex = stack.cards[0].parts.firstIndex(where: {
        if case .button = $0.kind { return true } else { return false }
    }) else { Issue.record("no button on card 0"); return }
    let scriptID = stack.cards[0].parts[bIndex].scriptID
    var index = 0
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i }
    )
    let button = HyperTalkObject.part(kind: "button", domain: .card,
                                      reference: .id(String(scriptID)), onCard: nil)
    #expect(try host.propertyValue("enabled", of: button) == "true")
    try host.setProperty("enabled", of: button, to: "false")
    #expect(try host.propertyValue("enabled", of: button) == "false")
    #expect(stack.cards[0].parts[bIndex].isEnabled == false)
}

@MainActor
@Test func appHostUnmodeledPropertyGetters() throws {
    // The runtime-audit property fixes, exercised directly on DocumentScriptHost:
    // `the script of` an object, and benign defaults for unmodeled stack props.
    var stack = Stack.makeNew()
    var index = 0
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i }
    )
    #expect(try host.propertyValue("cantmodify", of: .thisStack) == "false")
    #expect(try host.propertyValue("freesize", of: .thisStack) == "0")
    #expect(try host.propertyValue("script", of: .thisCard) == stack.cards[0].script)
}

@MainActor
@Test func corpusRuntimeAudit() async throws {
    // Gated on a sentinel file (xcodebuild doesn't pass shell env to the test
    // runner): `touch /tmp/contrapt-runtime-audit` to enable.
    guard FileManager.default.fileExists(atPath: "/tmp/contrapt-runtime-audit") else { return }
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad"
    // The app test runs sandboxed; the project folder isn't writable. Write the
    // report to the temp dir (and print it) instead.
    let outPath = NSTemporaryDirectory() + "corpus-runtime-audit.txt"

    let files = classicStackFiles(under: root)
    var all: [RuntimeAudit.Finding] = []
    for file in files {
        let name = (file as NSString).lastPathComponent
        all.append(contentsOf: await RuntimeAudit.run(classicStackAt: file, name: name))
    }

    // Rank by message (strip the specific quoted token so e.g. all
    // "Can't understand 'X'" group, but keep a representative example).
    func normalize(_ m: String) -> String {
        var out = ""
        var inQuote = false
        for ch in m { if ch == "'" || ch == "\"" { inQuote.toggle(); out += inQuote ? "'…" : "'" } else if !inQuote { out.append(ch) } }
        return out
    }
    var byKind: [String: [RuntimeAudit.Finding]] = [:]
    for f in all { byKind[normalize(f.message), default: []].append(f) }

    var report = "Contrapt corpus RUNTIME audit\nstacks: \(files.count)   runtime errors: \(all.count)   distinct: \(byKind.count)\n\n"
    for (kind, group) in byKind.sorted(by: { $0.value.count > $1.value.count }) {
        report += "[\(group.count)]  \(kind)\n"
        for f in group.prefix(4) { report += "      \(f.stack) › \(f.context): \(f.message)\n" }
        report += "\n"
    }
    try? report.write(toFile: outPath, atomically: true, encoding: .utf8)
    print("RUNTIME-AUDIT-BEGIN\n\(report)\nRUNTIME-AUDIT-END (\(files.count) stacks, \(all.count) errors; also at \(outPath))")
}

/// Fans out every button/field `mouseUp` handler of the Manhole stacks (the
/// gameplay hotspots), which the openStack/openCard sweep doesn't reach.
/// Gated: `touch /tmp/contrapt-manhole-audit`.
@MainActor
@Test func manholeButtonAudit() async throws {
    guard FileManager.default.fileExists(atPath: "/tmp/contrapt-manhole-audit") else { return }
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad"
    let files = classicStackFiles(under: root).filter {
        ($0 as NSString).lastPathComponent.lowercased().contains("manhole")
    }
    var all: [RuntimeAudit.Finding] = []
    for file in files {
        let name = (file as NSString).lastPathComponent
        all.append(contentsOf: await RuntimeAudit.runButtons(classicStackAt: file, name: name))
    }
    func normalize(_ m: String) -> String {
        var out = ""; var inQuote = false
        for ch in m { if ch == "'" || ch == "\"" { inQuote.toggle(); out += inQuote ? "'…" : "'" } else if !inQuote { out.append(ch) } }
        return out
    }
    var byKind: [String: [RuntimeAudit.Finding]] = [:]
    for f in all { byKind[normalize(f.message), default: []].append(f) }
    var report = "Manhole BUTTON audit\nfiles: \(files.count)   button errors: \(all.count)   distinct: \(byKind.count)\n\n"
    for (kind, group) in byKind.sorted(by: { $0.value.count > $1.value.count }) {
        report += "[\(group.count)]  \(kind)\n"
        for f in group.prefix(5) { report += "      \(f.stack) › \(f.context): \(f.message)\n" }
        report += "\n"
    }
    print("MANHOLE-AUDIT-BEGIN\n\(report)\nMANHOLE-AUDIT-END")
}

/// Classic stacks under `root` (first block is a STAK block), skipping build
/// and VCS dirs.
@MainActor
private func classicStackFiles(under root: String) -> [String] {
    let fm = FileManager.default
    guard let en = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isRegularFileKey],
                                 options: [.skipsHiddenFiles]) else { return [] }
    var files: [String] = []
    for case let url as URL in en {
        let path = url.path
        if path.contains("/.build/") || path.contains("/.git/") || path.contains("/DerivedData/") { en.skipDescendants(); continue }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
        guard let fh = try? FileHandle(forReadingFrom: url) else { continue }
        let head = try? fh.read(upToCount: 8); try? fh.close()
        if let head, head.count == 8, String(bytes: head[4..<8], encoding: .ascii) == "STAK" {
            files.append(path)
        }
    }
    return files.sorted()
}



