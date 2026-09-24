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

    func goToCard(_ destination: GoDestination) throws {
        destinations.append(destination)
    }

    /// Content lookups key the dictionary by the reference text, prefixed
    /// with the domain when qualified — e.g. "name", "1", "background 1",
    /// "id 6". Tests preset whichever keys they use.
    private func fieldKey(_ reference: HyperTalkObject.Reference, _ domain: HyperTalkObject.PartDomain) -> String {
        (domainText(domain) + referenceText(reference)).lowercased()
    }

    func fieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain) throws -> String {
        guard let text = fields[fieldKey(reference, domain)] else {
            throw HostError("There is no field \(referenceText(reference)) here.")
        }
        return text
    }

    func setFieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, to text: String) throws {
        guard fields[fieldKey(reference, domain)] != nil else {
            throw HostError("There is no field \(referenceText(reference)) here.")
        }
        fields[fieldKey(reference, domain)] = text
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
}

@discardableResult
func run(_ script: String, handler: String = "mouseUp", host: MockHost = MockHost(), maxSteps: Int = 100_000) throws -> MockHost {
    _ = try HyperTalk.run(handler: handler, in: script, host: host, maxSteps: maxSteps)
    return host
}

// MARK: - Commands

@Test func goToNextCard() throws {
    let host = try run("""
    on mouseUp
      go to next card
    end mouseUp
    """)
    #expect(host.destinations == [.next])
}

@Test func goVariants() throws {
    let host = try run("""
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

@Test func putIntoField() throws {
    let host = try run("""
    on mouseUp
      put "Hello" into field "Greeting"
    end mouseUp
    """, host: MockHost(fields: ["Greeting": ""]))
    #expect(host.fields["greeting"] == "Hello")
}

@Test func putAfterAndBefore() throws {
    let host = try run("""
    on mouseUp
      put "world" into field "f"
      put "hello " before field "f"
      put "!" after field "f"
    end mouseUp
    """, host: MockHost(fields: ["f": ""]))
    #expect(host.fields["f"] == "hello world!")
}

@Test func putWithoutContainerGoesToMessageBox() throws {
    let host = try run("""
    on mouseUp
      put "Hi there"
    end mouseUp
    """)
    #expect(host.messages == ["Hi there"])
}

@Test func variablesFlowThroughPut() throws {
    let host = try run("""
    on mouseUp
      put 6 * 7 into answer
      put answer into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "42")
}

// MARK: - Expressions

@Test func arithmeticPrecedence() throws {
    let host = try run("""
    on mouseUp
      put 2 + 3 * 4 into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "14")
}

@Test func parenthesesAndUnaryMinus() throws {
    let host = try run("""
    on mouseUp
      put -(2 + 3) * 4 into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "-20")
}

@Test func divisionFormatsNumbersCleanly() throws {
    let host = try run("""
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

@Test func concatenationOperators() throws {
    let host = try run("""
    on mouseUp
      put "Hello" && "World" into field "a"
      put "Hyper" & "Talk" into field "b"
    end mouseUp
    """, host: MockHost(fields: ["a": "", "b": ""]))
    #expect(host.fields["a"] == "Hello World")
    #expect(host.fields["b"] == "HyperTalk")
}

@Test func comparisonsAreNumericWhenBothSidesAreNumbers() throws {
    let host = try run("""
    on mouseUp
      if "10" > "9" then put "numeric" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "numeric")
}

@Test func stringComparisonIsCaseInsensitive() throws {
    let host = try run("""
    on mouseUp
      if "Apple" = "APPLE" then put "same" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "same")
}

@Test func isAndIsNotAndContains() throws {
    let host = try run("""
    on mouseUp
      if "abc" is "abc" then put "1" after field "out"
      if "abc" is not "xyz" then put "2" after field "out"
      if "HyperCard" contains "card" then put "3" after field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "123")
}

@Test func booleanOperators() throws {
    let host = try run("""
    on mouseUp
      if 1 < 2 and not (3 < 2) then put "yes" into field "out"
      if 1 > 2 or 2 > 1 then put "!" after field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "yes!")
}

@Test func unassignedVariableEvaluatesToItsOwnName() throws {
    let host = try run("""
    on mouseUp
      put greetings into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "greetings")
}

