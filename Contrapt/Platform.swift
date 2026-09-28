//
//  Platform.swift
//  Contrapt
//
//  The thin seam between iOS and macOS (D2). SwiftUI carries most of the
//  app across unchanged; this file holds the handful of places where the
//  underlying UIKit/AppKit APIs differ.
//

import SwiftUI
import HyperTalk

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

// MARK: - Edit-mode key handling (macOS)

#if os(macOS)
/// A local key-down monitor for the selected part's editing keys: Delete
/// removes it; the arrow keys nudge it (1px, or 10px with Shift). SwiftUI's
/// focus-scoped `onKeyPress` never receives these here (the card's part
/// gestures own focus), so we watch the event stream directly — while
/// deferring to text editing so the keys work normally in a focused field.
struct EditKeyCatcher: NSViewRepresentable {
    var isEnabled: Bool
    var onDelete: () -> Void
    /// Move the selected part by (dx, dy) in card points.
    var onNudge: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        update(context)
        context.coordinator.install()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) { update(context) }

    private func update(_ context: Context) {
        context.coordinator.onDelete = onDelete
        context.coordinator.onNudge = onNudge
        context.coordinator.isEnabled = isEnabled
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var onDelete: (() -> Void)?
        var onNudge: ((CGFloat, CGFloat) -> Void)?
        var isEnabled = false
        private var monitor: Any?

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled else { return event }
                // Leave text editing alone: a focused field editor keeps the key.
                if let responder = event.window?.firstResponder,
                   responder is NSText || responder is NSTextView {
                    return event
                }
                switch event.keyCode {
                case 51, 117: // Delete (backspace), forward delete
                    self.onDelete?()
                    return nil
                case 123, 124, 125, 126: // ← → ↓ ↑
                    let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
                    let (dx, dy): (CGFloat, CGFloat) = switch event.keyCode {
                    case 123: (-step, 0)
                    case 124: (step, 0)
                    case 125: (0, step)   // down = +y in card coordinates
                    default: (0, -step)   // 126 up = -y
                    }
                    self.onNudge?(dx, dy)
                    return nil
                default:
                    return event
                }
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif

// MARK: - Message box toggle routing (macOS)

/// Posted by the AppDelegate's key monitor when plain Cmd-M is pressed (and by
/// the Go menu item's click). The key window's ContentView toggles its box.
extension Notification.Name {
    static let contraptToggleMessageBox = Notification.Name("contraptToggleMessageBox")
}

#if os(macOS)
/// Hands the hosting NSWindow to SwiftUI state, so app-wide events (the Cmd-M
/// monitor) can be routed to the key window's stack only.
struct WindowBinder: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in onWindow(view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in onWindow(nsView?.window) }
    }
}
#endif

// MARK: - Full-screen presentation (macOS)

