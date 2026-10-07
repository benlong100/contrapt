//
//  StackLibrary.swift
//  Contrapt
//
//  A registry of stacks the user has opened or imported, so a script's
//  `go stack "Phone"` can resolve a bare name to a file — the app can't
//  freely browse the sandbox, so each entry is a security-scoped bookmark.
//  Doubles as a launcher/recents source (see `entries`).
//

import Foundation
import HyperTalk

@MainActor
final class StackLibrary {
    static let shared = StackLibrary()

    private let key = "stackLibraryBookmarks"
    private let folderKey = "stackLibraryFolderBookmarks"
    /// Granted folders are re-opened once per session, lazily, on the first
    /// name lookup that misses.
    private var didRehydrateFolders = false

    /// In-session name → URL, remembered on every `register`. A fast path that
    /// resolves without a bookmark round-trip and works even where security-
    /// scoped bookmarking can't (e.g. a non-user-selected file). Not persisted;
    /// the bookmarks below carry names across launches.
    private var urls: [String: URL] = [:]

    /// In-session record of which registered stacks are classic (data-fork
    /// STAK) and the import size chosen for them, so cross-stack navigation can
    /// re-import a sibling in place at the same size it was first opened at.
    /// The most recent value also seeds on-the-fly imports of siblings the
    /// user later locates by hand (`lastClassicActualSize`).
    private var classicSizes: [String: Bool] = [:]
    private(set) var lastClassicActualSize = false

    /// Stored name → bookmark data. Names are the file's base name, lowercased
    /// for case-insensitive lookup (as HyperCard resolves stack names).
    private var bookmarks: [String: Data] {
        get { (UserDefaults.standard.dictionary(forKey: key) as? [String: Data]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Security-scoped bookmarks to folders the user granted (a multi-file
    /// stack's containing folder). Under the App Sandbox a single-file grant
    /// doesn't let us enumerate its folder, so each sibling would otherwise
    /// need its own prompt; a folder grant covers every stack inside and, being
    /// a user-selected directory, both persists and survives relaunches.
    private var folderBookmarks: [Data] {
        get { (UserDefaults.standard.array(forKey: folderKey) as? [Data]) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: folderKey) }
    }

    /// The known stack names, for a launcher/recents list.
    var names: [String] { bookmarks.keys.sorted() }

    /// Remember a stack file by its base name, so `go stack "<name>"` finds it.
    /// `classicActualSize` records (for a classic STAK) the import size to reuse
    /// when cross-navigation re-imports it in place.
    func register(url: URL, classicActualSize: Bool? = nil) {
        let name = Self.name(for: url)
        guard !name.isEmpty else { return }
        urls[name] = url // in-session fast path, even if bookmarking fails below
        if let classicActualSize {
            classicSizes[name] = classicActualSize
            lastClassicActualSize = classicActualSize
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        guard let data = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        var updated = bookmarks
        updated[name] = data
        bookmarks = updated
    }

    /// Resolve a stack name to its file URL, if known and still reachable.
    /// The caller owns `startAccessingSecurityScopedResource()`.
    func url(forName name: String) -> URL? {
        if let url = urls[name.lowercased()] { return url } // in-session fast path
        // Re-open any granted folders once; a multi-file stack's siblings become
        // resolvable without a fresh prompt.
        if !didRehydrateFolders {
            rehydrateFolders()
            if let url = urls[name.lowercased()] { return url }
        }
        guard let data = bookmarks[name.lowercased()] else { return nil }
        var isStale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        guard let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        // Refresh a stale bookmark opportunistically.
        if isStale { register(url: url) }
        return url
    }

    /// The import size recorded for a classic stack name (false = fill window).
    func actualSize(forName name: String) -> Bool {
        classicSizes[name.lowercased()] ?? lastClassicActualSize
    }

    /// Registers every classic sibling stack in `url`'s folder by name, so a
    /// multi-file stack (e.g. the Manhole's six files, whose rooms link across
    /// them with `go … of stack "the Manhole 2"`) can cross-navigate. Each
    /// sibling re-imports on demand at `actualSize`. Best-effort: the sandbox
    /// may not grant folder access from a single-file open, in which case the
    /// first cross-navigation falls back to the locate picker.
    func registerSiblings(of url: URL, actualSize: Bool) {
        let folder = url.deletingLastPathComponent()
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return }
        for entry in entries where Self.isClassicStack(at: entry) {
            register(url: entry, classicActualSize: actualSize)
        }
    }

    /// Grants access to a user-selected folder: holds its security scope for
    /// the session, registers every stack inside by name, and persists a
    /// bookmark so the grant survives relaunches. The sandbox-correct way to
    /// make a multi-file stack's siblings resolvable from one prompt.
    @discardableResult
    func grantFolder(_ url: URL) -> Int {
        _ = url.startAccessingSecurityScopedResource() // held for the session
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        if let data = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil) {
            var updated = folderBookmarks
            if !updated.contains(data) { updated.append(data); folderBookmarks = updated }
        }
        return registerStacks(in: url)
    }

    /// Registers every classic or `.contrapt` stack directly inside `folder` by
    /// name (the folder's security scope must already be held). Returns the
    /// count registered.
    @discardableResult
    private func registerStacks(in folder: URL) -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return 0 }
        var count = 0
        for entry in entries where Self.isClassicStack(at: entry) || entry.pathExtension.lowercased() == "contrapt" {
            let name = Self.name(for: entry)
            urls[name] = entry
            if classicSizes[name] == nil { classicSizes[name] = lastClassicActualSize }
            count += 1
        }
        return count
    }

    /// Re-opens previously granted folders (once per session) so their stacks
    /// resolve by name again without re-prompting.
    func rehydrateFolders() {
        guard !didRehydrateFolders else { return }
        didRehydrateFolders = true
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        for data in folderBookmarks {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale) else { continue }
            _ = url.startAccessingSecurityScopedResource() // held for the session
            registerStacks(in: url)
        }
    }

    /// Whether the file at `url` is a classic HyperCard stack (its data fork
    /// opens with a STAK block: `{u32 size, "STAK", …}`).
    static func isClassicStack(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 8), head.count == 8 else { return false }
        return String(bytes: head[4..<8], encoding: .ascii) == "STAK"
    }

    /// The lookup key for a file: its base name without extension, lowercased.
    static func name(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.lowercased()
    }
}

/// Bridges `go card N of stack "X"` across the open: the target card is
/// stashed by stack name here, then the opened stack's ContentView consumes
/// it on appear and navigates there. Works the same for a new macOS window
/// or the iOS layer, which both start a fresh ContentView at card 0.
@MainActor
final class PendingStackNavigation {
    static let shared = PendingStackNavigation()
    private var targets: [String: GoDestination] = [:]

    func set(name: String, card: GoDestination) {
        targets[name.lowercased()] = card
    }

    /// The pending card for a stack name, removing it (one-shot).
    func consume(name: String) -> GoDestination? {
        targets.removeValue(forKey: name.lowercased())
    }
}
