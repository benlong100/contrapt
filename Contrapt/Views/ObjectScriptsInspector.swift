//
//  ObjectScriptsInspector.swift
//  Contrapt
//

import SwiftUI

/// Edits the scripts of the container objects — the current card, its
/// background, and the stack. Shown in the inspector when no part is
/// selected. Handlers here receive messages parts don't handle, plus
/// system messages like openCard and openStack.
struct ObjectScriptsInspector: View {
    @Binding var stack: Stack
    let cardIndex: Int

    private enum Scope: String, CaseIterable {
        case card = "Card"
        case background = "Background"
        case stack = "Stack"
    }

    @State private var scope: Scope = .card
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
                    Toggle("Card Marked", isOn: $stack.cards[cardIndex].isMarked)
                    Toggle("Don't Search Card", isOn: $stack.cards[cardIndex].dontSearch)
                    Toggle("Can't Delete Card", isOn: $stack.cards[cardIndex].cantDelete)
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
                    Menu {
                        ForEach(CardSizePreset.all) { preset in
                            Button("\(preset.name)  ·  \(Int(preset.size.width)) × \(Int(preset.size.height))") {
                                stack.cardSize = preset.size
                            }
                        }
                    } label: {
                        LabeledContent("Card Size", value: cardSizeLabel)
                    }
                    geometryRow("Width", value: $stack.cardSize.width)
                    geometryRow("Height", value: $stack.cardSize.height)
                } header: {
                    Text("Stack")
                } footer: {
                    Text("Card size applies to every card in the stack. Parts keep their positions, so shrinking may move some off the card.")
                }
                Section {
                    Toggle("Open Full Screen", isOn: $stack.isFullScreen)
                    ColorPicker("Padding Color", selection: paddingColorBinding, supportsOpacity: false)
                } header: {
                    Text("Presentation")
                } footer: {
                    Text("Full screen fills the space around the card with the padding color and hides the app chrome. Press Escape to leave.")
                }
            }
            ScriptFormSection(title: scriptTitle, script: scriptBinding, onExpand: { isEditorExpanded = true })
                .id(scope)
        }
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

    /// Shows the preset name when the size matches one, else the dimensions.
    private var cardSizeLabel: String {
        let size = stack.cardSize
        if let preset = CardSizePreset.all.first(where: { $0.size == size }) {
            return preset.name
        }
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    private func geometryRow(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number)
                .multilineTextAlignment(.trailing)
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
    ObjectScriptsInspector(stack: $stack, cardIndex: 0)
}
