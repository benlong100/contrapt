//
//  DocumentScriptHost.swift
//  HyperPad
//

import SwiftUI
import HyperTalk

/// Bridges a running script to the open document: `go` moves the current
/// card, `field` reads and writes field parts on the current card and its
/// background. Scripts can reach nothing else (D7: the interpreter is the
/// sandbox, and this host is its only door).
@MainActor
final class DocumentScriptHost: HyperTalkHost {
    private let document: Binding<StackDocument>
    private let currentCardIndex: Binding<Int>
    private let onMessage: (String) -> Void

    init(
        document: Binding<StackDocument>,
        currentCardIndex: Binding<Int>,
        onMessage: @escaping (String) -> Void
    ) {
        self.document = document
        self.currentCardIndex = currentCardIndex
        self.onMessage = onMessage
    }

    private var stack: Stack { document.wrappedValue.stack }

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
            document.wrappedValue.stack.cards[cardIndex].parts[partIndex].kind = kind
        case .background(let backgroundIndex, let partIndex):
            document.wrappedValue.stack.backgrounds[backgroundIndex].parts[partIndex].kind = kind
        }
    }
}
