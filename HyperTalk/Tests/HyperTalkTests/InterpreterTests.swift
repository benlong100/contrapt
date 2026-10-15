//
//  InterpreterTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

/// A host that records everything scripts do to it.
struct Drag: Equatable {
    var fromX: Int, fromY: Int, toX: Int, toY: Int
}

final class MockHost: HyperTalkHost {
    var fields: [String: String]
    var destinations: [GoDestination] = []
    var messages: [String] = []

    init(fields: [String: String] = [:]) {
        self.fields = Dictionary(uniqueKeysWithValues: fields.map { ($0.key.lowercased(), $0.value) })
    }

    /// The effects passed with each `go`, in order.
    var goEffects: [[ScreenEffect]] = []

    /// Every setScreenLocked call, in order — a dispatch that locks must end
    /// with the interpreter's end-of-dispatch unlock (false last).
    var screenLockHistory: [Bool] = []

    /// Scripted-paint drags, in order.
    var drags: [Drag] = []

    // MARK: HTTP (for url-container tests)

    /// Canned responses keyed by "METHOD URL"; falls back to `httpDefault`.
    var httpResponses: [String: (body: String, status: Int, headers: [String: String], error: String?)] = [:]
    var httpDefault: (body: String, status: Int, headers: [String: String], error: String?) = ("", 200, [:], nil)
    /// Every request made, in order, with the headers and timeout it carried.
    var httpRequests: [(method: String, url: String, body: String?, headers: [String: String], timeout: Double)] = []

    func httpRequest(method: String, url: String, body: String?, headers: [String: String], timeout: Double) async -> (body: String, status: Int, headers: [String: String], error: String?) {
        httpRequests.append((method, url, body, headers, timeout))
        return httpResponses["\(method) \(url)"] ?? httpDefault
    }

    // MARK: Persistent store (for stackData tests)

    /// Every scheduled send (`send … in <time>`), in order — the resolved
    /// message, baked arguments, target, and delay in seconds.
    var scheduledSends: [(message: String, arguments: [String], target: HyperTalkObject, afterSeconds: Double)] = []
    func scheduleSend(_ message: String, arguments: [String], to target: HyperTalkObject, afterSeconds: Double) throws {
        scheduledSends.append((message, arguments, target, afterSeconds))
    }

    /// Canned AI reply + optional error for `ask … with ai`; records prompts.
    var aiReply = ""
    var aiError: String? = nil
    var aiPrompts: [String] = []
    func aiRespond(prompt: String) async -> (reply: String, error: String?) {
        aiPrompts.append(prompt)
        return (aiReply, aiError)
    }

    /// The stack's persistent store (`stackData`). Retained on the instance so a
    /// value written in one run is readable from the next, as a real backing
    /// store would survive between runs.
    var persistentStore = ""
    func persistentData() -> String { persistentStore }
    func setPersistentData(_ encoded: String) { persistentStore = encoded }

    func drag(fromX: Int, fromY: Int, toX: Int, toY: Int) {
        drags.append(Drag(fromX: fromX, fromY: fromY, toX: toX, toY: toY))
    }

    func setScreenLocked(_ locked: Bool) {
        screenLockHistory.append(locked)
    }

    func goToCard(_ destination: GoDestination, effects: [ScreenEffect]) async throws {
        destinations.append(destination)
        goEffects.append(effects)
    }

    /// Content lookups key the dictionary by the reference text, prefixed
    /// with the domain when qualified — e.g. "name", "1", "background 1",
    /// "id 6". Tests preset whichever keys they use.
    private func fieldKey(_ reference: HyperTalkObject.Reference, _ domain: HyperTalkObject.PartDomain) -> String {
        (domainText(domain) + referenceText(reference)).lowercased()
    }

    /// The `onCard` of the last field access, for `field … of <card>` tests.
    var lastFieldCard: GoDestination?

