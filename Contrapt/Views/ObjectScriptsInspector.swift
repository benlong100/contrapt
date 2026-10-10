//
//  ObjectScriptsInspector.swift
//  Contrapt
//

import SwiftUI
import HyperTalk

/// Edits the scripts of the container objects — the current card, its
/// background, and the stack. Shown in the inspector when no part is
/// selected. Handlers here receive messages parts don't handle, plus
/// system messages like openCard and openStack.
struct ObjectScriptsInspector: View {
    @Binding var stack: Stack
    let cardIndex: Int
    /// Shared with the container so "Add Part" targets the selected layer.
    @Binding var scope: Scope

    enum Scope: String, CaseIterable {
        case card = "Card"
        case background = "Background"
        case stack = "Stack"
    }

    @State private var isEditorExpanded = false

    var body: some View {
        Form {
            Section {
                Picker("Object", selection: $scope) {
                    ForEach(Scope.allCases, id: \.self) { scope in
                        Text(scope.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("These scripts receive messages that parts don't handle, and system messages like openCard and openStack.")
            }
            if scope == .card {
                Section("Card") {
                    TextField("Name", text: $stack.cards[cardIndex].name)
                    HStack {
                        LabeledContent("Number", value: "\(cardIndex + 1) of \(stack.cards.count)")
                        Spacer()
                        LabeledContent("ID", value: "\(stack.cards[cardIndex].scriptID)")
                    }
                    Picker("Background", selection: cardBackgroundBinding) {
                        ForEach(Array(stack.backgrounds.enumerated()), id: \.element.id) { index, background in
                            Text(backgroundLabel(background, index: index)).tag(background.id)
                        }
                    }
                    Toggle("Card Marked", isOn: $stack.cards[cardIndex].isMarked)
                    Toggle("Don't Search Card", isOn: $stack.cards[cardIndex].dontSearch)
                    Toggle("Can't Delete Card", isOn: $stack.cards[cardIndex].cantDelete)
                }
                Section {
                    ColorPicker("Highlight Color", selection: cardHighlightBinding, supportsOpacity: false)
                    Button("Use Default Highlight") { stack.cards[cardIndex].highlightColor = nil }
                        .disabled(stack.cards[cardIndex].highlightColor == nil)
                } footer: {
                    Text("Colors this card's rich-text links and button icons. Default follows the app's accent color.")
                }
            }
            if scope == .background, let backgroundIndex {
                Section("Background") {
                    TextField("Name", text: $stack.backgrounds[backgroundIndex].name)
                    Toggle("Don't Search Background", isOn: $stack.backgrounds[backgroundIndex].dontSearch)
                    Toggle("Can't Delete Background", isOn: $stack.backgrounds[backgroundIndex].cantDelete)
                }
            }
            if scope == .stack {
                Section {
                    TextField("Name", text: $stack.name)
                    HStack {
                        LabeledContent("Cards", value: "\(stack.cards.count)")
                        Spacer()
                        LabeledContent("Backgrounds", value: "\(stack.backgrounds.count)")
                    }
                    Menu {
                        ForEach(CardSizePreset.all) { preset in
                            Button("\(preset.name)  ·  \(Int(preset.size.width)) × \(Int(preset.size.height))") {
                                stack.cardSize = preset.size
                            }
                        }
                    } label: {
                        LabeledContent("Card Size", value: cardSizeLabel)
                    }
                    HStack(spacing: 16) {
                        geometryCell("Width", value: $stack.cardSize.width)
                        geometryCell("Height", value: $stack.cardSize.height)
                    }
                } header: {
                    Text("Stack")
                } footer: {
                    Text("Card size applies to every card in the stack. Parts keep their positions, so shrinking may move some off the card.")
                }
                Section {
                    Picker("Theme", selection: $stack.theme) {
                        ForEach(ThemeSpec.all, id: \.name) { spec in
                            Text(spec.displayName).tag(spec.name)
                        }
                    }
                    Toggle("Open Full Screen", isOn: $stack.isFullScreen)
                    ColorPicker("Padding Color", selection: paddingColorBinding, supportsOpacity: false)
                } header: {
                    Text("Presentation")
                } footer: {
                    Text("Theme restyles the card's colors and controls; Classic keeps the original look and follows the system. Full screen fills the space around the card with the padding color and hides the app chrome. Press Escape to leave.")
                }
            }
            ScriptFormSection(title: scriptTitle, script: scriptBinding, onExpand: { isEditorExpanded = true })
                .id(scope)
        }
        // Return ends editing; clicking empty palette space releases focus.
        .endsTextEditingOnSubmitAndTap()
        .platformFullScreenCover(isPresented: $isEditorExpanded) {
            LargeScriptEditor(title: scriptTitle, script: scriptBinding)
        }
    }

    /// Bridges the stored padding-color string to a ColorPicker; edits are
    /// written back as #RRGGBB hex.
    private var paddingColorBinding: Binding<Color> {
        Binding(
            get: { Color(stackColor: stack.paddingColor) },
            set: { stack.paddingColor = $0.stackHexString }
        )
    }

    /// The current card's background index, if any.
    private var backgroundIndex: Int? {
        let backgroundID = stack.cards[cardIndex].backgroundID
        return stack.backgrounds.firstIndex { $0.id == backgroundID }
    }

    /// The current card's highlight color; unset (nil) shows the app accent
    /// and writes as a #RRGGBB hex once chosen.
    private var cardHighlightBinding: Binding<Color> {
        Binding(
            get: { stack.cards[cardIndex].highlightColor.map(Color.init(stackColor:)) ?? .accentColor },
            set: { stack.cards[cardIndex].highlightColor = $0.stackHexString }
        )
    }

    /// Reassigns the current card to another existing background. The card
    /// keeps its own (card-layer) parts; only the shared background changes.
    private var cardBackgroundBinding: Binding<UUID> {
        Binding(
            get: { stack.cards[cardIndex].backgroundID },
            set: { stack.cards[cardIndex].backgroundID = $0 }
        )
    }

    /// A background's picker label: its name (or "Background N") plus how many
    /// cards share it, so multiple backgrounds are easy to tell apart.
    private func backgroundLabel(_ background: Background, index: Int) -> String {
        let name = background.name.isEmpty ? "Background \(index + 1)" : background.name
        let count = stack.cards.filter { $0.backgroundID == background.id }.count
        return "\(name)  ·  \(count) card\(count == 1 ? "" : "s")"
    }

    /// Shows the preset name when the size matches one, else the dimensions.
    private var cardSizeLabel: String {
        let size = stack.cardSize
        if let preset = CardSizePreset.all.first(where: { $0.size == size }) {
            return preset.name
        }
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    /// A labelled numeric field, fixed to a modest width so Width and Height
    /// pack onto one row (matching the part inspector).
    private func geometryCell(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .numericPunctuationKeyboard()
        }
    }

    private var scriptTitle: String {
        switch scope {
        case .card: "Script of \(stack.cards[cardIndex].name)"
        case .background: "Background Script"
        case .stack: "Stack Script"
        }
    }

    private var scriptBinding: Binding<String> {
        switch scope {
        case .card:
            return $stack.cards[cardIndex].script
        case .background:
            let backgroundID = stack.cards[cardIndex].backgroundID
            if let index = stack.backgrounds.firstIndex(where: { $0.id == backgroundID }) {
                return $stack.backgrounds[index].script
            }
            return .constant("")
        case .stack:
            return $stack.script
        }
    }
}

#Preview {
    @Previewable @State var stack = Stack.makeNew()
    @Previewable @State var scope: ObjectScriptsInspector.Scope = .card
    ObjectScriptsInspector(stack: $stack, cardIndex: 0, scope: $scope)
}
