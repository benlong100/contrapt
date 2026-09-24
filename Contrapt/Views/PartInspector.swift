//
//  PartInspector.swift
//  Contrapt
//

import SwiftUI
import HyperTalk

/// Edits one part: identity, kind-specific text, geometry, and its script.
/// Presented as a trailing inspector column so the card stays visible.
struct PartInspector: View {
    @Binding var part: Part
    /// The stack's cards, as link destinations for the Link To… panel.
    var linkCards: [LinkTarget] = []
    var onDelete: () -> Void

    /// A card a button can link to.
    struct LinkTarget: Identifiable, Hashable {
        let scriptID: Int
        let name: String
        var id: Int { scriptID }
    }

    @State private var isEditorExpanded = false
    @State private var isLinkPanelPresented = false
    @State private var linkCardID: Int?

    var body: some View {
        Form {
            Section("Part") {
                TextField("Name", text: $part.name)
                LabeledContent("Kind", value: kindName)
                LabeledContent("ID", value: String(part.scriptID))
                Toggle("Visible", isOn: $part.isVisible)
            }
            kindSection
            Section("Position and Size") {
                geometryRow("X", value: $part.frame.x)
                geometryRow("Y", value: $part.frame.y)
                geometryRow("Width", value: $part.frame.width)
                geometryRow("Height", value: $part.frame.height)
            }
            ScriptFormSection(title: "Script", script: $part.script, onExpand: { isEditorExpanded = true })
                .id(part.id)
            Section {
                Button("Delete Part", role: .destructive) {
                    onDelete()
                }
            }
        }
        .platformFullScreenCover(isPresented: $isEditorExpanded) {
            LargeScriptEditor(title: "Script of \(part.name)", script: $part.script)
        }
        .sheet(isPresented: $isLinkPanelPresented) {
            linkPanel
        }
    }

    /// HyperCard's Link To panel: pick a destination and it writes the
    /// button's navigation script for you — no scripting required, which
    /// matters at lower user levels.
    private var linkPanel: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Card", selection: $linkCardID) {
                        ForEach(linkCards) { card in
                            Text(card.name).tag(Optional(card.scriptID))
                        }
                    }
                    Button("Link to This Card") {
                        if let id = linkCardID { applyLink("go to card id \(id)") }
                    }
                    .disabled(linkCardID == nil)
                } header: {
                    Text("This Card")
                } footer: {
                    Text("The button will go to the chosen card when tapped.")
                }
                Section {
                    Button("Link to This Stack") {
                        applyLink("go to first card")
                    }
                } header: {
                    Text("This Stack")
                } footer: {
                    Text("The button will go to the stack's first card.")
                }
            }
            .navigationTitle("Link To")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isLinkPanelPresented = false }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 340, minHeight: 320)
        #endif
    }

    /// Replaces the button's script with a generated navigation handler.
    private func applyLink(_ command: String) {
        part.script = "on mouseUp\n  \(command)\nend mouseUp"
        isLinkPanelPresented = false
    }

    private var kindName: String {
        switch part.kind {
        case .button: "Button"
        case .field: "Field"
        case .label: "Label"
        case .image: "Image"
        }
    }

    @ViewBuilder
    private var kindSection: some View {
        switch part.kind {
        case .button:
            Section("Button") {
                TextField("Title", text: buttonTitle)
                Button("Link To…", systemImage: "link") {
                    linkCardID = linkCards.first?.scriptID
                    isLinkPanelPresented = true
                }
            }
        case .field:
            Section("Field") {
                TextField("Placeholder", text: fieldPlaceholder)
                TextField("Contents", text: fieldContents, axis: .vertical)
                    .lineLimit(1...6)
                Toggle("Multiple Lines", isOn: fieldIsMultiline)
            }
        case .label:
            Section("Label") {
                TextField("Text", text: labelText)
            }
        case .image(let properties):
            Section("Image") {
                LabeledContent("Asset", value: properties.assetName)
            }
        }
    }

    private func geometryRow(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .numericPunctuationKeyboard()
        }
    }

    // MARK: - Kind-specific bindings

    private var buttonTitle: Binding<String> {
        Binding(
            get: {
                guard case .button(let properties) = part.kind else { return "" }
                return properties.title
            },
            set: {
                guard case .button(var properties) = part.kind else { return }
                properties.title = $0
                part.kind = .button(properties)
            }
        )
    }

    private var fieldPlaceholder: Binding<String> {
        Binding(
            get: {
                guard case .field(let properties) = part.kind else { return "" }
                return properties.placeholder
            },
            set: {
                guard case .field(var properties) = part.kind else { return }
                properties.placeholder = $0
                part.kind = .field(properties)
            }
        )
    }

    private var fieldContents: Binding<String> {
        Binding(
            get: {
                guard case .field(let properties) = part.kind else { return "" }
                return properties.text
            },
            set: {
                guard case .field(var properties) = part.kind else { return }
                properties.text = $0
                part.kind = .field(properties)
            }
        )
    }

    private var fieldIsMultiline: Binding<Bool> {
        Binding(
            get: {
                guard case .field(let properties) = part.kind else { return false }
                return properties.isMultiline
            },
            set: {
                guard case .field(var properties) = part.kind else { return }
                properties.isMultiline = $0
                part.kind = .field(properties)
            }
        )
    }

    private var labelText: Binding<String> {
        Binding(
            get: {
                guard case .label(let properties) = part.kind else { return "" }
                return properties.text
            },
            set: {
                guard case .label(var properties) = part.kind else { return }
                properties.text = $0
                part.kind = .label(properties)
            }
        )
    }
}
