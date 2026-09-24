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
    /// The image's true size in pixels. `NSImage.size` (and `UIImage.size`)
    /// report *points*, which a DPI tag scales away from the pixel count —
    /// so a 1024×768 image tagged 144 dpi would otherwise measure 512×384.
    var pixelSize: CGSize {
        #if canImport(UIKit)
        CGSize(width: size.width * scale, height: size.height * scale)
        #elseif canImport(AppKit)
        let pixelDimensions = representations
            .map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) }
            .filter { $0.width > 0 && $0.height > 0 }
        return pixelDimensions.max { $0.width * $0.height < $1.width * $1.height } ?? size
        #endif
    }

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

// MARK: - Delete key (macOS)

#if os(macOS)
/// A local key-down monitor for the Delete key. SwiftUI's focus-scoped
/// `onKeyPress` never receives the key here (the card's part gestures own
/// focus), so we watch the event stream directly — while deferring to text
/// editing so Delete still erases characters in a focused field.
struct DeleteKeyCatcher: NSViewRepresentable {
    var isEnabled: Bool
    var onDelete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.onDelete = onDelete
        context.coordinator.isEnabled = isEnabled
        context.coordinator.install()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDelete = onDelete
        context.coordinator.isEnabled = isEnabled
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var onDelete: (() -> Void)?
        var isEnabled = false
        private var monitor: Any?

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled else { return event }
                // 51 = Delete (backspace), 117 = forward delete.
                guard event.keyCode == 51 || event.keyCode == 117 else { return event }
                // Leave text editing alone: a focused field editor keeps the key.
                if let responder = event.window?.firstResponder,
                   responder is NSText || responder is NSTextView {
                    return event
                }
                self.onDelete?()
                return nil
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif

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
