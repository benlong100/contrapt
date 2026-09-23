//
//  ContentView.swift
//  HyperPad
//

import SwiftUI
import HyperTalk

/// Browse mode: shows the current card with card-to-card navigation.
/// Button taps dispatch the part's mouseUp handler through the interpreter.
/// Edit mode arrives in Phase 3.
struct ContentView: View {
    @Binding var document: StackDocument
    @State private var currentCardIndex = 0
    @State private var messageBoxText: String?
    @State private var scriptErrorText: String?

    var body: some View {
        Group {
            if document.stack.cards.isEmpty {
                ContentUnavailableView("No Cards", systemImage: "rectangle.on.rectangle.slash")
            } else {
                CardView(
                    stack: $document.stack,
                    cardIndex: cardIndex,
                    onButtonTap: runMouseUp
                )
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) {
            messageBox
        }
        .animation(.default, value: messageBoxText)
        .alert(
            "Script Error",
            isPresented: Binding(
                get: { scriptErrorText != nil },
                set: { if !$0 { scriptErrorText = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scriptErrorText ?? "")
        }
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

    /// HyperCard's message box, minimally: `put` with no destination lands
    /// here. Tap to dismiss.
    @ViewBuilder
    private var messageBox: some View {
        if let messageBoxText {
            Text(messageBoxText)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
                .onTapGesture { self.messageBoxText = nil }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Script dispatch

    private func runMouseUp(on part: Part) {
        let host = DocumentScriptHost(
            document: $document,
            currentCardIndex: $currentCardIndex,
            onMessage: { messageBoxText = $0 }
        )
        do {
            try HyperTalk.run(handler: "mouseUp", in: part.script, host: host)
        } catch {
            scriptErrorText = error.localizedDescription
        }
    }

    // MARK: - Navigation

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
