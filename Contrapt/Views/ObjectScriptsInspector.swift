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
            ScriptFormSection(title: scriptTitle, script: scriptBinding, onExpand: { isEditorExpanded = true })
                .id(scope)
        }
        .fullScreenCover(isPresented: $isEditorExpanded) {
            LargeScriptEditor(title: scriptTitle, script: scriptBinding)
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
