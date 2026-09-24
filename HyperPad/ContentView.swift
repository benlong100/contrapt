//
//  ContentView.swift
//  HyperPad
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
    @Environment(\.undoManager) private var undoManager

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
        .background(Color(.secondarySystemBackground))
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
        .fullScreenCover(isPresented: $isPaintingPresented) {
            PaintEditor(cardSize: document.stack.cardSize, initialDrawing: paintDrawingToEdit) { finished in
                savePaint(finished)
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            selectedPhoto = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                addImagePart(data: data, imageSize: image.size)
            }
        }
        .overlay(alignment: .bottom) {
            if isMessageBoxVisible {
                MessageBoxView(output: messageBoxText, onCommand: runMessageBoxCommand)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: isMessageBoxVisible)
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
                    PartInspector(part: partBinding) {
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
            ToolbarItemGroup(placement: .topBarTrailing) {
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
                        .disabled(document.stack.cards.count <= 1)
                    }
                    Button("Paint", systemImage: "paintbrush") {
                        openPaintEditor()
                    }
                    Toggle(isOn: $isSnappingEnabled) {
                        Label("Snap to Guides", systemImage: "grid")
                    }
                    .toggleStyle(.button)
                    Button("Inspector", systemImage: "slider.horizontal.3") {
                        isInspectorPresented = true
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
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Previous Card", systemImage: "chevron.left") {
                    goToPreviousCard()
                }
                Spacer()
                Text("Card \(cardIndex + 1) of \(document.stack.cards.count)")
                    .font(.callout)
                    .monospacedDigit()
                    .fixedSize()
                Spacer()
                Button("Next Card", systemImage: "chevron.right") {
                    goToNextCard()
                }
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
        stack.wrappedValue.cards[cardIndex].parts.append(part)
        selectedPartID = part.id
    }

    /// Opens paint mode with the current card's drawing, if any.
    private func openPaintEditor() {
        let card = document.stack.cards[cardIndex]
        if let name = card.paintDrawingAsset,
           let data = document.assets[name],
           let existing = try? PKDrawing(data: data) {
            paintDrawingToEdit = existing
        } else {
            paintDrawingToEdit = PKDrawing()
        }
        isPaintingPresented = true
    }

    /// Stores the finished drawing twice — the editable PencilKit data and
    /// a rendered PNG for display — and points the card at both. An empty
    /// drawing clears the paint layer.
    private func savePaint(_ drawing: PKDrawing) {
        if drawing.strokes.isEmpty {
            stack.wrappedValue.cards[cardIndex].paintDrawingAsset = nil
            stack.wrappedValue.cards[cardIndex].paintImageAsset = nil
            return
        }
        let cardSize = document.stack.cardSize
        let bounds = CGRect(x: 0, y: 0, width: cardSize.width, height: cardSize.height)
        let rendered = drawing.image(from: bounds, scale: 2)
        guard let png = rendered.pngData() else { return }
        let drawingName = document.storeAsset(drawing.dataRepresentation(), preferredExtension: "drawing")
        let imageName = document.storeAsset(png)
        var updated = document.stack
        updated.cards[cardIndex].paintDrawingAsset = drawingName
        updated.cards[cardIndex].paintImageAsset = imageName
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
        stack.wrappedValue.cards[cardIndex].parts.append(part)
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
        let card = Card(
            id: UUID(),
            name: "Card \(document.stack.cards.count + 1)",
            backgroundID: current.backgroundID,
            script: "",
            parts: []
        )
        stack.wrappedValue.cards.insert(card, at: cardIndex + 1)
        currentCardIndex = cardIndex + 1
        selectedPartID = nil
    }

    private func deleteCurrentCard() {
        guard document.stack.cards.count > 1 else { return }
        stack.wrappedValue.cards.remove(at: cardIndex)
        currentCardIndex = min(cardIndex, document.stack.cards.count - 1)
        selectedPartID = nil
    }

    // MARK: - Navigation

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
}

#Preview {
    ContentView(document: StackDocument())
}
