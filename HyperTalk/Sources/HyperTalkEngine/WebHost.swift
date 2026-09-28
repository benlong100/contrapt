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
    var currentIndex: Int = 0
    /// World-facing effects recorded during the current dispatch, drained by
    /// the engine afterwards.
    private(set) var recorded: [HostEffect] = []
    /// How suspending commands (`answer`/`ask`/`wait`) are answered.
    var interaction: EngineInteraction

    // Session state.
    private var globals: [String: String] = [:]
    private var backStack: [String] = []      // push/pop card
    private var history: [String] = []         // go back
    private var findState = FindState()
    private var sortContextIndex: Int?

    init(stack: Stack, interaction: EngineInteraction = EngineInteraction()) {
        self.stack = stack
        self.interaction = interaction
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

    func goToCard(_ destination: GoDestination, effects: [ScreenEffect]) throws {
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
        case .inBackground:
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
        recorded.append(.navigate(cardIndex: index, effects: effects.map(describe)))
    }

    // MARK: - Counting

    func count(_ countable: Countable) throws -> Int {
        switch countable {
        case .cards: return stack.cards.count
        case .backgrounds: return stack.backgrounds.count
        case .parts(let kind, let domain):
            let card = stack.cards[cardIndex]
            let cardParts = card.parts
            let bgParts = stack.backgrounds.first(where: { $0.id == card.backgroundID })?.parts ?? []
            func matching(_ parts: [Part]) -> Int { parts.filter { $0.kind.word == kind }.count }
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
        guard case .field(let p) = fieldPart(at: loc).kind else { throw HostError("That part is not a field.") }
        return p.text
    }

    func setFieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, onCard: GoDestination?, to text: String) throws {
        let ci = try onCard.map { try resolveCardIndex($0) } ?? cardIndex
        let loc = try locateField(reference: reference, domain: domain, cardIndex: ci)
        guard case .field(var p) = fieldPart(at: loc).kind else { throw HostError("That part is not a field.") }
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
            let indices = stack.cards.indices.filter {
                backgroundName(ofCardAt: $0)?.caseInsensitiveCompare(background) == .orderedSame
            }
            guard !indices.isEmpty else { throw HostError("There is no background named \"\(background)\".") }
            switch inner {
            case .first: return indices.first!
            case .last: return indices.last!
            case .number(let n):
                guard (1...indices.count).contains(n) else {
                    throw HostError("There is no card \(n) in background \"\(background)\".")
                }
                return indices[n - 1]
            default: throw HostError("That card reference isn't supported within a background.")
            }
        case .home, .back, .stack:
            throw HostError("Can't address a field of that card.")
        }
    }

    private func backgroundName(ofCardAt index: Int) -> String? {
        let bgID = stack.cards[index].backgroundID
        return stack.backgrounds.first(where: { $0.id == bgID })?.name
    }

    // MARK: - Message box, beep

    func showMessage(_ text: String) { recorded.append(.message(text)) }
    func beep() { recorded.append(.beep) }

    // MARK: - Globals

    func globalValue(_ name: String) -> String? { globals[name] }
    func setGlobalValue(_ name: String, to value: String) { globals[name] = value }

    // MARK: - Clock / convert

    func clock(_ field: ClockField) -> String {
        let now = Date()
        switch field {
        case .seconds: return String(Int(now.timeIntervalSince1970))
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
    func wait(seconds: Double) async { await interaction.wait(seconds) }

    // MARK: - Exists

    func exists(_ object: HyperTalkObject) -> Bool {
        switch object {
        case .part(let kind, let domain, let reference, let onCard):
            return (try? locatePart(kind: kind, domain: domain, reference: reference, onCard: onCard)) != nil
        case .card(let reference):
            return (try? cardIndexFor(reference)) != nil
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
            slots.append(FieldSlot(cardIndex: cardIndex, isBackground: isBackground, ordinal: ordinal,
                                   partID: part.id, scriptID: part.scriptID, text: p.text))
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

    private func describe(_ effect: ScreenEffect) -> String {
        var s = effect.kind.rawValue
        if let d = effect.direction { s += " \(d.rawValue)" }
        return s
    }

    private func destinationDescription(_ destination: GoDestination) -> String? {
        switch destination {
        case .named(let n): return n
        case .number(let n): return String(n)
        case .id(let id): return "id \(id)"
        default: return nil
        }
    }
}
