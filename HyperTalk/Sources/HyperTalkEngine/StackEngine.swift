//
//  StackEngine.swift
//  HyperTalkEngine
//
//  The public entry point the web bridge (and, later, JavaScriptKit) drives:
//  load an exported `stack.json`, forward browser events (a button's mouseUp,
//  opening a card, a message-box line) into the interpreter, then read back the
//  current card's renderable state and the queued world effects.
//
//  Compiled to WebAssembly, one instance backs one open stack in the browser.
//

import Foundation
import HyperTalk

public final class StackEngine {
    private let host: WebHost

    /// Loads an exported stack from its `stack.json` bytes.
    public init(stackJSON: Data, interaction: EngineInteraction = EngineInteraction(), persistentData: String = "") throws {
        let stack: Stack
        do {
            stack = try JSONDecoder().decode(Stack.self, from: stackJSON)
        } catch {
            throw EngineError("Couldn't read the stack: \(error.localizedDescription)")
        }
        guard !stack.cards.isEmpty else { throw EngineError("The stack has no cards.") }
        host = WebHost(stack: stack, interaction: interaction, persistentData: persistentData)
    }

    // MARK: - Read-only snapshot

    public var stackName: String { host.stack.name }
    public var cardCount: Int { host.stack.cards.count }
    public var currentCardIndex: Int { host.currentIndex }
    public var cardWidth: Double { host.stack.cardSize.width }
    public var cardHeight: Double { host.stack.cardSize.height }

    /// Replace how suspending commands (`answer`/`ask`/`wait`) are answered —
    /// the JS bridge sets these to real dialogs/timers.
    public func setInteraction(_ interaction: EngineInteraction) {
        host.interaction = interaction
    }

    // MARK: - Events

    /// A button (or locked field/label) was clicked: send `mouseUp` along its
    /// message path. Returns the world effects the caller should now apply.
    @discardableResult
    public func dispatchMouseUp(partScriptID: Int, clickLine: Int? = nil, clickText: String? = nil) async throws -> [HostEffect] {
        // A field click carries which line/word it landed on — recorded as
        // `the clickLine`/`the clickText` before the script runs (HyperCard's
        // list-field navigation idiom). Kept until the next field click.
        if let clickLine {
            let card = host.stack.cards[host.currentIndex]
            let layer: String? = card.parts.contains { $0.scriptID == partScriptID } ? "card"
                : host.stack.backgrounds.first { $0.id == card.backgroundID }?
                    .parts.contains { $0.scriptID == partScriptID } == true ? "bkgnd" : nil
            if let layer {
                host.clickLine = "line \(clickLine) of \(layer) field id \(partScriptID)"
                host.clickText = clickText ?? ""
            }
        }
        // A checkbox/radio click flips its hilite (the checked state) before
        // the message dispatches — exactly the app's CardView order.
        host.toggleHiliteIfToggleStyle(partScriptID: partScriptID)
        return try await send("mouseUp", toPartWithScriptID: partScriptID)
    }

    /// Send an arbitrary message to a part (e.g. `mouseDown`, `mouseUp`).
    @discardableResult
    public func send(_ message: String, toPartWithScriptID id: Int, arguments: [String] = []) async throws -> [HostEffect] {
        let path = try scriptPath(partScriptID: id)
        _ = try await HyperTalk.send(message, arguments: arguments, along: path, host: host)
        return host.takeEffects()
    }

    /// Make `index` the current card and send it `openCard` (as the app does on
    /// navigation). Use after applying a `navigate` effect, or to land the
    /// first card.
    @discardableResult
    public func openCard(index: Int) async throws -> [HostEffect] {
        guard host.stack.cards.indices.contains(index) else {
            throw EngineError("There is no card \(index + 1).")
        }
        host.currentIndex = index
        let path = scriptPath(part: nil, cardIndex: index)
        _ = try await HyperTalk.send("openCard", along: path, host: host)
        return host.takeEffects()
    }

    /// Send `openStack` then `openCard` for the first card — the page's initial
    /// load, mirroring the app's `.task`.
    @discardableResult
    public func start() async throws -> [HostEffect] {
        let path = scriptPath(part: nil, cardIndex: host.currentIndex)
        _ = try await HyperTalk.send("openStack", along: path, host: host)
        _ = try await HyperTalk.send("openCard", along: path, host: host)
        return host.takeEffects()
    }

