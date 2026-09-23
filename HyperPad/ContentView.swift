//
//  ContentView.swift
//  HyperPad
//

import SwiftUI

/// Browse mode: shows the current card with card-to-card navigation.
/// Edit mode arrives in Phase 3.
struct ContentView: View {
    @Binding var document: StackDocument
    @State private var currentCardIndex = 0

    var body: some View {
        Group {
            if document.stack.cards.isEmpty {
                ContentUnavailableView("No Cards", systemImage: "rectangle.on.rectangle.slash")
            } else {
                CardView(
                    stack: $document.stack,
                    cardIndex: cardIndex,
                    goToNextCard: goToNextCard
                )
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Previous Card", systemImage: "chevron.left") {
                    goToPreviousCard()
                }
                Spacer()
                Text("Card \(cardIndex + 1) of \(document.stack.cards.count)")
                    .font(.callout)
                    .monospacedDigit()
                    .fixedSize()
                Spacer()
                Button("Next Card", systemImage: "chevron.right") {
                    goToNextCard()
                }
            }
        }
    }

    /// Clamped so a shorter reopened stack can't strand the index.
    private var cardIndex: Int {
        min(currentCardIndex, document.stack.cards.count - 1)
    }

    private func goToNextCard() {
        let count = document.stack.cards.count
        guard count > 0 else { return }
        currentCardIndex = (cardIndex + 1) % count
    }

    private func goToPreviousCard() {
        let count = document.stack.cards.count
        guard count > 0 else { return }
        currentCardIndex = (cardIndex + count - 1) % count
    }
}

#Preview {
    ContentView(document: .constant(StackDocument()))
}
