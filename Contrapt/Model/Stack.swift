//
//  Stack.swift
//  Contrapt
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

/// A named card-size choice for the Stack inspector — HyperCard's classic
/// sizes (Classic 9″ is the original compact-Mac screen) plus modern ones.
nonisolated struct CardSizePreset: Identifiable, Hashable {
    let name: String
    let size: CardSize
    var id: String { name }

    static let all: [CardSizePreset] = [
        CardSizePreset(name: "Classic (9″)", size: CardSize(width: 512, height: 342)),
        CardSizePreset(name: "Small", size: CardSize(width: 416, height: 240)),
        CardSizePreset(name: "PowerBook", size: CardSize(width: 640, height: 400)),
        CardSizePreset(name: "Large", size: CardSize(width: 640, height: 480)),
        CardSizePreset(name: "iPad Landscape", size: CardSize(width: 1024, height: 768)),
        CardSizePreset(name: "iPad Portrait", size: CardSize(width: 768, height: 1024)),
        CardSizePreset(name: "Widescreen", size: CardSize(width: 1280, height: 720)),
        CardSizePreset(name: "Square", size: CardSize(width: 768, height: 768)),
    ]
}

/// A part's position and size in logical card coordinates.
nonisolated struct PartFrame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

// MARK: - Stack hierarchy

nonisolated struct Stack: Identifiable, Hashable {
    var formatVersion: Int
    var id: UUID
    var name: String
    var cardSize: CardSize
    var script: String
    var backgrounds: [Background]
    var cards: [Card]
    /// Allocator for scriptIDs — the short permanent numbers scripts use
    /// (`button id 6`). Never decremented; IDs are never reused.
    var nextID: Int = 1

    /// Claims the next permanent scriptID.
    mutating func claimScriptID() -> Int {
        let id = max(nextID, 1)
        nextID = id + 1
        return id
    }
}

extension Stack: Codable {
    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, cardSize, script, backgrounds, cards, nextID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        cardSize = try container.decode(CardSize.self, forKey: .cardSize)
        script = try container.decode(String.self, forKey: .script)
        backgrounds = try container.decode([Background].self, forKey: .backgrounds)
        cards = try container.decode([Card].self, forKey: .cards)
        nextID = try container.decodeIfPresent(Int.self, forKey: .nextID) ?? 1
    }
}

nonisolated struct Background: Identifiable, Hashable {
    var id: UUID
    var name: String
    var script: String
    var parts: [Part]
    /// The background's paint layer, beneath everything on every card
    /// sharing this background (same pair as Card's).
    var paintDrawingAsset: String? = nil
    var paintImageAsset: String? = nil
    /// Permanent short ID for scripts; assigned by the stack's allocator.
    var scriptID: Int = 0
}

extension Background: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, script, parts, paintDrawingAsset, paintImageAsset, scriptID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        script = try container.decode(String.self, forKey: .script)
        parts = try container.decode([Part].self, forKey: .parts)
        paintDrawingAsset = try container.decodeIfPresent(String.self, forKey: .paintDrawingAsset)
        paintImageAsset = try container.decodeIfPresent(String.self, forKey: .paintImageAsset)
        scriptID = try container.decodeIfPresent(Int.self, forKey: .scriptID) ?? 0
    }
}

nonisolated struct Card: Identifiable, Hashable {
    var id: UUID
    var name: String
    var backgroundID: UUID
    var script: String
    var parts: [Part]
    /// The card's paint layer (Phase 6): the editable PencilKit drawing,
    /// and its rendered PNG for display and for viewing unzipped stacks
    /// anywhere. Both live in the archive's assets.
    var paintDrawingAsset: String? = nil
    var paintImageAsset: String? = nil
    /// Permanent short ID for scripts; assigned by the stack's allocator.
    var scriptID: Int = 0
    /// HyperCard's Card Info checkboxes, also script properties.
    var isMarked: Bool = false
    var cantDelete: Bool = false
    var dontSearch: Bool = false
}

extension Card: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, backgroundID, script, parts, paintDrawingAsset, paintImageAsset, scriptID
        case isMarked, cantDelete, dontSearch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        backgroundID = try container.decode(UUID.self, forKey: .backgroundID)
        script = try container.decode(String.self, forKey: .script)
        parts = try container.decode([Part].self, forKey: .parts)
        paintDrawingAsset = try container.decodeIfPresent(String.self, forKey: .paintDrawingAsset)
        paintImageAsset = try container.decodeIfPresent(String.self, forKey: .paintImageAsset)
        scriptID = try container.decodeIfPresent(Int.self, forKey: .scriptID) ?? 0
        isMarked = try container.decodeIfPresent(Bool.self, forKey: .isMarked) ?? false
        cantDelete = try container.decodeIfPresent(Bool.self, forKey: .cantDelete) ?? false
        dontSearch = try container.decodeIfPresent(Bool.self, forKey: .dontSearch) ?? false
    }
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
    /// Hidden parts don't render or take taps in browse mode (scriptable
    /// via `set the visible of … to false`); edit mode shows them ghosted.
    var isVisible: Bool = true
    /// Permanent short ID for scripts (`button id 6`); assigned by the
    /// stack's allocator, stable across renames, never reused.
    var scriptID: Int = 0
}

