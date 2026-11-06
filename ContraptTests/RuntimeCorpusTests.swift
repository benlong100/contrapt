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
    // leaves the current id in place (names aren't imported).
    try host.setProperty("icon", of: button, to: "General Essay")
    #expect(try host.propertyValue("icon", of: button) == "5678")
    // Runtime glyph resolution: an id in the stack's icon library swaps the
    // drawn asset; an unknown id keeps the number but flags the icon missing.
    stack.icons["777"] = "glyph-777.png"
    try host.setProperty("icon", of: button, to: "777")
    if case .button(let b) = stack.cards[0].parts[bIndex].kind {
        #expect(b.iconAsset == "glyph-777.png")
        #expect(b.iconMissing == false)
    } else { Issue.record("button lost its kind") }
    try host.setProperty("icon", of: button, to: "99999")
    if case .button(let b) = stack.cards[0].parts[bIndex].kind {
        #expect(b.iconAsset == nil)
        #expect(b.iconMissing == true)
        #expect(b.iconID == 99999)
    } else { Issue.record("button lost its kind") }
}

@MainActor
@Test func hideCardPictureBlanksThePaintLayer() async throws {
    // Adventures of Sean covers its title art with an all-black CARD paint
    // layer and lifts it with `hide picture of card 1`. The property must be
    // real: hide → showPicture false (CardView skips the layer), show → true,
    // reads via `the showPict`.
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
    try await HyperTalk.send("probePict", along: [ScriptLayer(name: "t", source: """
    on probePict
      hide picture of this card
      put the showPict of this card into a
      show picture of this card
      hide background picture
      put a & "|" & the showPict of this card & "|" & the showPict of this background
    end probePict
    """, object: .thisCard)] + layers, host: host)
    #expect(shown.last == "false|true|false")
    #expect(stack.cards[0].showPicture == true)
    #expect(stack.backgrounds[0].showPicture == false)
}

@MainActor
@Test func backgroundFieldsAreSharedPartsWithPerCardText() async throws {
    // The Hacker Crackdown is a book: ONE background field holds a different
    // page of text on every card. True shared parts mean the field exists
    // once on the background, each card reads its own text through the
    // overlay, and a property write propagates everywhere at once.
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad/New Stacks - Oct 5 3rd batch/hypercard_the-hacker-crackdown"
    guard let path = classicStackFiles(under: root).first else { return }
    let imported = try LegacyStackImporter.importedStack(from: URL(fileURLWithPath: path))
    var stack = imported.stack

    // The text background has its fields ON the background, none copied to cards.
    let background = stack.backgrounds.max(by: { $0.parts.count < $1.parts.count })!
    let bgFieldIDs = Set(background.parts.filter { if case .field = $0.kind { true } else { false } }.map(\.id))
    #expect(!bgFieldIDs.isEmpty)
    for card in stack.cards {
        let copied = card.parts.filter { bgFieldIDs.contains($0.id) }
        #expect(copied.isEmpty)
    }

    // Find a background field whose per-card text differs across two cards —
    // the book's page field.
    let cardIndices = stack.cards.indices.filter { stack.cards[$0].backgroundID == background.id }
    let bgFields = background.parts.filter { if case .field = $0.kind { true } else { false } }
    var pageField: Part?
    var withText: [Int] = []
    for field in bgFields {
        let key = field.id.uuidString
        let indices = cardIndices.filter { !(stack.cards[$0].backgroundFieldContent[key]?.text ?? "").isEmpty }
        if indices.count >= 2,
           stack.cards[indices[0]].backgroundFieldContent[key]?.text != stack.cards[indices[1]].backgroundFieldContent[key]?.text {
            pageField = field
            withText = indices
            break
        }
    }
    let page = try #require(pageField)
    let fieldRef = HyperTalkObject.Reference.id(String(page.scriptID))
    let stackBinding = Binding(get: { stack }, set: { stack = $0 })
    func host(onCard index: Int) -> DocumentScriptHost {
        var card = index
        return DocumentScriptHost(
            stack: stackBinding,
            currentCardIndex: Binding(get: { card }, set: { card = $0 }),
            onMessage: { _ in },
            onAnswer: { _, buttons in buttons.first ?? "OK" },
            onAsk: { _, initial in initial },
            onNavigate: { _, _ in }
        )
    }
    let a = try host(onCard: withText[0]).fieldText(fieldRef, domain: .background, onCard: nil)
    let b = try host(onCard: withText[1]).fieldText(fieldRef, domain: .background, onCard: nil)
    #expect(!a.isEmpty)
    #expect(a != b)

    // Writing text on one card doesn't bleed into another.
    try host(onCard: withText[0]).setFieldText(fieldRef, domain: .background, onCard: nil, to: "rewritten page")
    let aAfter = try host(onCard: withText[0]).fieldText(fieldRef, domain: .background, onCard: nil)
    let bAfter = try host(onCard: withText[1]).fieldText(fieldRef, domain: .background, onCard: nil)
    #expect(aAfter == "rewritten page")
    #expect(bAfter == b)

    // A property write on one card reaches every card: it's the same part.
    let fieldObject = HyperTalkObject.part(kind: "field", domain: .background, reference: fieldRef, onCard: nil)
    try host(onCard: withText[0]).setProperty("width", of: fieldObject, to: "123")
    let widthElsewhere = try host(onCard: withText[1]).propertyValue("width", of: fieldObject)
    #expect(widthElsewhere == "123")
}


