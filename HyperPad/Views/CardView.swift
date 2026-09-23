//
//  CardView.swift
//  HyperPad
//

import SwiftUI

/// Renders one card: background parts beneath card parts, laid out in
/// logical card coordinates (D3) and scaled to fit the available space.
/// In browse mode parts are live controls; in edit mode they render inert
/// with selection chrome and move/resize gestures.
struct CardView: View {
    @Binding var stack: Stack
    let cardIndex: Int
    var isEditing: Bool = false
    @Binding var selectedPartID: UUID?
    var onButtonTap: (Part) -> Void

    /// Named coordinate space on the logical-size canvas, so gesture math
    /// works in card coordinates regardless of display scale.
    static let canvasSpace = "cardCanvas"

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = stack.cardSize.width
            let cardHeight = stack.cardSize.height
            let scale = min(proxy.size.width / cardWidth, proxy.size.height / cardHeight)
            cardCanvas
                .frame(width: cardWidth, height: cardHeight)
                .coordinateSpace(name: Self.canvasSpace)
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
                .onTapGesture {
                    if isEditing { selectedPartID = nil }
                }
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
            Group {
                if isEditing {
                    EditablePart(
                        part: $part,
                        isSelected: selectedPartID == part.id,
                        onSelect: { selectedPartID = part.id }
                    )
                } else {
                    PartView(part: $part, onButtonTap: { onButtonTap(part) })
                }
            }
            .frame(width: part.frame.width, height: part.frame.height)
            .position(
                x: part.frame.x + part.frame.width / 2,
                y: part.frame.y + part.frame.height / 2
            )
        }
    }
}

/// A part in edit mode: the control rendered inert, plus selection chrome
/// and move/resize gestures working in logical card coordinates.
private struct EditablePart: View {
    @Binding var part: Part
    let isSelected: Bool
    var onSelect: () -> Void

    @State private var frameAtGestureStart: PartFrame?

    private static let minSize: Double = 32

    var body: some View {
        PartView(part: $part, onButtonTap: {})
            .allowsHitTesting(false)
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }
            .gesture(moveGesture)
            .overlay {
                if isSelected {
                    Rectangle()
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    resizeHandle
                }
            }
    }

    private var resizeHandle: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            .offset(x: 11, y: 11)
            .gesture(resizeGesture)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(CardView.canvasSpace))
            .onChanged { value in
                if frameAtGestureStart == nil {
                    frameAtGestureStart = part.frame
                    onSelect()
                }
                guard let start = frameAtGestureStart else { return }
                part.frame.x = start.x + (value.location.x - value.startLocation.x)
                part.frame.y = start.y + (value.location.y - value.startLocation.y)
            }
            .onEnded { _ in frameAtGestureStart = nil }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(CardView.canvasSpace))
            .onChanged { value in
                if frameAtGestureStart == nil {
                    frameAtGestureStart = part.frame
                }
                guard let start = frameAtGestureStart else { return }
                part.frame.width = max(Self.minSize, start.width + (value.location.x - value.startLocation.x))
                part.frame.height = max(Self.minSize, start.height + (value.location.y - value.startLocation.y))
            }
            .onEnded { _ in frameAtGestureStart = nil }
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

#Preview("Editing") {
    @Previewable @State var stack = Stack.makeNew()
    @Previewable @State var selection: UUID?
    CardView(
        stack: $stack,
        cardIndex: 0,
        isEditing: true,
        selectedPartID: $selection,
        onButtonTap: { _ in }
    )
    .padding()
    .onAppear { selection = stack.cards[0].parts[2].id }
}
