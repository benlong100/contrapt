//
//  HelpStacks.swift
//  Contrapt
//
//  Help content is itself made of stacks (help-as-stacks): authored in
//  Contrapt, checked into the repo, and shipped in the app bundle. Opening
//  one copies it to a throwaway location first, so the bundle stays pristine
//  and any edits the user makes to the help vanish with the temp copy.
//
//  To update a help stack: open the repo's .contrapt in Contrapt, edit,
//  save — the synchronized project folder bundles it on the next build.
//

import Foundation

nonisolated enum HelpStacks {
    /// The bundled help stacks' resource names.
    static let whatsNew = "Whats New in HyperTalk"
    static let importing = "How to Import HyperCard Stacks"

    /// A fresh, disposable copy of a bundled help stack, ready to open like
    /// any document. Nil when the resource is missing from the bundle.
    static func freshCopy(of resourceName: String) -> URL? {
        guard let seed = Bundle.main.url(forResource: resourceName, withExtension: "contrapt") else {
            return nil
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HelpStacks-" + UUID().uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent(seed.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: seed, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
