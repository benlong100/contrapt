//
//  ContraptApp.swift
//  Contrapt
//
//  Created by Happy Wanderer on 9/23/26.
//

import SwiftUI
import UniformTypeIdentifiers
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

#if os(iOS)
/// The iOS root: Home in a plain window (the launch target), saved manually
/// on a debounce since a WindowGroup has no autosave. Other stacks open from
/// Files / the share sheet via `.onOpenURL`, presented full-screen over Home.
private struct RootView: View {
    @StateObject private var home = StackDocument.loadHome()
    @State private var opened: OpenedStack?
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var pendingNew: StackDocument?
    @State private var pendingFilename = "Untitled"
    @State private var saveTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            NavigationStack {
                ContentView(document: home, fileURL: HomeStack.workingURL)
                    // The Stacks menu replaces the document browser: new
                    // stacks and the tutorial are saved into Files (via the
                    // exporter), and Open browses for an existing one.
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Menu("Stacks", systemImage: "square.stack") {
                                Button("New Stack", systemImage: "doc.badge.plus") {
                                    startNew(.makeNew(), filename: "Untitled")
                                }
                                Button("Learn HyperTalk", systemImage: "graduationcap") {
                                    startNew(.tutorial(), filename: "Learn HyperTalk")
                                }
                                Divider()
                                Button("Open…", systemImage: "folder") {
                                    isImporterPresented = true
                                }
                            }
                        }
                    }
            }
            // An opened stack simply appears over Home (an opaque layer, not
            // a sliding sheet), so it feels like being on that stack rather
            // than a temporary modal.
            if let opened {
                OpenedStackView(stack: opened, onClose: closeOpened)
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.contraptStack]) { result in
            if case .success(let url) = result { openExternal(url) }
        }
        // New stacks and the tutorial are created in Files, then opened.
        .fileExporter(
            isPresented: $isExporterPresented,
            document: pendingNew,
            contentType: .contraptStack,
            defaultFilename: pendingFilename
        ) { result in
            if case .success(let url) = result { openExternal(url) }
        }
        .onChange(of: home.stack) { scheduleHomeSave() }
        .onChange(of: home.assets) { scheduleHomeSave() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveTask?.cancel(); home.write(to: HomeStack.workingURL) }
        }
        .onOpenURL { openExternal($0) }
    }

    /// Creates a stack in memory and presents the exporter to save it into
    /// Files; on success it opens over Home.
    private func startNew(_ stack: Stack, filename: String) {
        pendingNew = StackDocument(stack: stack)
        pendingFilename = filename
        isExporterPresented = true
    }

    /// Saves and closes the opened stack, releasing its security scope.
    private func closeOpened() {
        if let opened, opened.securityScoped {
            opened.url.stopAccessingSecurityScopedResource()
        }
        opened = nil
    }

    private func scheduleHomeSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            home.write(to: HomeStack.workingURL)
        }
    }

    private func openExternal(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        guard let document = StackDocument.load(from: url) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            return
        }
        opened = OpenedStack(document: document, url: url, securityScoped: scoped)
    }
}

/// A stack opened over Home from Files / the share sheet.
private struct OpenedStack: Identifiable {
    let id = UUID()
    let document: StackDocument
    let url: URL
    let securityScoped: Bool
}

/// Hosts an opened stack full-screen over Home, with a Home button that
/// saves edits back to the source file and returns.
private struct OpenedStackView: View {
    let stack: OpenedStack
    var onClose: () -> Void
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ContentView(document: stack.document, fileURL: stack.url)
        }
        .overlay(alignment: .topLeading) {
            Button {
                saveTask?.cancel()
                stack.document.write(to: stack.url)
                onClose()
            } label: {
                Label("Home", systemImage: "house.fill")
                    .labelStyle(.iconOnly)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
        }
        .onChange(of: stack.document.stack) { scheduleSave() }
        .onChange(of: stack.document.assets) { scheduleSave() }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            stack.document.write(to: stack.url)
        }
    }
}
#endif

@main
struct ContraptApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        DocumentGroup(newDocument: { StackDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
                .frame(minWidth: 900, minHeight: 640)
        }
        // Open new document windows large enough to show a whole card
        // comfortably with room for the inspector.
        .defaultSize(width: 1280, height: 900)
        // Don't show the open panel on launch; the app delegate opens Home.
        .defaultLaunchBehavior(.suppressed)
        .commands { stackCommands }
        #else
        // iOS launches straight into Home. `openDocument` is unavailable on
        // iOS and a WindowGroup can't preempt a DocumentGroup's launch, so
        // Home is a plain window; other stacks open via .onOpenURL from
        // Files / the share sheet, full-screen over Home.
        WindowGroup {
            RootView()
        }
        .commands { stackCommands }
        #endif
    }

    // HyperCard's Go menu plus the full-screen toggle, driven by the focused
    // document. Reaches iPad when a hardware keyboard is attached.
    @CommandsBuilder private var stackCommands: some Commands {
        CommandGroup(after: .toolbar) {
            FullScreenCommand()
        }
        CommandMenu("Go") {
            GoCommands()
        }
    }
}
