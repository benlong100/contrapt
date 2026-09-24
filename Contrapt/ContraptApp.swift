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

/// One-time launch bookkeeping.
enum FirstLaunch {
    private static let didOpenHomeKey = "didOpenHomeAtFirstLaunch"

    /// Returns true exactly once — the first launch after a fresh install —
    /// and records that Home has been auto-opened.
    static func shouldOpenHome() -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didOpenHomeKey) else { return false }
        defaults.set(true, forKey: didOpenHomeKey)
        return true
    }
}

#if os(iOS)
/// A hidden view behind the document launch screen that opens Home the
/// first time the app runs, so new users land in Home rather than the
/// empty browser.
private struct FirstLaunchHomeOpener: View {
    @Environment(\.openDocument) private var openDocument

    var body: some View {
        Color.clear
            .task {
                guard FirstLaunch.shouldOpenHome() else { return }
                try? await openDocument(at: HomeStack.ensureSeeded())
            }
    }
}
#endif

#if os(macOS)
/// Opens Home on the first launch after install. On macOS the document
/// app otherwise starts at an open panel; this lands new users in Home.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard FirstLaunch.shouldOpenHome() else { return }
        let url = HomeStack.ensureSeeded()
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
}
#endif

/// The Go menu's items, enabled only when a stack window is focused.
private struct GoCommands: View {
    @FocusedValue(\.cardNavigation) private var navigation
    @Environment(\.openDocument) private var openDocument

    var body: some View {
        // Home opens the Home stack and is always available.
        Button("Home") { openHome() }
            .keyboardShortcut("h", modifiers: [.command, .shift])
        Divider()
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
        Divider()
        Button("Reset Home to Default…") {
            HomeStack.reset()
            openHome()
        }
    }

    private func openHome() {
        let url = HomeStack.ensureSeeded()
        Task { try? await openDocument(at: url) }
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
        #endif
        // HyperCard's Go menu, driven by the focused document. Also
        // reaches iPad when a hardware keyboard is attached.
        .commands {
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
        } background: {
            FirstLaunchHomeOpener()
        }
        #endif
    }
}
