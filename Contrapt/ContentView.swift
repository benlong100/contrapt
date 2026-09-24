//
//  ContentView.swift
//  Contrapt
//

import PencilKit
import PhotosUI
import SwiftUI
import HyperTalk

/// The document view. Browse mode shows the current card with live parts;
/// button taps dispatch mouseUp through the interpreter. Edit mode makes
/// parts selectable, movable, and resizable, with a property inspector.
struct ContentView: View {
    @ObservedObject var document: StackDocument
    /// The document's location on disk, for sharing. Nil until first save.
    var fileURL: URL?
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openDocument) private var openDocument

    @State private var currentCardIndex = 0
    @State private var isEditing = false
    @State private var selectedPartID: UUID?
    @State private var isInspectorPresented = false
    @State private var messageBoxText: String?
    @State private var isMessageBoxVisible = false
    @State private var scriptErrorText: String?
    @State private var undoFlushTask: Task<Void, Never>?
    @State private var isPhotoPickerPresented = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isPaintingPresented = false
    @State private var paintDrawingToEdit = PKDrawing()
    @State private var paintTarget: PaintTarget = .card
    /// The button being linked, while the Link To panel floats over the card.
    @State private var linkingPartID: UUID?
    @State private var isGuidePresented = false
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

    var body: some View {
        Group {
            if document.stack.cards.isEmpty {
                ContentUnavailableView("No Cards", systemImage: "rectangle.on.rectangle.slash")
            } else {
                CardView(
                    stack: stack,
                    cardIndex: cardIndex,
                    isEditing: isEditing,
                    isSnappingEnabled: isSnappingEnabled,
                    selectedPartID: $selectedPartID,
                    onMouseMessage: sendMouseMessage,
                    onOpenInspector: { isInspectorPresented = true }
                )
                .padding()
            }
        }
        .environment(\.stackAssets, document.assets)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cardBackdrop)
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
        .sheet(isPresented: $isGuidePresented) {
            HyperTalkGuideView()
        }
        .platformFullScreenCover(isPresented: $isPaintingPresented) {
            PaintEditor(
                title: paintTarget == .card ? "Paint on Card" : "Paint on Background",
                cardSize: document.stack.cardSize,
                initialDrawing: paintDrawingToEdit
            ) { finished in
                savePaint(finished)
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            selectedPhoto = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = PlatformImage(data: data) else { return }
                addImagePart(data: data, imageSize: image.size)
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
                    ObjectScriptsInspector(stack: stack, cardIndex: cardIndex)
                }
            }
            .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        }
        .onChange(of: cardIndex) { _, newIndex in
            sendSystemMessage("openCard", toCardAt: newIndex)
        }
        .task {
            sendSystemMessage("openStack", toCardAt: cardIndex)
            sendSystemMessage("openCard", toCardAt: cardIndex)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isEditing {
                    Menu("Add", systemImage: "plus") {
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
                            isPhotoPickerPresented = true
                        }
                        Divider()
                        Button("New Card", systemImage: "rectangle.badge.plus") {
                            addCard()
                        }
                        Button("Delete Card", systemImage: "trash", role: .destructive) {
                            deleteCurrentCard()
                        }
                        .disabled(document.stack.cards.count <= 1 || document.stack.cards[cardIndex].cantDelete)
                    }
                    Menu("Paint", systemImage: "paintbrush") {
                        Button("Paint on Card", systemImage: "rectangle") {
                            openPaintEditor(target: .card)
                        }
                        Button("Paint on Background", systemImage: "rectangle.on.rectangle") {
                            openPaintEditor(target: .background)
                        }
                    }
                    Toggle(isOn: $isSnappingEnabled) {
                        Label("Snap to Guides", systemImage: "grid")
                    }
                    .toggleStyle(.button)
                    Button("Inspector", systemImage: "slider.horizontal.3") {
                        isInspectorPresented = true
                    }
                }
                Button("Home", systemImage: "house") {
                    openHome()
                }
                Button("HyperTalk Guide", systemImage: "book") {
                    isGuidePresented = true
                }
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
                    Button("Home", systemImage: "house") { openHome() }
                    Divider()
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
        .focusedValue(\.cardNavigation, cardNavigation)
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

    private func makeHost() -> DocumentScriptHost {
        DocumentScriptHost(
            stack: stack,
            currentCardIndex: $currentCardIndex,
            onMessage: { text in
                // `put` with no destination opens the message box, as in
                // HyperCard.
                messageBoxText = text
                isMessageBoxVisible = true
            }
        )
    }

    /// Runs a line typed into the message box in the current card's
    /// context; bare expressions display their value as output.
    private func runMessageBoxCommand(_ line: String) {
        do {
            if let value = try HyperTalk.execute(messageLine: line, along: scriptPath(cardAt: cardIndex, part: nil), host: makeHost()) {
                messageBoxText = value
            }
        } catch {
            scriptErrorText = error.localizedDescription
        }
    }

    /// The HyperCard message path for an object on the given card:
    /// part → card → background → stack.
    private func scriptPath(cardAt index: Int, part: Part?) -> [ScriptLayer] {
        guard document.stack.cards.indices.contains(index) else { return [] }
        let card = document.stack.cards[index]
        var layers: [ScriptLayer] = []
        if let part {
            let kind = switch part.kind {
            case .button: "button"
            case .field: "field"
            case .label: "label"
            case .image: "image"
            }
            layers.append(ScriptLayer(name: "\(kind) \"\(part.name)\" script", source: part.script))
        }
        layers.append(ScriptLayer(name: "card \"\(card.name)\" script", source: card.script))
        if let background = document.stack.backgrounds.first(where: { $0.id == card.backgroundID }) {
            layers.append(ScriptLayer(name: "background script", source: background.script))
        }
        layers.append(ScriptLayer(name: "stack script", source: document.stack.script))
        return layers
    }

    /// Dispatches a mouse message (mouseDown/mouseUp) from a press on a
    /// part, or on the card itself when `part` is nil. All pointing devices
    /// — finger, Pencil, trackpad, mouse — arrive through the same gestures.
    private func sendMouseMessage(_ message: String, to part: Part?) {
        do {
            try HyperTalk.send(message, along: scriptPath(cardAt: cardIndex, part: part), host: makeHost())
        } catch {
            scriptErrorText = error.localizedDescription
        }
    }

    /// System messages go to the card and up. Suppressed while editing,
    /// and while another system message is running (so an openCard that
    /// navigates can't cascade within one dispatch).
    private func sendSystemMessage(_ message: String, toCardAt index: Int) {
        guard !isEditing, !isSendingSystemMessage else { return }
        isSendingSystemMessage = true
        defer { isSendingSystemMessage = false }
        do {
            try HyperTalk.send(message, along: scriptPath(cardAt: index, part: nil), host: makeHost())
        } catch {
            scriptErrorText = error.localizedDescription
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
        var part = Part(
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
        var updated = document.stack
        part.scriptID = updated.claimScriptID()
        updated.cards[cardIndex].parts.append(part)
        stack.wrappedValue = updated
        selectedPartID = part.id
    }

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

    /// Imports picked image data as an asset and places an image part
    /// sized to fit, centered on the current card.
    private func addImagePart(data: Data, imageSize: CGSize) {
        let assetName = document.storeAsset(data)
        let maxSide: Double = 400
        let scale = min(1, min(maxSide / imageSize.width, maxSide / imageSize.height))
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let cardSize = document.stack.cardSize
        var part = Part(
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
        var updated = document.stack
        part.scriptID = updated.claimScriptID()
        updated.cards[cardIndex].parts.append(part)
        stack.wrappedValue = updated
        selectedPartID = part.id
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

    private func deleteCurrentCard() {
        guard document.stack.cards.count > 1 else { return }
        guard !document.stack.cards[cardIndex].cantDelete else { return }
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
    private func openHome() {
        let url = HomeStack.ensureSeeded()
        Task { try? await openDocument(at: url) }
    }

    /// Within-stack navigation actions published to the Go menu.
    private var cardNavigation: CardNavigation {
        CardNavigation(
            goFirst: goFirst, goLast: goLast,
            goPrevious: goToPreviousCard, goNext: goToNextCard
        )
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

struct CardNavigationKey: FocusedValueKey {
    typealias Value = CardNavigation
}

extension FocusedValues {
    var cardNavigation: CardNavigation? {
        get { self[CardNavigationKey.self] }
        set { self[CardNavigationKey.self] = newValue }
    }
}

#Preview {
    ContentView(document: StackDocument())
}
