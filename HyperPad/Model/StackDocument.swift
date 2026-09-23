//
//  StackDocument.swift
//  HyperPad
//

import SwiftUI
import UniformTypeIdentifiers

nonisolated extension UTType {
    /// Placeholder identifier and extension — finalized together with the
    /// product name at first external distribution (DECISIONS.md N1/N2).
    static let cardStack = UTType(exportedAs: "com.trompingmarmots.cardstack")
}

/// The SwiftUI document wrapper around a `Stack`. Value-semantic; the zip
/// container for media assets arrives in Phase 6 — until then a stack file
/// is the JSON manifest alone.
nonisolated struct StackDocument: FileDocument {
    var stack: Stack

    static var readableContentTypes: [UTType] { [.cardStack] }

    init(stack: Stack = .makeNew()) {
        self.stack = stack
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        stack = try Stack(fileData: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try stack.fileData())
    }
}

// MARK: - Serialization

nonisolated enum StackFileError: LocalizedError {
    case newerFormat(version: Int)

    var errorDescription: String? {
        switch self {
        case .newerFormat(let version):
            "This stack uses format version \(version), which requires a newer version of the app."
        }
    }
}

nonisolated extension Stack {
    /// Decodes a stack from file data. Received stacks are untrusted input
    /// (D4/D7): decoding is strict and gated on format version.
    init(fileData: Data) throws {
        let stack = try JSONDecoder().decode(Stack.self, from: fileData)
        guard stack.formatVersion <= StackFormat.currentVersion else {
            throw StackFileError.newerFormat(version: stack.formatVersion)
        }
        self = stack
    }

    /// Encodes deterministically (sorted keys, pretty printed) so stack files
    /// diff cleanly and remain human-readable.
    func fileData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// A new stack: one background, one card — the invariant every stack keeps.
    static func makeNew() -> Stack {
        let background = Background(id: UUID(), name: "Background 1", script: "", parts: [])
        let card = Card(id: UUID(), name: "Card 1", backgroundID: background.id, script: "", parts: [])
        return Stack(
            formatVersion: StackFormat.currentVersion,
            id: UUID(),
            name: "Untitled Stack",
            cardSize: CardSize(width: 1024, height: 768),
            script: "",
            backgrounds: [background],
            cards: [card]
        )
    }
}
