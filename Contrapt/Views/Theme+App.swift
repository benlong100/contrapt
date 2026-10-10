//
//  Theme+App.swift
//  Contrapt
//
//  The app-side resolution of a stack's ThemeSpec into SwiftUI colors, and the
//  Environment plumbing that carries it to the card's chrome (surface, ink,
//  accent, borders, button hilite). Classic resolves to the exact platform
//  semantic colors the app already used, so a classic stack is byte-identical —
//  themes are purely additive.
//

import SwiftUI
import HyperTalk

/// A stack theme resolved to concrete colors for rendering. Built from the
/// shared `ThemeSpec` catalog; Classic (`followsSystem`) delegates to the
/// platform semantic colors so nothing changes for unthemed stacks.
struct ResolvedTheme: Equatable {
    let spec: ThemeSpec

    init(_ spec: ThemeSpec) { self.spec = spec }
    init(named name: String) { self.spec = ThemeSpec.named(name) }

    var surface: Color { spec.followsSystem ? .cardSurface : Color(stackColor: spec.surface) }
    var ink: Color { spec.followsSystem ? .cardInk : Color(stackColor: spec.ink) }
    var accent: Color { spec.followsSystem ? .accentColor : Color(stackColor: spec.accent) }
    var border: Color { spec.followsSystem ? .fieldStroke : Color(stackColor: spec.border) }
    /// The surround behind the card; nil (Classic) keeps the existing desktop.
    var paddingColor: Color? { spec.followsSystem ? nil : Color(stackColor: spec.padding) }
    var cornerRadius: CGFloat { spec.cornerRadius }
    var inverseHilite: Bool { spec.inverseHilite }

    /// A forced light/dark appearance for modern themes so nested SwiftUI
    /// controls match; nil (Classic) follows the system.
    var colorScheme: ColorScheme? {
        switch spec.name {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    static let classic = ResolvedTheme(.classic)
}

private struct StackThemeKey: EnvironmentKey {
    static let defaultValue = ResolvedTheme.classic
}

extension EnvironmentValues {
    /// The current stack's resolved theme, read by the card's chrome views.
    var stackTheme: ResolvedTheme {
        get { self[StackThemeKey.self] }
        set { self[StackThemeKey.self] = newValue }
    }
}

extension View {
    /// Forces a light/dark appearance on the subtree for modern themes so
    /// semantic text colors (`.primary`, dynamic system colors) read correctly
    /// on the themed surface. A nil scheme (Classic) follows the system.
    @ViewBuilder
    func themedColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme { environment(\.colorScheme, scheme) } else { self }
    }
}
