//
//  DocumentScriptHost.swift
//  Contrapt
//

import SwiftUI
import HyperTalk

/// Session-wide HyperTalk globals — shared across cards and stacks while
/// the app runs, as in HyperCard.
@MainActor final class GlobalStore {
    static let shared = GlobalStore()
    var values: [String: String] = [:]
}

/// The `push card` / `pop card` back-stack, session-wide (the host is rebuilt
/// per script run, so the stack lives here).
@MainActor final class CardBackStack {
    static let shared = CardBackStack()
    var ids: [String] = []
}

/// Browser history for `go back` — the trail of cards a script navigated
/// away from. Session-wide, since the host is rebuilt per script run.
@MainActor final class VisitHistory {
    static let shared = VisitHistory()
    var ids: [String] = []
}

/// Where `find` last matched, so the view can box it on the card.
struct FindHighlight: Equatable {
    var partID: UUID
    /// Character range within the field's text (for future exact boxing).
    var range: Range<Int>?
}

/// The running `find` cursor and its results, kept across script runs (so
/// repeating `find` walks to the next match, as in HyperCard).
@MainActor final class FindSession {
    static let shared = FindSession()
    var query: String?
    var mode: FindMode = .wordPrefix
    var scope: String?          // the field reference searched, if any
    var cardIndex = 0
    var partID: UUID?
    var matchStart = 0
    var found: [FoundField: String] = [:]

    func reset() {
        query = nil
        partID = nil
        matchStart = 0
        found = [:]
    }
}

/// Bridges a running script to the open document: `go` moves the current
/// card, `field` reads and writes field parts on the current card and its
/// background. Scripts can reach nothing else (D7: the interpreter is the
/// sandbox, and this host is its only door).
@MainActor
final class DocumentScriptHost: HyperTalkHost {
    private let stackBinding: Binding<Stack>
    private let currentCardIndex: Binding<Int>
    private let onMessage: (String) -> Void
    private let onAnswer: (String, [String]) async -> String
    private let onAsk: (String, String) async -> String?
    private let onNavigate: (Int, [ScreenEffect]) -> Void
    private let onFind: (FindHighlight?) -> Void
    private let onGoHome: () -> Void
    private let onClickPart: (Part) -> Void
    private let onGoStack: (String, GoDestination?) -> Void

    init(
        stack: Binding<Stack>,
        currentCardIndex: Binding<Int>,
        onMessage: @escaping (String) -> Void,
        onAnswer: @escaping (String, [String]) async -> String,
        onAsk: @escaping (String, String) async -> String?,
        onNavigate: @escaping (Int, [ScreenEffect]) -> Void,
        onFind: @escaping (FindHighlight?) -> Void = { _ in },
        onGoHome: @escaping () -> Void = {},
        onClickPart: @escaping (Part) -> Void = { _ in },
        onGoStack: @escaping (String, GoDestination?) -> Void = { _, _ in }
    ) {
        self.stackBinding = stack
        self.currentCardIndex = currentCardIndex
        self.onMessage = onMessage
        self.onAnswer = onAnswer
        self.onAsk = onAsk
        self.onNavigate = onNavigate
        self.onFind = onFind
        self.onGoHome = onGoHome
        self.onClickPart = onClickPart
        self.onGoStack = onGoStack
    }

    private var stack: Stack { stackBinding.wrappedValue }

    /// Set during `sort` so field/property lookups resolve against each card
    /// in turn (see setSortContext); nil means the real current card.
    private var sortContextIndex: Int?

    private var cardIndex: Int {
        if let sortContextIndex { return sortContextIndex }
        return min(currentCardIndex.wrappedValue, stack.cards.count - 1)
    }

    func setSortContext(_ cardIndex: Int?) {
        sortContextIndex = cardIndex
    }

    func performMenu(_ item: String) throws {
        switch item.lowercased() {
        case "new card":
            // A new card shares the current card's background but starts with
            // an empty card layer, inserted just after it — as in HyperCard.
            // (Shared parts belong on the background; card parts are per-card.)
            let source = stack.cards[cardIndex]
            var card = Card(id: UUID(), name: "", backgroundID: source.backgroundID, script: "", parts: [])
            card.scriptID = stackBinding.wrappedValue.claimScriptID()
            let at = cardIndex + 1
            stackBinding.wrappedValue.cards.insert(card, at: at)
            onNavigate(at, [])
        case "delete card":
            guard stack.cards.count > 1 else { return } // keep at least one card
            guard !stack.cards[cardIndex].cantDelete else {
                throw HostError("This card can't be deleted.")
            }
            let idx = cardIndex
            stackBinding.wrappedValue.cards.remove(at: idx)
            onNavigate(min(idx, stackBinding.wrappedValue.cards.count - 1), [])
        default:
            return // menu items Contrapt doesn't model — ignore, as a no-op
        }
    }