@MainActor
@Test func icnSharpIconsImport() async throws {
    // Oblique Strategies ships one of its button icons as an ICN# (icon +
    // mask pair) rather than an ICON — the importer's fallback renders it
    // into the runtime icon library.
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad/New Stacks - Oct 5 3rd batch/hypercard_obliquestrategies"
    guard let path = classicStackFiles(under: root).first else { return }
    let url = URL(fileURLWithPath: path)
    let imported = try LegacyStackImporter.importedStack(from: url)
    guard let fork = ResourceFork.forkData(of: url) else { return }
    let icnIDs = ResourceFork.iconLists(from: fork).keys
    try #require(!icnIDs.isEmpty)
    for id in icnIDs {
        let asset = imported.stack.icons[String(id)]
        #expect(asset != nil)
        if let asset {
            #expect((imported.assets[asset]?.count ?? 0) > 0)
        }
    }
}

@Test func cicnColorIconDecodes() throws {
    // A minimal synthetic 8×8 1-bit cicn: left half color index 1 (red),
    // right half index 0 (white), full mask.
    var d = [UInt8](repeating: 0, count: 0x52)
    func put16(_ o: Int, _ v: Int) { d[o] = UInt8(v >> 8); d[o+1] = UInt8(v & 0xFF) }
    put16(0x04, 1)   // pixMap rowBytes
    put16(0x0A, 8); put16(0x0C, 8) // bounds bottom/right (top/left 0)
    put16(0x20, 1)   // pixelSize 1
    put16(0x36, 1)   // mask rowBytes
    put16(0x44, 1)   // icon bitmap rowBytes
    d += [UInt8](repeating: 0xFF, count: 8)  // mask: all opaque
    d += [UInt8](repeating: 0x00, count: 8)  // b/w icon bitmap (unused)
    // Color table: seed(4) flags(2) size(2)=1, entries {0: white} {1: red}
    d += [0,0,0,0, 0,0, 0,1]
    d += [0,0, 0xFF,0xFF, 0xFF,0xFF, 0xFF,0xFF]
    d += [0,1, 0xFF,0x00, 0x00,0x00, 0x00,0x00]
    d += [UInt8](repeating: 0xF0, count: 8)  // pixels: left half index 1
    let png = try #require(ResourceFork.cicnPNG(Data(d)))
    let canvas = PaintRasterizer.canvas(from: png, width: 8, height: 8)
    #expect(canvas[1, 4] == (255, 0, 0, 255))     // red left
    #expect(canvas[6, 4] == (255, 255, 255, 255)) // white right
}

