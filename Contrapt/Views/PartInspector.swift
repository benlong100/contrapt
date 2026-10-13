//
//  PartInspector.swift
//  Contrapt
//

import SwiftUI
import HyperTalk

/// Shown when several parts are selected: a count plus the actions that make
/// sense for a group (deselect, delete). Per-part editing needs a single
/// selection.
struct MultipleSelectionInspector: View {
    let count: Int
    var onDeselect: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                Button {
                    onDeselect()
                } label: {
                    Label("Card, Background & Stack", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
            }
            Section {
                LabeledContent("Selected", value: "\(count) objects")
            } footer: {
                Text("Move them together with the arrow keys or by dragging, copy/cut/paste as a group, or delete them. Select just one to edit its properties.")
            }
            Section {
                Button("Delete \(count) Objects", role: .destructive) { onDelete() }
            }
        }
    }
}

/// Edits one part: identity, kind-specific text, geometry, and its script.
/// Presented as a trailing inspector column so the card stays visible.
struct PartInspector: View {
    @Binding var part: Part
    /// Which layer the part lives on ("Card" / "Background"), shown with the
    /// kind — the owner knows, the part itself doesn't carry it.
    var layerName: String? = nil
    /// Begins Link To… — the owner shows a floating panel over the card so
    /// the user can navigate to a destination before capturing it.
    var onLinkTo: () -> Void = {}
    /// Deselects the part, returning the inspector to the Card/Background/
    /// Stack view — the way back without hunting for empty card to click.
    var onDeselect: () -> Void = {}
    var onDelete: () -> Void

    @State private var isEditorExpanded = false
    @State private var isMarkdownEditorExpanded = false
    @State private var isIconPickerPresented = false

