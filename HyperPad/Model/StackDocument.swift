//
//  StackDocument.swift
//  HyperPad
//

import Combine // required for @Published / ReferenceFileDocument's ObservableObject
import SwiftUI
import UniformTypeIdentifiers

nonisolated extension UTType {
    /// Placeholder identifier and extension — finalized together with the
    /// product name at first external distribution (DECISIONS.md N1/N2).
    static let cardStack = UTType(exportedAs: "com.trompingmarmots.cardstack")
}

/// What gets written: the manifest plus the assets it references.
nonisolated struct StackFileSnapshot: Sendable {
    let stack: Stack
    let assets: [String: Data]
}

/// The document wrapper around a `Stack`. A reference document so edits
/// register undo actions — which is also how SwiftUI learns the document
/// is dirty. On disk a stack is a flat store-only zip (D4): `stack.json`
/// plus `assets/*`; development-era plain-JSON stacks remain readable.
nonisolated final class StackDocument: ReferenceFileDocument {
    @Published var stack: Stack
    /// Media assets by name (image bytes, later paint and sounds). Asset
    /// bytes aren't undo-tracked; the parts referencing them are, and
    /// unreferenced assets are dropped at save time.
    @Published var assets: [String: Data] = [:]

    /// Bursts of changes (a drag, a typing run) coalesce into one undo step:
    /// the burst's opening snapshot is stashed here and registered when the
    /// burst ends — either because a gap opens between changes, or because
    /// the owning view's quiet-period flush fires.
    private var pendingUndoSnapshot: Stack?
    private var lastChangeAt: Date?
    private static let coalescingWindow: TimeInterval = 0.8

    static var readableContentTypes: [UTType] { [.cardStack] }

    init(stack: Stack = .makeNew()) {
        self.stack = stack
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if data.starts(with: [0x50, 0x4B]) { // "PK": the zip container
            let entries = try ZipArchive.extract(data)
            guard let manifest = entries["stack.json"] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            stack = try Stack(fileData: manifest)
            var loaded: [String: Data] = [:]
            for (name, bytes) in entries where name.hasPrefix("assets/") {
                loaded[String(name.dropFirst("assets/".count))] = bytes
            }
            assets = loaded
        } else {
            // Legacy development-era plain JSON.
            stack = try Stack(fileData: data)
        }
    }

    func snapshot(contentType: UTType) throws -> StackFileSnapshot {
        StackFileSnapshot(stack: stack, assets: assets)
    }

    func fileWrapper(snapshot: StackFileSnapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        var entries: [String: Data] = ["stack.json": try snapshot.stack.fileData()]
        let referenced = snapshot.stack.referencedAssetNames()
        for (name, data) in snapshot.assets where referenced.contains(name) {
            entries["assets/\(name)"] = data
        }
        return FileWrapper(regularFileWithContents: ZipArchive.archive(entries))
    }

    /// Stores asset bytes under a fresh name and returns it, sniffing the
    /// extension (unless one is given) so unzipped stacks stay
    /// human-friendly.
    func storeAsset(_ data: Data, preferredExtension: String? = nil) -> String {
        let ext: String = if let preferredExtension {
            preferredExtension
        } else if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            "png"
        } else if data.starts(with: [0xFF, 0xD8]) {
            "jpg"
        } else {
            "dat"
        }
        let name = UUID().uuidString.lowercased() + "." + ext
        assets[name] = data
        return name
    }

    // MARK: - Mutation choke point

    /// Every edit flows through here: assigns the new stack and arranges
    /// undo. Rapid successive changes coalesce into a single undo step that
    /// restores the state at the start of the burst. Because every undo
    /// action restores a complete document snapshot, interleavings stay
    /// self-consistent even in edge cases.
    func replaceStack(_ newStack: Stack, undoManager: UndoManager?) {
        guard newStack != stack else { return }
        let before = stack
        stack = newStack
        guard let undoManager else { return }

        // Undo and redo re-enter here; their registrations are what make
        // redo (and re-undo) work, and must never be coalesced.
        if undoManager.isUndoing || undoManager.isRedoing {
            pendingUndoSnapshot = nil
            undoManager.registerUndo(withTarget: self) { document in
                document.replaceStack(before, undoManager: undoManager)
            }
            return
        }

        let now = Date()
        if let lastChangeAt, now.timeIntervalSince(lastChangeAt) < Self.coalescingWindow {
            // Mid-burst: keep the burst's opening snapshot.
            if pendingUndoSnapshot == nil { pendingUndoSnapshot = before }
        } else {
            // A gap ended any previous burst; this change starts a new one.
            flushPendingUndo(with: undoManager)
            pendingUndoSnapshot = before
        }
        lastChangeAt = now
    }

    /// Registers the pending burst's opening snapshot as one undo action.
    /// The owning view calls this after a quiet period; it is also called
    /// when a new burst begins.
    func flushPendingUndo(with undoManager: UndoManager?) {
        guard let before = pendingUndoSnapshot else { return }
        pendingUndoSnapshot = nil
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { document in
            document.replaceStack(before, undoManager: undoManager)
        }
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

    /// A new stack: one background and two starter cards whose parts carry
    /// real HyperTalk (D9) — the template doubles as a first lesson.
    /// Every stack keeps at least one background and one card.
    static func makeNew() -> Stack {
        let background = Background(
            id: UUID(),
            name: "Background 1",
            script: "",
            parts: [
                Part(
                    id: UUID(),
                    name: "Next Card Button",
                    frame: PartFrame(x: 824, y: 668, width: 160, height: 60),
                    script: """
                    on mouseUp
                      go to next card
                    end mouseUp
                    """,
                    kind: .button(ButtonPart(title: "Next Card"))
                )
            ]
        )
        let firstCard = Card(
            id: UUID(),
            name: "Card 1",
            backgroundID: background.id,
            script: "",
            parts: [
                Part(
                    id: UUID(),
                    name: "Welcome Label",
                    frame: PartFrame(x: 64, y: 64, width: 640, height: 60),
                    script: "",
                    kind: .label(LabelPart(text: "Welcome to your new stack"))
                ),
                Part(
                    id: UUID(),
                    name: "Name",
                    frame: PartFrame(x: 64, y: 160, width: 520, height: 56),
                    script: "",
                    kind: .field(FieldPart(text: "", placeholder: "Type your name…"))
                ),
                Part(
                    id: UUID(),
                    name: "Greet Button",
                    frame: PartFrame(x: 64, y: 240, width: 160, height: 56),
                    script: """
                    on mouseUp
                      if field "Name" is empty then
                        put "Hello, stranger!" into field "Greeting"
                      else
                        put "Hello," && field "Name" & "!" into field "Greeting"
                      end if
                    end mouseUp
                    """,
                    kind: .button(ButtonPart(title: "Greet"))
                ),
                Part(
                    id: UUID(),
                    name: "Greeting",
                    frame: PartFrame(x: 64, y: 320, width: 520, height: 56),
                    script: "",
                    kind: .field(FieldPart(text: "", placeholder: ""))
                ),
            ]
        )
        let secondCard = Card(
            id: UUID(),
            name: "Card 2",
            backgroundID: background.id,
            script: """
            on openCard
              put "You've arrived at card 2"
            end openCard
            """,
            parts: [
                Part(
                    id: UUID(),
                    name: "Card 2 Label",
                    frame: PartFrame(x: 64, y: 64, width: 640, height: 60),
                    script: "",
                    kind: .label(LabelPart(text: "This is the second card"))
                ),
                Part(
                    id: UUID(),
                    name: "Back Button",
                    frame: PartFrame(x: 64, y: 160, width: 180, height: 56),
                    script: """
                    on mouseUp
                      go to first card
                    end mouseUp
                    """,
                    kind: .button(ButtonPart(title: "Back to Start"))
                ),
            ]
        )
        return Stack(
            formatVersion: StackFormat.currentVersion,
            id: UUID(),
            name: "Untitled Stack",
            cardSize: CardSize(width: 1024, height: 768),
            script: "",
            backgrounds: [background],
            cards: [firstCard, secondCard]
        )
    }
}