    func fieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, onCard: GoDestination?) throws -> String {
        // While sorting, every field read yields the current card's sort key.
        if let sortContext, sortContext < sortKeys.count { return sortKeys[sortContext] }
        lastFieldCard = onCard
        let key = (cardPrefix(onCard) + fieldKey(reference, domain))
        guard let text = fields[key] else {
            throw HostError("There is no field \(referenceText(reference)) here.")
        }
        return text
    }

    func setFieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, onCard: GoDestination?, to text: String) throws {
        lastFieldCard = onCard
        let key = (cardPrefix(onCard) + fieldKey(reference, domain))
        guard fields[key] != nil else {
            throw HostError("There is no field \(referenceText(reference)) here.")
        }
        fields[key] = text
    }

    /// A key prefix identifying `field … of <card>` in the flat `fields` dict.
    private func cardPrefix(_ onCard: GoDestination?) -> String {
        switch onCard {
        case nil: return ""
        case .previous: return "prev card."
        case .next: return "next card."
        case .first: return "first card."
        case .last: return "last card."
        case .number(let n): return "card \(n)."
        case .named(let s): return "card \(s).".lowercased()
        case .id(let i): return "id \(i)."
        case .inBackground(let inner, let bg): return cardPrefix(inner) + (bg?.lowercased() ?? "this bg") + "."
        case .markedCard(let n): return "marked card \(n)."
        default: return "other."
        }
    }

    func showMessage(_ text: String) {
        messages.append(text)
    }

    var beeps = 0

    func beep() {
        beeps += 1
    }

    /// `select` calls, in order; `selectionCleared` records `select empty`.
    var selections: [(reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, start: Int, end: Int)] = []
    var selectionCleared = false
    var selectionValues: [SelectionComponent: String] = [:]

    func setSelection(field reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, start: Int, end: Int) throws {
        selections.append((reference, domain, start, end))
    }

    func clearSelection() { selectionCleared = true }

    func selectionValue(_ component: SelectionComponent) -> String {
        selectionValues[component] ?? ""
    }

    /// Preset `the clickLine` / `the clickText` values for tests.
    var clickValues: [ClickField: String] = [:]

    func clickValue(_ field: ClickField) -> String {
        clickValues[field] ?? ""
    }

    /// Simulated XCMD/XFCN names (store lowercased), as an import records them.
    var externalNames: Set<String> = []

    func isExternalName(_ name: String) -> Bool {
        externalNames.contains(name.lowercased())
    }

    /// Properties keyed by a readable path like "button OK.width".
    var properties: [String: String] = [:]

    private func referenceText(_ reference: HyperTalkObject.Reference) -> String {
        switch reference {
        case .named(let name): name
        case .number(let number): String(number)
        case .id(let id): "id \(id)"
        }
    }

    /// A readable key for a card *object* (now a `GoDestination`): `card 2`,
    /// `card id 12`, `card About`, `card About of bg Content`. Matches the old
    /// `card <referenceText>` format for the number/named/id cases tests use.
    private func cardDestinationText(_ destination: GoDestination) -> String {
        switch destination {
        case .number(let n): return "card \(n)"
        case .named(let s): return "card \(s)"
        case .id(let i): return "card id \(i)"
        case .first: return "first card"
        case .last: return "last card"
        case .next: return "next card"
        case .previous: return "prev card"
        case .inBackground(let inner, let bg):
            return "\(cardDestinationText(inner)) of \(bg.map { "bg \($0)" } ?? "this bg")"
        case .markedCard(let n): return "marked card \(n)"
        default: return "card"
        }
    }

    private func domainText(_ domain: HyperTalkObject.PartDomain) -> String {
        switch domain {
        case .any: ""
        case .card: "card "
        case .background: "background "
        }
    }

    private func propertyKey(_ property: String, _ object: HyperTalkObject) -> String {
        switch object {
        case .part(let kind, let domain, let reference, let onCard):
            // Reuses the field-scope prefix: `cd btn id 8 of cd "Stack Menus"`
            // keys as "card stack menus.card button id 8.<property>".
            "\(cardPrefix(onCard))\(domainText(domain))\(kind) \(referenceText(reference)).\(property)"
        case .card(let destination): "\(cardDestinationText(destination)).\(property)"
        case .thisCard: "this card.\(property)"
        case .thisBackground: "this background.\(property)"
        case .thisStack: "this stack.\(property)"
        }
    }

    func propertyValue(_ property: String, of object: HyperTalkObject) throws -> String {
        guard let value = properties[propertyKey(property, object)] else {
            throw HostError("There is no property \"\(property)\" here.")
        }
        return value
    }

    func setProperty(_ property: String, of object: HyperTalkObject, to value: String) throws {
        properties[propertyKey(property, object)] = value
    }

    var globals: [String: String] = [:]

    func globalValue(_ name: String) -> String? {
        globals[name]
    }

    func setGlobalValue(_ name: String, to value: String) {
        globals[name] = value
    }

    /// A fixed clock so date/time tests are deterministic.
    func clock(_ field: ClockField) -> String {
        switch field {
        case .shortDate: "1/2/34"
        case .longDate: "Monday, January 2, 2034"
        case .abbreviatedDate: "Mon, Jan 2, 2034"
        case .shortTime: "3:45 PM"
        case .longTime: "3:45:07 PM"
        case .seconds: "2019686400"
        case .ticks: "121181184000"
        }
    }

    /// A deterministic `convert`: a UTC calendar and fixed patterns so tests
    /// don't depend on the machine's locale or time zone.
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func convert(_ value: String, from: [ConvertFormat], to: [ConvertFormat]) throws -> String {
        let date = try convertParse(value, from: from)
        return try convertFormat(date, to: to)
    }

    /// Scripted dialog responses for tests. `answerChoice` is the button
    /// `answer` returns (defaults to the first); `askResponse` is what `ask`
    /// returns (nil = the user cancelled). Both record their prompts.
    var answerChoice: String?
    var askResponse: String? = ""
    var answerPrompts: [String] = []
    var answerButtons: [[String]] = []
    var askPrompts: [String] = []

    func answer(_ prompt: String, buttons: [String]) async -> String {
        answerPrompts.append(prompt)
        answerButtons.append(buttons)
        return answerChoice ?? buttons.first ?? "OK"
    }

    func ask(_ prompt: String, initialAnswer: String) async -> String? {
        askPrompts.append(prompt)
        return askResponse
    }

    /// The path `answer file` returns (nil = the user cancelled, the default).
    var answerFileResponse: String?
    var answerFilePrompts: [String] = []
    var answerFileTypes: [String?] = []

    // Scripted custom menus (the host stores the bar; semantics live in the
    // interpreter).
    var menus: [HyperTalkMenu] = []
    func menuBarSnapshot() -> [HyperTalkMenu] { menus }
    func updateMenuBar(_ menus: [HyperTalkMenu]) { self.menus = menus }

    // In-memory file system for `open/read/write/close file` tests.
    var diskFiles: [String: String] = [:]
    var openFiles: [String: Int] = [:] // path -> read/write mark

    func fileOpen(_ path: String) throws {
        if diskFiles[path] == nil { diskFiles[path] = "" } // open creates, as in HC
        openFiles[path] = 0
    }

    func fileClose(_ path: String) throws {
        guard openFiles.removeValue(forKey: path) != nil else { throw HostError("File not open.") }
    }

    func fileRead(_ path: String, until delimiter: String?, count: Int?, at position: Int?) throws -> (text: String, atEOF: Bool) {
        guard var mark = openFiles[path], let content = diskFiles[path] else { throw HostError("File not open.") }
        if let position { mark = max(0, position - 1); openFiles[path] = mark }  // 1-based seek
        let characters = Array(content)
        guard mark < characters.count else { return ("", true) }
        var end = characters.count
        if let count { end = min(characters.count, mark + max(0, count)) }
        else if let delimiter, let d = delimiter.first {
            if let found = characters[mark...].firstIndex(of: d) { end = found + 1 }
        }
        openFiles[path] = end
        return (String(characters[mark..<end]), end >= characters.count)
    }

    func fileWrite(_ path: String, text: String, at position: FileWritePosition) throws {
        guard let mark = openFiles[path], let content = diskFiles[path] else { throw HostError("File not open.") }
        var characters = Array(content)
        let start: Int
        switch position {
        case .mark: start = mark
        case .eof: start = characters.count
        case .offset(let n): start = max(0, n - 1) // 1-based, as in HC
        }
        let incoming = Array(text)
        if start >= characters.count {
            characters.append(contentsOf: Array(repeating: " ", count: start - characters.count))
            characters.append(contentsOf: incoming)
        } else {
            // Overwrite in place (HC writes at the mark without inserting),
            // keeping any tail beyond the written span.
            let overwriteEnd = min(characters.count, start + incoming.count)
            characters.replaceSubrange(start..<overwriteEnd, with: incoming)
            if start + incoming.count > overwriteEnd {
                characters.append(contentsOf: incoming[(overwriteEnd - start)...])
            }
        }
        diskFiles[path] = String(characters)
        openFiles[path] = start + incoming.count
    }

    func answerFile(_ prompt: String, type: String?) async -> String? {
        answerFilePrompts.append(prompt)
        answerFileTypes.append(type)
        return answerFileResponse
    }

    /// Seconds requested by each `wait`; instant so tests don't actually pause.
    var waits: [Double] = []

    func wait(seconds: Double) async {
        waits.append(seconds)
    }

    /// How many `the mouse` reads report "down" before the button counts as
    /// released; 0 (the default) reads as up from the start.
    var mouseDownPolls = 0

    func mouseIsDown() -> Bool {
        guard mouseDownPolls > 0 else { return false }
        mouseDownPolls -= 1
        return true
    }

    /// How many `the mouseClick` reads report "no click yet" before a click
    /// lands; after that many false reads, the next read is true (once). The
    /// default never clicks, so `repeat until the mouseClick` would spin — only
    /// set it in tests that exercise the click-wait.
    var mouseClickPolls = 0
    private var mouseClicked = false

    func consumeMouseClick() -> Bool {
        if mouseClickPolls > 0 { mouseClickPolls -= 1; return false }
        if mouseClicked { return false }
        mouseClicked = true
        return true
    }

    /// Scripts for off-path `send … to <object>` targets, keyed like
    /// properties ("button OK", "card 2"). The returned path is just the
    /// object's own layer — enough to prove dispatch reached it.
    var objectScripts: [String: String] = [:]

    func scriptLayers(for object: HyperTalkObject) -> [ScriptLayer]? {
        let key: String
        switch object {
        case .part(let kind, _, let reference, _): key = "\(kind) \(referenceText(reference))"
        case .card(let destination): key = cardDestinationText(destination)
        default: return nil
        }
        guard let source = objectScripts[key] else { return nil }
        return [ScriptLayer(name: "\(key) script", source: source, object: object)]
    }

    /// Tools chosen by `choose <name> tool`, and the name `the tool` reads.
    var chosenTools: [String] = []
    var toolName = "browse tool"

    func chooseTool(_ name: String) { chosenTools.append(name) }
    func currentToolName() -> String { toolName }

    /// Pointer positions served to `the mouseLoc` polls, consumed in order
    /// (the last repeats) — a scripted drag path. Nil (default) reads 0,0.
    var mousePath: [(x: Int, y: Int)] = []

    func mouseLocation() -> (x: Int, y: Int)? {
        guard !mousePath.isEmpty else { return nil }
        return mousePath.count > 1 ? mousePath.removeFirst() : mousePath[0]
    }

    /// `play` calls, `play stop` count, and the canned `the sound` reading.
    var played: [(voice: String, tempo: Double, notes: [PlayNote])] = []
    var playStops = 0
    var playingName = "done"

    func play(voice: String, tempo: Double, notes: [PlayNote]) {
        played.append((voice, tempo, notes))
    }

    func stopPlay() { playStops += 1 }
    func playingSoundName() -> String { playingName }

    /// Records each `find`, and matches (via FindMatcher) against the field
    /// values it holds — enough to exercise the interpreter's result and
    /// found* wiring. The real cross-card search lives in the app's host.
    var findCalls: [(text: String, mode: FindMode, inField: HyperTalkObject.Reference?)] = []
    var foundValues: [FoundField: String] = [:]

    func find(_ text: String, mode: FindMode, inField: HyperTalkObject.Reference?, fieldDomain: HyperTalkObject.PartDomain) throws -> Bool {
        findCalls.append((text, mode, inField))
        let candidates: [String]
        if let inField {
            guard let text = fields[fieldKey(inField, fieldDomain)] else {
                throw HostError("There is no field \(inField) to search.")
            }
            candidates = [text]
        } else {
            candidates = Array(fields.values)
        }
        for value in candidates {
            if let range = FindMatcher.firstRange(in: value, query: text, mode: mode) {
                foundValues = [
                    .text: String(Array(value)[range]),
                    .chunk: "char \(range.lowerBound + 1) to \(range.upperBound) of field",
                    .line: "line 1 of field",
                    .field: "field",
                ]
                return true
            }
        }
        return false
    }

    func foundValue(_ field: FoundField) -> String { foundValues[field] ?? "" }

    /// A simple card back-stack for push/pop tests.
    var cardStack: [String] = []
    var currentCardID = "1"
    func pushCard() { cardStack.append(currentCardID) }
    func popCard() -> String? { cardStack.isEmpty ? nil : cardStack.removeLast() }

    /// Counts for `the number of …`. Fields default to `fields.count`.
    var cardCount = 1
    var backgroundCount = 1
    var buttonCount = 0
    /// Scoped card counts for `number of cds in this bg` tests, keyed by
    /// "this" / a bg name / "#N" / "id N". Falls back to cardCount.
    var backgroundCardCounts: [String: Int] = [:]
    /// `the number of marked cards`.
    var markedCardCount = 0

    func count(_ countable: Countable) throws -> Int {
        switch countable {
        case .cards(let scope):
            if let scope {
                let key: String
                switch scope {
                case .current: key = "this"
                case .reference(.named(let n)): key = n
                case .reference(.number(let n)): key = "#\(n)"
                case .reference(.id(let i)): key = "id \(i)"
                }
                return backgroundCardCounts[key] ?? cardCount
            }
            return sortKeys.isEmpty ? cardCount : sortKeys.count
        case .backgrounds: return backgroundCount
        case .markedCards: return markedCardCount
        case .parts(let kind, _):
            if kind == "part" { return fields.count + buttonCount }
            return kind == "field" ? fields.count : buttonCount
        }
    }

    /// `sort` support: one key value per card; during sort any field read
    /// returns the current card's key, so `sort by field "X"` uses these.
    var sortKeys: [String] = []
    var sortContext: Int?
    var reorderedTo: [Int]?
    func setSortContext(_ cardIndex: Int?) { sortContext = cardIndex }
    func reorderCards(_ order: [Int]) throws { reorderedTo = order }

    /// `mark`/`unmark` — card numbers currently marked (1-based; `nil` card
    /// means the current card, recorded as 1).
    var markedCardNumbers: Set<Int> = []
    func setMarked(_ marked: Bool, card: GoDestination?) throws {
        let n: Int = { if case .number(let x) = card { return x } else { return 1 } }()
        if marked { markedCardNumbers.insert(n) } else { markedCardNumbers.remove(n) }
    }

    /// `start using stack` support: a test library of stack name → full script,
    /// and the names currently in use (most-recently-added first).
    var stackLibrary: [String: String] = [:]
    private(set) var inUseStackNames: [String] = []
    func beginUsingStack(_ name: String) {
        inUseStackNames.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        inUseStackNames.insert(name, at: 0)
    }
    func endUsingStack(_ name: String) {
        inUseStackNames.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
    func inUseStackScripts() -> [(name: String, source: String)] {
        inUseStackNames.compactMap { name in
            stackLibrary.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }
                .map { (name, $0.value) }
        }
    }

    /// `doMenu` built-in actions performed (untrapped items).
    var performedMenu: [String] = []
    func performMenu(_ item: String) throws { performedMenu.append(item) }

    /// The last `click at` coordinates.
    var clickedAt: (x: Int, y: Int)?
    func click(x: Int, y: Int) { clickedAt = (x, y) }

    /// A field exists if it's in `fields`; any other part/card exists if a
    /// property was preset for it. `this …` objects always exist.
    func exists(_ object: HyperTalkObject) -> Bool {
        switch object {
        case .part(let kind, let domain, let reference, let onCard):
            if kind == "field", fields[fieldKey(reference, domain)] != nil { return true }
            let prefix = "\(cardPrefix(onCard))\(domainText(domain))\(kind) \(referenceText(reference))."
            return properties.keys.contains { $0.hasPrefix(prefix) }
        case .card(let destination):
            return properties.keys.contains { $0.hasPrefix("\(cardDestinationText(destination)).") }
        case .thisCard, .thisBackground, .thisStack:
            return true
        }
    }

    private func patterns(_ format: ConvertFormat) -> String? {
        switch format {
        case .shortDate: "M/d/yy"
        case .longDate: "EEEE, MMMM d, yyyy"
        case .abbreviatedDate: "EEE, MMM d, yyyy"
        case .shortTime: "h:mm a"
        case .longTime: "h:mm:ss a"
        case .seconds, .dateItems: nil
        }
    }

    private func formatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.timeZone = utcCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.twoDigitStartDate = HyperCardDate.centuryStart // HC century pivot
        formatter.dateFormat = pattern
        return formatter
    }

    /// A fixed "now" matching `clock(.seconds)`, so convert's fill-from-current
    /// behavior is deterministic in tests.
    private var referenceNow: Date { Date(timeIntervalSince1970: 2019686400) }

    private func convertParse(_ value: String, from: [ConvertFormat]) throws -> Date {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        // Empty converts as "now" (HyperCard fills omitted components from the
        // current date/time) — mirrors the app and web hosts.
        if trimmed.isEmpty { return referenceNow }
        let effective: [ConvertFormat]
        if !from.isEmpty {
            effective = from
        } else if let seconds = Double(trimmed) {
            return HyperCardDate.date(fromSeconds: seconds, calendar: utcCalendar) // 1904 epoch, UTC-consistent
        } else if trimmed.contains(",") {
            effective = [.dateItems]
        } else {
            // Try the pattern combinations until one reads the value.
            let candidates: [[ConvertFormat]] = [
                [.shortDate, .shortTime], [.longDate, .longTime],
                [.longDate], [.abbreviatedDate], [.shortDate],
                [.longTime], [.shortTime],
            ]
            for candidate in candidates {
                let pattern = candidate.compactMap(patterns).joined(separator: " ")
                if let date = formatter(pattern).date(from: trimmed) { return date }
            }
            throw HostError("Can't read \"\(value)\" as a date or time.")
        }

        if effective == [.seconds] {
            guard let seconds = Double(trimmed) else { throw HostError("Can't read \"\(value)\" as seconds.") }
            return HyperCardDate.date(fromSeconds: seconds, calendar: utcCalendar) // 1904 epoch, UTC-consistent
        }
        if effective == [.dateItems] {
            // Missing/empty components inherit from the current date/time.
            let now = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: referenceNow)
            let raw = trimmed.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            func part(_ index: Int, _ fallback: Int) -> Int {
                guard index < raw.count, !raw[index].isEmpty, let n = Int(raw[index]) else { return fallback }
                return n
            }
            var components = DateComponents()
            components.year = part(0, now.year!); components.month = part(1, now.month!); components.day = part(2, now.day!)
            components.hour = part(3, now.hour!); components.minute = part(4, now.minute!); components.second = part(5, now.second!)
            guard let date = utcCalendar.date(from: components) else { throw HostError("Bad dateItems.") }
            return date
        }
        let pattern = effective.compactMap(patterns).joined(separator: " ")
        guard let date = formatter(pattern).date(from: trimmed) else {
            throw HostError("Can't read \"\(value)\" as a date or time.")
        }
        return date
    }

    private func convertFormat(_ date: Date, to: [ConvertFormat]) throws -> String {
        if to == [.seconds] { return String(HyperCardDate.seconds(of: date, calendar: utcCalendar)) } // 1904 epoch, UTC-consistent
        if to == [.dateItems] {
            let c = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
            return [c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, c.weekday!].map(String.init).joined(separator: ",")
        }
        let pattern = to.compactMap(patterns).joined(separator: " ")
        guard !pattern.isEmpty else { throw HostError("Can't convert to that format.") }
        return formatter(pattern).string(from: date)
    }
}

