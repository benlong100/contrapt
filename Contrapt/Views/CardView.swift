//
//  CardView.swift
//  Contrapt
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
    /// A link tapped in a rich field: a card link to follow, or a web link.
    var onFollowLink: (FieldLink) -> Void = { _ in }

    @State private var guides = AlignmentGuides()
    @State private var isCardPressed = false
    @Environment(\.stackAssets) private var stackAssets

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

    /// HyperCard's authentic layering: background paint, background parts,
    /// card paint, card parts.
    private var cardCanvas: some View {
        ZStack(alignment: .topLeading) {
            cardSurface
            if let backgroundIndex {
                paintLayer(assetName: stack.backgrounds[backgroundIndex].paintImageAsset)
                partViews(for: $stack.backgrounds[backgroundIndex].parts)
            }
            paintLayer(assetName: stack.cards[cardIndex].paintImageAsset)
            partViews(for: $stack.cards[cardIndex].parts)
            guideLines
        }
    }

    /// A rendered paint layer, if the object has one.
    @ViewBuilder
    private func paintLayer(assetName: String?) -> some View {
        if let assetName,
           let data = stackAssets[assetName],
           let image = Image(assetData: data) {
            image
                .resizable()
                .frame(width: stack.cardSize.width, height: stack.cardSize.height)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var cardSurface: some View {
        let surface = RoundedRectangle(cornerRadius: 8)
            .fill(Color.cardSurface)
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
                    // Hidden parts stay editable, shown ghosted.
                    EditablePart(
                        part: $part,
                        isSelected: selectedPartID == part.id,
                        snap: snapContext,
                        guides: $guides,
                        onSelect: { selectedPartID = part.id },
                        onOpenInspector: onOpenInspector
                    )
                    .opacity(part.isVisible ? 1 : 0.35)
                } else if part.isVisible {
                    PartView(
                        part: $part,
                        onTap: { onMouseMessage("mouseUp", part) },
                        onMouseDown: { onMouseMessage("mouseDown", part) },
                        onFollowLink: onFollowLink
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

/// Renders a button in one of HyperCard's styles. Rectangular styles
/// invert to the accent color while pressed when Auto Hilite is on;
/// transparent has no chrome (a hot-zone); check-box and radio show their
/// glyph and don't momentary-highlight.
struct CardButtonStyle: ButtonStyle {
    var style: ButtonStyleKind
    var autoHilite: Bool

    func makeBody(configuration: Configuration) -> some View {
        let lit = autoHilite && configuration.isPressed && !style.isToggle
        return configuration.label
            .font(.body)
            .foregroundStyle(lit ? Color.white : Color.accentColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, style == .transparent ? 0 : 8)
            .background(background(lit: lit))
            .overlay(border)
            .compositingGroup()
            .shadow(color: style == .shadow ? .black.opacity(0.45) : .clear, radius: 0, x: 3, y: 3)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func background(lit: Bool) -> some View {
        switch style {
        case .transparent, .checkbox, .radio:
            if lit { shape.fill(Color.accentColor.opacity(0.25)) } else { Color.clear }
        case .roundRect:
            shape.fill(lit ? Color.accentColor : Color.accentColor.opacity(0.12))
        case .opaque, .rectangle, .shadow:
            shape.fill(lit ? Color.accentColor : Color.cardSurface)
        }
    }

    @ViewBuilder
    private var border: some View {
        switch style {
        case .transparent, .opaque, .checkbox, .radio:
            EmptyView()
        case .roundRect, .rectangle, .shadow:
            shape.stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
        }
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: style == .roundRect ? 8 : 0)
    }
}

extension FontDesign {
    var swiftUI: Font.Design {
        switch self {
        case .standard: .default
        case .serif: .serif
        case .monospaced: .monospaced
        case .rounded: .rounded
        }
    }
}

extension TextAlign {
    var swiftUI: TextAlignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }
}

extension TextFormat {
    /// The composed font (design, size, bold, italic).
    var font: Font {
        var font = Font.system(size: size, design: fontDesign.swiftUI)
        if isBold { font = font.bold() }
        if isItalic { font = font.italic() }
        return font
    }
}

/// The open document's media assets, for image parts.
private struct StackAssetsKey: EnvironmentKey {
    static let defaultValue: [String: Data] = [:]
}

extension EnvironmentValues {
    var stackAssets: [String: Data] {
        get { self[StackAssetsKey.self] }
        set { self[StackAssetsKey.self] = newValue }
    }
}

/// Renders a single part as its native SwiftUI control (D5). Unstyled parts
/// keep the native look; per-kind style properties come later.
struct PartView: View {
    @Binding var part: Part
    var onTap: () -> Void
    var onMouseDown: () -> Void = {}
    var onFollowLink: (FieldLink) -> Void = { _ in }

    @Environment(\.stackAssets) private var stackAssets
    @State private var isPressed = false

    var body: some View {
        switch part.kind {
        case .button(let properties):
            // The Button's action is HyperCard's mouseUp: it fires on
            // release inside. Toggle styles flip their hilite as well.
            Button {
                if properties.style.isToggle { toggleHilite() }
                onTap()
            } label: {
                buttonLabel(properties)
            }
            .buttonStyle(CardButtonStyle(style: properties.style, autoHilite: properties.autoHilite))
            .simultaneousGesture(pressDetector)
        case .field(let properties):
            if properties.kind == .rich {
                // A rich field renders its Markdown, display-only, with
                // trapped links, at the field's base font and size.
                RichFieldView(
                    markdown: properties.text,
                    fontDesign: properties.format.fontDesign,
                    size: properties.format.size,
                    onFollowLink: onFollowLink
                )
            } else if properties.isMultiline {
                // A HyperCard-style field: a text area filling its frame.
                TextEditor(text: fieldText)
                    .font(properties.format.font)
                    .underline(properties.format.isUnderline)
                    .multilineTextAlignment(properties.format.align.swiftUI)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.cardSurface)
                    .overlay(alignment: .topLeading) {
                        if properties.text.isEmpty {
                            Text(properties.placeholder)
                                .font(properties.format.font)
                                .foregroundStyle(Color.placeholderTextColor)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.fieldStroke, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                TextField(properties.placeholder, text: fieldText)
                    .font(properties.format.font)
                    .underline(properties.format.isUnderline)
                    .multilineTextAlignment(properties.format.align.swiftUI)
                    .textFieldStyle(.roundedBorder)
            }
        case .label(let properties):
            // Labels take presses too, like HyperCard's locked text:
            // mouseDown at touch-down, mouseUp on release inside.
            Text(properties.text)
                .font(.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(labelPressGesture)
        case .image(let properties):
            Group {
                if let data = stackAssets[properties.assetName], let image = Image(assetData: data) {
                    image
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(labelPressGesture)
        }
    }

    /// The button's label: check-box/radio show a glyph before the name;
    /// other styles show the (optional) centered title.
    @ViewBuilder
    private func buttonLabel(_ properties: ButtonPart) -> some View {
        switch properties.style {
        case .checkbox, .radio:
            HStack(spacing: 8) {
                Image(systemName: toggleGlyph(properties))
                if properties.showName {
                    Text(properties.title)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            Text(properties.showName ? properties.title : "")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func toggleGlyph(_ properties: ButtonPart) -> String {
        switch properties.style {
        case .radio: properties.hilite ? "largecircle.fill.circle" : "circle"
        default: properties.hilite ? "checkmark.square.fill" : "square"
        }
    }

    private func toggleHilite() {
        guard case .button(var properties) = part.kind else { return }
        properties.hilite.toggle()
        part.kind = .button(properties)
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

#Preview("Field Text") {
    @Previewable @State var selection: UUID?
    var stack: Stack = {
        var s = Stack.makeNew()
        func field(_ text: String, y: Double, _ fmt: TextFormat) -> Part {
            Part(id: UUID(), name: text, frame: PartFrame(x: 64, y: y, width: 560, height: 60),
                 script: "", kind: .field(FieldPart(text: text, placeholder: "", isMultiline: false, format: fmt)))
        }
        s.cards[0].parts = [
            field("Serif 24 bold", y: 60, TextFormat(fontDesign: .serif, size: 24, isBold: true)),
            field("Monospaced italic", y: 150, TextFormat(fontDesign: .monospaced, size: 18, isItalic: true)),
            field("Rounded underline center", y: 240, TextFormat(fontDesign: .rounded, size: 20, isUnderline: true, align: .center)),
            field("System right", y: 330, TextFormat(size: 17, align: .right)),
        ]
        return s.sanitized()
    }()
    CardView(stack: .constant(stack), cardIndex: 0, selectedPartID: $selection)
        .padding()
}

#Preview("Button Styles") {
    @Previewable @State var selection: UUID?
    var stack: Stack = {
        var s = Stack.makeNew()
        let styles: [(ButtonStyleKind, Bool)] = [
            (.roundRect, false), (.rectangle, false), (.shadow, false),
            (.opaque, false), (.transparent, false), (.checkbox, true), (.radio, true),
        ]
        var parts: [Part] = []
        for (i, entry) in styles.enumerated() {
            parts.append(Part(
                id: UUID(), name: entry.0.label,
                frame: PartFrame(x: 64, y: Double(60 + i * 90), width: 300, height: 60),
                script: "",
                kind: .button(ButtonPart(title: entry.0.label, style: entry.0, hilite: entry.1))
            ))
        }
        s.cards[0].parts = parts
        return s.sanitized()
    }()
    CardView(stack: .constant(stack), cardIndex: 0, selectedPartID: $selection)
        .padding()
}
