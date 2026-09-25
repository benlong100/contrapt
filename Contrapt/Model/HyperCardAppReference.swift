//
//  HyperCardAppReference.swift
//  Contrapt
//
//  Remembers the HyperCard application the user points us at, so the legacy
//  importer can resolve button ICON resources from it. Stored as a security-
//  scoped bookmark (the app lives outside our sandbox). Contrapt ships no
//  Apple icons; they come from the user's own copy at import time.
//

import Foundation

enum HyperCardAppReference {
    private static let key = "hyperCardAppBookmark"

    /// The remembered HyperCard app, if one was chosen and still resolves.
    static func url() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        guard let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        return url
    }

    /// Remember `url` (a HyperCard application) for future imports.
    static func save(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        guard let data = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
