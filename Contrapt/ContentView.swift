//
//  ContentView.swift
//  Contrapt
//

import Combine
import PencilKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import HyperTalk

/// The document view. Browse mode shows the current card with live parts;
/// button taps dispatch mouseUp through the interpreter. Edit mode makes
/// parts selectable, movable, and resizable, with a property inspector.
struct ContentView: View {
    @ObservedObject var document: StackDocument
    /// The document's location on disk, for sharing. Nil until first save.
    var fileURL: URL?
    /// iOS opens another stack (from `go stack "X"`) by layering it over Home;
    /// that's a RootView concern, so it's injected. nil on macOS, which opens
    /// a document window directly.
    var onOpenStackFile: ((URL, GoDestination?) -> Void)? = nil
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openURL) private var openURL
    #if os(macOS)
    @Environment(\.openDocument) private var openDocument
    #endif
    @ObservedObject private var cardClipboard = CardClipboard.shared
    @ObservedObject private var partClipboard = PartClipboard.shared

    @State private var currentCardIndex = 0
    @State private var isEditing = false
    @State private var selectedPartID: UUID?
    /// The field `find` last matched, boxed on the card until the next edit.
    @State private var findHighlight: FindHighlight?
    @State private var isInspectorPresented = false
    /// Edit-mode reveal overlays — HyperCard's button/field tool highlighting,
    /// so transparent or hidden parts are findable. Remembered across sessions.
    @AppStorage("revealButtons") private var revealButtons = false
    @AppStorage("revealFields") private var revealFields = false
    /// The inspector's Card/Background/Stack selection — also the layer that
    /// newly-added parts (buttons, fields, images…) go onto.
    @State private var objectScope: ObjectScriptsInspector.Scope = .card
    @State private var messageBoxText: String?
    @State private var isMessageBoxVisible = false
    @State private var scriptErrorText: String?
    @State private var undoFlushTask: Task<Void, Never>?
    @State private var isPhotoPickerPresented = false
    @State private var selectedPhoto: PhotosPickerItem?
    #if !os(macOS)
    /// Keyboard focus for the card area, so the Delete key can remove the
    /// selected part in edit mode (macOS uses a key monitor instead).
    @FocusState private var isCardFocused: Bool
    #endif
    #if os(macOS)
    /// The Mac uses a regular file picker so images don't have to go
    /// through Photos.
    @State private var isImageImporterPresented = false
    #endif
    #if os(iOS)
    @State private var isPaintingPresented = false
    @State private var paintDrawingToEdit = PKDrawing()
    @State private var paintTarget: PaintTarget = .card
    #endif
    /// The button being linked, while the Link To panel floats over the card.
    @State private var linkingPartID: UUID?
    /// A `go stack "X"` whose stack isn't in the library yet — remembered
    /// while the locate picker is shown, so the pick can open it.
    @State private var pendingGoStack: PendingGoStack?
    @State private var isStackLocatorPresented = false
    @State private var isGuidePresented = false
    /// A pending `answer` / `ask` dialog and its text field's contents.
    @State private var scriptDialog: ScriptDialog?
    @State private var askFieldText = ""
    /// The visual effect for the current scripted card transition, if any.
    @State private var cardTransition: ScreenEffect?
    /// Editing habit, not document data — persists across stacks.
    @AppStorage("snapToGuides") private var isSnappingEnabled = true

    /// The mutation choke point: every edit anywhere in the view tree —
    /// drags, typing, inspector fields, script effects — writes through
    /// this binding, which arranges undo and marks the document dirty.
    /// The restartable task ends the current coalescing burst after a
    /// quiet period, turning a whole drag or typing run into one undo step.
    private var stack: Binding<Stack> {
        Binding(
            get: { document.stack },
            set: { newValue in
                document.replaceStack(newValue, undoManager: undoManager)
                undoFlushTask?.cancel()
                undoFlushTask = Task {
                    try? await Task.sleep(for: .seconds(0.9))
                    guard !Task.isCancelled else { return }
                    document.flushPendingUndo(with: undoManager)
                }
            }
        )
    }

    /// The card and its selection/edit affordances. Split from `body` (with
    /// `decoratedStage`) so each modifier chain stays small enough for the
    /// compiler to type-check quickly — the whole chain at once overruns the
    /// budget on iOS.
    /// A CardView for the current card, optionally limited to one layer (so
    /// browse-mode transitions animate the card layer over a static background).
    private func cardView(includeBackground: Bool, includeCard: Bool) -> some View {
        CardView(
            stack: stack,
            cardIndex: cardIndex,
            isEditing: isEditing,
            isSnappingEnabled: isSnappingEnabled,
            selectedPartID: $selectedPartID,
            findHighlightPartID: findHighlight?.partID,
            findHighlightRange: findHighlight?.range,
            revealButtons: revealButtons,
            revealFields: revealFields,
            includeBackground: includeBackground,
            includeCard: includeCard,
            onMouseMessage: sendMouseMessage,
            onOpenInspector: { isInspectorPresented = true },
            onFollowLink: followLink
        )
    }

    private var cardStage: some View {
        Group {
            if document.stack.cards.isEmpty {
                ContentUnavailableView("No Cards", systemImage: "rectangle.on.rectangle.slash")
            } else {
                // Edit mode is a single card view (no transitions). In browse,
                // the background is drawn statically and only the card layer
                // carries the `visual effect` transition — so a shared
                // background stays put, as in HyperCard. The ZStack is a stable
                // container so the outgoing and incoming card layers overlap.
                ZStack {
                    if isEditing {
                        cardView(includeBackground: true, includeCard: true)
                    } else {
                        cardView(includeBackground: true, includeCard: false)
                        cardView(includeBackground: false, includeCard: true)
                            .id(cardIndex)
                            .transition(cardTransition?.transition ?? .identity)
                    }
                }
                // Actual-size stacks hug the card (small margin for the card
                // shadow); otherwise the usual breathing room.
                .padding(document.stack.presentAtActualSize ? 6 : 16)
                #if os(macOS)
                // Classic HyperCard browse cursor: the pointing finger over
                // the card. Edit mode keeps the arrow; text fields being
                // edited override with their own I-beam.
                .pointerStyle(isEditing ? nil : .link)
                #endif
            }
        }
        .environment(\.stackAssets, document.assets)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backdropColor)
        // In edit mode, the Delete key removes the selected part. A local
        // key monitor handles it (SwiftUI's onKeyPress never gets the key
        // while the card's part gestures own focus); it defers to any field
        // being edited so Delete still erases text there.
        #if os(macOS)
        .background(
            DeleteKeyCatcher(isEnabled: isEditing && selectedPartID != nil) {
                if let selectedPartID { deletePart(id: selectedPartID) }
            }
        )
        #else
        .focusable(isEditing)
        .focusEffectDisabled()
        .focused($isCardFocused)
        .onKeyPress { press in
            guard isEditing, let selectedPartID,
                  press.key == .delete || press.key == .deleteForward else { return .ignored }
            deletePart(id: selectedPartID)
            return .handled
        }
        .onChange(of: selectedPartID) { _, newValue in
            if isEditing, newValue != nil { isCardFocused = true }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { isCardFocused = false }
        }
        #endif
    }

    /// The card stage plus its pickers, overlays, alerts, and inspector.
    private var decoratedStage: some View {
        cardStage
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
        #if os(macOS)
        .fileImporter(isPresented: $isImageImporterPresented, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let image = PlatformImage(data: data) else { return }
            addImagePart(data: data, imageSize: image.pixelSize)
        }
        #endif
        .sheet(isPresented: $isGuidePresented) {
            HyperTalkGuideView()
        }
        #if os(iOS)
        // Painting is iPad-only (finger/Pencil); macOS imports art as images.
        .platformFullScreenCover(isPresented: $isPaintingPresented) {
            PaintEditor(
                title: paintTarget == .card ? "Paint on Card" : "Paint on Background",
                cardSize: document.stack.cardSize,
                initialDrawing: paintDrawingToEdit
            ) { finished in
                savePaint(finished)
            }
        }
        #endif
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            selectedPhoto = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = PlatformImage(data: data) else { return }
                addImagePart(data: data, imageSize: image.pixelSize)
            }
        }
        .overlay(alignment: .bottom) {
            if isMessageBoxVisible {
                MessageBoxView(output: messageBoxText, onCommand: runMessageBoxCommand)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if linkingPartID != nil {
                linkToPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: isMessageBoxVisible)
        .animation(.default, value: linkingPartID)
        .alert(
            "Script Error",
            isPresented: Binding(
                get: { scriptErrorText != nil },
                set: { if !$0 { scriptErrorText = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scriptErrorText ?? "")
        }
        .alert(
            scriptDialog?.prompt ?? "",
            isPresented: Binding(get: { scriptDialog != nil }, set: { _ in }),
            presenting: scriptDialog
        ) { dialog in
            switch dialog.kind {
            case .answer(let buttons):
                ForEach(buttons, id: \.self) { button in
                    Button(button) {
                        scriptDialog = nil
                        dialog.complete(button)
                    }
                }
            case .ask:
                TextField("", text: $askFieldText)
                Button("OK") {
                    let text = askFieldText
                    scriptDialog = nil
                    dialog.complete(text)
                }
                Button("Cancel", role: .cancel) {
                    scriptDialog = nil
                    dialog.complete(nil)
                }
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            Group {
                if let selectedPartID, let partBinding = partBinding(for: selectedPartID) {
                    PartInspector(
                        part: partBinding,
                        onLinkTo: { linkingPartID = selectedPartID }
                    ) {
                        deletePart(id: selectedPartID)
                    }
                } else {
                    ObjectScriptsInspector(stack: stack, cardIndex: cardIndex, scope: $objectScope)
                }
            }
            .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        }
    }

    var body: some View {
        decoratedStage
        .onChange(of: cardIndex) { _, newIndex in
            sendSystemMessage("openCard", toCardAt: newIndex)
        }
        .task {
            // Remember this stack so other stacks' `go stack "<name>"` can
            // find it later.
            if let fileURL {
                StackLibrary.shared.register(url: fileURL)
                // If we were opened by `go card N of stack "<name>"`, land on
                // that card before the openCard message fires.
                if let card = PendingStackNavigation.shared.consume(name: StackLibrary.name(for: fileURL)),
                   let index = cardIndexFor(card) {
                    currentCardIndex = index
                }
            }
            sendSystemMessage("openStack", toCardAt: cardIndex)
            sendSystemMessage("openCard", toCardAt: cardIndex)
        }
        // A `go stack "X"` whose stack isn't in the library yet: locate it once.
        .fileImporter(isPresented: $isStackLocatorPresented, allowedContentTypes: [.contraptStack]) { result in
            guard case .success(let url) = result, let pending = pendingGoStack else { return }
            pendingGoStack = nil
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            openResolvedStack(url, card: pending.card)
        }
        .toolbar { mainToolbar }
        .focusedValue(\.cardNavigation, cardNavigation)
        .focusedSceneValue(\.cardActions, cardActions)
        .focusedSceneValue(\.partActions, partActions)
        .focusedSceneValue(\.stackFullScreen, fullScreenBinding)
        .focusedSceneValue(\.guidePresented, $isGuidePresented)
        // Full-screen (presentation) mode: hide the app chrome and let the
        // padding color own the space around the card.
        .toolbar(isPresentingFullScreen ? .hidden : .automatic)
        #if os(macOS)
        .background(
            StackPresentation(
                isPresenting: isPresentingFullScreen,
                paddingColor: Color(stackColor: document.stack.paddingColor),
                onExit: exitFullScreen
            )
        )
        // Original-size stacks make the window content hug the card (with the
        // scene's .windowResizability(.contentSize)); other stacks stay
        // flexible around a comfortable default.
        .frame(
            minWidth: actualSizeWindow ? cardWindowSize.width : 900,
            idealWidth: actualSizeWindow ? cardWindowSize.width : 1000,
            maxWidth: actualSizeWindow ? cardWindowSize.width : .infinity,
            minHeight: actualSizeWindow ? cardWindowSize.height : 640,
            idealHeight: actualSizeWindow ? cardWindowSize.height : 700,
            maxHeight: actualSizeWindow ? cardWindowSize.height : .infinity
        )
        #else
        .overlay(alignment: .topTrailing) {
            if isPresentingFullScreen {
                Button("Exit Full Screen", systemImage: "arrow.down.right.and.arrow.up.left") {
                    exitFullScreen()
                }
                .labelStyle(.iconOnly)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
                .padding()
            }
        }
        #endif
    }

    /// Presentation is on when the stack asks for it, we're browsing (edit
    /// mode needs the chrome), and there's a card to show.
    private var isPresentingFullScreen: Bool {
        document.stack.isFullScreen && !isEditing && !document.stack.cards.isEmpty
    }

    /// Original-size stacks pin the window to the card (macOS). Not while
    /// full-screen (which owns the whole screen).
    private var actualSizeWindow: Bool {
        document.stack.presentAtActualSize && !isPresentingFullScreen
    }

    /// The window content size for an actual-size stack: the card plus a thin
    /// margin for its shadow.
    private var cardWindowSize: CGSize {
        CGSize(width: document.stack.cardSize.width + 12, height: document.stack.cardSize.height + 12)
    }

    private var backdropColor: Color {
        // Windowed: the classic Mac gray "desktop" surrounds the card, as in
        // HyperCard. Full screen uses the stack's scriptable paddingColor.
        isPresentingFullScreen ? Color(stackColor: document.stack.paddingColor) : Color.cardDesktop
    }

    /// A binding to the stack's full-screen flag, published to the scene so
    /// the View menu's toggle can drive it (via @FocusedBinding). Writes go
    /// through the undo choke point, like every other edit.
    private var fullScreenBinding: Binding<Bool> {
        Binding(
            get: { document.stack.isFullScreen },
            set: { stack.wrappedValue.isFullScreen = $0 }
        )
    }

    private func exitFullScreen() {
        if document.stack.isFullScreen { stack.wrappedValue.isFullScreen = false }
    }

    // MARK: - Link To

    /// A floating panel over the card while linking a button. Navigation
    /// stays live (both here and in the toolbar), so the user flips to the
    /// destination card, then captures it with "This Card" — HyperCard's
    /// Link To flow.
    @ViewBuilder
    private var linkToPanel: some View {
        VStack(spacing: 12) {
            Text("Link To")
                .font(.headline)
            Text("Go to the card you want, then link to it.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("Previous", systemImage: "chevron.left") { goToPreviousCard() }
                    .labelStyle(.iconOnly)
                Text("\(cardIndex + 1) of \(document.stack.cards.count)")
                    .font(.callout).monospacedDigit().fixedSize()
                Button("Next", systemImage: "chevron.right") { goToNextCard() }
                    .labelStyle(.iconOnly)
            }
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { linkingPartID = nil }
                Button("This Stack") { applyLink("go to first card") }
                Button("This Card") {
                    applyLink("go to card id \(document.stack.cards[cardIndex].scriptID)")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 12)
        .shadow(radius: 12)
    }

    /// Writes a generated navigation handler to the linking button, found
    /// anywhere in the stack (it lives on a different card than the one the
    /// user navigated to).
    private func applyLink(_ command: String) {
        defer { linkingPartID = nil }
        guard let id = linkingPartID else { return }
        let script = "on mouseUp\n  \(command)\nend mouseUp"
        var updated = document.stack
        for cardIdx in updated.cards.indices {
            if let partIdx = updated.cards[cardIdx].parts.firstIndex(where: { $0.id == id }) {
                updated.cards[cardIdx].parts[partIdx].script = script
                stack.wrappedValue = updated
                return
            }
        }
        for bgIdx in updated.backgrounds.indices {
            if let partIdx = updated.backgrounds[bgIdx].parts.firstIndex(where: { $0.id == id }) {
                updated.backgrounds[bgIdx].parts[partIdx].script = script
                stack.wrappedValue = updated
                return
            }
        }
    }

    // MARK: - Script dispatch

    @State private var isSendingSystemMessage = false

    /// The main toolbar, extracted into a builder so the body expression stays
    /// small enough for the compiler to type-check quickly (especially on iOS,
    /// where the Cards menu keeps the editing group inline).
    @ToolbarContentBuilder private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if isEditing {
                editingToolbarTools
            }
            #if os(macOS)
            Button("Home", systemImage: "house") {
                openHome()
            }
            #endif
            // On macOS the guide opens from the Help menu (see GuideCommand);
            // iOS has no menu bar, so it stays in the toolbar.
            #if !os(macOS)
            Button("HyperTalk Guide", systemImage: "book") {
                isGuidePresented = true
            }
            #endif
            if let fileURL {
                ShareLink(item: fileURL) {
                    Label("Share Stack", systemImage: "square.and.arrow.up")
                }
            }
            Button("Message Box", systemImage: "text.and.command.macwindow") {
                isMessageBoxVisible.toggle()
            }
            Button(isEditing ? "Done" : "Edit") {
                if isEditing {
                    selectedPartID = nil
                    isInspectorPresented = false
                } else {
                    // Entering edit mode opens the inspector and clears any
                    // lingering find box (a browse-mode artifact).
                    isInspectorPresented = true
                    findHighlight = nil
                }
                isEditing.toggle()
            }
        }
        ToolbarItemGroup(placement: cardNavigationPlacement) {
            Button("Previous Card", systemImage: "chevron.left") {
                goToPreviousCard()
            }
            Spacer()
            Menu {
                Button("First Card", systemImage: "backward.end") { goFirst() }
                Button("Last Card", systemImage: "forward.end") { goLast() }
            } label: {
                Text("Card \(cardIndex + 1) of \(document.stack.cards.count)")
                    .font(.callout)
                    .monospacedDigit()
                    .fixedSize()
            }
            Spacer()
            Button("Next Card", systemImage: "chevron.right") {
                goToNextCard()
            }
        }
    }

    /// The edit-mode toolbar buttons, extracted so the toolbar builder stays
    /// small enough for the compiler to type-check quickly (especially on iOS,
    /// where the Cards menu is inline).
    @ViewBuilder private var editingToolbarTools: some View {
        Menu("Add Part", systemImage: "plus") {
            // The target layer follows the inspector's Card/Background tab.
            Section("Adding to \(newPartLayerName)") {
                Button("Button", systemImage: "hand.tap") {
                    addPart(.button(ButtonPart(title: "New Button")))
                }
                Button("Field", systemImage: "character.textbox") {
                    addPart(.field(FieldPart(text: "", placeholder: "")))
                }
                Button("Label", systemImage: "textformat") {
                    addPart(.label(LabelPart(text: "New Label")))
                }
                Button("Image…", systemImage: "photo") {
                    #if os(macOS)
                    isImageImporterPresented = true
                    #else
                    isPhotoPickerPresented = true
                    #endif
                }
            }
        }
        // On macOS these live in the Edit menu (see CardCommands) to keep the
        // toolbar uncluttered; iOS has no menu bar, so the toolbar menu stays.
        #if !os(macOS)
        Menu("Cards", systemImage: "rectangle.stack") {
            Button("New Card", systemImage: "rectangle.badge.plus") {
                addCard()
            }
            Button("New Background", systemImage: "rectangle.on.rectangle.badge.plus") {
                addBackground()
            }
            Divider()
            Button("Cut Card", systemImage: "scissors") {
                cutCard()
            }
            .disabled(!canDeleteCurrentCard)
            Button("Copy Card", systemImage: "doc.on.doc") {
                copyCard()
            }
            Button("Paste Card", systemImage: "doc.on.clipboard") {
                pasteCard()
            }
            .disabled(cardClipboard.payload == nil)
            Divider()
            Button("Delete Card", systemImage: "trash", role: .destructive) {
                deleteCurrentCard()
            }
            .disabled(!canDeleteCurrentCard)
        }
        #endif
        Menu("Arrange", systemImage: "square.3.layers.3d") {
            Button("Bring to Front", systemImage: "arrow.up.to.line") { arrangeSelectedPart(.front) }
            Button("Bring Closer", systemImage: "chevron.up") { arrangeSelectedPart(.closer) }
            Button("Send Farther", systemImage: "chevron.down") { arrangeSelectedPart(.farther) }
            Button("Send to Back", systemImage: "arrow.down.to.line") { arrangeSelectedPart(.back) }
        }
        .disabled(selectedPartID == nil)
        // HyperCard's button/field tool highlighting: outline all buttons or
        // fields so transparent and hidden ones are findable while editing.
        Menu("Reveal", systemImage: "eye") {
            Toggle("Show Buttons", isOn: $revealButtons)
            Toggle("Show Fields", isOn: $revealFields)
        }
        // Painting is an iPad capability (finger/Pencil); the Mac imports
        // finished art as images instead. See PaintEditor.
        #if os(iOS)
        Menu("Paint", systemImage: "paintbrush") {
            Button("Paint on Card", systemImage: "rectangle") {
                openPaintEditor(target: .card)
            }
            Button("Paint on Background", systemImage: "rectangle.on.rectangle") {
                openPaintEditor(target: .background)
            }
        }
        #endif
        Toggle(isOn: $isSnappingEnabled) {
            Label("Snap to Guides", systemImage: "grid")
        }
        .toggleStyle(.button)
        Button("Inspector", systemImage: "slider.horizontal.3") {
            isInspectorPresented = true
        }
    }

    private func makeHost() -> DocumentScriptHost {
        DocumentScriptHost(
            stack: stack,
            currentCardIndex: $currentCardIndex,
            onMessage: { text in
                // `put` with no destination opens the message box, as in
                // HyperCard.
                messageBoxText = text
                isMessageBoxVisible = true
            },
            // `answer` / `ask` present a modal and suspend the script until
            // the user responds, resuming the interpreter's continuation.
            onAnswer: { prompt, buttons in
                await withCheckedContinuation { continuation in
                    scriptDialog = ScriptDialog(prompt: prompt, kind: .answer(buttons: buttons)) { result in
                        continuation.resume(returning: result ?? buttons.first ?? "OK")
                    }
                }
            },
            onAsk: { prompt, initial in
                await withCheckedContinuation { continuation in
                    askFieldText = initial
                    scriptDialog = ScriptDialog(prompt: prompt, kind: .ask) { result in
                        continuation.resume(returning: result)
                    }
                }
            },
            // A scripted `go`: play the first queued effect as an animated
            // card swap, or cut instantly when there's none.
            onNavigate: { index, effects in
                guard let effect = effects.first else {
                    cardTransition = nil
                    currentCardIndex = index
                    return
                }
                // Set the transition first so the *outgoing* card carries it
                // (a true crossfade needs both cards animating); swap on the
                // next runloop tick, inside the animation.
                cardTransition = effect
                DispatchQueue.main.async {
                    withAnimation(effect.animation) { currentCardIndex = index }
                }
            },
            // `find` boxes the matched field (or clears the box on a miss).
            onFind: { highlight in
                findHighlight = highlight
            },
            // `go home` opens the Home stack (macOS; iOS front door is Home).
            onGoHome: { openHome() },
            // `click at h,v` routes a mouseUp to the part under the point.
            onClickPart: { part in sendMouseMessage("mouseUp", to: part) },
            // `go stack "X"` resolves via the Stack Library and opens it.
            onGoStack: { name, card in goToStack(named: name, card: card) }
        )
    }

    /// Resolves `go stack "<name>"` through the Stack Library and opens it;
    /// if the name isn't known yet, prompts the user to locate it once.
    private func goToStack(named name: String, card: GoDestination?) {
        if let url = StackLibrary.shared.url(forName: name) {
            openResolvedStack(url, card: card)
        } else {
            pendingGoStack = PendingGoStack(name: name, card: card)
            isStackLocatorPresented = true
        }
    }

    /// Opens a resolved stack file, remembering it in the library. macOS opens
    /// a document window; iOS layers it over Home via the injected handler.
    private func openResolvedStack(_ url: URL, card: GoDestination?) {
        StackLibrary.shared.register(url: url)
        // Stash the target card so the opened stack lands on it (both the
        // macOS window and the iOS layer start a fresh ContentView at card 0).
        if let card {
            PendingStackNavigation.shared.set(name: StackLibrary.name(for: url), card: card)
        }
        #if os(macOS)
        Task { try? await openDocument(at: url) }
        #else
        onOpenStackFile?(url, card)
        #endif
    }

    struct PendingGoStack {
        let name: String
        let card: GoDestination?
    }

    /// Runs a line typed into the message box in the current card's
    /// context; bare expressions display their value as output.
    private func runMessageBoxCommand(_ line: String) {
        let host = makeHost()
        let path = scriptPath(cardAt: cardIndex, part: nil)
        Task { @MainActor in
            do {
                if let value = try await HyperTalk.execute(messageLine: line, along: path, host: host) {
                    messageBoxText = value
                }
            } catch {
                scriptErrorText = error.localizedDescription
            }
        }
    }

    /// The HyperCard message path for an object on the given card:
    /// part → card → background → stack.
    private func scriptPath(cardAt index: Int, part: Part?) -> [ScriptLayer] {
        guard document.stack.cards.indices.contains(index) else { return [] }
        let card = document.stack.cards[index]
        var layers: [ScriptLayer] = []
        if let part {
            let kind = part.kind.word
            // A part on this card is a card part; otherwise it belongs to the
            // shared background. Addressed by permanent id so `me` / `the
            // target` survive renames.
            let domain: HyperTalkObject.PartDomain = card.parts.contains(where: { $0.id == part.id }) ? .card : .background
            let object = HyperTalkObject.part(kind: kind, domain: domain, reference: .id(String(part.scriptID)))
            layers.append(ScriptLayer(name: "\(kind) \"\(part.name)\" script", source: part.script, object: object))
        }
        layers.append(ScriptLayer(name: "card \"\(card.name)\" script", source: card.script, object: .thisCard))
        if let background = document.stack.backgrounds.first(where: { $0.id == card.backgroundID }) {
            layers.append(ScriptLayer(name: "background script", source: background.script, object: .thisBackground))
        }
        layers.append(ScriptLayer(name: "stack script", source: document.stack.script, object: .thisStack))
        return layers
    }

    /// Dispatches a mouse message (mouseDown/mouseUp) from a press on a
    /// part, or on the card itself when `part` is nil. All pointing devices
    /// — finger, Pencil, trackpad, mouse — arrive through the same gestures.
    /// A link tapped in a rich field: card links navigate here (like `go`);
    /// web links hand off to the system browser. The app never fetches.
    private func followLink(_ link: FieldLink) {
        switch link {
        case .card(let reference):
            let cards = document.stack.cards
            let target: Int?
            if let number = Int(reference), (1...cards.count).contains(number) {
                target = number - 1
            } else if let index = cards.firstIndex(where: {
                $0.name.caseInsensitiveCompare(reference) == .orderedSame
            }) {
                target = index
            } else {
                target = nil // an unknown reference is ignored (no navigation)
            }
            if let target, target != cardIndex {
                // Following a card link pushes the source card, so a script
                // can `pop card` back to it (as an automatic `push card`).
                CardBackStack.shared.ids.append(String(cards[cardIndex].scriptID))
                currentCardIndex = target
            }
        case .external(let url):
            openURL(url)
        }
    }

    private func sendMouseMessage(_ message: String, to part: Part?) {
        let host = makeHost()
        let path = scriptPath(cardAt: cardIndex, part: part)
        Task { @MainActor in
            do {
                try await HyperTalk.send(message, along: path, host: host)
            } catch {
                scriptErrorText = error.localizedDescription
            }
        }
    }

    /// System messages go to the card and up. Suppressed while editing,
    /// and while another system message is running (so an openCard that
    /// navigates can't cascade within one dispatch).
    private func sendSystemMessage(_ message: String, toCardAt index: Int) {
        guard !isEditing, !isSendingSystemMessage else { return }
        isSendingSystemMessage = true
        let host = makeHost()
        let path = scriptPath(cardAt: index, part: nil)
        Task { @MainActor in
            defer { isSendingSystemMessage = false }
            do {
                try await HyperTalk.send(message, along: path, host: host)
            } catch {
                scriptErrorText = error.localizedDescription
            }
        }
    }

    // MARK: - Editing

    /// The selected part may live on the current card or its background.
    private func partBinding(for id: UUID) -> Binding<Part>? {
        let index = cardIndex
        let current = document.stack
        if let partIndex = current.cards[index].parts.firstIndex(where: { $0.id == id }) {
            return stack.cards[index].parts[partIndex]
        }
        let card = current.cards[index]
        if let backgroundIndex = current.backgrounds.firstIndex(where: { $0.id == card.backgroundID }),
           let partIndex = current.backgrounds[backgroundIndex].parts.firstIndex(where: { $0.id == id }) {
            return stack.backgrounds[backgroundIndex].parts[partIndex]
        }
        return nil
    }

    private func addPart(_ kind: PartKind) {
        let size: (width: Double, height: Double) = switch kind {
        case .button: (160, 56)
        case .field, .label: (320, 56)
        case .image: (320, 320) // images arrive via addImagePart instead
        }
        let cardSize = document.stack.cardSize
        let script = if case .button = kind {
            "on mouseUp\n  \nend mouseUp"
        } else {
            ""
        }
        let part = Part(
            id: UUID(),
            name: defaultName(for: kind),
            frame: PartFrame(
                x: (cardSize.width - size.width) / 2,
                y: (cardSize.height - size.height) / 2,
                width: size.width,
                height: size.height
            ),
            script: script,
            kind: kind
        )
        appendNewPart(part)
    }

    /// Appends a newly-created part to the card or the current card's shared
    /// background, per the New Parts layer selector, and selects it.
    private func appendNewPart(_ part: Part) {
        var part = part
        var updated = document.stack
        part.scriptID = updated.claimScriptID()
        let card = updated.cards[cardIndex]
        if objectScope == .background,
           let backgroundIndex = updated.backgrounds.firstIndex(where: { $0.id == card.backgroundID }) {
            updated.backgrounds[backgroundIndex].parts.append(part)
        } else {
            updated.cards[cardIndex].parts.append(part)
        }
        stack.wrappedValue = updated
        selectedPartID = part.id
    }

    /// The layer new parts land on, per the inspector's tab (Stack acts as
    /// Card, since parts can't live on the stack).
    private var newPartLayerName: String {
        objectScope == .background ? "Background" : "Card"
    }

    #if os(iOS)
    /// Which paint layer is being edited: the current card's own, or the
    /// shared background's (visible on every card using that background).
    enum PaintTarget {
        case card
        case background
    }

    private var currentBackgroundIndex: Int? {
        let backgroundID = document.stack.cards[cardIndex].backgroundID
        return document.stack.backgrounds.firstIndex { $0.id == backgroundID }
    }

    /// Opens paint mode on the chosen layer, loading its existing strokes
    /// (paintings stay editable — the stroke data lives in the stack).
    private func openPaintEditor(target: PaintTarget) {
        paintTarget = target
        let drawingAsset: String? = switch target {
        case .card:
            document.stack.cards[cardIndex].paintDrawingAsset
        case .background:
            currentBackgroundIndex.flatMap { document.stack.backgrounds[$0].paintDrawingAsset }
        }
        if let drawingAsset,
           let data = document.assets[drawingAsset],
           let existing = try? PKDrawing(data: data) {
            paintDrawingToEdit = existing
        } else {
            paintDrawingToEdit = PKDrawing()
        }
        isPaintingPresented = true
    }

    /// Stores the finished drawing twice — the editable PencilKit data and
    /// a rendered PNG for display — and points the target layer at both.
    /// An empty drawing clears the layer.
    private func savePaint(_ drawing: PKDrawing) {
        var updated = document.stack
        var drawingName: String?
        var imageName: String?
        if !drawing.strokes.isEmpty {
            let cardSize = document.stack.cardSize
            let bounds = CGRect(x: 0, y: 0, width: cardSize.width, height: cardSize.height)
            guard let png = drawing.image(from: bounds, scale: 2).pngDataCrossPlatform else { return }
            drawingName = document.storeAsset(drawing.dataRepresentation(), preferredExtension: "drawing")
            imageName = document.storeAsset(png)
        }
        switch paintTarget {
        case .card:
            updated.cards[cardIndex].paintDrawingAsset = drawingName
            updated.cards[cardIndex].paintImageAsset = imageName
        case .background:
            guard let backgroundIndex = currentBackgroundIndex else { return }
            updated.backgrounds[backgroundIndex].paintDrawingAsset = drawingName
            updated.backgrounds[backgroundIndex].paintImageAsset = imageName
        }
        stack.wrappedValue = updated
    }
    #endif

    /// Imports picked image data as an asset and places an image part
    /// sized to fit, centered on the current card.
    private func addImagePart(data: Data, imageSize: CGSize) {
        let assetName = document.storeAsset(data)
        let cardSize = document.stack.cardSize
        // Bring the image in at its natural pixel size, only shrinking it to
        // fit the card when it's larger — never scaling a small image up.
        let scale = min(1, min(cardSize.width / imageSize.width, cardSize.height / imageSize.height))
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let part = Part(
            id: UUID(),
            name: defaultName(for: .image(ImagePart(assetName: assetName))),
            frame: PartFrame(
                x: (cardSize.width - width) / 2,
                y: (cardSize.height - height) / 2,
                width: width,
                height: height
            ),
            script: "",
            kind: .image(ImagePart(assetName: assetName))
        )
        appendNewPart(part)
    }

    private func defaultName(for kind: PartKind) -> String {
        let base = switch kind {
        case .button: "Button"
        case .field: "Field"
        case .label: "Label"
        case .image: "Image"
        }
        let existing = document.stack.cards[cardIndex].parts.count
        return "\(base) \(existing + 1)"
    }

    /// Z-order changes for the selected part, within its own layer (later
    /// in the array = nearer the front). Part order is also part number, so
    /// this changes ordinals too — as in HyperCard.
    enum ArrangeAction { case front, closer, farther, back }

    private func arrangeSelectedPart(_ action: ArrangeAction) {
        guard let id = selectedPartID else { return }
        var updated = document.stack
        let index = cardIndex
        if reorder(&updated.cards[index].parts, id: id, action: action) {
            stack.wrappedValue = updated
            return
        }
        let card = updated.cards[index]
        if let backgroundIndex = updated.backgrounds.firstIndex(where: { $0.id == card.backgroundID }),
           reorder(&updated.backgrounds[backgroundIndex].parts, id: id, action: action) {
            stack.wrappedValue = updated
        }
    }

    private func reorder(_ parts: inout [Part], id: UUID, action: ArrangeAction) -> Bool {
        guard let i = parts.firstIndex(where: { $0.id == id }) else { return false }
        switch action {
        case .front:
            parts.append(parts.remove(at: i))
        case .back:
            parts.insert(parts.remove(at: i), at: 0)
        case .closer:
            if i < parts.count - 1 { parts.swapAt(i, i + 1) }
        case .farther:
            if i > 0 { parts.swapAt(i, i - 1) }
        }
        return true
    }

    private func deletePart(id: UUID) {
        var updated = document.stack
        let index = cardIndex
        updated.cards[index].parts.removeAll { $0.id == id }
        let card = updated.cards[index]
        if let backgroundIndex = updated.backgrounds.firstIndex(where: { $0.id == card.backgroundID }) {
            updated.backgrounds[backgroundIndex].parts.removeAll { $0.id == id }
        }
        stack.wrappedValue = updated
        selectedPartID = nil
    }

    // MARK: - Cut / Copy / Paste Part

    /// The selected part, wherever it lives (card layer or background layer).
    private func selectedPart() -> Part? {
        guard let id = selectedPartID else { return nil }
        if let part = document.stack.cards[cardIndex].parts.first(where: { $0.id == id }) {
            return part
        }
        let card = document.stack.cards[cardIndex]
        if let background = document.stack.backgrounds.first(where: { $0.id == card.backgroundID }) {
            return background.parts.first(where: { $0.id == id })
        }
        return nil
    }

    private func copySelectedPart() {
        guard let part = selectedPart() else { return }
        var assets: [String: Data] = [:]
        if case .image(let image) = part.kind, let data = document.assets[image.assetName] {
            assets[image.assetName] = data
        }
        partClipboard.payload = PartClipboard.Payload(part: part, assets: assets)
    }

    private func cutSelectedPart() {
        guard let id = selectedPartID, selectedPart() != nil else { return }
        copySelectedPart()
        deletePart(id: id)
    }

    /// Pastes the clipboard's part onto the current card, nudged down-right so
    /// it doesn't hide the original, with a fresh identity so repeated pastes
    /// never collide. Asset names are UUIDs, so re-adding them can't clash.
    private func pastePart() {
        guard let payload = partClipboard.payload else { return }
        for (name, data) in payload.assets where document.assets[name] == nil {
            document.assets[name] = data
        }
        var updated = document.stack
        var part = payload.part
        part.id = UUID()
        part.scriptID = updated.claimScriptID()
        part.frame.x += 20
        part.frame.y += 20
        updated.cards[cardIndex].parts.append(part)
        stack.wrappedValue = updated
        selectedPartID = part.id
    }

    /// Duplicates the selected part in place — a fresh copy nudged down-right,
    /// without touching the clipboard (as macOS's Duplicate does).
    private func duplicateSelectedPart() {
        guard let part = selectedPart() else { return }
        var updated = document.stack
        var copy = part
        copy.id = UUID()
        copy.scriptID = updated.claimScriptID()
        copy.frame.x += 20
        copy.frame.y += 20
        updated.cards[cardIndex].parts.append(copy)
        stack.wrappedValue = updated
        selectedPartID = copy.id
    }

    /// Part-editing actions published to the Edit menu on macOS. The flags are
    /// only true in edit mode, so the menu falls back to text editing (and
    /// card operations) otherwise.
    private var partActions: PartActions {
        PartActions(
            cut: cutSelectedPart,
            copy: copySelectedPart,
            paste: pastePart,
            duplicate: duplicateSelectedPart,
            delete: { if let id = selectedPartID { deletePart(id: id) } },
            canCopy: isEditing && selectedPartID != nil,
            canPaste: isEditing && partClipboard.payload != nil
        )
    }

    private func addCard() {
        let current = document.stack.cards[cardIndex]
        var card = Card(
            id: UUID(),
            name: "Card \(document.stack.cards.count + 1)",
            backgroundID: current.backgroundID,
            script: "",
            parts: []
        )
        var updated = document.stack
        card.scriptID = updated.claimScriptID()
        updated.cards.insert(card, at: cardIndex + 1)
        stack.wrappedValue = updated
        currentCardIndex = cardIndex + 1
        selectedPartID = nil
    }

    /// New Background: a fresh background plus a card on it — HyperCard's
    /// distinction from New Card (which reuses the current background).
    private func addBackground() {
        var updated = document.stack
        var background = Background(
            id: UUID(),
            name: "Background \(updated.backgrounds.count + 1)",
            script: "",
            parts: []
        )
        background.scriptID = updated.claimScriptID()
        updated.backgrounds.append(background)
        var card = Card(
            id: UUID(),
            name: "Card \(updated.cards.count + 1)",
            backgroundID: background.id,
            script: "",
            parts: []
        )
        card.scriptID = updated.claimScriptID()
        updated.cards.insert(card, at: cardIndex + 1)
        stack.wrappedValue = updated
        currentCardIndex = cardIndex + 1
        selectedPartID = nil
    }

    // MARK: - Cut / Copy / Paste Card

    private func copyCard() {
        let card = document.stack.cards[cardIndex]
        let background = document.stack.backgrounds.first { $0.id == card.backgroundID }
        var assets: [String: Data] = [:]
        for name in referencedAssetNames(card: card, background: background) {
            if let data = document.assets[name] { assets[name] = data }
        }
        cardClipboard.payload = CardClipboard.Payload(card: card, background: background, assets: assets)
    }

    private func cutCard() {
        copyCard()
        deleteCurrentCard()
    }

    private func pasteCard() {
        guard let payload = cardClipboard.payload else { return }

        // Bring over any assets the card/background reference but the target
        // doesn't have yet (UUID names never collide).
        for (name, data) in payload.assets where document.assets[name] == nil {
            document.assets[name] = data
        }

        var updated = document.stack
        var backgroundID = payload.card.backgroundID

        // If the source background isn't in this stack, insert a copy with
        // fresh part identities but the same UUID so the card can find it.
        if let background = payload.background,
           !updated.backgrounds.contains(where: { $0.id == background.id }) {
            var copy = background
            copy.scriptID = updated.claimScriptID()
            copy.parts = copy.parts.map { freshIdentity($0, in: &updated) }
            updated.backgrounds.append(copy)
            backgroundID = copy.id
        }

        var card = payload.card
        card.id = UUID()
        card.scriptID = updated.claimScriptID()
        card.backgroundID = backgroundID
        card.parts = card.parts.map { freshIdentity($0, in: &updated) }
        updated.cards.insert(card, at: cardIndex + 1)

        stack.wrappedValue = updated
        currentCardIndex = cardIndex + 1
        selectedPartID = nil
    }

    /// A copy of a part with a new UUID and a freshly claimed scriptID.
    private func freshIdentity(_ part: Part, in stack: inout Stack) -> Part {
        var part = part
        part.id = UUID()
        part.scriptID = stack.claimScriptID()
        return part
    }

    private func referencedAssetNames(card: Card, background: Background?) -> Set<String> {
        var names: Set<String> = []
        func collect(_ paintDrawing: String?, _ paintImage: String?, _ parts: [Part]) {
            if let paintDrawing { names.insert(paintDrawing) }
            if let paintImage { names.insert(paintImage) }
            for part in parts {
                if case .image(let image) = part.kind { names.insert(image.assetName) }
            }
        }
        collect(card.paintDrawingAsset, card.paintImageAsset, card.parts)
        if let background {
            collect(background.paintDrawingAsset, background.paintImageAsset, background.parts)
        }
        return names
    }

    /// Whether the current card may be deleted: more than one card exists,
    /// the card isn't protected, and deleting it wouldn't remove a
    /// protected background (its last card).
    private var canDeleteCurrentCard: Bool {
        guard document.stack.cards.count > 1 else { return false }
        guard !document.stack.cards[cardIndex].cantDelete else { return false }
        let backgroundID = document.stack.cards[cardIndex].backgroundID
        let othersShareBackground = document.stack.cards.enumerated()
            .contains { $0.offset != cardIndex && $0.element.backgroundID == backgroundID }
        if !othersShareBackground,
           let background = document.stack.backgrounds.first(where: { $0.id == backgroundID }),
           background.cantDelete {
            return false
        }
        return true
    }

    private func deleteCurrentCard() {
        guard canDeleteCurrentCard else { return }
        stack.wrappedValue.cards.remove(at: cardIndex)
        currentCardIndex = min(cardIndex, document.stack.cards.count - 1)
        selectedPartID = nil
    }

    // MARK: - Navigation

    /// The card prev/next controls sit in the bottom bar on iOS; macOS has
    /// no bottom bar, so they join the main toolbar.
    private var cardNavigationPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .bottomBar
        #else
        .automatic
        #endif
    }

    /// Clamped so a shorter reopened stack can't strand the index.
    private var cardIndex: Int {
        min(currentCardIndex, document.stack.cards.count - 1)
    }

    /// Resolves a `go card N of stack "X"` destination to a card index in this
    /// (the just-opened) stack, for the cases that name an initial card. Other
    /// destinations (next/previous/home/back/another stack) yield nil.
    private func cardIndexFor(_ destination: GoDestination) -> Int? {
        let cards = document.stack.cards
        guard !cards.isEmpty else { return nil }
        switch destination {
        case .first: return 0
        case .last: return cards.count - 1
        case .number(let n): return (1...cards.count).contains(n) ? n - 1 : nil
        case .named(let name): return cards.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            return cards.firstIndex { String($0.scriptID) == wanted }
        case .inBackground(let inner, let background):
            let indices = cards.indices.filter {
                backgroundName(ofCardAt: $0)?.caseInsensitiveCompare(background) == .orderedSame
            }
            guard !indices.isEmpty else { return nil }
            switch inner {
            case .first: return indices.first
            case .last: return indices.last
            case .number(let n): return (1...indices.count).contains(n) ? indices[n - 1] : nil
            default: return indices.first
            }
        default: return nil
        }
    }

    private func backgroundName(ofCardAt index: Int) -> String? {
        let backgroundID = document.stack.cards[index].backgroundID
        return document.stack.backgrounds.first { $0.id == backgroundID }?.name
    }

    private func goToNextCard() {
        let count = document.stack.cards.count
        guard count > 0 else { return }
        currentCardIndex = (cardIndex + 1) % count
    }

    private func goToPreviousCard() {
        let count = document.stack.cards.count
        guard count > 0 else { return }
        currentCardIndex = (cardIndex + count - 1) % count
    }

    private func goFirst() { currentCardIndex = 0 }
    private func goLast() { currentCardIndex = max(0, document.stack.cards.count - 1) }

    /// Opens the Home stack (seeding it on first use) as a document.
    /// macOS-only: SwiftUI's openDocument action isn't available on iOS,
    /// where the document browser is the front door.
    private func openHome() {
        #if os(macOS)
        let url = HomeStack.ensureSeeded()
        Task { try? await openDocument(at: url) }
        #endif
    }

    /// Within-stack navigation actions published to the Go menu.
    private var cardNavigation: CardNavigation {
        CardNavigation(
            goFirst: goFirst, goLast: goLast,
            goPrevious: goToPreviousCard, goNext: goToNextCard
        )
    }

    /// Card-management actions published to the Edit menu on macOS (where the
    /// toolbar's Cards menu is omitted to keep the toolbar clean).
    private var cardActions: CardActions {
        CardActions(
            newCard: addCard,
            newBackground: addBackground,
            cutCard: cutCard,
            copyCard: copyCard,
            pasteCard: pasteCard,
            deleteCard: deleteCurrentCard,
            canDeleteCard: canDeleteCurrentCard,
            canPasteCard: cardClipboard.payload != nil
        )
    }
}

/// A pending script dialog: `answer` shows a row of buttons, `ask` shows a
/// text field with OK/Cancel. `complete` resumes the suspended interpreter
/// — with the button label for `answer`, or the entered text (nil if
/// cancelled) for `ask`.
struct ScriptDialog: Identifiable {
    let id = UUID()
    let prompt: String
    let kind: Kind
    let complete: (String?) -> Void

    enum Kind {
        case answer(buttons: [String])
        case ask
    }
}

/// Bridges the focused document's navigation to app-level menu commands
/// (the Go menu). Nil when no document is focused, which disables the menu.
struct CardNavigation {
    var goFirst: () -> Void
    var goLast: () -> Void
    var goPrevious: () -> Void
    var goNext: () -> Void
}

/// An in-app clipboard for whole cards. Carries the card, its background,
/// and the asset bytes both reference, so Paste works within a document
/// and across windows. Asset names are UUIDs, so re-inserting them can't
/// collide.
final class CardClipboard: ObservableObject {
    static let shared = CardClipboard()

    struct Payload {
        let card: Card
        let background: Background?
        let assets: [String: Data]
    }

    @Published var payload: Payload?
}

/// Bridges the focused document's part-editing actions (Cut/Copy/Paste/Delete
/// on the selected part) to the Edit menu on macOS. `canCopy`/`canPaste` are
/// only true in edit mode with a selection, so the standard text and card
/// actions take over otherwise.
struct PartActions {
    var cut: () -> Void
    var copy: () -> Void
    var paste: () -> Void
    var duplicate: () -> Void
    var delete: () -> Void
    var canCopy: Bool
    var canPaste: Bool
}

/// An in-app clipboard for a single part, carrying any asset bytes the part
/// references (image parts) so Paste works across cards and windows. Asset
/// names are UUIDs, so re-inserting them can't collide.
final class PartClipboard: ObservableObject {
    static let shared = PartClipboard()

    struct Payload {
        let part: Part
        let assets: [String: Data]
    }

    @Published var payload: Payload?
}

/// Bridges the focused document's card-management actions to the Edit menu
/// (macOS). Nil when no document is focused, which disables the commands.
struct CardActions {
    var newCard: () -> Void
    var newBackground: () -> Void
    var cutCard: () -> Void
    var copyCard: () -> Void
    var pasteCard: () -> Void
    var deleteCard: () -> Void
    var canDeleteCard: Bool
    var canPasteCard: Bool
}

struct CardNavigationKey: FocusedValueKey {
    typealias Value = CardNavigation
}

struct CardActionsKey: FocusedValueKey {
    typealias Value = CardActions
}

struct PartActionsKey: FocusedValueKey {
    typealias Value = PartActions
}

/// Carries a binding to the focused stack's full-screen flag, so the View
/// menu's toggle can read and flip it through @FocusedBinding.
struct StackFullScreenKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

/// Carries a binding to the focused stack's HyperTalk Guide sheet flag, so the
/// Help menu can open it (macOS, where it's not in the toolbar).
struct GuidePresentedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var cardNavigation: CardNavigation? {
        get { self[CardNavigationKey.self] }
        set { self[CardNavigationKey.self] = newValue }
    }

    var cardActions: CardActions? {
        get { self[CardActionsKey.self] }
        set { self[CardActionsKey.self] = newValue }
    }

    var partActions: PartActions? {
        get { self[PartActionsKey.self] }
        set { self[PartActionsKey.self] = newValue }
    }

    var stackFullScreen: Binding<Bool>? {
        get { self[StackFullScreenKey.self] }
        set { self[StackFullScreenKey.self] = newValue }
    }

    var guidePresented: Binding<Bool>? {
        get { self[GuidePresentedKey.self] }
        set { self[GuidePresentedKey.self] = newValue }
    }
}

#Preview {
    ContentView(document: StackDocument())
}
