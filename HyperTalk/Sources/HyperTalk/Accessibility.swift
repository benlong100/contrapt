//
//  Accessibility.swift
//  HyperTalk
//
//  The canonical rules for how a part is announced to assistive technology —
//  what a screen reader calls it (label), reads as its contents (value), and
//  treats it as (role). Pure and shared: the native app applies it as SwiftUI
//  accessibility modifiers; the web export mirrors the same rules in its DOM
//  (role/aria-label/alt). Defined once here so both agree and it's unit-tested.
//
//  (A Contrapt card is a fixed-pixel, absolutely-positioned medium, so Dynamic
//  Type / text reflow doesn't apply — the accessibility that fits is VoiceOver
//  labeling + semantic roles, which is what this describes.)
//

import Foundation

public enum AccessibleRole: String, Sendable, Equatable {
    case button
    case staticText
    case textField
    case image
}

public struct AccessibilityInfo: Equatable, Sendable {
    public let role: AccessibleRole
    /// What the element is called ("Save", "Notes"). May be empty for a static
    /// text whose own content is the announcement.
    public let label: String
    /// The element's current contents, for fields (empty otherwise).
    public let value: String

    public init(role: AccessibleRole, label: String, value: String) {
        self.role = role
        self.label = label
        self.value = value
    }
}

public enum Accessibility {
    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The accessibility description for a part. `kind` is the part word
    /// ("button", "field", "label", "image"); `locked` applies to fields.
    public static func part(kind: String,
                            name: String = "",
                            title: String = "",
                            text: String = "",
                            placeholder: String = "",
                            locked: Bool = false) -> AccessibilityInfo {
        let name = trimmed(name), title = trimmed(title), placeholder = trimmed(placeholder)
        switch kind {
        case "button":
            // Prefer the part name; fall back to the visible title. Icon-only
            // buttons (no visible title) rely on this for a spoken name.
            let label = !name.isEmpty ? name : (!title.isEmpty ? title : "Button")
            return AccessibilityInfo(role: .button, label: label, value: "")
        case "field":
            if locked {
                // Display text: its content is the announcement; the name (if
                // any) labels it.
                return AccessibilityInfo(role: .staticText, label: name, value: text)
            }
            let label = !name.isEmpty ? name : (!placeholder.isEmpty ? placeholder : "Text field")
            return AccessibilityInfo(role: .textField, label: label, value: text)
        case "label":
            // A label's own text is what gets read.
            return AccessibilityInfo(role: .staticText, label: "", value: text)
        case "image":
            return AccessibilityInfo(role: .image, label: !name.isEmpty ? name : "Image", value: "")
        default:
            return AccessibilityInfo(role: .staticText, label: name, value: text)
        }
    }
}