@discardableResult
func run(_ script: String, handler: String = "mouseUp", host: MockHost = MockHost(), maxSteps: Int = 100_000) async throws -> MockHost {
    _ = try await HyperTalk.run(handler: handler, in: script, host: host, maxSteps: maxSteps)
    return host
}

// MARK: - Commands

@Test func unsetGlobalIsFalseInCondition() async throws {
    // A declared-but-never-set global is empty; `if it then` must take the
    // else branch rather than erroring (classic-stack flag idiom).
    let host = try await run("""
    on mouseUp
      global dragonFly
      if dragonFly then
        put "yes" into field "out"
      else
        put "no" into field "out"
      end if
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "no")
}

@Test func goToNextCard() async throws {
    let host = try await run("""
    on mouseUp
      go to next card
    end mouseUp
    """)
    #expect(host.destinations == [.next])
}

@Test func goVariants() async throws {
    let host = try await run("""
    on mouseUp
      go to previous card
      go first card
      go to the last card
      go to card 3
      go to card "Home"
      go to card (1 + 1)
    end mouseUp
    """)
    #expect(host.destinations == [.previous, .first, .last, .number(3), .named("Home"), .number(2)])
}

@Test func putIntoField() async throws {
    let host = try await run("""
    on mouseUp
      put "Hello" into field "Greeting"
    end mouseUp
    """, host: MockHost(fields: ["Greeting": ""]))
    #expect(host.fields["greeting"] == "Hello")
}

@Test func putAfterAndBefore() async throws {
    let host = try await run("""
    on mouseUp
      put "world" into field "f"
      put "hello " before field "f"
      put "!" after field "f"
    end mouseUp
    """, host: MockHost(fields: ["f": ""]))
    #expect(host.fields["f"] == "hello world!")
}

@Test func putWithoutContainerGoesToMessageBox() async throws {
    let host = try await run("""
    on mouseUp
      put "Hi there"
    end mouseUp
    """)
    #expect(host.messages == ["Hi there"])
}

@Test func variablesFlowThroughPut() async throws {
    let host = try await run("""
    on mouseUp
      put 6 * 7 into answer
      put answer into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "42")
}

