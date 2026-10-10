//
//  AccessibilityTests.swift
//  HyperTalk
//
//  The shared part-accessibility rules (label/value/role) that both the app's
//  VoiceOver modifiers and the web export's ARIA mirror.
//

import Testing
@testable import HyperTalk

@Test func buttonPrefersNameThenTitle() {
    #expect(Accessibility.part(kind: "button", name: "Save", title: "OK").label == "Save")
    #expect(Accessibility.part(kind: "button", name: "", title: "OK").label == "OK")
    #expect(Accessibility.part(kind: "button", name: "", title: "").label == "Button")
    #expect(Accessibility.part(kind: "button", name: "Save").role == AccessibleRole.button)
}

@Test func lockedFieldIsStaticTextWithContentAsValue() {
    let info = Accessibility.part(kind: "field", name: "Notes", text: "hello", locked: true)
    #expect(info.role == AccessibleRole.staticText)
    #expect(info.label == "Notes")
    #expect(info.value == "hello")
}

@Test func editableFieldIsTextFieldLabeledByNameThenPlaceholder() {
    let named = Accessibility.part(kind: "field", name: "Email", text: "x", placeholder: "you@site", locked: false)
    #expect(named.role == AccessibleRole.textField)
    #expect(named.label == "Email")
    #expect(named.value == "x")

    let placeheld = Accessibility.part(kind: "field", name: "", placeholder: "Search", locked: false)
    #expect(placeheld.label == "Search")

    let bare = Accessibility.part(kind: "field", locked: false)
    #expect(bare.label == "Text field")
}

@Test func labelPartReadsItsText() {
    let info = Accessibility.part(kind: "label", text: "Welcome")
    #expect(info.role == AccessibleRole.staticText)
    #expect(info.value == "Welcome")
}

@Test func imageUsesNameElseGenericImage() {
    #expect(Accessibility.part(kind: "image", name: "Logo").label == "Logo")
    #expect(Accessibility.part(kind: "image").label == "Image")
    #expect(Accessibility.part(kind: "image").role == AccessibleRole.image)
}

@Test func labelsAreTrimmed() {
    #expect(Accessibility.part(kind: "button", name: "  Go  ").label == "Go")
}