nonisolated enum PartKind: Hashable {
    case button(ButtonPart)
    case field(FieldPart)
    case label(LabelPart)
    case image(ImagePart)

    /// The word scripts and the UI use for this kind.
    var word: String {
        switch self {
        case .button: "button"
        case .field: "field"
        case .label: "label"
        case .image: "image"
        }
    }
}

nonisolated struct ButtonPart: Codable, Hashable {
    var title: String
}

nonisolated struct FieldPart: Hashable {
    var text: String
    var placeholder: String
    /// Multi-line fields render as a text area filling their frame, like
    /// HyperCard fields; single-line fields are compact entry boxes.
    var isMultiline: Bool

    init(text: String, placeholder: String, isMultiline: Bool = false) {
        self.text = text
        self.placeholder = placeholder
        self.isMultiline = isMultiline
    }
}

/// Manual Codable so older manifests without `isMultiline` still decode.
extension FieldPart: Codable {
    private enum CodingKeys: String, CodingKey {
        case text, placeholder, isMultiline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        placeholder = try container.decode(String.self, forKey: .placeholder)
        isMultiline = try container.decodeIfPresent(Bool.self, forKey: .isMultiline) ?? false
    }
}

nonisolated struct LabelPart: Codable, Hashable {
    var text: String
}

/// References an image stored in the stack archive's assets (D4).
nonisolated struct ImagePart: Codable, Hashable {
    var assetName: String
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
        case id, name, frame, script, type, button, field, label, image, visible, scriptID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        frame = try container.decode(PartFrame.self, forKey: .frame)
        script = try container.decode(String.self, forKey: .script)
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        scriptID = try container.decodeIfPresent(Int.self, forKey: .scriptID) ?? 0
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "button":
            kind = .button(try container.decode(ButtonPart.self, forKey: .button))
        case "field":
            kind = .field(try container.decode(FieldPart.self, forKey: .field))
        case "label":
            kind = .label(try container.decode(LabelPart.self, forKey: .label))
        case "image":
            kind = .image(try container.decode(ImagePart.self, forKey: .image))
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
        try container.encode(isVisible, forKey: .visible)
        try container.encode(scriptID, forKey: .scriptID)
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
        case .image(let properties):
            try container.encode("image", forKey: .type)
            try container.encode(properties, forKey: .image)
        }
    }
}

// MARK: - Sanitizing untrusted stacks

