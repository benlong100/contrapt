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

@MainActor
final class StackLibrary {
    static let shared = StackLibrary()

    private let key = "stackLibraryBookmarks"

    /// Stored name → bookmark data. Names are the file's base name, lowercased
    /// for case-insensitive lookup (as HyperCard resolves stack names).
    private var bookmarks: [String: Data] {
        get { (UserDefaults.standard.dictionary(forKey: key) as? [String: Data]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The known stack names, for a launcher/recents list.
    var names: [String] { bookmarks.keys.sorted() }

    /// Remember a stack file by its base name, so `go stack "<name>"` finds it.
    func register(url: URL) {
        let name = Self.name(for: url)
        guard !name.isEmpty else { return }
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

    /// The lookup key for a file: its base name without extension, lowercased.
    static func name(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.lowercased()
    }
}
