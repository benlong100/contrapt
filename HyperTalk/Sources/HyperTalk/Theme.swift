//
//  Theme.swift
//  HyperTalk
//
//  A small set of built-in visual themes a stack can adopt
//  (`set the theme of this stack to "dark"`). Pure, presentation-agnostic data:
//  the native app maps a spec to SwiftUI colors/fonts and the web export maps it
//  to CSS variables, so the catalog is defined — and unit-tested — once here and
//  shared by both runtimes. "Classic" is a no-op that keeps today's look.
//

import Foundation

public struct ThemeSpec: Equatable, Sendable {
    /// Canonical name, as stored on the stack and read by `the theme`.
    public let name: String
    /// Human label for the inspector.
    public let displayName: String
    /// When true (Classic), renderers keep their existing defaults and adapt to
    /// the OS (system light/dark) rather than forcing the palette below — so a
    /// classic stack looks exactly as it did before themes existed.
    public let followsSystem: Bool
    /// Palette as #RRGGBB (ignored when `followsSystem`).
    public let surface: String   // card background
    public let ink: String       // default text / 1-bit line color
    public let accent: String    // buttons & links when a card sets no highlightColor
    public let border: String    // field & button borders
    public let padding: String   // letterbox behind the card
    /// Part corner rounding in points (classic ≈ 0; modern ≈ 6).
    public let cornerRadius: Double
    /// Classic inverse-video button hilite (true) vs a modern filled hilite.
    public let inverseHilite: Bool
    /// Keep classic font substitution (false) or prefer a modern sans family.
    public let usesModernFont: Bool
}

public extension ThemeSpec {
    static let classic = ThemeSpec(
        name: "classic", displayName: "Classic", followsSystem: true,
        surface: "#FFFFFF", ink: "#000000", accent: "#0000FF", border: "#000000",
        padding: "#000000", cornerRadius: 0, inverseHilite: true, usesModernFont: false)

    static let light = ThemeSpec(
        name: "light", displayName: "Modern Light", followsSystem: false,
        surface: "#FFFFFF", ink: "#1C1C1E", accent: "#007AFF", border: "#D1D1D6",
        padding: "#F2F2F7", cornerRadius: 6, inverseHilite: false, usesModernFont: true)

    static let dark = ThemeSpec(
        name: "dark", displayName: "Dark", followsSystem: false,
        surface: "#1C1C1E", ink: "#F2F2F7", accent: "#0A84FF", border: "#3A3A3C",
        padding: "#000000", cornerRadius: 6, inverseHilite: false, usesModernFont: true)

    /// Every selectable theme, in inspector order.
    static let all: [ThemeSpec] = [.classic, .light, .dark]

    /// Resolve a stored/scripted theme name (case-insensitive, with a few
    /// friendly aliases) to a spec. Unknown / empty / nil → Classic.
    static func named(_ raw: String?) -> ThemeSpec {
        switch (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased() {
        case "light", "modern", "modern light": return .light
        case "dark", "modern dark": return .dark
        default: return .classic
        }
    }

    /// The canonical stored name for a raw value — what `the theme` reads back
    /// after a `set` (so an alias or unknown value normalizes).
    static func canonicalName(_ raw: String?) -> String { named(raw).name }
}
