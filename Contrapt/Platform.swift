//
//  Platform.swift
//  Contrapt
//
//  The thin seam between iOS and macOS (D2). SwiftUI carries most of the
//  app across unchanged; this file holds the handful of places where the
//  underlying UIKit/AppKit APIs differ.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

// MARK: - Images

extension PlatformImage {
    /// PNG bytes, however the platform spells it.
    var pngDataCrossPlatform: Data? {
        #if canImport(UIKit)
        pngData()
        #elseif canImport(AppKit)
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #endif
    }
}

extension Image {
    /// Builds a SwiftUI image from asset bytes, nil if undecodable.
    init?(assetData data: Data) {
        guard let image = PlatformImage(data: data) else { return nil }
        #if canImport(UIKit)
        self.init(uiImage: image)
        #elseif canImport(AppKit)
        self.init(nsImage: image)
        #endif
    }
}

// MARK: - Semantic colors

extension Color {
    /// The card surface and field backgrounds — the window's base fill.
    static var cardSurface: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .textBackgroundColor)
        #endif
    }

    /// The backdrop behind the card.
    static var cardBackdrop: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// A field's hairline border.
    static var fieldStroke: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGray4)
        #elseif canImport(AppKit)
        Color(nsColor: .separatorColor)
        #endif
    }

    /// Placeholder text in an empty field.
    static var placeholderTextColor: Color {
        #if canImport(UIKit)
        Color(uiColor: .placeholderText)
        #elseif canImport(AppKit)
        Color(nsColor: .placeholderTextColor)
        #endif
    }
}

// MARK: - View modifier seams

extension View {
    /// Inline navigation title on iOS; a no-op where the modifier is absent.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Code-entry field traits (no autocapitalization) where supported.
    func codeEntryTraits() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// Numeric-punctuation keyboard on iOS; a no-op elsewhere.
    func numericPunctuationKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }

    /// A cover presentation: full-screen on iOS, a sheet on macOS (which
    /// has no full-screen cover). Used for paint and the large editor.
    @ViewBuilder
    func platformFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }
}