#if os(macOS)
/// Drives true presentation mode: the window covers the whole screen with
/// its title bar hidden, and the menu bar and Dock are hidden — the stack
/// owns the screen, as classic HyperCard did. Escape leaves. Restores the
/// window exactly on exit.
struct StackPresentation: NSViewRepresentable {
    var isPresenting: Bool
    var paddingColor: Color
    var onExit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onExit = onExit
        let presenting = isPresenting
        let color = NSColor(paddingColor)
        DispatchQueue.main.async {
            context.coordinator.setPresenting(presenting, color: color, window: nsView.window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.setPresenting(false, color: nil, window: nil)
    }

    final class Coordinator {
        var onExit: () -> Void = {}
        private var isPresenting = false
        private weak var window: NSWindow?
        private var escapeMonitor: Any?
        private struct Saved {
            let styleMask: NSWindow.StyleMask
            let frame: NSRect
            let level: NSWindow.Level
            let backgroundColor: NSColor
            let isOpaque: Bool
            let toolbar: NSToolbar?
        }
        private var saved: Saved?

        func setPresenting(_ presenting: Bool, color: NSColor?, window newWindow: NSWindow?) {
            // Keep the fill in sync even when the presenting state is unchanged
            // (e.g. the padding color was edited while full-screen).
            if presenting, isPresenting, let color, let window {
                window.backgroundColor = color
            }
            guard presenting != isPresenting else { return }
            if presenting {
                guard let window = newWindow, let screen = window.screen ?? NSScreen.main else { return }
                self.window = window
                saved = Saved(
                    styleMask: window.styleMask, frame: window.frame, level: window.level,
                    backgroundColor: window.backgroundColor, isOpaque: window.isOpaque,
                    toolbar: window.toolbar
                )
                NSApp.presentationOptions = [.hideDock, .hideMenuBar]
                // Borderless so the window is square-cornered and edge-to-edge:
                // a titled window covering the screen shows its rounded corners
                // (desktop peeks through) and a titlebar hairline at the top.
                window.styleMask = [.borderless]
                // Paint the window itself so the whole screen is filled
                // immediately, before SwiftUI relays out to the new size.
                if let color {
                    window.isOpaque = true
                    window.backgroundColor = color
                }
                window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
                window.setFrame(screen.frame, display: true)
                window.makeKeyAndOrderFront(nil)
                installEscapeMonitor()
                isPresenting = true
            } else {
                NSApp.presentationOptions = []
                if let window = self.window, let saved {
                    window.styleMask = saved.styleMask
                    // Going borderless dropped the window's NSToolbar (SwiftUI's
                    // toolbar bridges to it); restoring the style mask alone
                    // doesn't bring it back, so reattach it.
                    if window.toolbar == nil { window.toolbar = saved.toolbar }
                    window.isOpaque = saved.isOpaque
                    window.backgroundColor = saved.backgroundColor
                    window.level = saved.level
                    window.setFrame(saved.frame, display: true)
                }
                saved = nil
                removeEscapeMonitor()
                isPresenting = false
            }
        }

        private func installEscapeMonitor() {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.keyCode == 53 else { return event } // 53 = Escape
                self.onExit()
                return nil
            }
        }

        private func removeEscapeMonitor() {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
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

// MARK: - Visual effects

extension ScreenEffect {
    /// The SwiftUI transition that renders this effect on a card swap.
    var transition: AnyTransition {
        switch kind {
        case .plain:
            return .identity
        case .dissolve:
            return .opacity
        case .iris, .barnDoor, .checkerboard, .venetianBlinds:
            // A growing shape mask reveals the incoming card layer (and masks
            // the outgoing one out) over the static background. Symmetric, so
            // it reads the same as the built-in dissolve does in this setup.
            return .modifier(
                active: EffectRevealModifier(progress: 0, kind: kind),
                identity: EffectRevealModifier(progress: 1, kind: kind)
            )
        case .wipe:
            switch direction {
            case .right: return .push(from: .leading)
            case .up: return .push(from: .bottom)
            case .down: return .push(from: .top)
            default: return .push(from: .trailing) // left, or unspecified
            }
        case .scroll:
            switch direction {
            case .right: return .move(edge: .leading)
            case .up: return .move(edge: .bottom)
            case .down: return .move(edge: .top)
            default: return .move(edge: .trailing)
            }
        case .zoom:
            return .scale.combined(with: .opacity)
        }
    }

    /// The timing curve and duration for this effect's speed.
    var animation: Animation {
        switch speed {
        case .verySlow: .easeInOut(duration: 1.3)
        case .slow: .easeInOut(duration: 0.9)
        case .normal: .easeInOut(duration: 0.5)
        case .fast: .easeInOut(duration: 0.28)
        case .veryFast: .easeInOut(duration: 0.12)
        }
    }
}

/// Applies an effect's reveal mask at a given progress (0 hidden → 1 shown).
/// Animatable, so the transition system tweens `progress`.
private struct EffectRevealModifier: ViewModifier, Animatable {
    var progress: CGFloat
    let kind: ScreenEffect.Kind

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.mask(EffectRevealShape(kind: kind, progress: progress).fill(style: FillStyle(eoFill: false)))
    }
}

/// The revealed region for a masked effect at `progress`: an iris circle, the
/// widening barn-door band, opening venetian slats, or growing checkerboard
/// tiles. progress 0 → empty (nothing shown), 1 → the full card.
private struct EffectRevealShape: Shape {
    let kind: ScreenEffect.Kind
    var progress: CGFloat

    func path(in rect: CGRect) -> Path {
        let p = max(0, min(1, progress))
        var path = Path()
        switch kind {
        case .iris:
            let radius = (hypot(rect.width, rect.height) / 2) * p
            path.addEllipse(in: CGRect(x: rect.midX - radius, y: rect.midY - radius,
                                       width: radius * 2, height: radius * 2))
        case .barnDoor:
            // A central vertical band widening to full width — doors opening.
            let width = rect.width * p
            path.addRect(CGRect(x: rect.midX - width / 2, y: rect.minY,
                                width: width, height: rect.height))
        case .venetianBlinds:
            let slats = 12
            let band = rect.height / CGFloat(slats)
            for i in 0..<slats {
                let y = rect.minY + CGFloat(i) * band
                path.addRect(CGRect(x: rect.minX, y: y, width: rect.width, height: band * p))
            }
        case .checkerboard:
            let columns = 8, rows = 6
            let cellW = rect.width / CGFloat(columns)
            let cellH = rect.height / CGFloat(rows)
            for row in 0..<rows {
                for column in 0..<columns {
                    let cx = rect.minX + (CGFloat(column) + 0.5) * cellW
                    let cy = rect.minY + (CGFloat(row) + 0.5) * cellH
                    path.addRect(CGRect(x: cx - cellW * p / 2, y: cy - cellH * p / 2,
                                        width: cellW * p, height: cellH * p))
                }
            }
        default:
            path.addRect(rect)
        }
        return path
    }
}

// MARK: - Stack colors

extension Color {
    /// Parses a stack color string — a color name (black, white, gray, …)
    /// or #RRGGBB / #RGB hex — falling back to black. Used for the stack's
    /// scriptable `paddingColor`.
    init(stackColor string: String) {
        let text = string.trimmingCharacters(in: .whitespaces).lowercased()
        // SwiftUI's built-in named colors…
        let named: [String: Color] = [
            "black": .black, "white": .white, "gray": .gray, "grey": .gray,
            "red": .red, "orange": .orange, "yellow": .yellow, "green": .green,
            "mint": .mint, "teal": .teal, "cyan": .cyan, "blue": .blue,
            "indigo": .indigo, "purple": .purple, "pink": .pink, "brown": .brown,
            "clear": .clear,
        ]
        if let color = named[text] {
            self = color
            return
        }
        // …plus common CSS color names SwiftUI doesn't provide, as hex.
        let namedHex: [String: String] = [
            "navy": "#000080", "maroon": "#800000", "olive": "#808000",
            "lime": "#00FF00", "aqua": "#00FFFF", "fuchsia": "#FF00FF",
            "magenta": "#FF00FF", "silver": "#C0C0C0", "gold": "#FFD700",
            "violet": "#EE82EE", "tan": "#D2B48C", "beige": "#F5F5DC",
            "ivory": "#FFFFF0", "coral": "#FF7F50", "salmon": "#FA8072",
            "crimson": "#DC143C", "khaki": "#F0E68C", "lavender": "#E6E6FA",
            "turquoise": "#40E0D0", "plum": "#DDA0DD", "orchid": "#DA70D6",
            "darkgray": "#404040", "darkgrey": "#404040", "lightgray": "#D3D3D3",
            "lightgrey": "#D3D3D3", "midnightblue": "#191970", "darkblue": "#00008B",
        ]
        if let hex = namedHex[text], let rgb = Color.rgbComponents(fromHex: hex) {
            self = Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
            return
        }
        if text.hasPrefix("#"), let rgb = Color.rgbComponents(fromHex: text) {
            self = Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
            return
        }
        self = .black
    }

    /// This color as a #RRGGBB hex string, for storing what a ColorPicker
    /// produced back into the stack's `paddingColor`.
    var stackHexString: String {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        let resolved = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = resolved.redComponent, g = resolved.greenComponent, b = resolved.blueComponent
        #endif
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// Red/green/blue in 0…1 from #RGB or #RRGGBB, nil if malformed.
    private static func rgbComponents(fromHex hex: String) -> (r: Double, g: Double, b: Double)? {
        var digits = hex
        digits.removeFirst() // '#'
        if digits.count == 3 {
            // #RGB → #RRGGBB
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
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

    /// The card "desktop": the surround behind a card in the document view,
    /// a classic Mac medium gray — the era's screen background, and what
    /// shows around a card that's smaller than the window (as in HyperCard).
    static var cardDesktop: Color {
        Color(red: 0.6, green: 0.6, blue: 0.6)
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

/// Ends text editing by resigning the focused field, wherever it is. SwiftUI
/// text fields otherwise hold first-responder status — Return submits but
/// keeps the caret, and clicks on empty form space don't move focus.
@MainActor func endTextEditing() {
    #if os(macOS)
    NSApp.keyWindow?.makeFirstResponder(nil)
    #else
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}

extension View {
    /// Inspector-form behavior: Return ends editing in the submitting field,
    /// and a click/tap on empty form space releases the focused field.
    func endsTextEditingOnSubmitAndTap() -> some View {
        onSubmit { endTextEditing() }
            .onTapGesture { endTextEditing() }
    }

    /// Escape dismisses (onExitCommand) on macOS; a no-op on iOS, which has
    /// no Escape key for views (hardware-keyboard Escape is a follow-up).
    @ViewBuilder
    func onEscapeKey(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }

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
