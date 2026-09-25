//
//  InterpreterTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

/// A host that records everything scripts do to it.
final class MockHost: HyperTalkHost {
    var fields: [String: String]
    var destinations: [GoDestination] = []
    var messages: [String] = []

    init(fields: [String: String] = [:]) {
        self.fields = Dictionary(uniqueKeysWithValues: fields.map { ($0.key.lowercased(), $0.value) })
    }

    /// The effects passed with each `go`, in order.
    var goEffects: [[ScreenEffect]] = []

    func goToCard(_ destination: GoDestination, effects: [ScreenEffect]) throws {
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
        case .inBackground(let inner, let bg): return cardPrefix(inner) + bg.lowercased() + "."
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

    /// Properties keyed by a readable path like "button OK.width".
    var properties: [String: String] = [:]

    private func referenceText(_ reference: HyperTalkObject.Reference) -> String {
        switch reference {
        case .named(let name): name
        case .number(let number): String(number)
        case .id(let id): "id \(id)"
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
        case .part(let kind, let domain, let reference):
            "\(domainText(domain))\(kind) \(referenceText(reference)).\(property)"
        case .card(let reference): "card \(referenceText(reference)).\(property)"
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
        case .abbreviatedDate: "Jan 2, 2034"
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
    var askPrompts: [String] = []

    func answer(_ prompt: String, buttons: [String]) async -> String {
        answerPrompts.append(prompt)
        return answerChoice ?? buttons.first ?? "OK"
    }

    func ask(_ prompt: String, initialAnswer: String) async -> String? {
        askPrompts.append(prompt)
        return askResponse
    }

    /// Seconds requested by each `wait`; instant so tests don't actually pause.
    var waits: [Double] = []

    func wait(seconds: Double) async {
        waits.append(seconds)
    }

    /// Records each `find`, and matches (via FindMatcher) against the field
    /// values it holds — enough to exercise the interpreter's result and
    /// found* wiring. The real cross-card search lives in the app's host.
    var findCalls: [(text: String, mode: FindMode, inField: HyperTalkObject.Reference?)] = []
    private var foundValues: [FoundField: String] = [:]

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
    func count(_ countable: Countable) throws -> Int {
        switch countable {
        case .cards: return sortKeys.isEmpty ? cardCount : sortKeys.count
        case .backgrounds: return backgroundCount
        case .parts(let kind, _): return kind == "field" ? fields.count : buttonCount
        }
    }

    /// `sort` support: one key value per card; during sort any field read
    /// returns the current card's key, so `sort by field "X"` uses these.
    var sortKeys: [String] = []
    var sortContext: Int?
    var reorderedTo: [Int]?
    func setSortContext(_ cardIndex: Int?) { sortContext = cardIndex }
    func reorderCards(_ order: [Int]) throws { reorderedTo = order }

    /// `doMenu` built-in actions performed (untrapped items).
    var performedMenu: [String] = []
    func performMenu(_ item: String) throws { performedMenu.append(item) }

    /// A field exists if it's in `fields`; any other part/card exists if a
    /// property was preset for it. `this …` objects always exist.
    func exists(_ object: HyperTalkObject) -> Bool {
        switch object {
        case .part(let kind, let domain, let reference):
            if kind == "field", fields[fieldKey(reference, domain)] != nil { return true }
            let prefix = "\(domainText(domain))\(kind) \(referenceText(reference))."
            return properties.keys.contains { $0.hasPrefix(prefix) }
        case .card(let reference):
            return properties.keys.contains { $0.hasPrefix("card \(referenceText(reference)).") }
        case .thisCard, .thisBackground, .thisStack:
            return true
        }
    }

    private func patterns(_ format: ConvertFormat) -> String? {
        switch format {
        case .shortDate: "M/d/yy"
        case .longDate: "EEEE, MMMM d, yyyy"
        case .abbreviatedDate: "MMM d, yyyy"
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
        formatter.dateFormat = pattern
        return formatter
    }

    private func convertParse(_ value: String, from: [ConvertFormat]) throws -> Date {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let effective: [ConvertFormat]
        if !from.isEmpty {
            effective = from
        } else if let seconds = Double(trimmed) {
            return Date(timeIntervalSince1970: seconds)
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
            return Date(timeIntervalSince1970: seconds)
        }
        if effective == [.dateItems] {
            let parts = trimmed.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            guard parts.count >= 3 else { throw HostError("Expected at least year, month, day in dateItems.") }
            var components = DateComponents()
            components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
            if parts.count > 3 { components.hour = parts[3] }
            if parts.count > 4 { components.minute = parts[4] }
            if parts.count > 5 { components.second = parts[5] }
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
        if to == [.seconds] { return String(Int(date.timeIntervalSince1970)) }
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
