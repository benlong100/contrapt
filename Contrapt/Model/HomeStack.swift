//
//  HomeStack.swift
//  Contrapt
//

import Foundation

/// The Home stack: a durable, editable starting point that lives with the
/// app. We keep the document-based architecture — Home is simply a stack
/// the app knows how to seed and open.
///
/// Seed-and-copy: the app bundle may ship a read-only `Home.contrapt` as
/// the pristine seed; on first launch it's copied to a writable spot in
/// Application Support, and that working copy is the user's Home forever
/// after (editable, autosaved like any stack). If no bundled seed exists,
/// a generated starter is written instead — so authoring a real Home and
/// adding it to the app target later just works, with no code change.
nonisolated enum HomeStack {
    /// The user's editable Home, in app-owned storage.
    static var workingURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Contrapt", isDirectory: true)
        return directory.appendingPathComponent("Home.contrapt")
    }

    /// Ensures a writable Home exists, seeding it on first launch. Returns
    /// the URL to open.
    @discardableResult
    static func ensureSeeded() -> URL {
        let url = workingURL
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: url.path) else { return url }

        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let seed = Bundle.main.url(forResource: "Home", withExtension: "contrapt"),
           let data = try? Data(contentsOf: seed) {
            try? data.write(to: url)
        } else {
            try? defaultHomeData().write(to: url)
        }
        return url
    }

    /// Rewrites Home from the seed/default, discarding the user's edits.
    static func reset() {
        try? FileManager.default.removeItem(at: workingURL)
        ensureSeeded()
    }

    /// A `.contrapt` archive for the generated starter Home.
    private static func defaultHomeData() -> Data {
        let manifest = (try? Stack.home().fileData()) ?? Data()
        return ZipArchive.archive(["stack.json": manifest])
    }
}

nonisolated extension Stack {
    /// The generated starter Home — a friendly welcome for first-time
    /// users, meant to be edited (or replaced by a bundled seed).
    static func home() -> Stack {
        let backgroundID = UUID()
        let background = Background(id: UUID(), name: "Home Background", script: "", parts: [])
        let card = Card(
            id: UUID(),
            name: "Home",
            backgroundID: backgroundID,
            script: "",
            parts: [
                Part(
                    id: UUID(), name: "Title",
                    frame: PartFrame(x: 64, y: 80, width: 896, height: 70),
                    script: "", kind: .label(LabelPart(text: "Welcome to Contrapt"))
                ),
                Part(
                    id: UUID(), name: "Intro",
                    frame: PartFrame(x: 64, y: 170, width: 896, height: 180),
                    script: "",
                    kind: .field(FieldPart(
                        text: """
                        This is your Home stack — a place that's always here, and yours to change.

                        Tap Edit to add buttons, fields, and art, or to read how anything works. Make Home a launcher, a notebook, a front door — whatever you like.
                        """,
                        placeholder: "",
                        isMultiline: true
                    ))
                ),
                Part(
                    id: UUID(), name: "Guide Hint",
                    frame: PartFrame(x: 64, y: 380, width: 896, height: 60),
                    script: "", kind: .label(LabelPart(text: "New here? Open the HyperTalk Guide from the toolbar."))
                ),
            ]
        )
        var background2 = background
        background2.id = backgroundID
        return Stack(
            formatVersion: StackFormat.currentVersion,
            id: UUID(),
            name: "Home",
            cardSize: CardSize(width: 1024, height: 768),
            script: "",
            backgrounds: [background2],
            cards: [card]
        ).sanitized()
    }
}