    var body: some View {
        Form {
            Section {
                Button {
                    onDeselect()
                } label: {
                    Label("Card, Background & Stack", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
            }
            Section("Part") {
                HStack(spacing: 8) {
                    Text("Name")
                    TextField("Name", text: $part.name)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    Spacer(minLength: 12)
                    Text("ID \(part.scriptID)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    // "Kind: Background Button" — the layer matters for
                    // scripting (`bg btn` vs `btn`) and for what deletes with
                    // the card, so say it up front.
                    Text("Kind: \(layerName.map { "\($0) " } ?? "")\(kindName)")
                        .foregroundStyle(.secondary)
                    if case .field = part.kind {
                        Picker("Field Kind", selection: fieldKind) {
                            Text("Plain").tag(FieldKind.plain)
                            Text("Rich").tag(FieldKind.rich)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 130)
                    }
                    Spacer(minLength: 8)
                    Text("Visible").foregroundStyle(.secondary)
                    Toggle("Visible", isOn: $part.isVisible)
                        .labelsHidden()
                }
                Toggle(isOn: $part.isLocked) {
                    // Locked parts stay selectable — the lock pins geometry
                    // (see EditablePart; "Move Locked Objects" overrides).
                    Text("Locked (pin position and size)")
                }
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
        // Return ends editing; clicking empty palette space releases focus.
        .endsTextEditingOnSubmitAndTap()
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
        .sheet(isPresented: $isIconPickerPresented) {
            IconPickerView(current: currentButtonIconSymbol) { setButtonIcon($0) }
        }
    }

    /// The button's current SF Symbol icon name, if any.
    private var currentButtonIconSymbol: String? {
        if case .button(let properties) = part.kind { return properties.iconSymbol }
        return nil
    }

    /// Whether the button carries an imported (PNG asset) icon.
    private var buttonHasImportedIcon: Bool {
        if case .button(let properties) = part.kind { return properties.iconAsset != nil }
        return false
    }

    /// Sets (or clears) the button's icon. A chosen symbol replaces any
    /// imported PNG icon; Remove (nil) clears both.
    private func setButtonIcon(_ symbol: String?) {
        guard case .button(var properties) = part.kind else { return }
        properties.iconSymbol = symbol
        properties.iconAsset = nil
        part.kind = .button(properties)
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
                HStack(spacing: 16) {
                    Toggle("Show Name", isOn: buttonShowName)
                    if properties.style.isToggle {
                        Toggle("Hilite", isOn: buttonHilite)
                    } else {
                        Toggle("Auto Hilite", isOn: buttonAutoHilite)
                    }
                }
                // HyperCard's Button Info "Family" pop-up: same-numbered
                // autoHilite buttons on a layer form a radio group.
                Picker("Family", selection: buttonFamily) {
                    Text("None").tag(0)
                    ForEach(1...15, id: \.self) { Text("\($0)").tag($0) }
                }
                fontAndSizeRow
                // Custom colors — scriptable as the fillColor / borderColor
                // of the button. Unset keeps the themed default look.
                HStack(spacing: 8) {
                    ColorPicker("Fill Color", selection: buttonFillBinding, supportsOpacity: false)
                    Button("Reset") { setButton { $0.fillColor = nil } }
                        .buttonStyle(.borderless)
                        .disabled(properties.fillColor == nil)
                }
                HStack(spacing: 8) {
                    ColorPicker("Edge Color", selection: buttonBorderBinding, supportsOpacity: false)
                    Button("Reset") { setButton { $0.borderColor = nil } }
                        .buttonStyle(.borderless)
                        .disabled(properties.borderColor == nil)
                }
                HStack(spacing: 8) {
                    ColorPicker("Text Color", selection: buttonTextColorBinding, supportsOpacity: false)
                    Button("Reset") { setButton { $0.textColor = nil } }
                        .buttonStyle(.borderless)
                        .disabled(properties.textColor == nil)
                }
                HStack(spacing: 8) {
                    Text("Icon").foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let symbol = currentButtonIconSymbol, !symbol.isEmpty {
                        Image(systemName: symbol).imageScale(.large)
                    } else if buttonHasImportedIcon {
                        Text("Imported").foregroundStyle(.secondary)
                    } else {
                        Text("None").foregroundStyle(.secondary)
                    }
                    Button("Choose…") { isIconPickerPresented = true }
                        .buttonStyle(.borderless)
                }
                Button("Link To…", systemImage: "link") {
                    onLinkTo()
                }
            }
        case .field(let properties):
            // The Plain/Rich picker lives up in the Part section now.
            Section {
                Picker("Style", selection: fieldStyle) {
                    ForEach(FieldStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
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
                Section {
                    fontAndSizeRow
                    // Leading — the field's textHeight, in points (0 = auto).
                    // Scriptable as `the textHeight of field`.
                    HStack(spacing: 8) {
                        Text("Line Height")
                        TextField("Auto", value: fieldTextHeightBinding, format: .number)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 70)
                        Text("pt — 0 is automatic").foregroundStyle(.secondary).font(.callout)
                    }
                    HStack(spacing: 8) {
                        ColorPicker("Text Color", selection: fieldTextColorBinding, supportsOpacity: false)
                        Button("Reset") { setField { $0.textColor = nil } }
                            .buttonStyle(.borderless)
                            .disabled(properties.textColor == nil)
                    }
                    HStack(spacing: 8) {
                        ColorPicker("Edge Color", selection: fieldBorderBinding, supportsOpacity: false)
                        Button("Reset") { setField { $0.borderColor = nil } }
                            .buttonStyle(.borderless)
                            .disabled(properties.borderColor == nil)
                    }
                }
            } else {
                Section("Field") {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 8) {
                            Toggle("Multiple Lines", isOn: fieldIsMultiline)
                            Toggle("Lock Text", isOn: fieldLockText)
                        }
                        VStack(spacing: 8) {
                            Toggle("Show Lines", isOn: fieldShowLines)
                            Toggle("Wide Margins", isOn: fieldWideMargins)
                            Toggle("Don't Wrap", isOn: fieldDontWrap)
                            Toggle("Auto Select", isOn: fieldAutoSelect)
                        }
                    }
                    // Custom colors — scriptable as the textColor / borderColor
                    // of the field. Unset keeps the themed default look.
                    HStack(spacing: 8) {
                        ColorPicker("Text Color", selection: fieldTextColorBinding, supportsOpacity: false)
                        Button("Reset") { setField { $0.textColor = nil } }
                            .buttonStyle(.borderless)
                            .disabled(properties.textColor == nil)
                    }
                    HStack(spacing: 8) {
                        ColorPicker("Edge Color", selection: fieldBorderBinding, supportsOpacity: false)
                        Button("Reset") { setField { $0.borderColor = nil } }
                            .buttonStyle(.borderless)
                            .disabled(properties.borderColor == nil)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Contents").foregroundStyle(.secondary)
                        // A TextEditor, not a TextField(axis: .vertical): the
                        // vertical-axis TextField SUBMITS on Return (and the
                        // form's end-editing-on-submit then select-all'd the
                        // text) — in an editor, Return types a return.
                        TextEditor(text: fieldContents)
                            .font(.body)
                            .frame(minHeight: 60, maxHeight: 140)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    }
                }
                Section {
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

    /// Mutates the part's ButtonPart in place (no-op for non-buttons).
    private func setButton(_ mutate: (inout ButtonPart) -> Void) {
        guard case .button(var properties) = part.kind else { return }
        mutate(&properties)
        part.kind = .button(properties)
    }

    /// The custom fill color; unset shows white and writes as #RRGGBB hex
    /// once chosen (Reset clears back to the themed default).
    private var buttonFillBinding: Binding<Color> {
        Binding(
            get: {
                guard case .button(let properties) = part.kind else { return .white }
                return properties.fillColor.map(Color.init(stackColor:)) ?? .white
            },
            set: { color in setButton { $0.fillColor = color.stackHexString } }
        )
    }

    /// The custom title color; unset shows the label color.
    private var buttonTextColorBinding: Binding<Color> {
        Binding(
            get: {
                guard case .button(let properties) = part.kind else { return .primary }
                return properties.textColor.map(Color.init(stackColor:)) ?? .primary
            },
            set: { color in setButton { $0.textColor = color.stackHexString } }
        )
    }

    /// The custom edge color; unset shows the accent.
    private var buttonBorderBinding: Binding<Color> {
        Binding(
            get: {
                guard case .button(let properties) = part.kind else { return .accentColor }
                return properties.borderColor.map(Color.init(stackColor:)) ?? .accentColor
            },
            set: { color in setButton { $0.borderColor = color.stackHexString } }
        )
    }

    /// Mutates the part's FieldPart in place (no-op for non-fields).
    private func setField(_ mutate: (inout FieldPart) -> Void) {
        guard case .field(var properties) = part.kind else { return }
        mutate(&properties)
        part.kind = .field(properties)
    }

    /// The field's line height (leading) in points; 0 reads/writes as "auto"
    /// (nil — the font's natural height). Scriptable as `the textHeight`.
    private var fieldTextHeightBinding: Binding<Double> {
        Binding(
            get: {
                guard case .field(let properties) = part.kind else { return 0 }
                return properties.textHeight ?? 0
            },
            set: { value in setField { $0.textHeight = value > 0 ? value : nil } }
        )
    }

    /// The field's whole-text color; unset shows the label color and writes
    /// as #RRGGBB hex once chosen (Reset clears back to the default).
    private var fieldTextColorBinding: Binding<Color> {
        Binding(
            get: {
                guard case .field(let properties) = part.kind else { return .primary }
                return properties.textColor.map(Color.init(stackColor:)) ?? .primary
            },
            set: { color in setField { $0.textColor = color.stackHexString } }
        )
    }

    /// The field's custom border color; unset shows the accent.
    private var fieldBorderBinding: Binding<Color> {
        Binding(
            get: {
                guard case .field(let properties) = part.kind else { return .accentColor }
                return properties.borderColor.map(Color.init(stackColor:)) ?? .accentColor
            },
            set: { color in setField { $0.borderColor = color.stackHexString } }
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

    private var buttonFamily: Binding<Int> {
        Binding(
            get: {
                guard case .button(let properties) = part.kind else { return 0 }
                return properties.family
            },
            set: {
                guard case .button(var properties) = part.kind else { return }
                properties.family = $0
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
    /// A binding to one TextFormat property, working for whichever part kind
    /// carries a format — fields and buttons both do.
    private func fieldFormat<Value>(_ keyPath: WritableKeyPath<TextFormat, Value>, default fallback: Value) -> Binding<Value> {
        Binding(
            get: {
                switch part.kind {
                case .field(let properties): return properties.format[keyPath: keyPath]
                case .button(let properties): return properties.format[keyPath: keyPath]
                default: return fallback
                }
            },
            set: {
                switch part.kind {
                case .field(var properties):
                    properties.format[keyPath: keyPath] = $0
                    part.kind = .field(properties)
                case .button(var properties):
                    properties.format[keyPath: keyPath] = $0
                    part.kind = .button(properties)
                default:
                    break
                }
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

    private var fieldLockText: Binding<Bool> { fieldFlag(\.lockText) }
    private var fieldShowLines: Binding<Bool> { fieldFlag(\.showLines) }
    private var fieldWideMargins: Binding<Bool> { fieldFlag(\.wideMargins) }
    private var fieldDontWrap: Binding<Bool> { fieldFlag(\.dontWrap) }
    private var fieldAutoSelect: Binding<Bool> { fieldFlag(\.autoSelect) }

    /// A binding to one Bool on the field's FieldPart.
    private func fieldFlag(_ keyPath: WritableKeyPath<FieldPart, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                guard case .field(let properties) = part.kind else { return false }
                return properties[keyPath: keyPath]
            },
            set: {
                guard case .field(var properties) = part.kind else { return }
                properties[keyPath: keyPath] = $0
                part.kind = .field(properties)
            }
        )
    }

    private var fieldStyle: Binding<FieldStyle> {
        Binding(
            get: {
                guard case .field(let properties) = part.kind else { return .rectangle }
                return properties.style
            },
            set: {
                guard case .field(var properties) = part.kind else { return }
                properties.style = $0
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