    /// A timed send firing: deliver `message` to the part (located anywhere
    /// in the stack) or, with no part, along the given card's path. A target
    /// that no longer exists is dropped silently — the send dies with it.
    @discardableResult
    public func deliverScheduled(message: String, arguments: [String], partScriptID: Int?, cardScriptID: Int) async throws -> [HostEffect] {
        if let partScriptID {
            // The part may live on any card's layer or any background.
            for (cardIndex, card) in host.stack.cards.enumerated() {
                if let part = card.parts.first(where: { $0.scriptID == partScriptID }) {
                    let path = scriptPath(part: part, domain: .card, cardIndex: cardIndex)
                    _ = try await HyperTalk.send(message, arguments: arguments, along: path, host: host)
                    return host.takeEffects()
                }
            }
            for background in host.stack.backgrounds {
                guard let part = background.parts.first(where: { $0.scriptID == partScriptID }),
                      let cardIndex = host.stack.cards.firstIndex(where: { $0.backgroundID == background.id })
                else { continue }
                let path = scriptPath(part: part, domain: .background, cardIndex: cardIndex)
                _ = try await HyperTalk.send(message, arguments: arguments, along: path, host: host)
                return host.takeEffects()
            }
            return []
        }
        guard let cardIndex = host.stack.cards.firstIndex(where: { $0.scriptID == cardScriptID }) else {
            return []
        }
        let path = scriptPath(part: nil, cardIndex: cardIndex)
        _ = try await HyperTalk.send(message, arguments: arguments, along: path, host: host)
        return host.takeEffects()
    }

    /// Run one message-box line; returns its printed value (for a bare
    /// expression) or nil.
    public func runMessage(_ line: String) async throws -> String? {
        let path = scriptPath(part: nil, cardIndex: host.currentIndex)
        return try await HyperTalk.execute(messageLine: line, along: path, host: host)
    }

    /// Effects accumulated but not yet drained (e.g. from the last event).
    public func drainEffects() -> [HostEffect] { host.takeEffects() }

    // MARK: - Render state

    public func currentCardState() -> CardState { cardState(at: host.currentIndex) }

    public func cardState(at index: Int) -> CardState {
        let card = host.stack.cards[index]
        let background = host.stack.backgrounds.first { $0.id == card.backgroundID }
        // Stamp the script selection onto its field's render part.
        func stamped(_ parts: [Part]) -> [RenderPart] {
            parts.map { part in
                var rendered = Self.render(part)
                if let selection = host.selection, selection.scriptID == part.scriptID {
                    rendered.selStart = selection.range.lowerBound
                    rendered.selEnd = selection.range.upperBound
                }
                return rendered
            }
        }
        return CardState(
            cardIndex: index,
            cardScriptID: card.scriptID,
            cardName: card.name,
            backgroundParts: stamped(background?.parts ?? []),
            cardParts: stamped(card.parts),
            cardShowPicture: card.showPicture,
            backgroundShowPicture: background?.showPicture ?? true,
            menus: host.scriptedMenus.map { menu in
                MenuState(name: menu.name, enabled: menu.enabled,
                          items: menu.items.map { .init(name: $0.name, enabled: $0.enabled, checkMark: $0.checkMark) })
            },
            viewportWidth: host.cardWindowViewport?.width,
            viewportHeight: host.cardWindowViewport?.height,
            theme: host.stack.theme
        )
    }

    /// Convenience for tests/JS: a field's current text on the current card.
    public func fieldText(named name: String) -> String? {
        try? host.fieldText(.named(name), domain: .any, onCard: nil)
    }

    /// The visitor edited a field on the page: record its text, so the state
    /// scripts read tracks what was typed. The part is identified by its
    /// permanent scriptID on the current card (or its background).
    public func setField(partScriptID id: Int, text: String) throws {
        try host.setFieldText(.id(String(id)), domain: .any, onCard: nil, to: text)
    }

    // MARK: - Message path

    /// The message path for a part identified by permanent scriptID on the
    /// current card — mirrors the app's `scriptPath(cardAt:part:)`.
    private func scriptPath(partScriptID id: Int) throws -> [ScriptLayer] {
        let card = host.stack.cards[host.currentIndex]
        if let index = card.parts.firstIndex(where: { $0.scriptID == id }) {
            return scriptPath(part: card.parts[index], domain: .card, cardIndex: host.currentIndex)
        }
        if let background = host.stack.backgrounds.first(where: { $0.id == card.backgroundID }),
           let index = background.parts.firstIndex(where: { $0.scriptID == id }) {
            return scriptPath(part: background.parts[index], domain: .background, cardIndex: host.currentIndex)
        }
        throw EngineError("There is no part with id \(id) on the current card.")
    }