// MARK: - Expressions

@Test func arithmeticPrecedence() async throws {
    let host = try await run("""
    on mouseUp
      put 2 + 3 * 4 into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "14")
}

@Test func parenthesesAndUnaryMinus() async throws {
    let host = try await run("""
    on mouseUp
      put -(2 + 3) * 4 into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "-20")
}

@Test func divisionFormatsNumbersCleanly() async throws {
    let host = try await run("""
    on mouseUp
      put 10 / 4 into field "a"
      put 8 / 4 into field "b"
      put 10 div 3 into field "c"
      put 10 mod 3 into field "d"
    end mouseUp
    """, host: MockHost(fields: ["a": "", "b": "", "c": "", "d": ""]))
    #expect(host.fields["a"] == "2.5")
    #expect(host.fields["b"] == "2")
    #expect(host.fields["c"] == "3")
    #expect(host.fields["d"] == "1")
}

@Test func concatenationOperators() async throws {
    let host = try await run("""
    on mouseUp
      put "Hello" && "World" into field "a"
      put "Hyper" & "Talk" into field "b"
    end mouseUp
    """, host: MockHost(fields: ["a": "", "b": ""]))
    #expect(host.fields["a"] == "Hello World")
    #expect(host.fields["b"] == "HyperTalk")
}

