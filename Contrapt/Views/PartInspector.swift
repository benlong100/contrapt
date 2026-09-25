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
    @State private var isMarkdownEditorExpanded = false

    var body: some View {
        Form {
            Section("Part") {
                TextField("Name", text: $part.name)
                LabeledContent("Kind", value: kindName)
                if case .field = part.kind {
                    Picker("Field Kind", selection: fieldKind) {
                        Text("Plain").tag(FieldKind.plain)
                        Text("Rich").tag(FieldKind.rich)
                    }
                    .pickerStyle(.segmented)
                }
                LabeledContent("ID", value: String(part.scriptID))
                Toggle("Visible", isOn: $part.isVisible)
            }
            kindSection
            Section("Position and Size") {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 8) {
                        geometryCell("X", value: $part.frame.x)
                        geometryCell("Y", value: $part.frame.y)
                    }
                    VStack(spacing: 8) {
                        geometryCell("W", value: $part.frame.width)
                        geometryCell("H", value: $part.frame.height)
                    }
                }
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
        .platformFullScreenCover(isPresented: $isMarkdownEditorExpanded) {
            LargeMarkdownEditor(
                title: "Markdown of \(part.name)",
                markdown: fieldContents,
                fontDesign: fieldFontDesign.wrappedValue,
                size: fieldTextSize.wrappedValue
            )
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
        case .field(let properties):
            // The Plain/Rich picker lives up in the Part section now.
            if properties.kind == .rich {
                Section {
                    TextEditor(text: fieldContents)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 180)
                    Button("Edit with Preview", systemImage: "arrow.up.left.and.arrow.down.right") {
                        isMarkdownEditorExpanded = true
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Markdown")
                } footer: {
                    Text("Bold, italic, headings, lists, and links. Card links like [Home](card:Home) navigate; https links open in the browser.")
                }
                Section("Text") {
                    fontAndSizeRow
                }
            } else {
                Section("Field") {
                    Toggle("Multiple Lines", isOn: fieldIsMultiline)
                    TextField("Contents", text: fieldContents, axis: .vertical)
                        .lineLimit(1...6)
                }
                Section("Text") {
                    fontAndSizeRow
                    Toggle("Bold", isOn: fieldBold)
                    Toggle("Italic", isOn: fieldItalic)
                    Toggle("Underline", isOn: fieldUnderline)
                    Picker("Align", selection: fieldAlign) {
                        ForEach(TextAlign.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
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

    /// Font and size on one row. The stepper is label-less (just the +/−
    /// control) with the value shown as plain text — a titled Stepper under
    /// fixedSize demands a huge width and stretches the whole inspector.
    private var fontAndSizeRow: some View {
        HStack(spacing: 12) {
            Text("Font").foregroundStyle(.secondary)
            Picker("Font", selection: fieldFontDesign) {
                ForEach(FontDesign.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            Spacer(minLength: 8)
            Text("Size \(Int(fieldTextSize.wrappedValue)) pt")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Stepper("Size", value: fieldTextSize, in: 8...96, step: 1)
                .labelsHidden()
        }
    }

    /// One labelled numeric field, fixed to a modest width so X/Y and W/H
    /// pack into two columns without stretching the inspector.
    private func geometryCell(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            TextField(title, value: value, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
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

    private var fieldKind: Binding<FieldKind> {
        Binding(
            get: {
                guard case .field(let properties) = part.kind else { return .plain }
                return properties.kind
            },
            set: {
                guard case .field(var properties) = part.kind else { return }
                properties.kind = $0
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
