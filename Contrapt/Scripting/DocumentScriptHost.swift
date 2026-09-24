//
//  DocumentScriptHost.swift
//  Contrapt
//

import SwiftUI
import HyperTalk

/// Bridges a running script to the open document: `go` moves the current
/// card, `field` reads and writes field parts on the current card and its
/// background. Scripts can reach nothing else (D7: the interpreter is the
/// sandbox, and this host is its only door).
@MainActor
final class DocumentScriptHost: HyperTalkHost {
    private let stackBinding: Binding<Stack>
    private let currentCardIndex: Binding<Int>
    private let onMessage: (String) -> Void

    init(
        stack: Binding<Stack>,
        currentCardIndex: Binding<Int>,
        onMessage: @escaping (String) -> Void
    ) {
        self.stackBinding = stack
        self.currentCardIndex = currentCardIndex
        self.onMessage = onMessage
    }

    private var stack: Stack { stackBinding.wrappedValue }

    private var cardIndex: Int {
        min(currentCardIndex.wrappedValue, stack.cards.count - 1)
    }

    // MARK: - HyperTalkHost

    func goToCard(_ destination: GoDestination) throws {
        let count = stack.cards.count
        guard count > 0 else { throw HostError("This stack has no cards.") }
        switch destination {
        case .next:
            currentCardIndex.wrappedValue = (cardIndex + 1) % count
        case .previous:
            currentCardIndex.wrappedValue = (cardIndex + count - 1) % count
        case .first:
            currentCardIndex.wrappedValue = 0
        case .last:
            currentCardIndex.wrappedValue = count - 1
        case .number(let number):
            guard (1...count).contains(number) else {
                throw HostError("There is no card \(number) — this stack has \(count) card\(count == 1 ? "" : "s").")
            }
            currentCardIndex.wrappedValue = number - 1
        case .named(let name):
            guard let index = stack.cards.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw HostError("There is no card named \"\(name)\".")
            }
            currentCardIndex.wrappedValue = index
        }
    }

    func fieldText(named name: String) throws -> String {
        guard let location = locateField(named: name),
              case .field(let properties) = part(at: location).kind else {
            throw HostError("There is no field named \"\(name)\" on this card.")
        }
        return properties.text
    }

    func setFieldText(named name: String, to text: String) throws {
        guard let location = locateField(named: name),
              case .field(var properties) = part(at: location).kind else {
            throw HostError("There is no field named \"\(name)\" on this card.")
        }
        properties.text = text
        setKind(.field(properties), at: location)
    }

    func showMessage(_ text: String) {
        onMessage(text)
    }

    func beep() {
        Beeper.shared.beep()
    }

    // MARK: - Properties

    func propertyValue(_ property: String, of object: HyperTalkObject) throws -> String {
        switch object {
        case .part(let kind, let name):
            let location = try locatePart(kind: kind, named: name)
            return try partProperty(property, of: part(at: location), kind: kind)
        case .card(let which):
            let index = try cardIndexFor(which)
            return try cardProperty(property, cardAt: index)
        case .thisCard:
            return try cardProperty(property, cardAt: cardIndex)
        case .thisBackground:
            guard property == "name" else { throw Self.noSuchProperty(property, of: "this background") }
            let card = stack.cards[cardIndex]
            guard let background = stack.backgrounds.first(where: { $0.id == card.backgroundID }) else {
                throw HostError("This card has no background.")
            }
            return background.name
        case .thisStack:
            switch property {
            case "name": return stack.name
            case "cards": return String(stack.cards.count)
            default: throw Self.noSuchProperty(property, of: "this stack")
            }
        }
    }

    func setProperty(_ property: String, of object: HyperTalkObject, to value: String) throws {
        switch object {
        case .part(let kind, let name):
            let location = try locatePart(kind: kind, named: name)
            var updated = part(at: location)
            try applyPartProperty(property, to: &updated, kind: kind, value: value)
            setPart(updated, at: location)
        case .card(let which):
            let index = try cardIndexFor(which)
            guard property == "name" else { throw Self.noSuchProperty(property, of: "a card") }
            stackBinding.wrappedValue.cards[index].name = value
        case .thisCard:
            guard property == "name" else { throw Self.noSuchProperty(property, of: "this card") }
            stackBinding.wrappedValue.cards[cardIndex].name = value
        case .thisBackground:
            guard property == "name" else { throw Self.noSuchProperty(property, of: "this background") }
            let card = stack.cards[cardIndex]
            guard let index = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID }) else {
                throw HostError("This card has no background.")
            }
            stackBinding.wrappedValue.backgrounds[index].name = value
        case .thisStack:
            guard property == "name" else { throw Self.noSuchProperty(property, of: "this stack") }
            stackBinding.wrappedValue.name = value
        }
    }

    private func partProperty(_ property: String, of part: Part, kind: String) throws -> String {
        switch property {
        case "name": return part.name
        case "visible": return part.isVisible ? "true" : "false"
        case "width": return numberText(part.frame.width)
        case "height": return numberText(part.frame.height)
        case "left": return numberText(part.frame.x)
        case "top": return numberText(part.frame.y)
        case "right": return numberText(part.frame.x + part.frame.width)
        case "bottom": return numberText(part.frame.y + part.frame.height)
        case "title":
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.title
        case "text":
            switch part.kind {
            case .field(let properties): return properties.text
            case .label(let properties): return properties.text
            default: throw Self.noSuchProperty(property, of: kind)
            }
        case "placeholder":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.placeholder
        default:
            throw Self.noSuchProperty(property, of: kind)
        }
    }

    private func applyPartProperty(_ property: String, to part: inout Part, kind: String, value: String) throws {
        switch property {
        case "name":
            part.name = value
        case "visible":
            switch value.lowercased() {
            case "true": part.isVisible = true
            case "false": part.isVisible = false
            default: throw HostError("The visible property must be true or false, not \"\(value)\".")
            }
        case "width": part.frame.width = max(16, try number(value, for: property))
        case "height": part.frame.height = max(16, try number(value, for: property))
        case "left": part.frame.x = try number(value, for: property)
        case "top": part.frame.y = try number(value, for: property)
        case "right": part.frame.x = try number(value, for: property) - part.frame.width
        case "bottom": part.frame.y = try number(value, for: property) - part.frame.height
        case "title":
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            properties.title = value
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
        default:
            throw Self.noSuchProperty(property, of: kind)
        }
    }

    private func cardProperty(_ property: String, cardAt index: Int) throws -> String {
        switch property {
        case "name": return stack.cards[index].name
        case "number": return String(index + 1)
        default: throw Self.noSuchProperty(property, of: "a card")
        }
    }

    private func cardIndexFor(_ which: String) throws -> Int {
        if let number = Int(which.trimmingCharacters(in: .whitespaces)) {
            guard (1...stack.cards.count).contains(number) else {
                throw HostError("There is no card \(number) — this stack has \(stack.cards.count) card\(stack.cards.count == 1 ? "" : "s").")
            }
            return number - 1
        }
        guard let index = stack.cards.firstIndex(where: { $0.name.caseInsensitiveCompare(which) == .orderedSame }) else {
            throw HostError("There is no card named \"\(which)\".")
        }
        return index
    }

    private func number(_ value: String, for property: String) throws -> Double {
        guard let number = Double(value.trimmingCharacters(in: .whitespaces)), number.isFinite else {
            throw HostError("The \(property) property needs a number, not \"\(value)\".")
        }
        return number
    }

    private func numberText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func noSuchProperty(_ property: String, of what: String) -> HostError {
        HostError("There is no property \"\(property)\" of \(what == "this stack" || what == "this card" || what == "this background" || what == "a card" ? what : "a \(what)").")
    }

    // MARK: - Field lookup

    /// Card parts win over background parts, matching HyperCard's layering.
    private enum FieldLocation {
        case card(partIndex: Int)
        case background(backgroundIndex: Int, partIndex: Int)
    }

    private func locateField(named name: String) -> FieldLocation? {
        let card = stack.cards[cardIndex]
        if let partIndex = index(ofFieldNamed: name, in: card.parts) {
            return .card(partIndex: partIndex)
        }
        if let backgroundIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID }),
           let partIndex = index(ofFieldNamed: name, in: stack.backgrounds[backgroundIndex].parts) {
            return .background(backgroundIndex: backgroundIndex, partIndex: partIndex)
        }
        return nil
    }

    private func index(ofFieldNamed name: String, in parts: [Part]) -> Int? {
        parts.firstIndex { part in
            if case .field = part.kind {
                return part.name.caseInsensitiveCompare(name) == .orderedSame
            }
            return false
        }
    }

    // MARK: - Part lookup (any kind, for properties)

    /// Finds a part of the given kind by name — card parts first, then the
    /// background's, matching HyperCard's layering.
    private func locatePart(kind: String, named name: String) throws -> FieldLocation {
        let card = stack.cards[cardIndex]
        if let partIndex = index(ofKind: kind, named: name, in: card.parts) {
            return .card(partIndex: partIndex)
        }
        if let backgroundIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID }),
           let partIndex = index(ofKind: kind, named: name, in: stack.backgrounds[backgroundIndex].parts) {
            return .background(backgroundIndex: backgroundIndex, partIndex: partIndex)
        }
        throw HostError("There is no \(kind) named \"\(name)\" on this card.")
    }

    private func index(ofKind kind: String, named name: String, in parts: [Part]) -> Int? {
        parts.firstIndex { part in
            part.kind.word == kind && part.name.caseInsensitiveCompare(name) == .orderedSame
        }
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