    func click(x: Int, y: Int) {
        let px = Double(x), py = Double(y)
        func hit(_ parts: [Part]) -> Part? {
            // Topmost first (last in z-order).
            for part in parts.reversed() where part.isVisible {
                let f = part.frame
                if px >= f.x, px <= f.x + f.width, py >= f.y, py <= f.y + f.height { return part }
            }
            return nil
        }
        let card = stack.cards[cardIndex]
        if let part = hit(card.parts) { onClickPart(part); return }
        if let bgIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID }),
           let part = hit(stack.backgrounds[bgIndex].parts) { onClickPart(part) }
        // Nothing under the point — a click on empty card is a no-op here.
    }

    func reorderCards(_ order: [Int]) throws {
        let cards = stack.cards
        guard order.count == cards.count, Set(order) == Set(0..<cards.count) else {
            throw HostError("Sort produced an invalid card order.")
        }
        // Keep the user on the same card after the reorder.
        let currentID = cards.indices.contains(cardIndex) ? cards[cardIndex].id : nil
        stackBinding.wrappedValue.cards = order.map { cards[$0] }
        if let currentID, let newIndex = stackBinding.wrappedValue.cards.firstIndex(where: { $0.id == currentID }) {
            currentCardIndex.wrappedValue = newIndex
        }
    }

    // MARK: - HyperTalkHost

    func goToCard(_ destination: GoDestination, effects: [ScreenEffect]) throws {
        if case .home = destination { onGoHome(); return }
        if case .stack(let name, let card) = destination { onGoStack(name, card); return }
        let count = stack.cards.count
        guard count > 0 else { throw HostError("This stack has no cards.") }
        // `go back` returns to the last card the script navigated away from.
        if case .back = destination {
            guard let id = VisitHistory.shared.ids.popLast(),
                  let index = stack.cards.firstIndex(where: { String($0.scriptID) == id }) else {
                return // nothing to go back to — harmless, as in HyperCard
            }
            onNavigate(index, effects)
            return
        }
        let target: Int
        switch destination {
        case .next:
            target = (cardIndex + 1) % count
        case .previous:
            target = (cardIndex + count - 1) % count
        case .first:
            target = 0
        case .last:
            target = count - 1
        case .number(let number):
            guard (1...count).contains(number) else {
                throw HostError("There is no card \(number) — this stack has \(count) card\(count == 1 ? "" : "s").")
            }
            target = number - 1
        case .named(let name):
            guard let index = stack.cards.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw HostError("There is no card named \"\(name)\".")
            }
            target = index
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            guard let index = stack.cards.firstIndex(where: { String($0.scriptID) == wanted }) else {
                throw HostError("There is no card with id \(id).")
            }
            target = index
        case .inBackground:
            target = try resolveCardIndex(destination)
        case .home, .back, .stack:
            return // handled above / not a same-stack destination
        }
        // Remember where we came from so a later `go back` can return here.
        VisitHistory.shared.ids.append(String(stack.cards[cardIndex].scriptID))
        // The view owns the animated transition (see ContentView.navigate).
        onNavigate(target, effects)
    }

    func count(_ countable: Countable) throws -> Int {
        switch countable {
        case .cards:
            return stack.cards.count
        case .backgrounds:
            return stack.backgrounds.count
        case .parts(let kind, let domain):
            let card = stack.cards[cardIndex]
            let cardParts = card.parts
            let backgroundParts = stack.backgrounds.first(where: { $0.id == card.backgroundID })?.parts ?? []
            func matching(_ parts: [Part]) -> Int {
                parts.filter { $0.kind.word == kind }.count
            }
            switch domain {
            case .card: return matching(cardParts)
            case .background: return matching(backgroundParts)
            case .any: return matching(cardParts) + matching(backgroundParts)
            }
        }
    }

    func fieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, onCard: GoDestination?) throws -> String {
        let ci = try onCard.map { try resolveCardIndex($0) } ?? cardIndex
        let location = try locateField(reference: reference, domain: domain, cardIndex: ci)
        guard case .field(let properties) = fieldPart(at: location).kind else {
            throw HostError("That part is not a field.")
        }
        return properties.text
    }

    func setFieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, onCard: GoDestination?, to text: String) throws {
        let ci = try onCard.map { try resolveCardIndex($0) } ?? cardIndex
        let location = try locateField(reference: reference, domain: domain, cardIndex: ci)
        guard case .field(var properties) = fieldPart(at: location).kind else {
            throw HostError("That part is not a field.")
        }
        properties.text = text
        switch location {
        case .card(let cardIndex, let partIndex):
            stackBinding.wrappedValue.cards[cardIndex].parts[partIndex].kind = .field(properties)
        case .background(let backgroundIndex, let partIndex):
            stackBinding.wrappedValue.backgrounds[backgroundIndex].parts[partIndex].kind = .field(properties)
        }
    }

    /// Where a field lives, including which card — so `field "X" of prev card`
    /// can read/write without navigating.
    private enum RemoteFieldLocation {
        case card(cardIndex: Int, partIndex: Int)
        case background(backgroundIndex: Int, partIndex: Int)
    }

    private func fieldPart(at location: RemoteFieldLocation) -> Part {
        switch location {
        case .card(let cardIndex, let partIndex): stack.cards[cardIndex].parts[partIndex]
        case .background(let backgroundIndex, let partIndex): stack.backgrounds[backgroundIndex].parts[partIndex]
        }
    }

    private func locateField(reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, cardIndex ci: Int) throws -> RemoteFieldLocation {
        let card = stack.cards[ci]
        let backgroundIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID })
        func onCard() -> RemoteFieldLocation? {
            index(ofKind: "field", matching: reference, in: card.parts).map { .card(cardIndex: ci, partIndex: $0) }
        }
        func onBackground() -> RemoteFieldLocation? {
            guard let backgroundIndex,
                  let partIndex = index(ofKind: "field", matching: reference, in: stack.backgrounds[backgroundIndex].parts) else { return nil }
            return .background(backgroundIndex: backgroundIndex, partIndex: partIndex)
        }
        // Honor the requested layer first, then fall back to the other.
        // HyperCard background fields import as per-card card parts, so a
        // `background field "X"` reference actually lives on the card — the
        // fallback finds it (and vice versa) rather than failing.
        if domain != .background, let found = onCard() { return found }
        if domain != .card, let found = onBackground() { return found }
        if let found = onCard() ?? onBackground() { return found }
        switch reference {
        case .named(let name): throw HostError("There is no field named \"\(name)\" on that card.")
        case .number(let number): throw HostError("There is no field \(number) on that card.")
        case .id(let id): throw HostError("There is no field with id \(id) on that card.")
        }
    }

    /// Resolves a card destination (from `field … of <card>`) to an index.
    private func resolveCardIndex(_ destination: GoDestination) throws -> Int {
        let count = stack.cards.count
        guard count > 0 else { throw HostError("This stack has no cards.") }
        switch destination {
        case .next: return (cardIndex + 1) % count
        case .previous: return (cardIndex + count - 1) % count
        case .first: return 0
        case .last: return count - 1
        case .number(let number):
            guard (1...count).contains(number) else { throw HostError("There is no card \(number).") }
            return number - 1
        case .named(let name):
            guard let index = stack.cards.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw HostError("There is no card named \"\(name)\".")
            }
            return index
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            guard let index = stack.cards.firstIndex(where: { String($0.scriptID) == wanted }) else {
                throw HostError("There is no card with id \(id).")
            }
            return index
        case .inBackground(let inner, let background):
            let indices = stack.cards.indices.filter {
                backgroundName(ofCardAt: $0)?.caseInsensitiveCompare(background) == .orderedSame
            }
            guard !indices.isEmpty else {
                throw HostError("There is no background named \"\(background)\".")
            }
            switch inner {
            case .first: return indices.first!
            case .last: return indices.last!
            case .number(let number):
                guard (1...indices.count).contains(number) else {
                    throw HostError("There is no card \(number) in background \"\(background)\".")
                }
                return indices[number - 1]
            default:
                throw HostError("That card reference isn't supported within a background.")
            }
        case .home, .back, .stack:
            throw HostError("Can't address a field of that card.")
        }
    }

    private func backgroundName(ofCardAt index: Int) -> String? {
        let backgroundID = stack.cards[index].backgroundID
        return stack.backgrounds.first(where: { $0.id == backgroundID })?.name
    }

    func showMessage(_ text: String) {
        onMessage(text)
    }

    /// The XCMD/XFCN names recorded at import — calls to them no-op rather
    /// than raising "Can't understand" (the compiled code can't run here).
    func isExternalName(_ name: String) -> Bool {
        stack.externalCommands.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    func beep() {
        Beeper.shared.beep()
    }

    // MARK: - Globals

    func globalValue(_ name: String) -> String? {
        GlobalStore.shared.values[name]
    }

    func setGlobalValue(_ name: String, to value: String) {
        GlobalStore.shared.values[name] = value
    }

    // MARK: - Clock

    func clock(_ field: ClockField) -> String {
        let now = Date()
        switch field {
        case .seconds:
            return String(Int(now.timeIntervalSince1970))
        case .ticks:
            return String(Int(now.timeIntervalSince1970 * 60))
        case .shortDate, .longDate, .abbreviatedDate, .shortTime, .longTime:
            let formatter = DateFormatter()
            switch field {
            case .shortDate: formatter.dateStyle = .short
            case .longDate: formatter.dateStyle = .full
            case .abbreviatedDate: formatter.dateStyle = .medium
            case .shortTime: formatter.timeStyle = .short
            case .longTime: formatter.timeStyle = .medium
            default: break
            }
            return formatter.string(from: now)
        }
    }

    // MARK: - Convert

    /// Reformats a date/time, matching the styles `the date` / `the time`
    /// produce so values round-trip. Uses the user's calendar and locale;
    /// `seconds` counts from the Unix epoch, as `the seconds` does.
    func convert(_ value: String, from: [ConvertFormat], to: [ConvertFormat]) throws -> String {
        let date = try convertParse(value, from: from)
        return try convertRender(date, to: to)
    }

    // MARK: - Dialogs

    func answer(_ prompt: String, buttons: [String]) async -> String {
        await onAnswer(prompt, buttons)
    }

    func ask(_ prompt: String, initialAnswer: String) async -> String? {
        await onAsk(prompt, initialAnswer)
    }

    func wait(seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    func exists(_ object: HyperTalkObject) -> Bool {
        switch object {
        case .part(let kind, let domain, let reference):
            return (try? locatePart(kind: kind, domain: domain, reference: reference)) != nil
        case .card(let reference):
            return (try? cardIndexFor(reference)) != nil
        case .thisCard:
            return !stack.cards.isEmpty
        case .thisBackground:
            let card = stack.cards[cardIndex]
            return stack.backgrounds.contains { $0.id == card.backgroundID }
        case .thisStack:
            return true
        }
    }

    // MARK: - Find

    /// One searchable field, in stack traversal order.
    private struct FieldSlot {
        let cardIndex: Int
        let isBackground: Bool
        let ordinal: Int       // position among fields in its own layer
        let partID: UUID
        let text: String
    }

    func find(_ text: String, mode: FindMode, inField reference: HyperTalkObject.Reference?, fieldDomain domain: HyperTalkObject.PartDomain) throws -> Bool {
        let query = text.trimmingCharacters(in: .whitespaces)
        let session = FindSession.shared
        let slots = fieldSlots(inField: reference, domain: domain)
        // A named-but-missing scoped field is an error, not a quiet miss —
        // otherwise `find "x" in card field id 16` looks like "x isn't there".
        if slots.isEmpty, let reference {
            throw HostError("There is no \(fieldDescription(reference, domain)) to search.")
        }
        guard !query.isEmpty, !slots.isEmpty else {
            beep(); onFind(nil); return false
        }

        // Continue from the last match when the same search repeats, so
        // repeating `find` walks to the next occurrence.
        let scopeKey = reference.map { referenceKey($0, domain) }
        let continuing = session.query == query && session.mode == mode && session.scope == scopeKey && session.partID != nil
        let startIndex: Int
        if continuing, let index = slots.firstIndex(where: { $0.cardIndex == session.cardIndex && $0.partID == session.partID }) {
            startIndex = index
        } else {
            startIndex = slots.firstIndex { $0.cardIndex >= cardIndex } ?? 0
        }

        // Scan every slot from the start point, giving the first slot the
        // supplied offset (the rest start at 0).
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

        // Continuing, resume past the last match; if that finds nothing, wrap
        // around from the top (so repeating `find` on a lone match re-boxes
        // it, as HyperCard does) rather than reporting "not found".
        let match = scan(firstOffset: continuing ? session.matchStart + 1 : 0)
            ?? (continuing ? scan(firstOffset: 0) : nil)
        guard let (slot, range) = match else {
            // HyperCard beeps and leaves everything put.
            beep()
            onFind(nil)
            return false
        }

        // Record the match, navigate to its card, and box the field.
        let characters = Array(slot.text)
        let matched = String(characters[range])
        let descriptor = "\(slot.isBackground ? "background" : "card") field \(slot.ordinal)"
        let lineNumber = characters[0..<range.lowerBound].filter { $0 == "\n" }.count + 1
        session.query = query
        session.mode = mode
        session.scope = scopeKey
        session.cardIndex = slot.cardIndex
        session.partID = slot.partID
        session.matchStart = range.lowerBound
        session.found = [
            .text: matched,
            .field: descriptor,
            .chunk: "char \(range.lowerBound + 1) to \(range.upperBound) of \(descriptor)",
            .line: "line \(lineNumber) of \(descriptor)",
        ]
        currentCardIndex.wrappedValue = slot.cardIndex
        onFind(FindHighlight(partID: slot.partID, range: range))
        return true
    }

    func foundValue(_ field: FoundField) -> String {
        FindSession.shared.found[field] ?? ""
    }

    // MARK: - Push / pop card

    func pushCard() {
        guard cardIndex < stack.cards.count else { return }
        CardBackStack.shared.ids.append(String(stack.cards[cardIndex].scriptID))
    }

    func popCard() -> String? {
        CardBackStack.shared.ids.isEmpty ? nil : CardBackStack.shared.ids.removeLast()
    }

    /// Every searchable field across the stack, in card order (card fields
    /// before background fields), honoring `dontSearch` on cards and
    /// backgrounds and any `in <field>` restriction.
    private func fieldSlots(inField reference: HyperTalkObject.Reference?, domain: HyperTalkObject.PartDomain) -> [FieldSlot] {
        var slots: [FieldSlot] = []
        for (index, card) in stack.cards.enumerated() where !card.dontSearch {
            if domain != .background {
                appendFieldSlots(from: card.parts, cardIndex: index, isBackground: false, reference: reference, into: &slots)
            }
            if domain != .card,
               let background = stack.backgrounds.first(where: { $0.id == card.backgroundID }),
               !background.dontSearch {
                appendFieldSlots(from: background.parts, cardIndex: index, isBackground: true, reference: reference, into: &slots)
            }
        }
        return slots
    }

    private func appendFieldSlots(from parts: [Part], cardIndex: Int, isBackground: Bool, reference: HyperTalkObject.Reference?, into slots: inout [FieldSlot]) {
        var ordinal = 0
        for part in parts {
            guard case .field(let properties) = part.kind else { continue }
            ordinal += 1
            if let reference, !fieldMatches(part: part, ordinal: ordinal, reference: reference) { continue }
            slots.append(FieldSlot(cardIndex: cardIndex, isBackground: isBackground, ordinal: ordinal, partID: part.id, text: properties.text))
        }
    }

    private func fieldMatches(part: Part, ordinal: Int, reference: HyperTalkObject.Reference) -> Bool {
        switch reference {
        case .named(let name): return part.name.caseInsensitiveCompare(name) == .orderedSame
        case .number(let number): return ordinal == number
        case .id(let id): return String(part.scriptID) == id.trimmingCharacters(in: .whitespaces)
        }
    }

    /// A human-readable field reference for `find` errors, e.g.
    /// "card field id 16" or "background field \"Notes\"".
    private func fieldDescription(_ reference: HyperTalkObject.Reference, _ domain: HyperTalkObject.PartDomain) -> String {
        let layer = switch domain {
        case .any: ""
        case .card: "card "
        case .background: "background "
        }
        switch reference {
        case .named(let name): return "\(layer)field \"\(name)\""
        case .number(let number): return "\(layer)field \(number)"
        case .id(let id): return "\(layer)field id \(id)"
        }
    }

    private func referenceKey(_ reference: HyperTalkObject.Reference, _ domain: HyperTalkObject.PartDomain) -> String {
        let prefix = switch domain {
        case .any: ""
        case .card: "card "
        case .background: "background "
        }
        switch reference {
        case .named(let name): return prefix + name.lowercased()
        case .number(let number): return prefix + String(number)
        case .id(let id): return prefix + "id " + id
        }
    }

    private func convertFormatter(_ formats: [ConvertFormat]) -> DateFormatter? {
        let formatter = DateFormatter()
        for format in formats {
            switch format {
            case .shortDate: formatter.dateStyle = .short
            case .longDate: formatter.dateStyle = .full
            case .abbreviatedDate: formatter.dateStyle = .medium
            case .shortTime: formatter.timeStyle = .short
            case .longTime: formatter.timeStyle = .medium
            case .seconds, .dateItems: return nil
            }
        }
        return formatter
    }

    private func convertParse(_ value: String, from: [ConvertFormat]) throws -> Date {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if from == [.seconds] || (from.isEmpty && Double(trimmed) != nil) {
            guard let seconds = Double(trimmed) else {
                throw HostError("Can't read \"\(value)\" as seconds.")
            }
            return Date(timeIntervalSince1970: seconds)
        }
        if from == [.dateItems] || (from.isEmpty && trimmed.contains(",")) {
            let parts = trimmed.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            guard parts.count >= 3 else {
                throw HostError("Expected at least year, month, and day in dateItems.")
            }
            var components = DateComponents()
            components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
            if parts.count > 3 { components.hour = parts[3] }
            if parts.count > 4 { components.minute = parts[4] }
            if parts.count > 5 { components.second = parts[5] }
            guard let date = Calendar.current.date(from: components) else {
                throw HostError("Can't read \"\(value)\" as dateItems.")
            }
            return date
        }
        if !from.isEmpty {
            guard let date = convertFormatter(from)?.date(from: trimmed) else {
                throw HostError("Can't read \"\(value)\" in that format.")
            }
            return date
        }
        // Auto-detect: try the style combinations until one reads it.
        let candidates: [[ConvertFormat]] = [
            [.shortDate, .shortTime], [.longDate, .longTime],
            [.longDate], [.abbreviatedDate], [.shortDate],
            [.longTime], [.shortTime],
        ]
        for candidate in candidates {
            if let date = convertFormatter(candidate)?.date(from: trimmed) { return date }
        }
        throw HostError("Can't read \"\(value)\" as a date or time.")
    }

    private func convertRender(_ date: Date, to: [ConvertFormat]) throws -> String {
        if to == [.seconds] { return String(Int(date.timeIntervalSince1970)) }
        if to == [.dateItems] {
            let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
            return [c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, c.weekday!]
                .map(String.init).joined(separator: ",")
        }
        guard let formatter = convertFormatter(to) else {
            throw HostError("Can't convert to that combination of formats.")
        }
        return formatter.string(from: date)
    }

    // MARK: - Properties

    func propertyValue(_ property: String, of object: HyperTalkObject) throws -> String {
        switch object {
        case .part(let kind, let domain, let reference):
            let location = try locatePart(kind: kind, domain: domain, reference: reference)
            if property == "number" {
                return String(ordinal(of: location, kind: kind))
            }
            return try partProperty(property, of: part(at: location), kind: kind)
        case .card(let reference):
            let index = try cardIndexFor(reference)
            return try cardProperty(property, cardAt: index)
        case .thisCard:
            return try cardProperty(property, cardAt: cardIndex)
        case .thisBackground:
            let card = stack.cards[cardIndex]
            guard let background = stack.backgrounds.first(where: { $0.id == card.backgroundID }) else {
                throw HostError("This card has no background.")
            }
            switch property {
            case "name": return background.name
            case "longname": return "bkgnd \"\(background.name)\""
            case "longid": return "bkgnd id \(background.scriptID)"
            case "id": return String(background.scriptID)
            case "cantdelete": return background.cantDelete ? "true" : "false"
            case "dontsearch": return background.dontSearch ? "true" : "false"
            default: throw Self.noSuchProperty(property, of: "this background")
            }
        case .thisStack:
            switch property {
            case "name": return stack.name
            case "longname", "longid": return "stack \"\(stack.name)\""
            case "cards": return String(stack.cards.count)
            case "width": return numberText(stack.cardSize.width)
            case "height": return numberText(stack.cardSize.height)
            case "fullscreen": return stack.isFullScreen ? "true" : "false"
            case "paddingcolor": return stack.paddingColor
            default: throw Self.noSuchProperty(property, of: "this stack")
            }
        }
    }

    func setProperty(_ property: String, of object: HyperTalkObject, to value: String) throws {
        guard property != "id" else {
            throw HostError("The id of an object can't be changed.")
        }
        switch object {
        case .part(let kind, let domain, let reference):
            let location = try locatePart(kind: kind, domain: domain, reference: reference)
            var updated = part(at: location)
            try applyPartProperty(property, to: &updated, kind: kind, value: value)
            setPart(updated, at: location)
        case .card(let reference):
            try setCardProperty(property, cardAt: try cardIndexFor(reference), to: value)
        case .thisCard:
            try setCardProperty(property, cardAt: cardIndex, to: value)
        case .thisBackground:
            let card = stack.cards[cardIndex]
            guard let index = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID }) else {
                throw HostError("This card has no background.")
            }
            switch property {
            case "name": stackBinding.wrappedValue.backgrounds[index].name = value
            case "cantdelete": stackBinding.wrappedValue.backgrounds[index].cantDelete = try boolean(value, for: property)
            case "dontsearch": stackBinding.wrappedValue.backgrounds[index].dontSearch = try boolean(value, for: property)
            default: throw Self.noSuchProperty(property, of: "this background")
            }
        case .thisStack:
            switch property {
            case "name": stackBinding.wrappedValue.name = value
            case "width": stackBinding.wrappedValue.cardSize.width = try number(value, for: property)
            case "height": stackBinding.wrappedValue.cardSize.height = try number(value, for: property)
            case "fullscreen": stackBinding.wrappedValue.isFullScreen = try boolean(value, for: property)
            case "paddingcolor": stackBinding.wrappedValue.paddingColor = value
            default: throw Self.noSuchProperty(property, of: "this stack")
            }
        }
    }

    private func partProperty(_ property: String, of part: Part, kind: String) throws -> String {
        switch property {
        case "name": return part.name
        case "longname": return "\(kind) \"\(part.name)\""
        case "longid": return "\(kind) id \(part.scriptID)"
        case "id": return String(part.scriptID)
        case "visible": return part.isVisible ? "true" : "false"
        case "width": return numberText(part.frame.width)
        case "height": return numberText(part.frame.height)
        case "left": return numberText(part.frame.x)
        case "top": return numberText(part.frame.y)
        case "right": return numberText(part.frame.x + part.frame.width)
        case "bottom": return numberText(part.frame.y + part.frame.height)
        case "rect", "rectangle":
            return [part.frame.x, part.frame.y, part.frame.x + part.frame.width, part.frame.y + part.frame.height]
                .map(numberText).joined(separator: ",")
        case "loc", "location":
            return [part.frame.x + part.frame.width / 2, part.frame.y + part.frame.height / 2]
                .map(numberText).joined(separator: ",")
        case "title":
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.title
        case "showname":
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.showName ? "true" : "false"
        case "autohilite", "autohighlight":
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.autoHilite ? "true" : "false"
        case "style":
            switch part.kind {
            case .button(let properties): return properties.style.rawValue
            case .field(let properties): return properties.style.rawValue
            default: throw Self.noSuchProperty(property, of: kind)
            }
        case "hilite", "highlight":
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.hilite ? "true" : "false"
        case "text":
            switch part.kind {
            case .field(let properties): return properties.text
            case .label(let properties): return properties.text
            default: throw Self.noSuchProperty(property, of: kind)
            }
        case "placeholder":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.placeholder
        case "textfont":
            guard let format = Self.format(of: part) else { throw Self.noSuchProperty(property, of: kind) }
            return format.fontDesign.rawValue
        case "textsize":
            guard let format = Self.format(of: part) else { throw Self.noSuchProperty(property, of: kind) }
            return numberText(format.size)
        case "textstyle":
            guard let format = Self.format(of: part) else { throw Self.noSuchProperty(property, of: kind) }
            return Self.styleList(format)
        case "textalign":
            guard let format = Self.format(of: part) else { throw Self.noSuchProperty(property, of: kind) }
            return format.align.rawValue
        case "locktext":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.lockText ? "true" : "false"
        case "showlines":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.showLines ? "true" : "false"
        case "widemargins":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.wideMargins ? "true" : "false"
        default:
            throw Self.noSuchProperty(property, of: kind)
        }
    }

    private func applyPartProperty(_ property: String, to part: inout Part, kind: String, value: String) throws {
        switch property {
        case "name":
            part.name = value
        case "visible":
            part.isVisible = try boolean(value, for: property)
        case "width": part.frame.width = max(16, try number(value, for: property))
        case "height": part.frame.height = max(16, try number(value, for: property))
        case "left": part.frame.x = try number(value, for: property)
        case "top": part.frame.y = try number(value, for: property)
        case "right": part.frame.x = try number(value, for: property) - part.frame.width
        case "bottom": part.frame.y = try number(value, for: property) - part.frame.height
        case "rect", "rectangle":
            let n = try numberList(value, count: 4, for: property)
            part.frame = PartFrame(x: n[0], y: n[1], width: max(16, n[2] - n[0]), height: max(16, n[3] - n[1]))
        case "loc", "location":
            let n = try numberList(value, count: 2, for: property)
            part.frame.x = n[0] - part.frame.width / 2
            part.frame.y = n[1] - part.frame.height / 2
        case "title":
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            properties.title = value
            part.kind = .button(properties)
        case "showname":
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            properties.showName = try boolean(value, for: property)
            part.kind = .button(properties)
        case "autohilite", "autohighlight":
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            properties.autoHilite = try boolean(value, for: property)
            part.kind = .button(properties)
        case "style":
            switch part.kind {
            case .button(var properties):
                guard let style = ButtonStyleKind.parse(value) else {
                    throw HostError("Unknown button style \"\(value)\". Try roundRect, rectangle, shadow, opaque, transparent, checkbox, or radio.")
                }
                properties.style = style
                part.kind = .button(properties)
            case .field(var properties):
                guard let style = FieldStyle(rawValue: value.lowercased().trimmingCharacters(in: .whitespaces)) else {
                    throw HostError("Unknown field style \"\(value)\". Try transparent, opaque, rectangle, or shadow.")
                }
                properties.style = style
                part.kind = .field(properties)
            default:
                throw Self.noSuchProperty(property, of: kind)
            }
        case "hilite", "highlight":
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            properties.hilite = try boolean(value, for: property)
            part.kind = .button(properties)
        case "text":
            switch part.kind {
            case .field(var properties):
                properties.text = value
                part.kind = .field(properties)
            case .label(var properties):
                properties.text = value
                part.kind = .label(properties)
            default:
                throw Self.noSuchProperty(property, of: kind)
            }
        case "placeholder":
            guard case .field(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            properties.placeholder = value
            part.kind = .field(properties)
        case "textfont":
            try withFieldFormat(&part, kind: kind) { format in
                guard let design = Self.parseFontDesign(value) else {
                    throw HostError("Unknown font \"\(value)\". Try system, serif, monospaced, or rounded.")
                }
                format.fontDesign = design
            }
        case "textsize":
            let size = try number(value, for: property)
            try withFieldFormat(&part, kind: kind) { $0.size = min(max(size, 4), 256) }
        case "textstyle":
            try withFieldFormat(&part, kind: kind) { Self.applyStyleList(value, to: &$0) }
        case "textalign":
            guard let align = TextAlign(rawValue: value.lowercased().trimmingCharacters(in: .whitespaces)) else {
                throw HostError("Unknown alignment \"\(value)\". Try left, center, or right.")
            }
            try withFieldFormat(&part, kind: kind) { $0.align = align }
        case "locktext":
            try withField(&part, kind: kind) { $0.lockText = try boolean(value, for: property) }
        case "showlines":
            try withField(&part, kind: kind) { $0.showLines = try boolean(value, for: property) }
        case "widemargins":
            try withField(&part, kind: kind) { $0.wideMargins = try boolean(value, for: property) }
        default:
            throw Self.noSuchProperty(property, of: kind)
        }
    }

    /// Mutates a field's FieldPart, or throws if the part isn't a field.
    private func withField(_ part: inout Part, kind: String, _ body: (inout FieldPart) throws -> Void) throws {
        guard case .field(var properties) = part.kind else { throw Self.noSuchProperty("field option", of: kind) }
        try body(&properties)
        part.kind = .field(properties)
    }

    /// The text format of a part that has one (fields and buttons), else nil.
    private static func format(of part: Part) -> TextFormat? {
        switch part.kind {
        case .field(let properties): properties.format
        case .button(let properties): properties.format
        default: nil
        }
    }

    /// Mutates the text format of a field or button, or throws otherwise.
    private func withFieldFormat(_ part: inout Part, kind: String, _ body: (inout TextFormat) throws -> Void) throws {
        switch part.kind {
        case .field(var properties):
            try body(&properties.format)
            part.kind = .field(properties)
        case .button(var properties):
            try body(&properties.format)
            part.kind = .button(properties)
        default:
            throw Self.noSuchProperty("text formatting", of: kind)
        }
    }

    /// "plain", or a comma list of bold/italic/underline.
    static func styleList(_ format: TextFormat) -> String {
        var parts: [String] = []
        if format.isBold { parts.append("bold") }
        if format.isItalic { parts.append("italic") }
        if format.isUnderline { parts.append("underline") }
        return parts.isEmpty ? "plain" : parts.joined(separator: ",")
    }

    static func applyStyleList(_ value: String, to format: inout TextFormat) {
        let tokens = value.lowercased().split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        format.isBold = tokens.contains("bold")
        format.isItalic = tokens.contains("italic")
        format.isUnderline = tokens.contains("underline")
    }

    static func parseFontDesign(_ value: String) -> FontDesign? {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespaces)
        return FontDesign.allCases.first { $0.rawValue == normalized || $0.label.lowercased() == normalized }
    }

    private func cardProperty(_ property: String, cardAt index: Int) throws -> String {
        let card = stack.cards[index]
        switch property {
        case "name": return card.name
        case "longname": return "card \"\(card.name)\""
        case "longid": return "card id \(card.scriptID)"
        case "highlightcolor": return card.highlightColor ?? ""
        case "number": return String(index + 1)
        case "id": return String(card.scriptID)
        case "marked": return card.isMarked ? "true" : "false"
        case "cantdelete": return card.cantDelete ? "true" : "false"
        case "dontsearch": return card.dontSearch ? "true" : "false"
        default: throw Self.noSuchProperty(property, of: "a card")
        }
    }

    private func setCardProperty(_ property: String, cardAt index: Int, to value: String) throws {
        func flag() throws -> Bool {
            switch value.lowercased() {
            case "true": return true
            case "false": return false
            default: throw HostError("The \(property) property must be true or false, not \"\(value)\".")
            }
        }
        switch property {
        case "name": stackBinding.wrappedValue.cards[index].name = value
        case "marked": stackBinding.wrappedValue.cards[index].isMarked = try flag()
        case "cantdelete": stackBinding.wrappedValue.cards[index].cantDelete = try flag()
        case "dontsearch": stackBinding.wrappedValue.cards[index].dontSearch = try flag()
        case "highlightcolor":
            // Empty clears it back to the app accent.
            stackBinding.wrappedValue.cards[index].highlightColor = value.isEmpty ? nil : value
        default: throw Self.noSuchProperty(property, of: "a card")
        }
    }

    private func cardIndexFor(_ reference: HyperTalkObject.Reference) throws -> Int {
        switch reference {
        case .number(let number):
            guard (1...stack.cards.count).contains(number) else {
                throw HostError("There is no card \(number) — this stack has \(stack.cards.count) card\(stack.cards.count == 1 ? "" : "s").")
            }
            return number - 1
        case .named(let which):
            guard let index = stack.cards.firstIndex(where: { $0.name.caseInsensitiveCompare(which) == .orderedSame }) else {
                throw HostError("There is no card named \"\(which)\".")
            }
            return index
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            guard let index = stack.cards.firstIndex(where: { String($0.scriptID) == wanted }) else {
                throw HostError("There is no card with id \(id).")
            }
            return index
        }
    }

    private func boolean(_ value: String, for property: String) throws -> Bool {
        switch value.lowercased() {
        case "true": return true
        case "false": return false
        default: throw HostError("The \(property) property must be true or false, not \"\(value)\".")
        }
    }

    private func number(_ value: String, for property: String) throws -> Double {
        guard let number = Double(value.trimmingCharacters(in: .whitespaces)), number.isFinite else {
            throw HostError("The \(property) property needs a number, not \"\(value)\".")
        }
        return number
    }

    /// A comma-separated list of exactly `count` numbers ("10,20,110,70").
    private func numberList(_ value: String, count: Int, for property: String) throws -> [Double] {
        let numbers = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == count, numbers.allSatisfy(\.isFinite) else {
            throw HostError("The \(property) property needs \(count) numbers separated by commas, not \"\(value)\".")
        }
        return numbers
    }

    private func numberText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func noSuchProperty(_ property: String, of what: String) -> HostError {
        HostError("There is no property \"\(property)\" of \(what == "this stack" || what == "this card" || what == "this background" || what == "a card" ? what : "a \(what)").")
    }

    // MARK: - Part lookup

    /// Card parts win over background parts, matching HyperCard's layering.
    private enum FieldLocation {
        case card(partIndex: Int)
        case background(backgroundIndex: Int, partIndex: Int)
    }

    /// Finds a part of the given kind by name, ordinal, or permanent ID.
    /// Unqualified references search card parts first, then the
    /// background's; `card`/`background` qualifiers restrict the layer.
    private func locatePart(kind: String, domain: HyperTalkObject.PartDomain, reference: HyperTalkObject.Reference) throws -> FieldLocation {
        let card = stack.cards[cardIndex]
        let backgroundIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID })
        func onCard() -> FieldLocation? {
            index(ofKind: kind, matching: reference, in: card.parts).map { .card(partIndex: $0) }
        }
        func onBackground() -> FieldLocation? {
            guard let backgroundIndex,
                  let partIndex = index(ofKind: kind, matching: reference, in: stack.backgrounds[backgroundIndex].parts) else { return nil }
            return .background(backgroundIndex: backgroundIndex, partIndex: partIndex)
        }
        // Honor the requested layer, then fall back to the other: importing
        // moves buttons to the background and fields to the card, so a
        // `background field` / `card button` may live on the opposite layer.
        if domain != .background, let found = onCard() { return found }
        if domain != .card, let found = onBackground() { return found }
        if let found = onCard() ?? onBackground() { return found }
        let where_ = switch domain {
        case .any: "on this card"
        case .card: "on this card (card layer)"
        case .background: "on this background"
        }
        switch reference {
        case .named(let name):
            throw HostError("There is no \(kind) named \"\(name)\" \(where_).")
        case .number(let number):
            throw HostError("There is no \(kind) \(number) \(where_).")
        case .id(let id):
            throw HostError("There is no \(kind) with id \(id) \(where_).")
        }
    }

    private func index(ofKind kind: String, matching reference: HyperTalkObject.Reference, in parts: [Part]) -> Int? {
        switch reference {
        case .named(let name):
            return parts.firstIndex { part in
                part.kind.word == kind && part.name.caseInsensitiveCompare(name) == .orderedSame
            }
        case .number(let number):
            // Ordinal among parts of this kind, in part (z) order.
            guard number >= 1 else { return nil }
            var seen = 0
            for (index, part) in parts.enumerated() where part.kind.word == kind {
                seen += 1
                if seen == number { return index }
            }
            return nil
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            return parts.firstIndex { part in
                part.kind.word == kind && String(part.scriptID) == wanted
            }
        }
    }

    /// A part's ordinal among its kind within its owning layer.
    private func ordinal(of location: FieldLocation, kind: String) -> Int {
        let parts: [Part]
        let partIndex: Int
        switch location {
        case .card(let index):
            parts = stack.cards[cardIndex].parts
            partIndex = index
        case .background(let backgroundIndex, let index):
            parts = stack.backgrounds[backgroundIndex].parts
            partIndex = index
        }
        var seen = 0
        for (index, part) in parts.enumerated() where part.kind.word == kind {
            seen += 1
            if index == partIndex { return seen }
        }
        return seen
    }

    private func setPart(_ part: Part, at location: FieldLocation) {
        switch location {
        case .card(let partIndex):
            stackBinding.wrappedValue.cards[cardIndex].parts[partIndex] = part
        case .background(let backgroundIndex, let partIndex):
            stackBinding.wrappedValue.backgrounds[backgroundIndex].parts[partIndex] = part
        }
    }

    private func part(at location: FieldLocation) -> Part {
        switch location {
        case .card(let partIndex):
            stack.cards[cardIndex].parts[partIndex]
        case .background(let backgroundIndex, let partIndex):
            stack.backgrounds[backgroundIndex].parts[partIndex]
        }
    }

    private func setKind(_ kind: PartKind, at location: FieldLocation) {
        switch location {
        case .card(let partIndex):
            stackBinding.wrappedValue.cards[cardIndex].parts[partIndex].kind = kind
        case .background(let backgroundIndex, let partIndex):
            stackBinding.wrappedValue.backgrounds[backgroundIndex].parts[partIndex].kind = kind
        }
    }
}