@Test func comparisonsAreNumericWhenBothSidesAreNumbers() async throws {
    let host = try await run("""
    on mouseUp
      if "10" > "9" then put "numeric" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "numeric")
}

@Test func stringComparisonIsCaseInsensitive() async throws {
    let host = try await run("""
    on mouseUp
      if "Apple" = "APPLE" then put "same" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "same")
}

@Test func isAndIsNotAndContains() async throws {
    let host = try await run("""
    on mouseUp
      if "abc" is "abc" then put "1" after field "out"
      if "abc" is not "xyz" then put "2" after field "out"
      if "HyperCard" contains "card" then put "3" after field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "123")
}

@Test func booleanOperators() async throws {
    let host = try await run("""
    on mouseUp
      if 1 < 2 and not (3 < 2) then put "yes" into field "out"
      if 1 > 2 or 2 > 1 then put "!" after field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "yes!")
}

@Test func unassignedVariableEvaluatesToItsOwnName() async throws {
    let host = try await run("""
    on mouseUp
      put greetings into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "greetings")
}

@Test func builtInConstants() async throws {
    let host = try await run("""
    on mouseUp
      put empty into field "out"
      put "a" & space & "b" & quote after field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": "junk"]))
    #expect(host.fields["out"] == "a b\"")
}

@Test func fieldNamesCanBeComputed() async throws {
    let host = try await run("""
    on mouseUp
      put 2 into n
      put "hi" into field ("out" & n)
    end mouseUp
    """, host: MockHost(fields: ["out2": ""]))
    #expect(host.fields["out2"] == "hi")
}

// MARK: - Control flow

@Test func ifElseBlocks() async throws {
    let host = try await run("""
    on mouseUp
      if 1 > 2 then
        put "then" into field "out"
      else
        put "else" into field "out"
      end if
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "else")
}

@Test func elseIfChain() async throws {
    let host = try await run("""
    on mouseUp
      put 2 into x
      if x = 1 then
        put "one" into field "out"
      else if x = 2 then
        put "two" into field "out"
      else
        put "many" into field "out"
      end if
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "two")
}

@Test func singleLineIfWithElseLine() async throws {
    let host = try await run("""
    on mouseUp
      if 5 > 3 then put "big" into field "out"
      else put "small" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "big")
}

@Test func blockThenWithInlineElseLetsOuterIfOwnTheEndIf() async throws {
    // Apple's Home stack newLink nests a block-then + inline-else inside an
    // outer block-if that owns the sole `end if`. The inline `else` closes the
    // inner if; `end if` closes the outer.
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      put "File" into fileType
      if fileType is "File" then
        put "checking" into field "out"
        if it is "Document" then
          put "Document" into field "out"
        else put "Application" into field "out"
      end if
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "Application")
}

@Test func repeatWithCounter() async throws {
    let host = try await run("""
    on mouseUp
      repeat with i = 1 to 5
        put i after field "out"
      end repeat
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "12345")
}

@Test func repeatDownTo() async throws {
    let host = try await run("""
    on mouseUp
      repeat with i = 3 down to 1
        put i after field "out"
      end repeat
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "321")
}

@Test func repeatTimes() async throws {
    let host = try await run("""
    on mouseUp
      repeat 4 times
        put "x" after field "out"
      end repeat
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "xxxx")
}

@Test func repeatWhileAndUntil() async throws {
    let host = try await run("""
    on mouseUp
      put 0 into n
      repeat while n < 3
        put n + 1 into n
      end repeat
      put n into field "a"
      repeat until n = 6
        put n + 1 into n
      end repeat
      put n into field "b"
    end mouseUp
    """, host: MockHost(fields: ["a": "", "b": ""]))
    #expect(host.fields["a"] == "3")
    #expect(host.fields["b"] == "6")
}

@Test func exitRepeatAndNextRepeat() async throws {
    let host = try await run("""
    on mouseUp
      repeat with i = 1 to 10
        if i = 3 then next repeat
        if i = 6 then exit repeat
        put i after field "out"
      end repeat
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "1245")
}

@Test func exitHandlerStopsExecution() async throws {
    let host = try await run("""
    on mouseUp
      put "before" into field "out"
      exit mouseUp
      put "after" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "before")
}

@Test func nestedRepeatsRespectExit() async throws {
    let host = try await run("""
    on mouseUp
      repeat with i = 1 to 3
        repeat forever
          exit repeat
        end repeat
        put i after field "out"
      end repeat
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "123")
}

// MARK: - Handlers and dispatch

@Test func onlyTheNamedHandlerRuns() async throws {
    let host = try await run("""
    on openCard
      put "opened" into field "out"
    end openCard

    on mouseUp
      put "clicked" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "clicked")
}

@Test func missingHandlerReturnsFalse() async throws {
    let handled = try await HyperTalk.run(handler: "mouseUp", in: """
    on openCard
      go to next card
    end openCard
    """, host: MockHost())
    #expect(handled == false)
}

@Test func caseInsensitivity() async throws {
    let host = try await run("""
    ON MOUSEUP
      PUT "Loud" INTO FIELD "out"
      GO TO NEXT CARD
    END MOUSEUP
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "Loud")
    #expect(host.destinations == [.next])
}

@Test func commentsAreIgnored() async throws {
    let host = try await run("""
    on mouseUp -- runs on tap
      -- a full-line comment
      put "ok" into field "out" -- trailing comment
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "ok")
}

// MARK: - Errors

@Test func runawayLoopIsStopped() async throws {
    await #expect(throws: ScriptError.self) {
        try await run("""
        on mouseUp
          repeat forever
            put 1 into x
          end repeat
        end mouseUp
        """, maxSteps: 100)
    }
}

