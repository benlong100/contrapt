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
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            guard let index = stack.cards.firstIndex(where: { String($0.scriptID) == wanted }) else {
                throw HostError("There is no card with id \(id).")
            }
            currentCardIndex.wrappedValue = index
        }
    }

    func fieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain) throws -> String {
        let location = try locatePart(kind: "field", domain: domain, reference: reference)
        guard case .field(let properties) = part(at: location).kind else {
            throw HostError("That part is not a field.")
        }
        return properties.text
    }

    func setFieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, to text: String) throws {
        let location = try locatePart(kind: "field", domain: domain, reference: reference)
        guard case .field(var properties) = part(at: location).kind else {
            throw HostError("That part is not a field.")
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
            case "id": return String(background.scriptID)
            case "cantdelete": return background.cantDelete ? "true" : "false"
            case "dontsearch": return background.dontSearch ? "true" : "false"
            default: throw Self.noSuchProperty(property, of: "this background")
            }
        case .thisStack:
            switch property {
            case "name": return stack.name
            case "cards": return String(stack.cards.count)
            case "width": return numberText(stack.cardSize.width)
            case "height": return numberText(stack.cardSize.height)
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
            default: throw Self.noSuchProperty(property, of: "this stack")
            }
        }
    }

    private func partProperty(_ property: String, of part: Part, kind: String) throws -> String {
        switch property {
        case "name": return part.name
        case "id": return String(part.scriptID)
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
        case "showname":
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.showName ? "true" : "false"
        case "autohilite", "autohighlight":
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.autoHilite ? "true" : "false"
        case "style":
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.style.rawValue
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
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.format.fontDesign.rawValue
        case "textsize":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return numberText(properties.format.size)
        case "textstyle":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return Self.styleList(properties.format)
        case "textalign":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.format.align.rawValue
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
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            guard let style = ButtonStyleKind.parse(value) else {
                throw HostError("Unknown button style \"\(value)\". Try roundRect, rectangle, shadow, opaque, transparent, checkbox, or radio.")
            }
            properties.style = style
            part.kind = .button(properties)
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
        default:
            throw Self.noSuchProperty(property, of: kind)
        }
    }

    /// Mutates a field's text format, or throws if the part isn't a field.
    private func withFieldFormat(_ part: inout Part, kind: String, _ body: (inout TextFormat) throws -> Void) throws {
        guard case .field(var properties) = part.kind else { throw Self.noSuchProperty("text formatting", of: kind) }
        try body(&properties.format)
        part.kind = .field(properties)
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
        if domain != .background,
           let partIndex = index(ofKind: kind, matching: reference, in: card.parts) {
            return .card(partIndex: partIndex)
        }
        if domain != .card,
           let backgroundIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID }),
           let partIndex = index(ofKind: kind, matching: reference, in: stack.backgrounds[backgroundIndex].parts) {
            return .background(backgroundIndex: backgroundIndex, partIndex: partIndex)
        }
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
