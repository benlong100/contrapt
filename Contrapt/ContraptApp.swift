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
        // Contrapt doesn't use tabbed windows, so drop the View menu's Show
        // Tab Bar / Show All Tabs items.
        NSWindow.allowsAutomaticWindowTabbing = false
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
        // …and prune the native Full Screen item, plus the redundant Save and
        // Revert To items, each time a menu is about to open (SwiftUI re-adds
        // them after a one-time removal). The app autosaves, so Save/Revert To
        // aren't needed; Duplicate/Rename/Move To stay.
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { _ in
            Self.pruneUnwantedMenuItems()
        }
    }

    /// Removes menu items Contrapt doesn't want, wherever they land: AppKit's
    /// automatic Full Screen item (leaving Contrapt's own command), and the
    /// autosave-redundant Save and Revert To items.
    private static func pruneUnwantedMenuItems() {
        let unwanted = ["toggleFullScreen:", "saveDocument:", "revertDocumentToSaved:"]
            .map(NSSelectorFromString)
        for submenu in NSApp.mainMenu?.items.compactMap(\.submenu) ?? [] {
            for item in submenu.items {
                if let action = item.action, unwanted.contains(action) {
                    submenu.removeItem(item)
                } else if item.submenu != nil, item.title.hasPrefix("Revert") {
                    // "Revert To" is a versions submenu with no action of its own.
                    submenu.removeItem(item)
                }
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

/// The card-management items (New Card, New Background, Cut/Copy/Paste Card,
/// Delete Card), added to the Edit menu on macOS. On iOS these live in the
/// toolbar's Cards menu instead, since there's no menu bar. Enabled only when
/// a stack window is focused.
private struct CardCommands: View {
    @FocusedValue(\.cardActions) private var actions

    var body: some View {
        Group {
            Button("New Card") { actions?.newCard() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Background") { actions?.newBackground() }
            Divider()
            Button("Cut Card") { actions?.cutCard() }
                .disabled(!(actions?.canDeleteCard ?? false))
            Button("Copy Card") { actions?.copyCard() }
            Button("Paste Card") { actions?.pasteCard() }
                .disabled(!(actions?.canPasteCard ?? false))
            Divider()
            Button("Delete Card") { actions?.deleteCard() }
                .disabled(!(actions?.canDeleteCard ?? false))
        }
        .disabled(actions == nil)
    }
}

#if os(macOS)
/// The Edit menu's Cut/Copy/Paste/Delete, made part-aware: in edit mode with a
/// selected part they act on that part; otherwise they fall through to the
/// standard text actions via the responder chain, so the same items and
/// shortcuts serve both parts and text fields. Select All always targets text
/// (there's no part multi-selection). macOS-only (it calls AppKit directly).
private struct EditActionCommands: View {
    @FocusedValue(\.partActions) private var parts

    var body: some View {
        Button("Cut") {
            if let parts, parts.canCopy, !isEditingText { parts.cut() }
            else { send(#selector(NSText.cut(_:))) }
        }
        .keyboardShortcut("x", modifiers: .command)

        Button("Copy") {
            if let parts, parts.canCopy, !isEditingText { parts.copy() }
            else { send(#selector(NSText.copy(_:))) }
        }
        .keyboardShortcut("c", modifiers: .command)

        Button("Paste") {
            if let parts, parts.canPaste, !isEditingText { parts.paste() }
            else { send(#selector(NSText.paste(_:))) }
        }
        .keyboardShortcut("v", modifiers: .command)

        // Part-only: duplicate the selected part in place.
        Button("Duplicate") { parts?.duplicate() }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!(parts?.canCopy ?? false) || isEditingText)

        Button("Delete") {
            if let parts, parts.canCopy, !isEditingText { parts.delete() }
            else { send(#selector(NSText.delete(_:))) }
        }

        Button("Select All") { send(#selector(NSText.selectAll(_:))) }
            .keyboardShortcut("a", modifiers: .command)
    }

    /// True while a field editor (or any text view) is first responder, so
    /// text editing keeps the standard behavior.
    private var isEditingText: Bool {
        let responder = NSApp.keyWindow?.firstResponder
        return responder is NSText || responder is NSTextView
    }

    private func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}
#endif

/// The Help menu's HyperTalk Guide item (macOS, where it's not in the
/// toolbar). Enabled only when a stack window is focused.
private struct GuideCommand: View {
    @FocusedBinding(\.guidePresented) private var isPresented: Bool?

    var body: some View {
        Button("HyperTalk Guide") { isPresented = true }
            .disabled(isPresented == nil)
    }
}

#if os(macOS)
/// The File menu's "Export as Website…" item — writes the focused stack as a
/// static site into a chosen folder, then reveals it in the Finder.
private struct ExportWebsiteCommand: View {
    @FocusedValue(\.websiteExport) private var export

    var body: some View {
        Button("Export as Website…") { run() }
            .disabled(export == nil)
    }

    private func run() {
        guard let export else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to write the exported website into."
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        // Mirror import's size choice: render the exported page at the card's
        // true size, or scaled to fill the browser window.
        let sizeAlert = NSAlert()
        sizeAlert.messageText = "Website Size"
        sizeAlert.informativeText = "Show the card at its original size, or scaled to fill the browser window?"
        sizeAlert.addButton(withTitle: "Original Size")
        sizeAlert.addButton(withTitle: "Scaled to Fit")
        sizeAlert.addButton(withTitle: "Cancel")
        let actualSize: Bool
        switch sizeAlert.runModal() {
        case .alertFirstButtonReturn: actualSize = true
        case .alertSecondButtonReturn: actualSize = false
        default: return
        }
        do {
            let site = try export.export(directory, actualSize)
            NSWorkspace.shared.activateFileViewerSelecting([site])
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
#endif

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
    @State private var isLegacyImporterPresented = false
    @State private var isHyperCardAppPickerPresented = false
    @State private var pendingLegacyStackURL: URL?
    @State private var isExporterPresented = false
    @State private var pendingNew: StackDocument?
    @State private var pendingFilename = "Untitled"
    @State private var saveTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            NavigationStack {
                // The Stacks menu replaces the document browser: new stacks and
                // the tutorial are saved into Files (via the exporter), and Open
                // browses for an existing one. It's handed to ContentView's own
                // toolbar (not a second `.toolbar` here) — two `.toolbar`
                // modifiers on one view break Menu selection on iPad.
                ContentView(document: home, fileURL: HomeStack.workingURL,
                            onOpenStackFile: { url, _ in openExternal(url) },
                            leadingToolbarContent: AnyView(stacksMenu))
            }
            // An opened stack simply appears over Home (an opaque layer, not
            // a sliding sheet), so it feels like being on that stack rather
            // than a temporary modal.
            if let opened {
                OpenedStackView(stack: opened, onClose: closeOpened,
                                onOpenStack: { url in openExternal(url) })
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.contraptStack]) { result in
            if case .success(let url) = result { openExternal(url) }
        }
        // Classic HyperCard stacks have no uniform type, so accept any file
        // and let the importer validate the STAK header.
        .fileImporter(isPresented: $isLegacyImporterPresented, allowedContentTypes: [.data, .item]) { result in
            if case .success(let url) = result { pendingLegacyStackURL = url }
        }
        // After picking a stack, choose the import size.
        .confirmationDialog("Import at what size?",
                            isPresented: Binding(get: { pendingLegacyStackURL != nil },
                                                 set: { if !$0 { pendingLegacyStackURL = nil } }),
                            presenting: pendingLegacyStackURL) { url in
            Button("Original Size") { importLegacy(url, presentAtActualSize: true) }
            Button("Fill Window") { importLegacy(url, presentAtActualSize: false) }
            Button("Cancel", role: .cancel) {}
        }
        // Point Contrapt at a HyperCard app so imported button icons resolve.
        .fileImporter(isPresented: $isHyperCardAppPickerPresented, allowedContentTypes: [.data, .item]) { result in
            if case .success(let url) = result { HyperCardAppReference.save(url) }
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

    /// Home's leading toolbar menu, hosted inside ContentView's own toolbar.
    private var stacksMenu: some View {
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
            Button("Import HyperCard Stack…", systemImage: "tray.and.arrow.down") {
                isLegacyImporterPresented = true
            }
            Button("Set HyperCard App for Icons…", systemImage: "app.badge") {
                isHyperCardAppPickerPresented = true
            }
        }
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

    /// Import a chosen legacy stack at the chosen size, then open it over Home.
    private func importLegacy(_ url: URL, presentAtActualSize: Bool) {
        pendingLegacyStackURL = nil
        guard let contrapt = try? LegacyStackImporter.importedContraptFile(
            from: url, iconApp: HyperCardAppReference.url(), presentAtActualSize: presentAtActualSize) else { return }
        openExternal(contrapt)
    }

    private func openExternal(_ url: URL) {
        // Replacing one opened stack with another (`go stack "X"`): release the
        // previous stack's security scope first.
        if let previous = opened, previous.securityScoped {
            previous.url.stopAccessingSecurityScopedResource()
        }
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
    /// Opening another stack from within this one (`go stack "X"`).
    var onOpenStack: (URL) -> Void = { _ in }
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ContentView(document: stack.document, fileURL: stack.url,
                        onOpenStackFile: { url, _ in onOpenStack(url) })
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

#if os(macOS)
/// Presents an open panel for a classic HyperCard stack, imports it (Phase 1:
/// structure, parts, text, scripts — artwork deferred), and opens the result
/// as a new Contrapt document.
@MainActor private func importLegacyStack() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.message = "Choose a classic HyperCard stack to import."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    // Present at the original (small, 1:1) card size, or scaled to fill.
    let sizeAlert = NSAlert()
    sizeAlert.messageText = "Import Size"
    sizeAlert.informativeText = "Open the card at its original HyperCard size, or scaled to fill the window?"
    sizeAlert.addButton(withTitle: "Original Size")
    sizeAlert.addButton(withTitle: "Fill Window")
    sizeAlert.addButton(withTitle: "Cancel")
    let actualSize: Bool
    switch sizeAlert.runModal() {
    case .alertFirstButtonReturn: actualSize = true
    case .alertSecondButtonReturn: actualSize = false
    default: return
    }
    // Resolve the HyperCard app for button icons — remembered, or offered once.
    var iconApp = HyperCardAppReference.url()
    if iconApp == nil, let picked = promptForHyperCardApp() {
        HyperCardAppReference.save(picked)
        iconApp = picked
    }
    do {
        let contrapt = try LegacyStackImporter.importedContraptFile(from: url, iconApp: iconApp, presentAtActualSize: actualSize)
        NSDocumentController.shared.openDocument(withContentsOf: contrapt, display: true) { _, _, _ in }
    } catch {
        NSAlert(error: error).runModal()
    }
}

/// Offers an open panel to locate the user's HyperCard application (for button
/// icons). Optional — Cancel skips icons.
@MainActor private func promptForHyperCardApp() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.message = "Optional: choose your HyperCard application to import its button icons. Cancel to skip — Contrapt ships none itself."
    panel.prompt = "Use for Icons"
    return panel.runModal() == .OK ? panel.url : nil
}

/// The File-menu command to (re)choose the HyperCard app for button icons.
@MainActor private func setHyperCardApp() {
    if let picked = promptForHyperCardApp() { HyperCardAppReference.save(picked) }
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
            // Window size is governed by ContentView's frame (a fixed card size
            // for original-size imports, else a flexible default) together with
            // .windowResizability(.contentSize) below.
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        // Open new document windows large enough to show a whole card
        // comfortably with room for the inspector.
        .defaultSize(width: 1280, height: 900)
        // The window hugs its content, so an original-size import opens small.
        .windowResizability(.contentSize)
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
        #if os(macOS)
        // Replace the DocumentGroup's default File > New: keep a "New Stack"
        // item but free up ⌘N so it can drive New Card in the Edit menu
        // (HyperCard's binding).
        CommandGroup(replacing: .newItem) {
            Button("New Stack") {
                NSDocumentController.shared.newDocument(nil)
            }
            Button("Import HyperCard Stack…") {
                importLegacyStack()
            }
            Button("Set HyperCard App for Icons…") {
                setHyperCardApp()
            }
            Divider()
            ExportWebsiteCommand()
        }
        // Cut/Copy/Paste/Delete act on the selected part in edit mode, else
        // on text (Select All stays text-only).
        CommandGroup(replacing: .pasteboard) {
            EditActionCommands()
        }
        // The Card menu's items, folded into the Edit menu after the standard
        // Cut/Copy/Paste group.
        CommandGroup(after: .pasteboard) {
            Divider()
            CardCommands()
        }
        // The HyperTalk Guide, in the Help menu.
        CommandGroup(replacing: .help) {
            GuideCommand()
        }
        #endif
        CommandMenu("Go") {
            GoCommands()
        }
    }
}
