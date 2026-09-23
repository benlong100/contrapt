//
//  PartInspector.swift
//  HyperPad
//

import SwiftUI

/// Edits one part: identity, kind-specific text, geometry, and its script.
/// Presented as a trailing inspector column so the card stays visible.
struct PartInspector: View {
    @Binding var part: Part
    var onDelete: () -> Void

    var body: some View {
        Form {
            Section("Part") {
                TextField("Name", text: $part.name)
                LabeledContent("Kind", value: kindName)
            }
            kindSection
            Section("Position and Size") {
                geometryRow("X", value: $part.frame.x)
                geometryRow("Y", value: $part.frame.y)
                geometryRow("Width", value: $part.frame.width)
                geometryRow("Height", value: $part.frame.height)
            }
            Section("Script") {
                TextEditor(text: $part.script)
                    .font(.system(.callout, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 220)
            }
            Section {
                Button("Delete Part", role: .destructive) {
                    onDelete()
                }
            }
        }
    }

    private var kindName: String {
        switch part.kind {
        case .button: "Button"
        case .field: "Field"
        case .label: "Label"
        }
    }

    @ViewBuilder
    private var kindSection: some View {
        switch part.kind {
        case .button:
            Section("Button") {
                TextField("Title", text: buttonTitle)
            }
        case .field:
            Section("Field") {
                TextField("Placeholder", text: fieldPlaceholder)
                TextField("Contents", text: fieldContents)
            }
        case .label:
            Section("Label") {
                TextField("Text", text: labelText)
            }
        }
    }

    private func geometryRow(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
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