    private func scriptPath(part: Part, domain: HyperTalkObject.PartDomain, cardIndex: Int) -> [ScriptLayer] {
        let object = HyperTalkObject.part(kind: part.kind.word, domain: domain, reference: .id(String(part.scriptID)), onCard: nil)
        var layers = [ScriptLayer(name: "\(part.kind.word) \"\(part.name)\" script", source: part.script, object: object)]
        layers += scriptPath(part: nil, cardIndex: cardIndex)
        return layers
    }

    private func scriptPath(part: Part?, cardIndex: Int) -> [ScriptLayer] {
        guard host.stack.cards.indices.contains(cardIndex) else { return [] }
        let card = host.stack.cards[cardIndex]
        var layers: [ScriptLayer] = []
        layers.append(ScriptLayer(name: "card \"\(card.name)\" script", source: card.script, object: .thisCard))
        if let background = host.stack.backgrounds.first(where: { $0.id == card.backgroundID }) {
            layers.append(ScriptLayer(name: "background script", source: background.script, object: .thisBackground))
        }
        layers.append(ScriptLayer(name: "stack script", source: host.stack.script, object: .thisStack))
        return layers
    }

    // MARK: - Rendering a part

    private static func render(_ part: Part) -> RenderPart {
        var text: String?
        var hilite: Bool?
        var scroll: Double?
        var asset: String?
        switch part.kind {
        case .button(let b): text = b.showName ? b.title : ""; hilite = b.hilite
        case .field(let f): text = f.text; scroll = f.scroll
        case .label(let l): text = l.text
        case .image(let i): asset = i.assetName
        }
        var rendered = RenderPart(
            scriptID: part.scriptID,
            kind: part.kind.word,
            name: part.name,
            x: part.frame.x, y: part.frame.y, width: part.frame.width, height: part.frame.height,
            visible: part.isVisible,
            enabled: part.isEnabled,
            text: text,
            hilite: hilite,
            scroll: scroll
        )
        rendered.asset = asset
        return rendered
    }
}

// MARK: - Renderable snapshot (Encodable for the JS bridge)

public struct CardState: Codable, Equatable, Sendable {
    public let cardIndex: Int
    public let cardScriptID: Int
    public let cardName: String
    public let backgroundParts: [RenderPart]
    public let cardParts: [RenderPart]
    /// `show/hide [background] picture` — whether each paint layer draws.
    public let cardShowPicture: Bool
    public let backgroundShowPicture: Bool
    /// The scripted menu bar, rendered by the page as a strip.
    public let menus: [MenuState]
    /// The card-window viewport crop; nil shows the whole card.
    public let viewportWidth: Double?
    public let viewportHeight: Double?
    /// The stack's current theme name (`set the theme of this stack`), so the
    /// page can re-apply the palette live after a dispatch changes it.
    public let theme: String
}

/// A scripted menu, serialized for the page's menu strip.
public struct MenuState: Codable, Equatable, Sendable {
    public let name: String
    public let enabled: Bool
    public let items: [Item]

    public struct Item: Codable, Equatable, Sendable {
        public let name: String
        public let enabled: Bool
        public let checkMark: Bool
    }
}

/// The mutable, script-visible bits of a part the page re-reads after each
/// event (text, hilite, visibility, geometry). Static layout/style stays in
/// the exported `stack.json`; this carries what scripts can change.
public struct RenderPart: Codable, Equatable, Sendable {
    public let scriptID: Int
    public let kind: String
    public let name: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let visible: Bool
    /// `enable`/`disable` — a disabled part grays and ignores clicks.
    public let enabled: Bool
    public let text: String?
    public let hilite: Bool?
    /// A scrolling field's current offset (`the scroll of field`).
    public let scroll: Double?
    /// The script selection's character range when it lies in this field
    /// (`select line 2 of field 1`); nil otherwise.
    public var selStart: Int?
    public var selEnd: Int?
    /// An image part's asset name — or, after `import picture from url`, the
    /// URL itself (the page's <img> loads either).
    public var asset: String?
}