// Full openStack runs against real imported stacks touch app-global session
// singletons (using-stack store, selection, menus) — serialized so two such
// runs don't interleave.
@Suite(.serialized) struct OpenStackSessionTests {
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
    @Test func seanOpenStackBuildsCustomMenus() async throws {
        // Adventures of Sean 2's openStack runs setUpMenus (`create menu "File"`,
        // `put "About…,Quit" into menu …`). Running the REAL stack's openStack
        // must populate the scripted menu bar the strip renders.
        let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad/New Stacks - Oct 5 3rd batch/AdventuresOfSeanMacintosh"
        guard let path = classicStackFiles(under: root).first else { return }
        var stack = try LegacyStackImporter.importedStack(from: URL(fileURLWithPath: path)).stack
        var index = 0
        var menus: [HyperTalkMenu] = []
        let host = DocumentScriptHost(
            stack: Binding(get: { stack }, set: { stack = $0 }),
            currentCardIndex: Binding(get: { index }, set: { index = $0 }),
            onMessage: { _ in },
            onAnswer: { _, buttons in buttons.first ?? "OK" },
            onAsk: { _, initial in initial },
            onNavigate: { i, _ in index = i },
            menuBar: Binding(get: { menus }, set: { menus = $0 })
        )
        let layers = try #require(host.scriptLayers(for: .thisCard))
        try? await HyperTalk.send("openStack", along: layers, host: host)
        try? await HyperTalk.send("openCard", along: layers, host: host)
        print("SEAN-MENUS: \(menus.map { "\($0.name)[\($0.items.count)]" }.joined(separator: " "))")
        #expect(!menus.isEmpty)
        #expect(menus.contains { !$0.items.isEmpty })
        // The title card's all-black CARD paint curtain must be lifted by the
        // stack's own scripts (`hide picture of card 1`), revealing the bg art.
        print("SEAN-PICT: card0.showPicture=\(stack.cards[0].showPicture)")
        #expect(stack.cards[0].showPicture == false)
    }
}

// The chosen tool and paint settings are session-global (HyperCard has one
// tool), so tests that choose tools must not run in parallel with each other.
@Suite(.serialized) struct ToolSessionTests {
    @MainActor
    @Test func scriptedPaintingDrawsOnTheCardLayer() async throws {
        // `choose rect tool` + `drag from … to …` rasterizes onto the card's
        // paint PNG: filled rect pixels are black, the eraser restores
        // transparency, and the bucket floods a hollow shape's interior.
        var stack = Stack(formatVersion: StackFormat.currentVersion, id: UUID(), name: "Paint",
                          cardSize: CardSize(width: 100, height: 80),
                          script: "", backgrounds: [], cards: [])
        var background = Background(id: UUID(), name: "BG", script: "", parts: [])
        background.scriptID = stack.claimScriptID()
        stack.backgrounds.append(background)
        var card = Card(id: UUID(), name: "C1", backgroundID: background.id, script: "", parts: [])
        card.scriptID = stack.claimScriptID()
        stack.cards.append(card)

        var assets: [String: Data] = [:]
        let host = DocumentScriptHost(
            stack: Binding(get: { stack }, set: { stack = $0 }),
            currentCardIndex: .constant(0),
            onMessage: { _ in },
            onAnswer: { _, buttons in buttons.first ?? "OK" },
            onAsk: { _, initial in initial },
            onNavigate: { _, _ in },
            assetData: { assets[$0] },
            onAssetWrite: { name, data in assets[name] = data }
        )
        host.resetPaint()
        defer { host.resetPaint() } // session state — leave defaults for other tests

        func pixel(_ x: Int, _ y: Int) -> (r: UInt8, a: UInt8) {
            guard let asset = stack.cards[0].paintImageAsset, let data = assets[asset] else { return (0, 0) }
            let canvas = PaintRasterizer.canvas(from: data, width: 100, height: 80)
            let px = canvas[x, y]
            return (px.r, px.a)
        }

        // Each line as its own dispatch — the message-box idiom. The chosen tool
        // and paint settings must survive between dispatches (fresh host each).
        for line in ["choose rect tool", "set the filled to true", "drag from 10,10 to 30,30"] {
            _ = try await HyperTalk.execute(messageLine: line, along: [ScriptLayer(name: "card", source: "")], host: host)
        }
        #expect(pixel(20, 20) == (0, 255))   // black inside the filled rect
        #expect(pixel(50, 50).a == 0)        // untouched canvas stays transparent

        _ = try await HyperTalk.run(handler: "p", in: """
        on p
          choose eraser tool
          drag from 20,20 to 20,20
        end p
        """, host: host, maxSteps: 1000)
        #expect(pixel(20, 20).a == 0)        // erased back to transparent

        _ = try await HyperTalk.run(handler: "p", in: """
        on p
          reset paint
          choose rect tool
          drag from 50,40 to 90,70
          choose bucket tool
          click at 70,55
        end p
        """, host: host, maxSteps: 1000)
        #expect(pixel(50, 40) == (0, 255))   // hollow rect outline
        #expect(pixel(70, 55) == (0, 255))   // bucket filled the interior
        #expect(pixel(45, 55).a == 0)        // outside stays clear
    }

