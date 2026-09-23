//
//  Stack.swift
//  HyperPad
//

import Foundation

/// The stack document model: Stack → Background/Card → Part.
///
/// These types define the on-disk exchange format (DECISIONS.md D4), so the
/// JSON they produce is treated as public API: stable named fields, a
/// discriminated-union encoding for parts, and a format version gate.

nonisolated enum StackFormat {
    /// Version of the stack file format this build reads and writes.
    static let currentVersion = 1
}

// MARK: - Geometry

/// Logical card dimensions in points (D3: fixed card size, scaled to fit).
/// A distinct type rather than CGSize so the JSON encodes stable named fields.
nonisolated struct CardSize: Codable, Hashable {
    var width: Double
    var height: Double
}

/// A part's position and size in logical card coordinates.
nonisolated struct PartFrame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

// MARK: - Stack hierarchy

nonisolated struct Stack: Codable, Identifiable, Hashable {
    var formatVersion: Int
    var id: UUID
    var name: String
    var cardSize: CardSize
    var script: String
    var backgrounds: [Background]
    var cards: [Card]
}

nonisolated struct Background: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var script: String
    var parts: [Part]
}

nonisolated struct Card: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var backgroundID: UUID
    var script: String
    var parts: [Part]
}

// MARK: - Parts

/// A widget placed on a card or background, rendered as a native SwiftUI
/// control at runtime (D5). Style properties are added per-kind later, with
/// nil meaning "native default" — mirroring the skin philosophy (D8).
nonisolated struct Part: Identifiable, Hashable {
    var id: UUID
    var name: String
    var frame: PartFrame
    var script: String
    var kind: PartKind
}

nonisolated enum PartKind: Hashable {
    case button(ButtonPart)
    case field(FieldPart)
    case label(LabelPart)
}

nonisolated struct ButtonPart: Codable, Hashable {
    var title: String
}

nonisolated struct FieldPart: Codable, Hashable {
    var text: String
    var placeholder: String
}

nonisolated struct LabelPart: Codable, Hashable {
    var text: String
}

// MARK: - Part coding

/// Custom Codable so a part encodes as `"type": "button"` plus a per-kind
/// payload object, rather than Swift's synthesized enum nesting — this JSON
/// is the exchange format and should read cleanly.
///
/// Adding a new part kind is a format change: bump `StackFormat.currentVersion`
/// so older builds refuse newer stacks instead of failing mid-decode.
extension Part: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, frame, script, type, button, field, label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        frame = try container.decode(PartFrame.self, forKey: .frame)
        script = try container.decode(String.self, forKey: .script)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "button":
            kind = .button(try container.decode(ButtonPart.self, forKey: .button))
        case "field":
            kind = .field(try container.decode(FieldPart.self, forKey: .field))
        case "label":
            kind = .label(try container.decode(LabelPart.self, forKey: .label))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown part type '\(type)'"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(frame, forKey: .frame)
        try container.encode(script, forKey: .script)
        switch kind {
        case .button(let properties):
            try container.encode("button", forKey: .type)
            try container.encode(properties, forKey: .button)
        case .field(let properties):
            try container.encode("field", forKey: .type)
            try container.encode(properties, forKey: .field)
        case .label(let properties):
            try container.encode("label", forKey: .type)
            try container.encode(properties, forKey: .label)
        }
    }
}
