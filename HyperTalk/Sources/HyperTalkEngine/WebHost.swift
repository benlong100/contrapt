//
//  WebHost.swift
//  HyperTalkEngine
//
//  A headless `HyperTalkHost` for the exported website: it owns an in-memory
//  `Stack` (mutating it in place, as the app's host mutates its document) and
//  records world-facing side effects for the JS bridge to apply. It is a
//  faithful port of the app's DocumentScriptHost, with SwiftUI bindings
//  replaced by direct storage and app callbacks replaced by the effect queue.
//
//  Session state (globals, the push/pop back-stack, `go back` history, the
//  running `find` cursor) lives on the instance — the engine persists across
//  dispatches within a page, so a fresh host is NOT built per script run.
//

import Foundation
import HyperTalk

final class WebHost: HyperTalkHost {
    /// The live stack. Scripts read and write it; `currentCardState()` renders
    /// from it after each dispatch.
    var stack: Stack
    /// The card the page is showing (0-based).
    var currentIndex: Int = 0 {
        // The script selection doesn't survive leaving the card (HyperCard) —
        // and this catches every card-change path (go, openCard, find, sort).
        didSet { if oldValue != currentIndex { selection = nil } }
    }
    /// World-facing effects recorded during the current dispatch, drained by
    /// the engine afterwards.
    private(set) var recorded: [HostEffect] = []
    /// How suspending commands (`answer`/`ask`/`wait`) are answered.
    var interaction: EngineInteraction

    // Session state.
    /// The scripted menu bar (`create menu` / `put … into menu`) — rendered by
    /// the page as a strip, like the app's.
    var scriptedMenus: [HyperTalkMenu] = []
    /// The card-window viewport (`set the rect/width/height of card window`):
    /// nil shows the whole card; a size crops it, as in the app.
    var cardWindowViewport: (width: Double, height: Double)?
    private var globals: [String: String] = [:]
    /// The stack's persistent `stackData` store (one encoded array string),
    /// seeded from localStorage at load and flushed back via a `persist` effect.
    private var persistentStore: String
    private var backStack: [String] = []      // push/pop card
    private var history: [String] = []         // go back
    private var findState = FindState()
    private var sortContextIndex: Int?

    /// Environment globals (userLevel/textArrows/powerKeys/blindTyping) —
    /// per-engine, read back by the Home Preferences idiom.
    private var environment: [String: String] = [:]

    func environmentSetting(_ name: String) -> String? {
        if let stored = environment[name] { return stored }
        switch name {
        case "userlevel": return "5"
        case "textarrows", "powerkeys", "blindtyping": return "false"
        default: return nil
        }
    }

    func setEnvironmentSetting(_ name: String, to value: String) -> Bool {
        switch name {
        case "userlevel":
            environment[name] = String(max(1, min(5, Int(Double(value) ?? 5))))
        case "textarrows", "powerkeys", "blindtyping":
            environment[name] = value.lowercased() == "true" ? "true" : "false"
        default: return false
        }
        return true
    }

    /// `type <expr>` at the script selection — same semantics as the app
    /// host: replace the selected range, caret after. No selection → no-op.
    func typeText(_ text: String, withCommandKey: Bool) {
        guard !withCommandKey, let selected = selection else { return }
        let reference = HyperTalkObject.Reference.id(String(selected.scriptID))
        guard let current = try? fieldText(reference, domain: .any, onCard: nil) else { return }
        let characters = Array(current)
        let lo = max(0, min(selected.range.lowerBound, characters.count))
        let hi = max(lo, min(selected.range.upperBound, characters.count))
        let updated = String(characters[0..<lo]) + text + String(characters[hi...])
        guard (try? setFieldText(reference, domain: .any, onCard: nil, to: updated)) != nil else { return }
        let caret = lo + text.count
        selection = (scriptID: selected.scriptID, layer: selected.layer, range: caret..<caret)
    }

    func menuBarSnapshot() -> [HyperTalkMenu] { scriptedMenus }
    func updateMenuBar(_ menus: [HyperTalkMenu]) { scriptedMenus = menus }

    func windowProperty(_ property: String, window: String) -> String? {
        guard window == "card" || window == "cd" else { return nil }
        let width = cardWindowViewport?.width ?? stack.cardSize.width
        let height = cardWindowViewport?.height ?? stack.cardSize.height
        switch property {
        case "rect", "rectangle": return "0,0,\(Int(width)),\(Int(height))"
        case "width": return String(Int(width))
        case "height": return String(Int(height))
        case "scroll": return "0,0"
        default: return nil
        }
    }

    func setWindowProperty(_ property: String, window: String, to value: String) throws {
        guard window == "card" || window == "cd" else { return }
        func apply(width: Double, height: Double) {
            // A viewport at least the card's size means no crop.
            if width >= stack.cardSize.width, height >= stack.cardSize.height {
                cardWindowViewport = nil
            } else {
                cardWindowViewport = (max(64, width), max(64, height))
            }
        }
        let numbers = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        switch property {
        case "rect", "rectangle":
            guard numbers.count == 4 else { return }
            apply(width: numbers[2] - numbers[0], height: numbers[3] - numbers[1])
        case "width" where numbers.count == 1:
            apply(width: numbers[0], height: cardWindowViewport?.height ?? stack.cardSize.height)
        case "height" where numbers.count == 1:
            apply(width: cardWindowViewport?.width ?? stack.cardSize.width, height: numbers[0])
        default:
            break
        }
    }

