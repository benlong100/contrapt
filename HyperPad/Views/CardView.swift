//
//  CardView.swift
//  HyperPad
//

import SwiftUI

/// Renders one card: background parts beneath card parts, laid out in
/// logical card coordinates (D3) and scaled to fit the available space.
/// In browse mode parts are live controls; in edit mode they render inert
/// with selection chrome, move/resize gestures, and alignment snapping.
struct CardView: View {
    @Binding var stack: Stack
    let cardIndex: Int
    var isEditing: Bool = false
    var isSnappingEnabled: Bool = true
    @Binding var selectedPartID: UUID?
    /// Browse-mode mouse messages: the message name (mouseDown/mouseUp)
    /// plus the part it targets — nil means the card itself.
    var onMouseMessage: (String, Part?) -> Void = { _, _ in }
    var onOpenInspector: () -> Void = {}

    @State private var guides = AlignmentGuides()
    @State private var isCardPressed = false

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
            cardSurface
            if let backgroundIndex {
                partViews(for: $stack.backgrounds[backgroundIndex].parts)
            }
            partViews(for: $stack.cards[cardIndex].parts)
            guideLines
        }
    }

    @ViewBuilder
    private var cardSurface: some View {
        let surface = RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemBackground))
            .shadow(radius: 8)
        if isEditing {
            surface.onTapGesture { selectedPartID = nil }
        } else {
            surface.gesture(cardPressGesture)
        }
    }

    /// Press on empty canvas: mouseDown at touch-down, mouseUp on release —
    /// but only if released inside the card, as in HyperCard.
    private var cardPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isCardPressed {
                    isCardPressed = true
                    onMouseMessage("mouseDown", nil)
                }
            }
            .onEnded { value in
                isCardPressed = false
                if (0...stack.cardSize.width).contains(value.location.x),
                   (0...stack.cardSize.height).contains(value.location.y) {
                    onMouseMessage("mouseUp", nil)
                }
            }
    }

    private var backgroundIndex: Int? {
        stack.backgrounds.firstIndex { $0.id == stack.cards[cardIndex].backgroundID }
    }

    /// Everything a drag can snap against on this card.
    private var snapContext: SnapContext {
        var parts: [(id: UUID, frame: PartFrame)] = []
        if let backgroundIndex {
            parts += stack.backgrounds[backgroundIndex].parts.map { ($0.id, $0.frame) }
        }
        parts += stack.cards[cardIndex].parts.map { ($0.id, $0.frame) }
        return SnapContext(cardSize: stack.cardSize, parts: parts, isEnabled: isSnappingEnabled)
    }

    private func partViews(for parts: Binding<[Part]>) -> some View {
        ForEach(parts) { $part in
            Group {
                if isEditing {
                    EditablePart(
                        part: $part,
                        isSelected: selectedPartID == part.id,
                        snap: snapContext,
                        guides: $guides,
                        onSelect: { selectedPartID = part.id },
                        onOpenInspector: onOpenInspector
                    )
                } else {
                    PartView(
                        part: $part,
                        onTap: { onMouseMessage("mouseUp", part) },
                        onMouseDown: { onMouseMessage("mouseDown", part) }
                    )
                }
            }
            .frame(width: part.frame.width, height: part.frame.height)
            .position(
                x: part.frame.x + part.frame.width / 2,
                y: part.frame.y + part.frame.height / 2
            )
        }
    }

    @ViewBuilder
    private var guideLines: some View {
        ForEach(guides.verticalLines, id: \.self) { x in
            Rectangle()
                .fill(Color.orange)
                .frame(width: 1, height: stack.cardSize.height)
                .position(x: x, y: stack.cardSize.height / 2)
                .allowsHitTesting(false)
        }
        ForEach(guides.horizontalLines, id: \.self) { y in
            Rectangle()
                .fill(Color.orange)
                .frame(width: stack.cardSize.width, height: 1)
                .position(x: stack.cardSize.width / 2, y: y)
                .allowsHitTesting(false)
        }
    }
}

/// Guide lines lit during a drag, in card coordinates.
struct AlignmentGuides: Equatable {
    var verticalLines: [Double] = []
    var horizontalLines: [Double] = []

    mutating func addVertical(_ x: Double) {
        if !verticalLines.contains(x) { verticalLines.append(x) }
    }

    mutating func addHorizontal(_ y: Double) {
        if !horizontalLines.contains(y) { horizontalLines.append(y) }
    }
}

/// Snapping for edit-mode drags: alignment targets (card edges and center,
/// other parts' edges and centers) win within a tolerance and light a
/// guide; otherwise positions fall to an 8-point grid.
struct SnapContext {
    let cardSize: CardSize
    let parts: [(id: UUID, frame: PartFrame)]
    var isEnabled = true

    static let gridSpacing: Double = 8
    static let alignmentTolerance: Double = 6

    enum Axis {
        case horizontal
        case vertical
    }

    private func targets(axis: Axis, excluding id: UUID) -> [Double] {
        var targets: [Double] = switch axis {
        case .horizontal: [0, cardSize.width / 2, cardSize.width]
        case .vertical: [0, cardSize.height / 2, cardSize.height]
        }
        for (partID, frame) in parts where partID != id {
            switch axis {
            case .horizontal:
                targets += [frame.x, frame.x + frame.width / 2, frame.x + frame.width]
            case .vertical:
                targets += [frame.y, frame.y + frame.height / 2, frame.y + frame.height]
            }
        }
        return targets
    }