    @MainActor
    @Test func typeTypesAndPartToolDragMovesButtons() async throws {
        var stack = Stack(formatVersion: StackFormat.currentVersion, id: UUID(), name: "Input",
                          cardSize: CardSize(width: 300, height: 200),
                          script: "", backgrounds: [], cards: [])
        var background = Background(id: UUID(), name: "BG", script: "", parts: [])
        background.scriptID = stack.claimScriptID()
        stack.backgrounds.append(background)
        var card = Card(id: UUID(), name: "C1", backgroundID: background.id, script: "", parts: [])
        card.scriptID = stack.claimScriptID()
        var field = Part(id: UUID(), name: "Entry",
                         frame: PartFrame(x: 10, y: 10, width: 200, height: 60),
                         script: "", kind: .field(FieldPart(text: "ab", placeholder: "")))
        field.scriptID = stack.claimScriptID()
        card.parts.append(field)
        var button = Part(id: UUID(), name: "Mover",
                          frame: PartFrame(x: 20, y: 100, width: 60, height: 20),
                          script: "", kind: .button(ButtonPart(title: "Mover")))
        button.scriptID = stack.claimScriptID()
        card.parts.append(button)
        stack.cards.append(card)

        var index = 0
        let host = DocumentScriptHost(
            stack: Binding(get: { stack }, set: { stack = $0 }),
            currentCardIndex: Binding(get: { index }, set: { index = $0 }),
            onMessage: { _ in },
            onAnswer: { _, buttons in buttons.first ?? "OK" },
            onAsk: { _, initial in initial },
            onNavigate: { i, _ in index = i }
        )

        // select-then-type: caret insert, range replace.
        _ = try await HyperTalk.run(handler: "p", in: """
        on p
          select after text of card field "Entry"
          type "cd" & return
          type "e"
        end p
        """, host: host, maxSteps: 1000)
        if case .field(let props) = stack.cards[0].parts[0].kind {
            #expect(props.text == "abcd\ne")
        } else {
            Issue.record("field vanished")
        }
        host.clearSelection()

        // drag with the button tool moves the part under the start point.
        _ = try await HyperTalk.run(handler: "p", in: """
        on p
          choose button tool
          drag from 50,110 to 200,150
          choose browse tool
        end p
        """, host: host, maxSteps: 1000)
        let moved = stack.cards[0].parts[1].frame
        #expect(moved.x == 170) // 200 - 60/2
        #expect(moved.y == 140) // 150 - 20/2
    }
}

