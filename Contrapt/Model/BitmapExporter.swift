//
//  BitmapExporter.swift
//  Contrapt
//
//  Exports a stack's card and background paint bitmaps as named PNG files,
//  and replaces them from a folder of same-named files — the round trip that
//  lets imported HyperCard art be upscaled in an external tool and brought
//  back in. File names carry the owner's permanent scriptID ("card 3 id
//  17.png"), so replacements match by ID even if cards are renamed or
//  reordered between export and replace.
//

import Foundation

nonisolated enum BitmapExporter {
    struct BitmapError: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// A filesystem-safe base name for the exported folder (no path separators).
    static func folderName(for stack: Stack) -> String {
        WebsiteExporter.sanitizedFolderName(stack.name.isEmpty ? "Stack" : stack.name) + " Bitmaps"
    }

    /// The exported files as name → PNG bytes: one entry per card and
    /// background that has a paint image.
    static func entries(stack: Stack, assets: [String: Data]) -> [String: Data] {
        var entries: [String: Data] = [:]
        for (index, background) in stack.backgrounds.enumerated() {
            if let asset = background.paintImageAsset, let data = assets[asset] {
                entries["background \(index + 1) id \(background.scriptID).png"] = data
            }
        }
        for (index, card) in stack.cards.enumerated() {
            if let asset = card.paintImageAsset, let data = assets[asset] {
                entries["card \(index + 1) id \(card.scriptID).png"] = data
            }
        }
        return entries
    }

    /// Writes the stack's bitmaps into a "<Name> Bitmaps" folder inside
    /// `parentDirectory`, returning the created folder.
    @discardableResult
    static func export(stack: Stack, assets: [String: Data], into parentDirectory: URL) throws -> URL {
        let files = entries(stack: stack, assets: assets)
        guard !files.isEmpty else {
            throw BitmapError(message: "This stack has no card or background bitmaps to export.")
        }
        let fm = FileManager.default
        let folder = parentDirectory.appendingPathComponent(folderName(for: stack), isDirectory: true)
        // Fresh folder each export so stale bitmaps don't linger.
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, data) in files {
            try data.write(to: folder.appendingPathComponent(name))
        }
        return folder
    }

    /// The outcome of scanning a replacement folder: the stack with its paint
    /// images swapped to fresh assets, the new asset bytes to store, and the
    /// PNG files that didn't match anything.
    struct Replacement {
        var stack: Stack
        var newAssets: [String: Data]
        var replaced: Int
        var unmatched: [String]
    }

    /// Reads `directory`'s PNG files, matches each to a card or background by
    /// the scriptID in its name, and returns the stack with those paint
    /// images pointing at fresh assets (so the change is a normal, undoable
    /// stack edit; the old assets are pruned at save). Any PencilKit drawing
    /// is left alone — editing paint afterwards re-renders from the drawing
    /// and would discard the replacement, but imported stacks carry images
    /// only, so in practice there is none.
    static func replacements(for stack: Stack, from directory: URL) throws -> Replacement {
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var updated = stack
        var newAssets: [String: Data] = [:]
        var replaced = 0
        var unmatched: [String] = []
        for file in files {
            guard let (isCard, scriptID) = parseName(file.lastPathComponent),
                  let data = try? Data(contentsOf: file) else {
                unmatched.append(file.lastPathComponent)
                continue
            }
            let assetName = UUID().uuidString.lowercased() + ".png"
            if isCard, let index = updated.cards.firstIndex(where: { $0.scriptID == scriptID }) {
                updated.cards[index].paintImageAsset = assetName
            } else if !isCard, let index = updated.backgrounds.firstIndex(where: { $0.scriptID == scriptID }) {
                updated.backgrounds[index].paintImageAsset = assetName
            } else {
                unmatched.append(file.lastPathComponent)
                continue
            }
            newAssets[assetName] = data
            replaced += 1
        }
        guard replaced > 0 else {
            throw BitmapError(message: "No matching bitmap files were found. Expected PNG files named as exported, like “card 1 id 12.png”.")
        }
        return Replacement(stack: updated, newAssets: newAssets, replaced: replaced, unmatched: unmatched)
    }

    /// Parses an exported file name — "card 3 id 17.png" → (card: true, 17).
    /// Nil if the name doesn't fit the exported pattern.
    private static func parseName(_ filename: String) -> (isCard: Bool, scriptID: Int)? {
        let base = (filename as NSString).deletingPathExtension.lowercased()
        guard let idRange = base.range(of: " id ", options: .backwards),
              let scriptID = Int(base[idRange.upperBound...].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        if base.hasPrefix("card") { return (true, scriptID) }
        if base.hasPrefix("background") { return (false, scriptID) }
        return nil
    }
}