@Test func builtInConstants() throws {
    let host = try run("""
    on mouseUp
      put empty into field "out"
      put "a" & space & "b" & quote after field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": "junk"]))
    #expect(host.fields["out"] == "a b\"")
}

@Test func fieldNamesCanBeComputed() throws {
    let host = try run("""
    on mouseUp
      put 2 into n
      put "hi" into field ("out" & n)
    end mouseUp
    """, host: MockHost(fields: ["out2": ""]))
    #expect(host.fields["out2"] == "hi")
}

// MARK: - Control flow

@Test func ifElseBlocks() throws {
    let host = try run("""
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

@Test func elseIfChain() throws {
    let host = try run("""
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

@Test func singleLineIfWithElseLine() throws {
    let host = try run("""
    on mouseUp
      if 5 > 3 then put "big" into field "out"
      else put "small" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "big")
}

@Test func repeatWithCounter() throws {
    let host = try run("""
    on mouseUp
      repeat with i = 1 to 5
        put i after field "out"
      end repeat
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "12345")
}

@Test func repeatDownTo() throws {
    let host = try run("""
    on mouseUp
      repeat with i = 3 down to 1
        put i after field "out"
      end repeat
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "321")
}

@Test func repeatTimes() throws {
    let host = try run("""
    on mouseUp
      repeat 4 times
        put "x" after field "out"
      end repeat
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "xxxx")
}

@Test func repeatWhileAndUntil() throws {
    let host = try run("""
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

@Test func exitRepeatAndNextRepeat() throws {
    let host = try run("""
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

@Test func exitHandlerStopsExecution() throws {
    let host = try run("""
    on mouseUp
      put "before" into field "out"
      exit mouseUp
      put "after" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "before")
}

@Test func nestedRepeatsRespectExit() throws {
    let host = try run("""
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

@Test func onlyTheNamedHandlerRuns() throws {
    let host = try run("""
    on openCard
      put "opened" into field "out"
    end openCard

    on mouseUp
      put "clicked" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "clicked")
}

@Test func missingHandlerReturnsFalse() throws {
    let handled = try HyperTalk.run(handler: "mouseUp", in: """
    on openCard
      go to next card
    end openCard
    """, host: MockHost())
    #expect(handled == false)
}

@Test func caseInsensitivity() throws {
    let host = try run("""
    ON MOUSEUP
      PUT "Loud" INTO FIELD "out"
      GO TO NEXT CARD
    END MOUSEUP
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "Loud")
    #expect(host.destinations == [.next])
}

@Test func commentsAreIgnored() throws {
    let host = try run("""
    on mouseUp -- runs on tap
      -- a full-line comment
      put "ok" into field "out" -- trailing comment
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "ok")
}

// MARK: - Errors

@Test func runawayLoopIsStopped() throws {
    #expect(throws: ScriptError.self) {
        try run("""
        on mouseUp
          repeat forever
            put 1 into x
          end repeat
        end mouseUp
        """, maxSteps: 100)
    }
}

@Test func unknownCommandReportsLine() throws {
    do {
        try run("""
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

@Test func missingEndRepeatReportsBlockLine() throws {
    do {
        try run("""
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

@Test func unknownFieldSurfacesHostErrorWithLine() throws {
    do {
        try run("""
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

@Test func arithmeticOnTextIsAFriendlyError() throws {
    do {
        try run("""
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

@Test func divideByZeroIsAFriendlyError() throws {
    #expect(throws: ScriptError.self) {
        try run("""
        on mouseUp
          put 1 / 0 into x
        end mouseUp
        """)
    }
}

@Test func unterminatedStringReportsLine() throws {
    do {
        try run("""
        on mouseUp
          put "oops into x
        end mouseUp
        """)
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.line == 2)
    }
}

@Test func beepBeepsOnceOrCounted() throws {
    let host = try run("""
    on mouseUp
      beep
      beep 3
    end mouseUp
    """)
    #expect(host.beeps == 4)
}