    init(stack: Stack, interaction: EngineInteraction = EngineInteraction(), persistentData: String = "") {
        self.stack = stack
        self.interaction = interaction
        self.persistentStore = persistentData
    }

    func takeEffects() -> [HostEffect] {
        defer { recorded.removeAll(keepingCapacity: true) }
        return recorded
    }

    /// The current card, honoring an in-progress `sort` context.
    /// (Non-private so the properties/lookup extension in the sibling file can
    /// reach it — `private` is file-scoped in Swift.)
    var cardIndex: Int {
        if let sortContextIndex { return sortContextIndex }
        return min(currentIndex, max(0, stack.cards.count - 1))
    }

    // MARK: - Navigation

    func goToCard(_ destination: GoDestination, effects: [ScreenEffect]) async throws {
        if case .home = destination { recorded.append(.goHome); return }
        if case .stack(let name, let card) = destination {
            recorded.append(.goStack(name: name, card: card.flatMap(destinationDescription)))
            return
        }
        let count = stack.cards.count
        guard count > 0 else { throw HostError("This stack has no cards.") }
        if case .back = destination {
            guard let id = history.popLast(),
                  let index = stack.cards.firstIndex(where: { String($0.scriptID) == id }) else { return }
            navigate(to: index, effects: effects, recordHistory: false)
            return
        }
        let target: Int
        switch destination {
        case .next: target = (cardIndex + 1) % count
        case .previous: target = (cardIndex + count - 1) % count
        case .first: target = 0
        case .last: target = count - 1
        case .number(let n):
            guard (1...count).contains(n) else {
                throw HostError("There is no card \(n) — this stack has \(count) card\(count == 1 ? "" : "s").")
            }
            target = n - 1
        case .named(let name):
            guard let i = stack.cards.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw HostError("There is no card named \"\(name)\".")
            }
            target = i
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            guard let i = stack.cards.firstIndex(where: { String($0.scriptID) == wanted }) else {
                throw HostError("There is no card with id \(id).")
            }
            target = i
        case .inBackground, .markedCard, .relativeMarked:
            target = try resolveCardIndex(destination)
        case .home, .back, .stack:
            return
        }
        navigate(to: target, effects: effects, recordHistory: true)
    }

    private func navigate(to index: Int, effects: [ScreenEffect], recordHistory: Bool) {
        if recordHistory, stack.cards.indices.contains(cardIndex) {
            history.append(String(stack.cards[cardIndex].scriptID))
        }
        currentIndex = index
        recorded.append(.navigate(cardIndex: index, effects: effects))
    }

    // MARK: - Counting

    func count(_ countable: Countable) throws -> Int {
        switch countable {
        case .cards(let scope):
            guard let scope else { return stack.cards.count }
            let wanted: UUID?
            switch scope {
            case .current:
                wanted = stack.cards[cardIndex].backgroundID
            case .reference(let reference):
                wanted = backgroundID(for: reference)
            }
            guard let wanted else { throw HostError("There is no such background.") }
            return stack.cards.count { $0.backgroundID == wanted }
        case .backgrounds: return stack.backgrounds.count
        case .markedCards: return stack.cards.count(where: { $0.isMarked })
        case .parts(let kind, let domain):
            let card = stack.cards[cardIndex]
            let cardParts = card.parts
            let bgParts = stack.backgrounds.first(where: { $0.id == card.backgroundID })?.parts ?? []
            func matching(_ parts: [Part]) -> Int {
                if kind == "part" { return parts.filter { $0.kind.word == "button" || $0.kind.word == "field" }.count }
                return parts.filter { $0.kind.word == kind }.count
            }
            switch domain {
            case .card: return matching(cardParts)
            case .background: return matching(bgParts)
            case .any: return matching(cardParts) + matching(bgParts)
            }
        }
    }

    // MARK: - Fields

    func fieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, onCard: GoDestination?) throws -> String {
        let ci = try onCard.map { try resolveCardIndex($0) } ?? cardIndex
        let loc = try locateField(reference: reference, domain: domain, cardIndex: ci)
        let found = fieldPart(at: loc)
        guard case .field(let p) = found.kind else { throw HostError("That part is not a field.") }
        // Non-sharedText background fields read this card's overlay text.
        if case .background = loc, !p.sharedText {
            return stack.cards[ci].backgroundFieldContent[found.id.uuidString]?.text ?? ""
        }
        return p.text
    }

    func setFieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, onCard: GoDestination?, to text: String) throws {
        let ci = try onCard.map { try resolveCardIndex($0) } ?? cardIndex
        let loc = try locateField(reference: reference, domain: domain, cardIndex: ci)
        let found = fieldPart(at: loc)
        guard case .field(var p) = found.kind else { throw HostError("That part is not a field.") }
        if case .background = loc, !p.sharedText {
            var content = stack.cards[ci].backgroundFieldContent[found.id.uuidString] ?? BackgroundFieldContent()
            content.text = text
            stack.cards[ci].backgroundFieldContent[found.id.uuidString] = content
            return
        }
        p.text = text
        switch loc {
        case .card(let c, let i): stack.cards[c].parts[i].kind = .field(p)
        case .background(let b, let i): stack.backgrounds[b].parts[i].kind = .field(p)
        }
    }

    private enum RemoteFieldLocation {
        case card(cardIndex: Int, partIndex: Int)
        case background(backgroundIndex: Int, partIndex: Int)
    }

    private func fieldPart(at loc: RemoteFieldLocation) -> Part {
        switch loc {
        case .card(let c, let i): stack.cards[c].parts[i]
        case .background(let b, let i): stack.backgrounds[b].parts[i]
        }
    }

    private func locateField(reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, cardIndex ci: Int) throws -> RemoteFieldLocation {
        let card = stack.cards[ci]
        let bgIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID })
        func onCard() -> RemoteFieldLocation? {
            index(ofKind: "field", matching: reference, in: card.parts).map { .card(cardIndex: ci, partIndex: $0) }
        }
        func onBackground() -> RemoteFieldLocation? {
            guard let bgIndex,
                  let i = index(ofKind: "field", matching: reference, in: stack.backgrounds[bgIndex].parts) else { return nil }
            return .background(backgroundIndex: bgIndex, partIndex: i)
        }
        if domain != .background, let f = onCard() { return f }
        if domain != .card, let f = onBackground() { return f }
        if let f = onCard() ?? onBackground() { return f }
        switch reference {
        case .named(let n): throw HostError("There is no field named \"\(n)\" on that card.")
        case .number(let n): throw HostError("There is no field \(n) on that card.")
        case .id(let id): throw HostError("There is no field with id \(id) on that card.")
        }
    }

    // MARK: - Card resolution

    func setMarked(_ marked: Bool, card: GoDestination?) throws {
        let index = try card.map { try resolveCardIndex($0) } ?? cardIndex
        stack.cards[index].isMarked = marked
    }

    /// `delete button 1` / `delete card field "x"` / `delete image 2`.
    func deletePart(_ object: HyperTalkObject) throws {
        guard case .part(let kind, let domain, let reference, let onCard) = object else {
            throw HostError("That isn't a deletable object.")
        }
        switch try locatePart(kind: kind, domain: domain, reference: reference, onCard: onCard) {
        case .card(let cardIndex, let partIndex):
            stack.cards[cardIndex].parts.remove(at: partIndex)
        case .background(let backgroundIndex, let partIndex):
            stack.backgrounds[backgroundIndex].parts.remove(at: partIndex)
        }
    }

    /// `delete background <ref>` — only a background no card uses can go.
    func deleteBackground(_ reference: HyperTalkObject.Reference) throws {
        guard let id = backgroundID(for: reference) else { throw HostError("There is no such background.") }
        guard !stack.cards.contains(where: { $0.backgroundID == id }) else {
            throw HostError("That background still has cards — delete them first.")
        }
        stack.backgrounds.removeAll { $0.id == id }
    }

    /// `delete [the] [card|bkgnd] picture` — the engine model carries no paint
    /// asset (the page reads paint from stack.json), so hiding the layer is
    /// its observable effect; the app host truly removes the asset.
    func clearPicture(background: Bool, card: GoDestination?) throws {
        let ci = try card.map { try resolveCardIndex($0) } ?? cardIndex
        if background {
            let bgID = stack.cards[ci].backgroundID
            guard let bi = stack.backgrounds.firstIndex(where: { $0.id == bgID }) else { return }
            stack.backgrounds[bi].showPicture = false
        } else {
            stack.cards[ci].showPicture = false
        }
    }

    /// `delete [the] <card>` — remove a card (nil = the current one), guarding
    /// the last remaining card and cantDelete, then land on the nearest card.
    func deleteCard(_ card: GoDestination?) throws {
        let index = try card.map { try resolveCardIndex($0) } ?? cardIndex
        guard stack.cards.count > 1 else { throw HostError("The last remaining card can't be deleted.") }
        guard !stack.cards[index].cantDelete else { throw HostError("This card can't be deleted.") }
        stack.cards.remove(at: index)
        let next = min(currentIndex > index ? currentIndex - 1 : currentIndex, stack.cards.count - 1)
        currentIndex = max(0, next)
        recorded.append(.navigate(cardIndex: currentIndex, effects: []))
    }

    /// `make a card [using background <ref>]` — append a card at the end of
    /// the stack (nil background = the current card's), without navigating.
    func makeCard(background: HyperTalkObject.Reference?) throws -> Int {
        var targetBackground = stack.cards[cardIndex].backgroundID
        if let background {
            guard let found = backgroundID(for: background) else {
                throw HostError("There is no such background to make the card with.")
            }
            targetBackground = found
        }
        var card = Card(id: UUID(), name: "", backgroundID: targetBackground, script: "", parts: [])
        card.scriptID = stack.claimScriptID()
        stack.cards.append(card)
        return stack.cards.count
    }

    /// Merge scaffolding: a background with NO fields yet gets one per key —
    /// stacked single-line fields, with a "text" key given the tall multiline
    /// slot. A designed background (any field present) is left untouched.
    /// A missing background is left for makeCard to report.
    func scaffoldBackgroundFields(keys: [String], background: HyperTalkObject.Reference?) throws {
        let targetBackground = background.flatMap { backgroundID(for: $0) }
            ?? (background == nil ? stack.cards[cardIndex].backgroundID : nil)
        guard let targetBackground,
              let backgroundIndex = stack.backgrounds.firstIndex(where: { $0.id == targetBackground }),
              !keys.isEmpty,
              !stack.backgrounds[backgroundIndex].parts.contains(where: {
                  if case .field = $0.kind { return true } else { return false }
              }) else { return }
        // The layout: margins all around, a short row per key, and the
        // remaining height to a key named "text" (the feed/article body).
        let margin = 20.0, rowHeight = 32.0, gap = 10.0
        let width = stack.cardSize.width - margin * 2
        let shortRows = Double(keys.filter { $0.lowercased() != "text" }.count)
        let tallHeight = max(100, stack.cardSize.height - margin * 2 - shortRows * (rowHeight + gap))
        var y = margin
        for key in keys {
            let isBody = key.lowercased() == "text"
            guard var field = try? JSONDecoder().decode(
                FieldPart.self, from: Data("{\"text\":\"\"}".utf8)) else { return }
            field.isMultiline = isBody
            var part = Part(id: UUID(), name: key,
                            frame: PartFrame(x: margin, y: y, width: width,
                                             height: isBody ? tallHeight : rowHeight),
                            script: "", kind: .field(field))
            part.scriptID = stack.claimScriptID()
            stack.backgrounds[backgroundIndex].parts.append(part)
            y += (isBody ? tallHeight : rowHeight) + gap
        }
    }

    /// Timed send: resolve the target NOW to stable scriptIDs (they survive
    /// navigation and renames) and hand the page a timer effect. A background
    /// or stack target travels the scheduling card's path when it fires (the
    /// message bubbles card → background → stack).
    func scheduleSend(_ message: String, arguments: [String], to target: HyperTalkObject, afterSeconds: Double) throws {
        var partScriptID: Int?
        var cardScriptID = stack.cards[cardIndex].scriptID
        switch target {
        case .part(let kind, let domain, let reference, let onCard):
            let location = try locatePart(kind: kind, domain: domain, reference: reference, onCard: onCard)
            switch location {
            case .card(let ci, let pi):
                partScriptID = stack.cards[ci].parts[pi].scriptID
                cardScriptID = stack.cards[ci].scriptID
            case .background(let bi, let pi):
                partScriptID = stack.backgrounds[bi].parts[pi].scriptID
            }
        case .card(let destination):
            cardScriptID = stack.cards[try resolveCardIndex(destination)].scriptID
        default:
            break // thisCard / thisBackground / thisStack — the current card's path
        }
        recorded.append(.scheduleSend(message: message, arguments: arguments,
                                      partScriptID: partScriptID, cardScriptID: cardScriptID,
                                      afterSeconds: afterSeconds))
    }

    /// `import picture from url …` — the web export points the image part at
    /// the URL itself (the page's <img> fetches it; session-only, like every
    /// web-side mutation). Nil target = a new centered image part on the
    /// current card. Returns the part's id.
    func importPicture(fromURL url: String, into target: HyperTalkObject?) async throws -> Int {
        if let target {
            guard case .part(let kind, let domain, let reference, let onCard) = target, kind == "image" else {
                throw HostError("'import picture … into' needs an image part, like image \"Photo\".")
            }
            let location = try locatePart(kind: "image", domain: domain, reference: reference, onCard: onCard)
            var part = self.part(at: location)
            part.kind = .image(ImagePart(assetName: url))
            setPart(part, at: location)
            return part.scriptID
        }
        let width = min(200.0, stack.cardSize.width - 40)
        let height = min(150.0, stack.cardSize.height - 40)
        var part = Part(id: UUID(), name: "",
                        frame: PartFrame(x: (stack.cardSize.width - width) / 2,
                                         y: (stack.cardSize.height - height) / 2,
                                         width: width, height: height),
                        script: "", kind: .image(ImagePart(assetName: url)))
        part.scriptID = stack.claimScriptID()
        stack.cards[cardIndex].parts.append(part)
        return part.scriptID
    }

    /// Click-state semantics, applied before mouseUp dispatches (mirroring
    /// the app's CardView): a button in a FAMILY (autoHilite) hilites and
    /// clears its same-layer family siblings — HyperCard's radio group; a
    /// family-less checkbox/radio flips its checked state. Card and
    /// background families are distinct namespaces.
    func toggleHiliteIfToggleStyle(partScriptID id: Int, preferLayer: String? = nil) {
        let card = stack.cards[currentIndex]
        // Flip the hilite in the layer the click actually hit — a card and a
        // background button may share this scriptID (see dispatchMouseUp).
        let preferBackground = (preferLayer == "bkgnd" || preferLayer == "background" || preferLayer == "bg")
        func toggleCard() -> Bool {
            guard let index = card.parts.firstIndex(where: { $0.scriptID == id }),
                  case .button(let button) = card.parts[index].kind else { return false }
            applyClickHilite(to: &stack.cards[currentIndex].parts, at: index, button: button)
            return true
        }
        func toggleBackground() -> Bool {
            guard let backgroundIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID }),
                  let index = stack.backgrounds[backgroundIndex].parts.firstIndex(where: { $0.scriptID == id }),
                  case .button(let button) = stack.backgrounds[backgroundIndex].parts[index].kind else { return false }
            applyClickHilite(to: &stack.backgrounds[backgroundIndex].parts, at: index, button: button)
            return true
        }
        let ordered = preferBackground ? [toggleBackground, toggleCard] : [toggleCard, toggleBackground]
        for toggle in ordered where toggle() { return }
    }

    private func applyClickHilite(to parts: inout [Part], at index: Int, button: ButtonPart) {
        if button.family > 0, button.autoHilite {
            for i in parts.indices {
                guard case .button(var sibling) = parts[i].kind, sibling.family == button.family else { continue }
                sibling.hilite = (i == index)
                parts[i].kind = .button(sibling)
            }
        } else if button.style == .checkbox || button.style == .radio {
            var flipped = button
            flipped.hilite.toggle()
            parts[index].kind = .button(flipped)
        }
    }


    /// `the selectedButton of family N` — the hilited member on the layer
    /// (bare/card-qualified = the card layer; bkgnd-qualified = background),
    /// as "card button <n>" / "bkgnd button <n>" by button number. Card and
    /// background families are distinct namespaces (HyperCard Help's rule).
    func selectedButtonOfFamily(_ family: Int, domain: HyperTalkObject.PartDomain, onCard: GoDestination?) -> String {
        guard family > 0, let layer = familyLayer(domain: domain, onCard: onCard) else { return "" }
        var buttonNumber = 0
        for part in layer.parts {
            guard case .button(let button) = part.kind else { continue }
            buttonNumber += 1
            if button.family == family, button.hilite {
                return "\(layer.isBackground ? "bkgnd" : "card") button \(buttonNumber)"
            }
        }
        return ""
    }

    func familyExists(_ family: Int, domain: HyperTalkObject.PartDomain, onCard: GoDestination?) -> Bool {
        guard family > 0, let layer = familyLayer(domain: domain, onCard: onCard) else { return false }
        return layer.parts.contains { part in
            if case .button(let button) = part.kind { return button.family == family }
            return false
        }
    }

    private func familyLayer(domain: HyperTalkObject.PartDomain, onCard: GoDestination?) -> (parts: [Part], isBackground: Bool)? {
        let index: Int
        if let onCard {
            guard let resolved = try? resolveCardIndex(onCard) else { return nil }
            index = resolved
        } else {
            index = cardIndex
        }
        guard stack.cards.indices.contains(index) else { return nil }
        let card = stack.cards[index]
        if domain == .background {
            guard let background = stack.backgrounds.first(where: { $0.id == card.backgroundID }) else { return nil }
            return (background.parts, true)
        }
        return (card.parts, false)
    }

    func resolveCardIndex(_ destination: GoDestination) throws -> Int {
        let count = stack.cards.count
        guard count > 0 else { throw HostError("This stack has no cards.") }
        switch destination {
        case .next: return (cardIndex + 1) % count
        case .previous: return (cardIndex + count - 1) % count
        case .first: return 0
        case .last: return count - 1
        case .number(let n):
            guard (1...count).contains(n) else { throw HostError("There is no card \(n).") }
            return n - 1
        case .named(let name):
            guard let i = stack.cards.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw HostError("There is no card named \"\(name)\".")
            }
            return i
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            guard let i = stack.cards.firstIndex(where: { String($0.scriptID) == wanted }) else {
                throw HostError("There is no card with id \(id).")
            }
            return i
        case .inBackground(let inner, let background):
            let indices: [Int]
            if let background {
                indices = stack.cards.indices.filter {
                    backgroundName(ofCardAt: $0)?.caseInsensitiveCompare(background) == .orderedSame
                }
                guard !indices.isEmpty else { throw HostError("There is no background named \"\(background)\".") }
            } else {
                // Unnamed (`of bkgnd` / `of this bkgnd`) — the current card's.
                let wanted = stack.cards[cardIndex].backgroundID
                indices = stack.cards.indices.filter { stack.cards[$0].backgroundID == wanted }
            }
            switch inner {
            case .first: return indices.first!
            case .last: return indices.last!
            case .number(let n):
                guard (1...indices.count).contains(n) else {
                    throw HostError("There is no card \(n) in that background.")
                }
                return indices[n - 1]
            case .named(let name):
                guard let i = indices.first(where: { stack.cards[$0].name.caseInsensitiveCompare(name) == .orderedSame }) else {
                    throw HostError("There is no card named \"\(name)\" in that background.")
                }
                return i
            case .id(let id):
                let wanted = id.trimmingCharacters(in: .whitespaces)
                guard let i = indices.first(where: { String(stack.cards[$0].scriptID) == wanted }) else {
                    throw HostError("There is no card with id \(id) in that background.")
                }
                return i
            default: throw HostError("That card reference isn't supported within a background.")
            }
        case .markedCard(let n):
            let marked = stack.cards.indices.filter { stack.cards[$0].isMarked }
            guard (1...marked.count).contains(n) else { throw HostError("There is no marked card \(n).") }
            return marked[n - 1]
        case .relativeMarked(let forward):
            let marked = stack.cards.indices.filter { stack.cards[$0].isMarked }
            guard !marked.isEmpty else { throw HostError("There are no marked cards.") }
            return forward ? (marked.first { $0 > cardIndex } ?? marked.first!)
                           : (marked.last { $0 < cardIndex } ?? marked.last!)
        case .home, .back, .stack:
            throw HostError("Can't address a field of that card.")
        }
    }

    func adjacentBackgroundCardNumber(forward: Bool) -> Int? {
        let cards = stack.cards
        guard !cards.isEmpty else { return nil }
        // Distinct backgrounds in stack (card) order.
        var order: [UUID] = []
        for c in cards where !order.contains(c.backgroundID) { order.append(c.backgroundID) }
        guard order.count > 1 else { return nil }
        let current = cards[cardIndex].backgroundID
        guard let pos = order.firstIndex(of: current) else { return nil }
        let target = forward ? order[(pos + 1) % order.count]
                             : order[(pos - 1 + order.count) % order.count]
        guard let i = cards.firstIndex(where: { $0.backgroundID == target }) else { return nil }
        return i + 1
    }

    /// Resolves a count scope's background (`bg "Paths"` / `bg 2` / `bg id 7`).
    private func backgroundID(for reference: HyperTalkObject.Reference) -> UUID? {
        switch reference {
        case .named(let name):
            return stack.backgrounds.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
        case .number(let number):
            guard (1...stack.backgrounds.count).contains(number) else { return nil }
            return stack.backgrounds[number - 1].id
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            return stack.backgrounds.first { String($0.scriptID) == wanted }?.id
        }
    }

    private func backgroundName(ofCardAt index: Int) -> String? {
        let bgID = stack.cards[index].backgroundID
        return stack.backgrounds.first(where: { $0.id == bgID })?.name
    }

    // MARK: - Message box, beep

    func showMessage(_ text: String) { recorded.append(.message(text)) }

    /// Where the page's last field click landed (see StackEngine.dispatchMouseUp).
    var clickLine = ""
    var clickText = ""
    func clickValue(_ field: ClickField) -> String {
        switch field {
        case .line: clickLine
        case .text: clickText
        case .location: "" // the page doesn't report press coordinates yet
        }
    }

    // MARK: - Script selection (`select` / the selected* readers)

    /// The current script selection: which field (by permanent id), its
    /// layer word for descriptors, and a character range in its text.
    var selection: (scriptID: Int, layer: String, range: Range<Int>)?

    func setSelection(field reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, start: Int, end: Int) throws {
        let location = try locatePart(kind: "field", domain: domain, reference: reference)
        let part = part(at: location)
        let layer: String
        if case .background = location { layer = "bkgnd" } else { layer = "card" }
        let length = fieldTextOf(part).count
        let lo = max(0, min(start, length))
        let hi = max(lo, min(end, length))
        selection = (part.scriptID, layer, lo..<hi)
    }

    func clearSelection() { selection = nil }

    func selectionValue(_ component: SelectionComponent) -> String {
        guard let selection, let part = partWithScriptID(selection.scriptID) else { return "" }
        let fieldDescriptor = "\(selection.layer) field id \(selection.scriptID)"
        let text = Array(fieldTextOf(part))
        let range = selection.range.clamped(to: 0..<text.count)
        switch component {
        case .field:
            return fieldDescriptor
        case .text:
            return String(text[range])
        case .chunk:
            return "char \(range.lowerBound + 1) to \(range.upperBound) of \(fieldDescriptor)"
        case .line:
            let startLine = text[0..<range.lowerBound].count { $0 == "\n" } + 1
            let endLine = text[0..<max(range.lowerBound, range.upperBound == 0 ? 0 : range.upperBound - 1)]
                .count { $0 == "\n" } + 1
            return startLine == endLine
                ? "line \(startLine) of \(fieldDescriptor)"
                : "line \(startLine) to \(endLine) of \(fieldDescriptor)"
        }
    }

    private func fieldTextOf(_ part: Part) -> String {
        if case .field(let f) = part.kind { return f.text }
        return ""
    }

    private func partWithScriptID(_ id: Int) -> Part? {
        let card = stack.cards[cardIndex]
        if let part = card.parts.first(where: { $0.scriptID == id }) { return part }
        return stack.backgrounds.first { $0.id == card.backgroundID }?
            .parts.first { $0.scriptID == id }
    }
    func beep() { recorded.append(.beep) }

    // MARK: - Globals

    func globalValue(_ name: String) -> String? { globals[name] }
    func setGlobalValue(_ name: String, to value: String) { globals[name] = value }

    // MARK: - Persistent stack data (`stackData`)

    /// Reads from the in-memory store (seeded from localStorage at load).
    func persistentData() -> String { persistentStore }
    /// Updates the store and records a `persist` effect for the page to flush
    /// to localStorage, so the write survives a reload.
    func setPersistentData(_ encoded: String) {
        persistentStore = encoded
        recorded.append(.persist(encoded: encoded))
    }

    // MARK: - Clock / convert

    func clock(_ field: ClockField) -> String {
        let now = Date()
        switch field {
        case .seconds: return String(HyperCardDate.seconds(of: now)) // 1904 epoch, as in HyperCard
        case .ticks: return String(Int(now.timeIntervalSince1970 * 60))
        case .shortDate, .longDate, .abbreviatedDate, .shortTime, .longTime:
            let f = DateFormatter()
            switch field {
            case .shortDate: f.dateStyle = .short
            case .longDate: f.dateStyle = .full
            case .abbreviatedDate: f.dateStyle = .medium
            case .shortTime: f.timeStyle = .short
            case .longTime: f.timeStyle = .medium
            default: break
            }
            return f.string(from: now)
        }
    }

    func convert(_ value: String, from: [ConvertFormat], to: [ConvertFormat]) throws -> String {
        try convertRender(convertParse(value, from: from), to: to)
    }

    // MARK: - Dialogs / wait

    func answer(_ prompt: String, buttons: [String]) async -> String { await interaction.answer(prompt, buttons) }
    func ask(_ prompt: String, initialAnswer: String) async -> String? { await interaction.ask(prompt, initialAnswer) }
    func answerFile(_ prompt: String, type: String?) async -> String? { await interaction.answerFile(prompt, type) }
    func wait(seconds: Double) async { await interaction.wait(seconds) }

    /// `url`/`post`/`delete url` — delegated to the JS `fetch` bridge. The
    /// browser enforces CORS, so a stack can only reach hosts that permit it;
    /// there's no in-page consent prompt (unlike the app, the browser's own
    /// permission model governs the request).
    func httpRequest(method: String, url: String, body: String?, headers: [String: String], timeout: Double)
        async -> (body: String, status: Int, headers: [String: String], error: String?) {
        await interaction.httpRequest(method, url, body, headers, timeout)
    }

    // MARK: - Exists

    func exists(_ object: HyperTalkObject) -> Bool {
        switch object {
        case .part(let kind, let domain, let reference, let onCard):
            return (try? locatePart(kind: kind, domain: domain, reference: reference, onCard: onCard)) != nil
        case .card(let destination):
            return (try? resolveCardIndex(destination)) != nil
        case .thisCard: return !stack.cards.isEmpty
        case .thisBackground:
            let card = stack.cards[cardIndex]
            return stack.backgrounds.contains { $0.id == card.backgroundID }
        case .thisStack: return true
        }
    }

    // MARK: - Find

    private struct FindState {
        var query: String?
        var mode: FindMode = .wordPrefix
        var scope: String?
        var cardIndex = 0
        var partID: UUID?
        var matchStart = 0
        var found: [FoundField: String] = [:]
    }

    private struct FieldSlot {
        let cardIndex: Int
        let isBackground: Bool
        let ordinal: Int
        let partID: UUID
        let scriptID: Int
        let text: String
    }

    func find(_ text: String, mode: FindMode, inField reference: HyperTalkObject.Reference?, fieldDomain domain: HyperTalkObject.PartDomain) throws -> Bool {
        let query = text.trimmingCharacters(in: .whitespaces)
        let slots = fieldSlots(inField: reference, domain: domain)
        if slots.isEmpty, let reference {
            throw HostError("There is no \(fieldDescription(reference, domain)) to search.")
        }
        guard !query.isEmpty, !slots.isEmpty else {
            recorded.append(.beep); recorded.append(.clearFindHighlight); return false
        }
        let scopeKey = reference.map { referenceKey($0, domain) }
        let continuing = findState.query == query && findState.mode == mode && findState.scope == scopeKey && findState.partID != nil
        let startIndex: Int
        if continuing, let i = slots.firstIndex(where: { $0.cardIndex == findState.cardIndex && $0.partID == findState.partID }) {
            startIndex = i
        } else {
            startIndex = slots.firstIndex { $0.cardIndex >= cardIndex } ?? 0
        }
        func scan(firstOffset: Int) -> (slot: FieldSlot, range: Range<Int>)? {
            for step in 0..<slots.count {
                let slot = slots[(startIndex + step) % slots.count]
                let from = step == 0 ? firstOffset : 0
                if let range = FindMatcher.firstRange(in: slot.text, query: query, mode: mode, from: from) {
                    return (slot, range)
                }
            }
            return nil
        }
        let match = scan(firstOffset: continuing ? findState.matchStart + 1 : 0)
            ?? (continuing ? scan(firstOffset: 0) : nil)
        guard let (slot, range) = match else {
            recorded.append(.beep); recorded.append(.clearFindHighlight); return false
        }
        let characters = Array(slot.text)
        let matched = String(characters[range])
        let descriptor = "\(slot.isBackground ? "background" : "card") field \(slot.ordinal)"
        let lineNumber = characters[0..<range.lowerBound].filter { $0 == "\n" }.count + 1
        findState.query = query
        findState.mode = mode
        findState.scope = scopeKey
        findState.cardIndex = slot.cardIndex
        findState.partID = slot.partID
        findState.matchStart = range.lowerBound
        findState.found = [
            .text: matched,
            .field: descriptor,
            .chunk: "char \(range.lowerBound + 1) to \(range.upperBound) of \(descriptor)",
            .line: "line \(lineNumber) of \(descriptor)",
        ]
        currentIndex = slot.cardIndex
        recorded.append(.navigate(cardIndex: slot.cardIndex, effects: []))
        recorded.append(.findHighlight(partScriptID: slot.scriptID, start: range.lowerBound, end: range.upperBound))
        return true
    }

    func foundValue(_ field: FoundField) -> String { findState.found[field] ?? "" }

    private func fieldSlots(inField reference: HyperTalkObject.Reference?, domain: HyperTalkObject.PartDomain) -> [FieldSlot] {
        var slots: [FieldSlot] = []
        for (index, card) in stack.cards.enumerated() where !card.dontSearch {
            if domain != .background {
                appendFieldSlots(from: card.parts, cardIndex: index, isBackground: false, reference: reference, into: &slots)
            }
            if domain != .card,
               let bg = stack.backgrounds.first(where: { $0.id == card.backgroundID }), !bg.dontSearch {
                appendFieldSlots(from: bg.parts, cardIndex: index, isBackground: true, reference: reference, into: &slots)
            }
        }
        return slots
    }

    private func appendFieldSlots(from parts: [Part], cardIndex: Int, isBackground: Bool, reference: HyperTalkObject.Reference?, into slots: inout [FieldSlot]) {
        var ordinal = 0
        for part in parts {
            guard case .field(let p) = part.kind else { continue }
            ordinal += 1
            if let reference, !fieldMatches(part: part, ordinal: ordinal, reference: reference) { continue }
            let text = (isBackground && !p.sharedText)
                ? (stack.cards[cardIndex].backgroundFieldContent[part.id.uuidString]?.text ?? "")
                : p.text
            slots.append(FieldSlot(cardIndex: cardIndex, isBackground: isBackground, ordinal: ordinal,
                                   partID: part.id, scriptID: part.scriptID, text: text))
        }
    }

    private func fieldMatches(part: Part, ordinal: Int, reference: HyperTalkObject.Reference) -> Bool {
        switch reference {
        case .named(let n): return part.name.caseInsensitiveCompare(n) == .orderedSame
        case .number(let n): return ordinal == n
        case .id(let id): return String(part.scriptID) == id.trimmingCharacters(in: .whitespaces)
        }
    }

    private func fieldDescription(_ reference: HyperTalkObject.Reference, _ domain: HyperTalkObject.PartDomain) -> String {
        let layer = switch domain { case .any: ""; case .card: "card "; case .background: "background " }
        switch reference {
        case .named(let n): return "\(layer)field \"\(n)\""
        case .number(let n): return "\(layer)field \(n)"
        case .id(let id): return "\(layer)field id \(id)"
        }
    }

    private func referenceKey(_ reference: HyperTalkObject.Reference, _ domain: HyperTalkObject.PartDomain) -> String {
        let prefix = switch domain { case .any: ""; case .card: "card "; case .background: "background " }
        switch reference {
        case .named(let n): return prefix + n.lowercased()
        case .number(let n): return prefix + String(n)
        case .id(let id): return prefix + "id " + id
        }
    }

    // MARK: - Push / pop

    func pushCard() {
        guard cardIndex < stack.cards.count else { return }
        backStack.append(String(stack.cards[cardIndex].scriptID))
    }
    func popCard() -> String? { backStack.isEmpty ? nil : backStack.removeLast() }

    // MARK: - Sort

    func setSortContext(_ cardIndex: Int?) { sortContextIndex = cardIndex }

    func reorderCards(_ order: [Int]) throws {
        let cards = stack.cards
        guard order.count == cards.count, Set(order) == Set(0..<cards.count) else {
            throw HostError("Sort produced an invalid card order.")
        }
        let currentID = cards.indices.contains(cardIndex) ? cards[cardIndex].id : nil
        stack.cards = order.map { cards[$0] }
        if let currentID, let newIndex = stack.cards.firstIndex(where: { $0.id == currentID }) {
            currentIndex = newIndex
        }
    }

    // MARK: - Menu / click

    func performMenu(_ item: String) throws {
        switch item.lowercased() {
        case "new card":
            // Shares the background, empty card layer — mirrors the app host.
            let source = stack.cards[cardIndex]
            var card = Card(id: UUID(), name: "", backgroundID: source.backgroundID, script: "", parts: [])
            card.scriptID = stack.claimScriptID()
            let at = cardIndex + 1
            stack.cards.insert(card, at: at)
            currentIndex = at
            recorded.append(.navigate(cardIndex: at, effects: []))
        case "delete card":
            guard stack.cards.count > 1 else { return }
            guard !stack.cards[cardIndex].cantDelete else { throw HostError("This card can't be deleted.") }
            let idx = cardIndex
            stack.cards.remove(at: idx)
            currentIndex = min(idx, stack.cards.count - 1)
            recorded.append(.navigate(cardIndex: currentIndex, effects: []))
        default:
            return
        }
    }

    func click(x: Int, y: Int) {
        let px = Double(x), py = Double(y)
        func hit(_ parts: [Part]) -> Part? {
            for part in parts.reversed() where part.isVisible {
                let f = part.frame
                if px >= f.x, px <= f.x + f.width, py >= f.y, py <= f.y + f.height { return part }
            }
            return nil
        }
        let card = stack.cards[cardIndex]
        if let part = hit(card.parts) { recorded.append(.clickPart(scriptID: part.scriptID)); return }
        if let bgIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID }),
           let part = hit(stack.backgrounds[bgIndex].parts) { recorded.append(.clickPart(scriptID: part.scriptID)) }
    }

    // MARK: - Effect helpers

    private func destinationDescription(_ destination: GoDestination) -> String? {
        switch destination {
        case .named(let n): return n
        case .number(let n): return String(n)
        case .id(let id): return "id \(id)"
        default: return nil
        }
    }
}