@MainActor
@Test func printVerbsProduceCardAndTextPDFs() async throws {
    // `open printing` / `print this card` / `close printing` batches card
    // pages into one PDF; `print field` paginates text — the dialog is a
    // closure, so the test captures the PDF bytes instead.
    var stack = Stack(formatVersion: StackFormat.currentVersion, id: UUID(), name: "Printed",
                      cardSize: CardSize(width: 200, height: 150),
                      script: "", backgrounds: [], cards: [])
    var background = Background(id: UUID(), name: "BG", script: "", parts: [])
    background.scriptID = stack.claimScriptID()
    stack.backgrounds.append(background)
    for i in 1...3 {
        var card = Card(id: UUID(), name: "C\(i)", backgroundID: background.id, script: "", parts: [])
        card.scriptID = stack.claimScriptID()
        if i == 1 {
            var field = Part(id: UUID(), name: "Notes",
                             frame: PartFrame(x: 10, y: 10, width: 180, height: 100),
                             script: "", kind: .field(FieldPart(text: "Hello, printer.", placeholder: "")))
            field.scriptID = stack.claimScriptID()
            card.parts.append(field)
        }
        stack.cards.append(card)
    }

    var printed: [(pdf: Data, title: String)] = []
    var index = 0
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i },
        onPresentPrint: { pdf, title in printed.append((pdf, title)) }
    )

    func pageCount(_ data: Data) -> Int {
        // Count page objects without PDFKit: "/Type /Page" minus "/Pages".
        let text = String(decoding: data, as: UTF8.self)
        return text.components(separatedBy: "/Type /Page").count - 1
            - (text.components(separatedBy: "/Type /Pages").count - 1)
    }

    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      open printing with dialog
      print this card
      go next card
      print this card
      close printing
    end p
    """, host: host, maxSteps: 1000)
    try #require(printed.count == 1)
    #expect(pageCount(printed[0].pdf) == 2)
    #expect(printed[0].title == "Printed")

    _ = try await HyperTalk.run(handler: "p", in: "on p\nprint all cards\nend p", host: host, maxSteps: 1000)
    try #require(printed.count == 2)
    #expect(pageCount(printed[1].pdf) == 3)

    _ = try await HyperTalk.run(handler: "p", in: "on p\ngo first card\nprint card field \"Notes\"\nend p", host: host, maxSteps: 1000)
    try #require(printed.count == 3)
    #expect(pageCount(printed[2].pdf) == 1)

    // `print <document> with <app>` stays an accepted no-op.
    _ = try await HyperTalk.run(handler: "p", in: "on p\nprint \"report\" with \"TeachText\"\nend p", host: host, maxSteps: 1000)
    #expect(printed.count == 3)
}


@MainActor
@Test func radioAndCheckboxButtonStylesImport() throws {
    // HyperCard button-style nibbles: radioButton=6, checkBox=5 (verified
    // against Canton College Kiosk's Home). The importer once mapped 8/9, so
    // every radio/checkbox fell to roundRect — the "all pushbuttons" bug.
    let home = "/Applications/Basilisk II/BasiliskShared/Greg Jewett Stacks/Canton College Kiosk/Home"
    guard FileManager.default.fileExists(atPath: home) else { return }
    let imported = try LegacyStackImporter.importedStack(from: URL(fileURLWithPath: home))
    func style(ofButtonNamed name: String) -> ButtonStyleKind? {
        for card in imported.stack.cards {
            for part in card.parts where part.name == name {
                if case .button(let b) = part.kind { return b.style }
            }
        }
        for bg in imported.stack.backgrounds {
            for part in bg.parts where part.name == name {
                if case .button(let b) = part.kind { return b.style }
            }
        }
        return nil
    }
    #expect(style(ofButtonNamed: "Browsing") == .radio)
    #expect(style(ofButtonNamed: "Scripting") == .radio)
    #expect(style(ofButtonNamed: "Text Arrows") == .checkbox)
    #expect(style(ofButtonNamed: "Blind Typing") == .checkbox)
}

@MainActor
@Test func paintTextGlobalsRoundTrip() async throws {
    // The text-paint tool settings as globals (`set textHeight to N` / `the
    // textHeight`) round-trip in the app host (Hyper-Wordle reads `the
    // textHeight` for chart layout after setting it).
    var stack = Stack.makeNew(); var idx = 0
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { idx }, set: { idx = $0 }),
        onMessage: { _ in }, onAnswer: { _, b in b.first ?? "OK" },
        onAsk: { _, i in i }, onNavigate: { i, _ in idx = i })
    host.resetPaint()
    defer { host.resetPaint() }
    #expect(host.paintSetting("textheight") == "0")
    #expect(host.setPaintSetting("textheight", to: "18"))
    #expect(host.paintSetting("textheight") == "18")
    #expect(host.setPaintSetting("textsize", to: "24"))
    #expect(host.paintSetting("textsize") == "24")
}

@MainActor
@Test func foundChunkIsAWritableContainer() async throws {
    // `find` then `put … after the foundChunk` / `delete the foundChunk` —
    // the search-and-replace idiom (Writing Tools' makeSubstitutions, card
    // "Metaphors" line 46). the foundChunk must resolve as a writable
    // container, not just a readable descriptor.
    var stack = Stack(formatVersion: StackFormat.currentVersion, id: UUID(), name: "Find",
                      cardSize: CardSize(width: 300, height: 200),
                      script: "", backgrounds: [], cards: [])
    var background = Background(id: UUID(), name: "BG", script: "", parts: [])
    background.scriptID = stack.claimScriptID()
    stack.backgrounds.append(background)
    var card = Card(id: UUID(), name: "C1", backgroundID: background.id, script: "", parts: [])
    card.scriptID = stack.claimScriptID()
    var field = Part(id: UUID(), name: "Text",
                     frame: PartFrame(x: 10, y: 10, width: 280, height: 150),
                     script: "", kind: .field(FieldPart(text: "the *S* ran fast", placeholder: "")))
    field.scriptID = stack.claimScriptID()
    card.parts.append(field)
    stack.cards.append(card)

    var index = 0
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i }
    )
    func text() -> String {
        if case .field(let f) = stack.cards[0].parts[0].kind { return f.text }
        return ""
    }
    // put after the foundChunk: insert the substitution, then delete the match.
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      find whole "*S*" in card field "Text"
      put "dog" after the foundChunk
      delete the foundChunk
    end p
    """, host: host, maxSteps: 2000)
    #expect(text() == "the dog ran fast")
}

