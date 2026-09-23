//
//  ContentView.swift
//  HyperPad
//

import SwiftUI

/// Phase 1 placeholder document view: proves the document round-trip
/// (open, edit, autosave) works. Replaced by the card view in Phase 2.
struct ContentView: View {
    @Binding var document: StackDocument

    var body: some View {
        List {
            Section("Stack") {
                LabeledContent("Cards", value: "\(document.stack.cards.count)")
                LabeledContent(
                    "Card Size",
                    value: "\(Int(document.stack.cardSize.width)) × \(Int(document.stack.cardSize.height))"
                )
                LabeledContent("Format", value: "v\(document.stack.formatVersion)")
            }
            Section("Cards") {
                ForEach(document.stack.cards) { card in
                    Text(card.name)
                }
                .onDelete(perform: deleteCards)
                Button("Add Card", systemImage: "plus") {
                    addCard()
                }
            }
        }
    }

    private func addCard() {
        // Every stack keeps at least one background (see Stack.makeNew).
        guard let backgroundID = document.stack.backgrounds.first?.id else { return }
        let card = Card(
            id: UUID(),
            name: "Card \(document.stack.cards.count + 1)",
            backgroundID: backgroundID,
            script: "",
            parts: []
        )
        document.stack.cards.append(card)
    }

    private func deleteCards(at offsets: IndexSet) {
        document.stack.cards.remove(atOffsets: offsets)
    }
}

#Preview {
    ContentView(document: .constant(StackDocument()))
}