nonisolated extension Stack {
    /// Repairs a decoded stack so that hostile or damaged files can't
    /// break the app (D7): geometry is clamped to finite, sane bounds;
    /// structural invariants (at least one background and one card, no
    /// dangling background references, unique IDs) are restored; and
    /// scripts are capped. Applied to every loaded document.
    func sanitized() -> Stack {
        var stack = self

        // Card size: finite and within reason.
        if !stack.cardSize.width.isFinite || !stack.cardSize.height.isFinite {
            stack.cardSize = CardSize(width: 1024, height: 768)
        }
        stack.cardSize.width = min(max(stack.cardSize.width, 200), 8192)
        stack.cardSize.height = min(max(stack.cardSize.height, 200), 8192)

        // Structural invariants.
        if stack.backgrounds.isEmpty {
            stack.backgrounds = [Background(id: UUID(), name: "Background 1", script: "", parts: [])]
        }
        if stack.cards.isEmpty {
            stack.cards = [Card(id: UUID(), name: "Card 1", backgroundID: stack.backgrounds[0].id, script: "", parts: [])]
        }
        // Unique IDs — duplicates make ForEach behavior undefined. When a
        // background is re-identified, references to it are remapped.
        var seen: Set<UUID> = []
        func uniqued(_ id: UUID) -> UUID {
            if seen.contains(id) { return UUID() }
            seen.insert(id)
            return id
        }
        stack.id = uniqued(stack.id)
        var backgroundRemap: [UUID: UUID] = [:]
        for index in stack.backgrounds.indices {
            let original = stack.backgrounds[index].id
            let unique = uniqued(original)
            if unique != original { backgroundRemap[original] = unique }
            stack.backgrounds[index].id = unique
            stack.backgrounds[index].parts = sanitizedParts(stack.backgrounds[index].parts, cardSize: stack.cardSize, uniqued: uniqued)
        }
        for index in stack.cards.indices {
            stack.cards[index].id = uniqued(stack.cards[index].id)
            if let mapped = backgroundRemap[stack.cards[index].backgroundID] {
                stack.cards[index].backgroundID = mapped
            }
            stack.cards[index].parts = sanitizedParts(stack.cards[index].parts, cardSize: stack.cardSize, uniqued: uniqued)
            stack.cards[index].script = Self.cappedScript(stack.cards[index].script)
        }

        // Dangling background references — repaired after re-identification.
        let backgroundIDs = Set(stack.backgrounds.map(\.id))
        for index in stack.cards.indices where !backgroundIDs.contains(stack.cards[index].backgroundID) {
            stack.cards[index].backgroundID = stack.backgrounds[0].id
        }
        stack.script = Self.cappedScript(stack.script)
        for index in stack.backgrounds.indices {
            stack.backgrounds[index].script = Self.cappedScript(stack.backgrounds[index].script)
        }

        // Permanent scriptIDs: keep valid unique ones, then assign the
        // missing or duplicated from above the maximum. This also migrates
        // stacks from before scriptIDs existed.
        var usedScriptIDs = Set<Int>()
        var maxScriptID = 0
        func validated(_ id: Int) -> Int {
            guard id > 0, !usedScriptIDs.contains(id) else { return 0 }
            usedScriptIDs.insert(id)
            maxScriptID = max(maxScriptID, id)
            return id
        }
        for index in stack.backgrounds.indices {
            stack.backgrounds[index].scriptID = validated(stack.backgrounds[index].scriptID)
            for partIndex in stack.backgrounds[index].parts.indices {
                stack.backgrounds[index].parts[partIndex].scriptID = validated(stack.backgrounds[index].parts[partIndex].scriptID)
            }
        }
        for index in stack.cards.indices {
            stack.cards[index].scriptID = validated(stack.cards[index].scriptID)
            for partIndex in stack.cards[index].parts.indices {
                stack.cards[index].parts[partIndex].scriptID = validated(stack.cards[index].parts[partIndex].scriptID)
            }
        }
        var nextAssignable = maxScriptID + 1
        func assigned() -> Int {
            defer { nextAssignable += 1 }
            return nextAssignable
        }
        for index in stack.backgrounds.indices {
            if stack.backgrounds[index].scriptID == 0 { stack.backgrounds[index].scriptID = assigned() }
            for partIndex in stack.backgrounds[index].parts.indices where stack.backgrounds[index].parts[partIndex].scriptID == 0 {
                stack.backgrounds[index].parts[partIndex].scriptID = assigned()
            }
        }
        for index in stack.cards.indices {
            if stack.cards[index].scriptID == 0 { stack.cards[index].scriptID = assigned() }
            for partIndex in stack.cards[index].parts.indices where stack.cards[index].parts[partIndex].scriptID == 0 {
                stack.cards[index].parts[partIndex].scriptID = assigned()
            }
        }
        stack.nextID = max(stack.nextID, nextAssignable)

        return stack
    }

    private func sanitizedParts(_ parts: [Part], cardSize: CardSize, uniqued: (UUID) -> UUID) -> [Part] {
        parts.map { part in
            var part = part
            part.id = uniqued(part.id)
            part.script = Self.cappedScript(part.script)
            var frame = part.frame
            if !frame.x.isFinite { frame.x = 0 }
            if !frame.y.isFinite { frame.y = 0 }
            if !frame.width.isFinite { frame.width = 100 }
            if !frame.height.isFinite { frame.height = 44 }
            frame.width = min(max(frame.width, 16), cardSize.width)
            frame.height = min(max(frame.height, 16), cardSize.height)
            frame.x = min(max(frame.x, 0), cardSize.width - 16)
            frame.y = min(max(frame.y, 0), cardSize.height - 16)
            part.frame = frame
            return part
        }
    }

    /// A script longer than any plausible hand-written one is truncated
    /// rather than fed to the tokenizer wholesale.
    private static func cappedScript(_ script: String) -> String {
        script.count > 1_000_000 ? String(script.prefix(1_000_000)) : script
    }
}

// MARK: - Assets

nonisolated extension Stack {
    /// Every asset name the stack still references; unreferenced assets
    /// are dropped at save time.
    func referencedAssetNames() -> Set<String> {
        var names: Set<String> = []
        for card in cards {
            if let paint = card.paintDrawingAsset { names.insert(paint) }
            if let paint = card.paintImageAsset { names.insert(paint) }
            for part in card.parts {
                if case .image(let image) = part.kind { names.insert(image.assetName) }
            }
        }
        for background in backgrounds {
            if let paint = background.paintDrawingAsset { names.insert(paint) }
            if let paint = background.paintImageAsset { names.insert(paint) }
            for part in background.parts {
                if case .image(let image) = part.kind { names.insert(image.assetName) }
            }
        }
        return names
    }
}