@MainActor
@Test func chainedOpenCardAutoAdvanceFires() async throws {
    // Writing Tools: cards 1–3 each `on openCard / visual … / go next card`,
    // an auto-advancing intro. Every arrival must send openCard so the chain
    // continues — the engine side proves the interpreter navigates.
    let path = "/Applications/Basilisk II/BasiliskShared/Greg Jewett Stacks/Writing:Revision Tools™/Working v5.3/Writing Tools™"
    guard FileManager.default.fileExists(atPath: path) else { return }
    var stack = try LegacyStackImporter.importedStack(from: URL(fileURLWithPath: path)).stack
    var navigatedTo: Int?
    var index = 1
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { to, _ in navigatedTo = to }
    )
    // Card 2's openCard (visual wipe right / go next card) must navigate on.
    let path2 = [ScriptLayer(name: "card", source: stack.cards[1].script),
                 ScriptLayer(name: "stack", source: stack.script)]
    try await HyperTalk.send("openCard", along: path2, host: host)
    #expect(navigatedTo == 2)
}

@MainActor
@Test func dumpSeanSoundsAndLine251() async throws {
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad/New Stacks - Oct 5 3rd batch/AdventuresOfSeanMacintosh"
    guard let path = classicStackFiles(under: root).first else { return }
    let imported = try LegacyStackImporter.importedStack(from: URL(fileURLWithPath: path))
    print("SOUNDS: \(imported.stack.sounds.keys.sorted().joined(separator: ", "))")
    if let buzzer = imported.stack.sounds["buzzer"],
       let wav = imported.assets[buzzer.asset] {
        let decoded = SndSound.samplesFromWAV(wav)
        print("BUZZER: wavBytes=\(wav.count) samples=\(decoded?.samples.count ?? -1) rate=\(decoded?.sampleRate ?? 0) baseNote=\(buzzer.baseNote)")
    } else {
        print("BUZZER: missing from sounds/assets")
    }
    let lines = imported.stack.script.components(separatedBy: "\n")
    for i in 244...min(258, lines.count - 1) {
        print("L\(i + 1): \(lines[i])")
    }
}

@MainActor
@Test func dumpSeanPaint() async throws {
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad/New Stacks - Oct 5 3rd batch/AdventuresOfSeanMacintosh"
    guard let path = classicStackFiles(under: root).first else { return }
    let imported = try LegacyStackImporter.importedStack(from: URL(fileURLWithPath: path))
    let stack = imported.stack
    let card0 = stack.cards[0]
    let bg = stack.backgrounds.first { $0.id == card0.backgroundID }
    print("SEANPAINT card0 paint=\(card0.paintImageAsset ?? "nil") bgPaint=\(bg?.paintImageAsset ?? "nil") cardSize=\(stack.cardSize) parts=\(card0.parts.count)")
    for (name, data) in imported.assets where name == card0.paintImageAsset || name == bg?.paintImageAsset {
        let out = NSTemporaryDirectory() + "sean-\(name)"
        try data.write(to: URL(fileURLWithPath: out))
        print("SEANPAINT wrote \(out) bytes=\(data.count)")
    }
}


