//
//  CardView.swift
//  HyperPad
//

import SwiftUI

/// Renders one card in browse mode: background parts beneath card parts,
/// laid out in logical card coordinates (D3) and scaled to fit the
/// available space.
struct CardView: View {
    @Binding var stack: Stack
    let cardIndex: Int
    /// Invoked when a button part is tapped; the owner dispatches the
    /// part's mouseUp handler.
    var onButtonTap: (Part) -> Void

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = stack.cardSize.width
            let cardHeight = stack.cardSize.height
            let scale = min(proxy.size.width / cardWidth, proxy.size.height / cardHeight)
            cardCanvas
                .frame(width: cardWidth, height: cardHeight)
                .scaleEffect(scale)
                .frame(width: cardWidth * scale, height: cardHeight * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var cardCanvas: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(radius: 8)
            if let backgroundIndex {
                partViews(for: $stack.backgrounds[backgroundIndex].parts)
            }
            partViews(for: $stack.cards[cardIndex].parts)
        }
    }

    private var backgroundIndex: Int? {
        stack.backgrounds.firstIndex { $0.id == stack.cards[cardIndex].backgroundID }
    }

    private func partViews(for parts: Binding<[Part]>) -> some View {
        ForEach(parts) { $part in
            PartView(part: $part, onButtonTap: { onButtonTap(part) })
                .frame(width: part.frame.width, height: part.frame.height)
                .position(
                    x: part.frame.x + part.frame.width / 2,
                    y: part.frame.y + part.frame.height / 2
                )
        }
    }
}

/// Renders a single part as its native SwiftUI control (D5). Unstyled parts
/// keep the native look; per-kind style properties come later.
struct PartView: View {
    @Binding var part: Part
    var onButtonTap: () -> Void

    var body: some View {
        switch part.kind {
        case .button(let properties):
            Button {
                onButtonTap()
            } label: {
                Text(properties.title)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.bordered)
        case .field(let properties):
            TextField(properties.placeholder, text: fieldText)
                .textFieldStyle(.roundedBorder)
        case .label(let properties):
            Text(properties.text)
                .font(.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    /// Field contents are document data, as in HyperCard: typing into a
    /// field edits the stack.
    private var fieldText: Binding<String> {
        Binding(
            get: {
                guard case .field(let properties) = part.kind else { return "" }
                return properties.text
            },
            set: { newValue in
                guard case .field(var properties) = part.kind else { return }
                properties.text = newValue
                part.kind = .field(properties)
            }
        )
    }
}
