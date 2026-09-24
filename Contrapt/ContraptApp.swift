//
//  ContraptApp.swift
//  Contrapt
//
//  Created by Happy Wanderer on 9/23/26.
//

import SwiftUI

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
        DocumentGroupLaunchScene {
            NewDocumentButton("New Stack")
            NewDocumentButton("Learn HyperTalk", for: StackDocument.self) {
                StackDocument(stack: .tutorial())
            }
        }
        #endif
    }
}