@MainActor
@Test func perChunkTextStyleWritesSplitAndMergeRuns() async throws {
    // `set the textStyle of word 2 of card field 1 to bold` — the write side
    // of styled text. Reads confirm the span (bold), its neighbors (plain),
    // replacement semantics (plain clears), and textSize over a chunk.
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
    try await HyperTalk.send("probeStyle", along: [ScriptLayer(name: "t", source: """
    on probeStyle
      put "one two three" into card field 1
      set the textStyle of word 2 of card field 1 to bold
      put the textStyle of word 2 of card field 1 into a
      put the textStyle of word 1 of card field 1 into b
      put the textStyle of char 1 to 13 of card field 1 into c
      set the textStyle of word 2 of card field 1 to plain
      put the textStyle of char 1 to 13 of card field 1 into d
      set the textSize of word 3 of card field 1 to 24
      put the textSize of word 3 of card field 1 into e
      put a & "|" & b & "|" & c & "|" & d & "|" & e
    end probeStyle
    """, object: .thisCard)] + layers, host: host)
    #expect(shown.last == "bold|plain|mixed|plain|24")
    // The runs themselves merged back: plain-everywhere leaves only the
    // trailing 24pt run (word 3 starts at char 9).
    var runs: [StyleRun] = []
    for p in stack.cards[0].parts { if case .field(let f) = p.kind, !f.styleRuns.isEmpty { runs = f.styleRuns } }
    #expect(runs.count == 1)
    #expect(runs.first?.start == 8)
    #expect(runs.first?.format.size == 24)
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

// Palette tests share the PaletteRegistry.shared singleton and interleave at
// `await` points, so they're serialized to keep one's reset() from wiping the
// other's window mid-flight.
@Suite(.serialized) @MainActor struct PaletteSessionTests {
@Test func paletteWindowLifecycle() async throws {
    // `palette "Tuber","2,40"` opens a registered window; `the windows`,
    // `there is a window`, the visible/loc props, and show/hide/close all
    // behave (Tubers' palette-management idiom). Rendering is a later step.
    DocumentScriptHost.PaletteRegistry.shared.reset()
    defer { DocumentScriptHost.PaletteRegistry.shared.reset() }
    var stack = Stack.makeNew()
    stack.externalCommands = ["palette"]
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
    try await HyperTalk.send("p", along: [ScriptLayer(name: "t", source: """
    on p
      palette "Tuber","2,40"
      put there is a window "Tuber"
      put the number of windows
      put the visible of window "Tuber"
      put the loc of window "Tuber"
      hide window "Tuber"
      put the visible of window "Tuber"
      close window "Tuber"
      put there is a window "Tuber"
      put the number of windows
    end p
    """, object: .thisCard)] + layers, host: host)
    // Opened: exists, 2 windows (card + Tuber), visible, at its loc.
    #expect(Array(shown.prefix(4)) == ["true", "2", "true", "2,40"])
    // Hidden → invisible; closed → gone, back to 1 window.
    #expect(Array(shown.suffix(3)) == ["false", "false", "1"])
}

@Test func paletteButtonsAttachAndLabel() async throws {
    // A stack carrying a PLTE (stored in `stack.palettes`) opens with its
    // buttons attached to the registered window, so ContentView can render
    // them. Labels derive from each button's command.
    DocumentScriptHost.PaletteRegistry.shared.reset()
    defer { DocumentScriptHost.PaletteRegistry.shared.reset() }
    var stack = Stack.makeNew()
    stack.externalCommands = ["palette"]
    stack.palettes["tuber"] = PaletteDefinition(buttons: [
        PaletteButtonDefinition(top: 235, left: 298, bottom: 268, right: 330, command: "doMenu \"Prev\""),
        PaletteButtonDefinition(top: 235, left: 334, bottom: 268, right: 366, command: "paletteHandlerHome"),
    ])
    var index = 0
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i }
    )
    let layers = try #require(host.scriptLayers(for: .thisCard))
    try await HyperTalk.send("p", along: [ScriptLayer(name: "t", source: """
    on p
      palette "Tuber","2,40"
    end p
    """, object: .thisCard)] + layers, host: host)
    let window = try #require(DocumentScriptHost.PaletteRegistry.shared.windows
        .first { $0.name.caseInsensitiveCompare("Tuber") == .orderedSame })
    #expect(window.buttons.count == 2)
    // doMenu "Prev" → "Prev"; paletteHandlerHome → "Home".
    #expect(window.buttons.map(\.label) == ["Prev", "Home"])
}
}

