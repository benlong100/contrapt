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
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        openHome()
        return true
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
        }
        #endif
    }
}