    /// Snaps a proposed origin, considering the part's leading edge,
    /// center, and trailing edge against all targets.
    func snapPosition(raw: Double, length: Double, axis: Axis, excluding id: UUID, guides: inout AlignmentGuides) -> Double {
        guard isEnabled else { return raw }
        var best: (delta: Double, target: Double)?
        for target in targets(axis: axis, excluding: id) {
            for offset in [0, length / 2, length] {
                let delta = target - (raw + offset)
                if abs(delta) <= Self.alignmentTolerance, abs(delta) < abs(best?.delta ?? .infinity) {
                    best = (delta, target)
                }
            }
        }
        if let best {
            switch axis {
            case .horizontal: guides.addVertical(best.target)
            case .vertical: guides.addHorizontal(best.target)
            }
            return raw + best.delta
        }
        return (raw / Self.gridSpacing).rounded() * Self.gridSpacing
    }

    /// Snaps a proposed length so the far edge aligns or lands on the grid.
    func snapLength(raw: Double, origin: Double, axis: Axis, excluding id: UUID, guides: inout AlignmentGuides) -> Double {
        guard isEnabled else { return raw }
        let rawEdge = origin + raw
        var best: (delta: Double, target: Double)?
        for target in targets(axis: axis, excluding: id) {
            let delta = target - rawEdge
            if abs(delta) <= Self.alignmentTolerance, abs(delta) < abs(best?.delta ?? .infinity) {
                best = (delta, target)
            }
        }
        if let best {
            switch axis {
            case .horizontal: guides.addVertical(best.target)
            case .vertical: guides.addHorizontal(best.target)
            }
            return raw + best.delta
        }
        return (raw / Self.gridSpacing).rounded() * Self.gridSpacing
    }
}

/// A part in edit mode: the control rendered inert, plus selection chrome
/// and move/resize gestures working in logical card coordinates.
private struct EditablePart: View {
    @Binding var part: Part
    let isSelected: Bool
    let snap: SnapContext
    @Binding var guides: AlignmentGuides
    var onSelect: () -> Void
    var onOpenInspector: () -> Void

    @State private var frameAtGestureStart: PartFrame?

    private static let minSize: Double = 32

    var body: some View {
        PartView(part: $part, onTap: {})
            .allowsHitTesting(false)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                onSelect()
                onOpenInspector()
            }
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
        // Visible knob inside a larger invisible touch target.
        Circle()
            .fill(Color.accentColor)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            .contentShape(Rectangle())
            .offset(x: 20, y: 20)
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
                let rawX = start.x + (value.location.x - value.startLocation.x)
                let rawY = start.y + (value.location.y - value.startLocation.y)
                var lit = AlignmentGuides()
                part.frame.x = snap.snapPosition(raw: rawX, length: start.width, axis: .horizontal, excluding: part.id, guides: &lit)
                part.frame.y = snap.snapPosition(raw: rawY, length: start.height, axis: .vertical, excluding: part.id, guides: &lit)
                guides = lit
            }
            .onEnded { _ in
                frameAtGestureStart = nil
                guides = AlignmentGuides()
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(CardView.canvasSpace))
            .onChanged { value in
                if frameAtGestureStart == nil {
                    frameAtGestureStart = part.frame
                }
                guard let start = frameAtGestureStart else { return }
                let rawWidth = start.width + (value.location.x - value.startLocation.x)
                let rawHeight = start.height + (value.location.y - value.startLocation.y)
                var lit = AlignmentGuides()
                part.frame.width = max(Self.minSize, snap.snapLength(raw: rawWidth, origin: start.x, axis: .horizontal, excluding: part.id, guides: &lit))
                part.frame.height = max(Self.minSize, snap.snapLength(raw: rawHeight, origin: start.y, axis: .vertical, excluding: part.id, guides: &lit))
                guides = lit
            }
            .onEnded { _ in
                frameAtGestureStart = nil
                guides = AlignmentGuides()
            }
    }
}

/// Renders a single part as its native SwiftUI control (D5). Unstyled parts
/// keep the native look; per-kind style properties come later.
struct PartView: View {
    @Binding var part: Part
    var onTap: () -> Void
    var onMouseDown: () -> Void = {}

    @State private var isPressed = false

    var body: some View {
        switch part.kind {
        case .button(let properties):
            // The Button's action is HyperCard's mouseUp: it fires on
            // release inside. The simultaneous gesture adds mouseDown.
            Button {
                onTap()
            } label: {
                Text(properties.title)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.bordered)
            .simultaneousGesture(pressDetector)
        case .field(let properties):
            TextField(properties.placeholder, text: fieldText)
                .textFieldStyle(.roundedBorder)
        case .label(let properties):
            // Labels take presses too, like HyperCard's locked text:
            // mouseDown at touch-down, mouseUp on release inside.
            Text(properties.text)
                .font(.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(labelPressGesture)
        }
    }

    private var pressDetector: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isPressed {
                    isPressed = true
                    onMouseDown()
                }
            }
            .onEnded { _ in isPressed = false }
    }

    private var labelPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isPressed {
                    isPressed = true
                    onMouseDown()
                }
            }
            .onEnded { value in
                isPressed = false
                // Release inside sends mouseUp; sliding off cancels.
                if (0...part.frame.width).contains(value.location.x),
                   (0...part.frame.height).contains(value.location.y) {
                    onTap()
                }
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
        selectedPartID: $selection
    )
    .padding()
    .onAppear { selection = stack.cards[0].parts[2].id }
}
