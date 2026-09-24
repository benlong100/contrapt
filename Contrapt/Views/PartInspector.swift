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
    /// Begins Link To… — the owner shows a floating panel over the card so
    /// the user can navigate to a destination before capturing it.
    var onLinkTo: () -> Void = {}
    var onDelete: () -> Void

    @State private var isEditorExpanded = false

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
        case .button(let properties):
            Section("Button") {
                TextField("Title", text: buttonTitle)
                Picker("Style", selection: buttonStyle) {
                    ForEach(ButtonStyleKind.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                Toggle("Show Name", isOn: buttonShowName)
                if properties.style.isToggle {
                    Toggle("Hilite (on)", isOn: buttonHilite)
                } else {
                    Toggle("Auto Hilite", isOn: buttonAutoHilite)
                }
                Button("Link To…", systemImage: "link") {
                    onLinkTo()
                }
            }
        case .field:
            Section("Field") {
                TextField("Placeholder", text: fieldPlaceholder)
                TextField("Contents", text: fieldContents, axis: .vertical)
                    .lineLimit(1...6)
                Toggle("Multiple Lines", isOn: fieldIsMultiline)
            }
            Section("Text") {
                Picker("Font", selection: fieldFontDesign) {
                    ForEach(FontDesign.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Stepper(value: fieldTextSize, in: 8...96, step: 1) {
                    LabeledContent("Size", value: "\(Int(fieldTextSize.wrappedValue)) pt")
                }
                Toggle("Bold", isOn: fieldBold)
                Toggle("Italic", isOn: fieldItalic)
                Toggle("Underline", isOn: fieldUnderline)
                Picker("Align", selection: fieldAlign) {
                    ForEach(TextAlign.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
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

    private var buttonStyle: Binding<ButtonStyleKind> {
        Binding(
            get: {
                guard case .button(let properties) = part.kind else { return .roundRect }
                return properties.style
            },
            set: {
                guard case .button(var properties) = part.kind else { return }
                properties.style = $0
                part.kind = .button(properties)
            }
        )
    }

    private var buttonHilite: Binding<Bool> {
        Binding(
            get: {
                guard case .button(let properties) = part.kind else { return false }
                return properties.hilite
            },
            set: {
                guard case .button(var properties) = part.kind else { return }
                properties.hilite = $0
                part.kind = .button(properties)
            }
        )
    }

    private var buttonShowName: Binding<Bool> {
        Binding(
            get: {
                guard case .button(let properties) = part.kind else { return true }
                return properties.showName
            },
            set: {
                guard case .button(var properties) = part.kind else { return }
                properties.showName = $0
                part.kind = .button(properties)
            }
        )
    }

    private var buttonAutoHilite: Binding<Bool> {
        Binding(
            get: {
                guard case .button(let properties) = part.kind else { return true }
                return properties.autoHilite
            },
            set: {
                guard case .button(var properties) = part.kind else { return }
                properties.autoHilite = $0
                part.kind = .button(properties)
            }
        )
    }

    /// Projects one field-format value into a binding that writes back
    /// through the part's kind.
    private func fieldFormat<Value>(_ keyPath: WritableKeyPath<TextFormat, Value>, default fallback: Value) -> Binding<Value> {
        Binding(
            get: {
                guard case .field(let properties) = part.kind else { return fallback }
                return properties.format[keyPath: keyPath]
            },
            set: {
                guard case .field(var properties) = part.kind else { return }
                properties.format[keyPath: keyPath] = $0
                part.kind = .field(properties)
            }
        )
    }

    private var fieldFontDesign: Binding<FontDesign> { fieldFormat(\.fontDesign, default: .standard) }
    private var fieldTextSize: Binding<Double> { fieldFormat(\.size, default: 17) }
    private var fieldBold: Binding<Bool> { fieldFormat(\.isBold, default: false) }
    private var fieldItalic: Binding<Bool> { fieldFormat(\.isItalic, default: false) }
    private var fieldUnderline: Binding<Bool> { fieldFormat(\.isUnderline, default: false) }
    private var fieldAlign: Binding<TextAlign> { fieldFormat(\.align, default: .left) }

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
