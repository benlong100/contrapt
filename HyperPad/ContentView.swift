//
//  ContentView.swift
//  HyperPad
//

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
    @State private var scriptErrorText: String?
    @State private var undoFlushTask: Task<Void, Never>?
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
                    onButtonTap: runMouseUp,
                    onOpenInspector: { isInspectorPresented = true }
                )
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) {
            messageBox
        }
        .animation(.default, value: messageBoxText)
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
                    ContentUnavailableView("No Part Selected", systemImage: "cursorarrow.click")
                }
            }
            .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
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
                        Divider()
                        Button("New Card", systemImage: "rectangle.badge.plus") {
                            addCard()
                        }
                        Button("Delete Card", systemImage: "trash", role: .destructive) {
                            deleteCurrentCard()
                        }
                        .disabled(document.stack.cards.count <= 1)
                    }
                    Toggle(isOn: $isSnappingEnabled) {
                        Label("Snap to Guides", systemImage: "grid")
                    }
                    .toggleStyle(.button)
                    Button("Part Info", systemImage: "slider.horizontal.3") {
                        isInspectorPresented = true
                    }
                    .disabled(selectedPartID == nil)
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

    /// HyperCard's message box, minimally: `put` with no destination lands
    /// here. Tap to dismiss.
    @ViewBuilder
    private var messageBox: some View {
        if let messageBoxText {
            Text(messageBoxText)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
                .onTapGesture { self.messageBoxText = nil }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Script dispatch

    private func runMouseUp(on part: Part) {
        let host = DocumentScriptHost(
            stack: stack,
            currentCardIndex: $currentCardIndex,
            onMessage: { messageBoxText = $0 }
        )
        do {
            try HyperTalk.run(handler: "mouseUp", in: part.script, host: host)
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

    private func defaultName(for kind: PartKind) -> String {
        let base = switch kind {
        case .button: "Button"
        case .field: "Field"
        case .label: "Label"
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