@Test func unknownCommandReportsLine() async throws {
    do {
        try await run("""
        on mouseUp
          put 1 into x
          launch the missiles
        end mouseUp
        """)
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.line == 3)
        #expect(error.message.contains("launch"))
    }
}

@Test func missingEndRepeatReportsBlockLine() async throws {
    do {
        try await run("""
        on mouseUp
          repeat 3 times
            put 1 into x
        end mouseUp
        """)
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.line == 2)
        #expect(error.message.contains("end repeat"))
    }
}

@Test func unknownFieldSurfacesHostErrorWithLine() async throws {
    do {
        try await run("""
        on mouseUp
          put "x" into field "nope"
        end mouseUp
        """)
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.line == 2)
        #expect(error.message.contains("nope"))
    }
}

@Test func arithmeticOnTextIsAFriendlyError() async throws {
    do {
        try await run("""
        on mouseUp
          put "pie" + 1 into x
        end mouseUp
        """)
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.line == 2)
        #expect(error.message.contains("pie"))
    }
}

@Test func divideByZeroIsAFriendlyError() async throws {
    await #expect(throws: ScriptError.self) {
        try await run("""
        on mouseUp
          put 1 / 0 into x
        end mouseUp
        """)
    }
}

@Test func unterminatedStringReportsLine() async throws {
    do {
        try await run("""
        on mouseUp
          put "oops into x
        end mouseUp
        """)
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.line == 2)
    }
}

@Test func beepBeepsOnceOrCounted() async throws {
    let host = try await run("""
    on mouseUp
      beep
      beep 3
    end mouseUp
    """)
    #expect(host.beeps == 4)
}
