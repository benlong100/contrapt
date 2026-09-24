//
//  ContraptApp.swift
//  Contrapt
//
//  Created by Happy Wanderer on 9/23/26.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

// Note: programmatically opening a document at a URL uses SwiftUI's
// openDocument action, which is macOS-only. On iOS the document browser
// is the front door; forcing launch into Home there needs an architecture
// change (see project memory).

#if os(macOS)
/// Launches into Home instead of the open panel — every launch, and on
/// dock reopen with no windows. Opening a specific stack from Finder still
/// works normally (this hook isn't called in that case).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Suppress AppKit's automatic "Enter Full Screen" View-menu item —
        // Contrapt's full-screen is its own presentation mode. Set before the
        // menu is built. (collectionBehavior alone doesn't remove this item.)
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The DocumentGroup's launch panel is suppressed (see the scene's
        // defaultLaunchBehavior). Open Home ourselves, deferred a beat so
        // the document scene is ready. Skipped if a document is already
        // opening (e.g. launched by opening a stack from Finder).
        DispatchQueue.main.async {
            guard NSApp.windows.allSatisfy({ !$0.isVisible }) else { return }
            self.openHome()
        }
        // Contrapt's full-screen is our own presentation mode (see
        // StackPresentation), so strip macOS's native full-screen. Remove the
        // green-button capability per window…
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.remove(.fullScreenAuxiliary)
        }
        // …and delete the native "Enter Full Screen" item each time a menu is
        // about to open, since SwiftUI re-adds it after a one-time removal.
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { _ in
            Self.removeNativeFullScreenMenuItem()
        }
    }

    /// Removes AppKit's automatic Full Screen item (action `toggleFullScreen:`)
    /// wherever it landed in the menu, leaving Contrapt's own command.
    private static func removeNativeFullScreenMenuItem() {
        let toggle = NSSelectorFromString("toggleFullScreen:")
        for submenu in NSApp.mainMenu?.items.compactMap(\.submenu) ?? [] {
            for item in submenu.items where item.action == toggle {
                submenu.removeItem(item)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { openHome() }
        return true
    }

    private func openHome() {
        let url = HomeStack.ensureSeeded()
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
}
#endif

/// The Go menu's items, enabled only when a stack window is focused.
private struct GoCommands: View {
    @FocusedValue(\.cardNavigation) private var navigation
    #if os(macOS)
    @Environment(\.openDocument) private var openDocument
    #endif

    var body: some View {
        #if os(macOS)
        // Home opens the Home stack (macOS-only: openDocument).
        Button("Home") { openHome() }
            .keyboardShortcut("h", modifiers: [.command, .shift])
        Divider()
        #endif
        // Within-stack navigation needs a focused stack window.
        Group {
            Button("Back") { navigation?.goPrevious() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Forward") { navigation?.goNext() }
                .keyboardShortcut("]", modifiers: .command)
            Button("First Card") { navigation?.goFirst() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Last Card") { navigation?.goLast() }
                .keyboardShortcut(.downArrow, modifiers: .command)
        }
        .disabled(navigation == nil)
        #if os(macOS)
        Divider()
        Button("Reset Home to Default…") {
            HomeStack.reset()
            openHome()
        }
        #endif
    }

    #if os(macOS)
    private func openHome() {
        let url = HomeStack.ensureSeeded()
        Task { try? await openDocument(at: url) }
    }
    #endif
}

/// The View menu's Full Screen toggle, enabled when a stack is focused.
private struct FullScreenCommand: View {
    @FocusedBinding(\.stackFullScreen) private var isFullScreen: Bool?

    var body: some View {
        Button(isFullScreen == true ? "Exit Full Screen" : "Enter Full Screen") {
            isFullScreen?.toggle()
        }
        .keyboardShortcut("f", modifiers: [.command, .shift])
        .disabled(isFullScreen == nil)
    }
}

@main
struct ContraptApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        DocumentGroup(newDocument: { StackDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 640)
                #endif
        }
        #if os(macOS)
        // Open new document windows large enough to show a whole card
        // comfortably with room for the inspector.
        .defaultSize(width: 1280, height: 900)
        // Don't show the open panel on launch; the app delegate opens Home.
        .defaultLaunchBehavior(.suppressed)
        #endif
        // HyperCard's Go menu, driven by the focused document. Also
        // reaches iPad when a hardware keyboard is attached.
        .commands {
            CommandGroup(after: .toolbar) {
                FullScreenCommand()
            }
            CommandMenu("Go") {
                GoCommands()
            }
        }
        // The launch scene's New/Learn buttons are an iOS-only feature;
        // macOS gets New and Open from the standard File menu. (A Help-menu
        // entry point for the tutorial is a natural macOS follow-up.)
        #if os(iOS)
        DocumentGroupLaunchScene("Contrapt") {
            NewDocumentButton("New Stack")
            NewDocumentButton("Learn HyperTalk", for: StackDocument.self) {
                StackDocument(stack: .tutorial())
            }
        }
        #endif
    }
}