@MainActor
@Test func flashAndSpeakShimsRouteAsBuiltins() async throws {
    // Flash and SpeakText are shimmed natively and treated as externals even
    // when the stack carries no XCMD resource. Flash fires the screen-flash
    // closure with its count; both are commands returning empty.
    var stack = Stack.makeNew()
    var index = 0
    var flashes: [Int] = []
    let host = DocumentScriptHost(
        stack: Binding(get: { stack }, set: { stack = $0 }),
        currentCardIndex: Binding(get: { index }, set: { index = $0 }),
        onMessage: { _ in },
        onAnswer: { _, buttons in buttons.first ?? "OK" },
        onAsk: { _, initial in initial },
        onNavigate: { i, _ in index = i },
        onFlash: { flashes.append($0) }
    )
    #expect(host.isExternalName("Flash"))
    #expect(host.isExternalName("SpeakText"))
    let layers = try #require(host.scriptLayers(for: .thisCard))
    try await HyperTalk.send("p", along: [ScriptLayer(name: "t", source: """
    on p
      Flash 4
      Flash
      SpeakText "hello"
    end p
    """, object: .thisCard)] + layers, host: host)
    #expect(flashes == [4, 3])
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
    // Background fields are shared parts now; a card's text lives in its
    // backgroundFieldContent overlay, keyed by the shared part's UUID.
    let background = stack.backgrounds.first { $0.id == page2.backgroundID }
    func text(_ card: Card, _ name: String) -> String {
        for p in background?.parts ?? [] where p.name == name {
            if case .field(let f) = p.kind {
                if f.sharedText { return f.text }
                return card.backgroundFieldContent[p.id.uuidString]?.text ?? ""
            }
        }
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
    // Gated on an env var — xcodebuild forwards TEST_RUNNER_-prefixed vars:
    //   TEST_RUNNER_CONTRAPT_RUNTIME=1 xcodebuild test -scheme ContraptTests …
    // (A /tmp sentinel can't work: the sandboxed runner sees its own /tmp.)
    guard ProcessInfo.processInfo.environment["CONTRAPT_RUNTIME"] != nil else { return }
    let root = "/Users/wanderer/Desktop/Homemade Apps/HyperPad"
    // The app test runs sandboxed; the project folder isn't writable. Write the
    // report to the temp dir (and print it) instead.
    let outPath = NSTemporaryDirectory() + "corpus-runtime-audit.txt"

    // CONTRAPT_RUNTIME_FILTER narrows the sweep to paths containing the
    // substring — the fast way to re-run one crashing stack in isolation.
    var files = classicStackFiles(under: root)
    if let filter = ProcessInfo.processInfo.environment["CONTRAPT_RUNTIME_FILTER"] {
        files = files.filter { $0.localizedCaseInsensitiveContains(filter) }
    }
    var all: [RuntimeAudit.Finding] = []
    for (i, file) in files.enumerated() {
        let name = (file as NSString).lastPathComponent
        // Progress marker: on a crash, the log's last RTA line names the
        // culprit stack.
        print("RTA \(i + 1)/\(files.count): \(file)")
        let findings = await RuntimeAudit.run(classicStackAt: file, name: name)
        // Findings stream to the log as they land, so a crash late in the
        // sweep doesn't lose the earlier results.
        for f in findings { print("RTF\t\(f.stack)\t\(f.context)\t\(f.message)") }
        all.append(contentsOf: findings)
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



