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
    @Binding var selectedPartIDs: Set<UUID>
    /// The field `find` last matched, boxed on the card (browse mode).
    var findHighlightPartID: UUID? = nil
    /// The matched character range within that field, so a locked plain field
    /// can box the exact word rather than the whole field.
    var findHighlightRange: Range<Int>? = nil
    /// The script selection (`select line 2 of field 1`) to highlight.
    var selectionPartID: UUID? = nil
    var selectionRange: Range<Int>? = nil
    /// Edit-mode reveal overlays (HyperCard's button/field tool highlighting).
    var revealButtons = false
    var revealFields = false
    /// When true, locked parts can still be selected (to unlock them).
    var selectLocked = false
    /// Which layers to draw. Splitting them lets a card-transition animate the
    /// card layer over a static background (default: both, the whole card).
    var includeBackground = true
    var includeCard = true
    /// Browse-mode mouse messages: the message name (mouseDown/mouseUp)
    /// plus the part it targets — nil means the card itself.
    var onMouseMessage: (String, Part?) -> Void = { _, _ in }
    var onOpenInspector: () -> Void = {}
    /// A link tapped in a rich field: a card link to follow, or a web link.
    var onFollowLink: (FieldLink) -> Void = { _ in }

    @State private var guides = AlignmentGuides()
    @State private var isCardPressed = false
    /// Each selected part's frame at the start of a group drag, so every part
    /// moves by the same delta as the dragged one.
    @State private var dragStartFrames: [UUID: PartFrame] = [:]
    @Environment(\.stackAssets) private var stackAssets

    /// Named coordinate space on the logical-size canvas, so gesture math
    /// works in card coordinates regardless of display scale.
    static let canvasSpace = "cardCanvas"

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = stack.cardSize.width
            let cardHeight = stack.cardSize.height
            let fit = min(proxy.size.width / cardWidth, proxy.size.height / cardHeight)
            // "Actual size" stacks never upscale (a small classic card on the
            // desktop); they still shrink to fit a smaller window.
            let scale = stack.presentAtActualSize ? min(fit, 1) : fit
            cardCanvas
                .frame(width: cardWidth, height: cardHeight)
                .coordinateSpace(name: Self.canvasSpace)
                .scaleEffect(scale)
                .frame(width: cardWidth * scale, height: cardHeight * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// HyperCard's authentic layering: background paint, background parts,
    /// card paint, card parts. The two layers can be rendered separately so a
    /// `visual effect` transitions only the card layer, leaving a shared
    /// background static (as in HyperCard) — see `includeBackground`/`includeCard`.
    private var cardCanvas: some View {
        ZStack(alignment: .topLeading) {
            if includeBackground {
                cardSurface
                if let backgroundIndex {
                    paintLayer(assetName: stack.backgrounds[backgroundIndex].paintImageAsset)
                    partViews(for: $stack.backgrounds[backgroundIndex].parts)
                }
            }
            if includeCard {
                paintLayer(assetName: stack.cards[cardIndex].paintImageAsset)
                partViews(for: $stack.cards[cardIndex].parts)
                guideLines
            }
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
                .interpolation(.none) // keep 1-bit paint crisp when scaled up
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
            surface.onTapGesture { selectedPartIDs = [] }
        } else {
            // .simultaneousGesture (not .gesture): a plain .gesture with a
            // minimumDistance:0 DragGesture takes exclusive control of the
            // gesture arena and starves toolbar Menus of their item taps
            // (the whole menu highlights but nothing fires). Recognizing
            // simultaneously leaves the menu's own gestures working.
            surface.simultaneousGesture(cardPressGesture)
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

    // MARK: - Selection & group move

    /// Click selection: plain replaces, additive (⌘/⇧-click) toggles.
    private func selectPart(_ id: UUID, additive: Bool) {
        if additive {
            if selectedPartIDs.contains(id) { selectedPartIDs.remove(id) }
            else { selectedPartIDs.insert(id) }
        } else {
            selectedPartIDs = [id]
        }
    }

    /// Start a group drag: if the dragged part wasn't selected, collapse to it;
    /// then snapshot every selected part's starting frame.
    private func beginGroupMove(dragged id: UUID) {
        if !selectedPartIDs.contains(id) { selectedPartIDs = [id] }
        var frames: [UUID: PartFrame] = [:]
        for pid in selectedPartIDs { if let f = frame(of: pid) { frames[pid] = f } }
        dragStartFrames = frames
    }

    /// Move every selected part by the dragged part's (already snapped) delta,
    /// clamping each origin to the card as loading does.
    private func groupMove(dx: CGFloat, dy: CGFloat) {
        for (pid, start) in dragStartFrames {
            var f = start
            f.x = min(max(start.x + dx, 0), max(0, stack.cardSize.width - 16))
            f.y = min(max(start.y + dy, 0), max(0, stack.cardSize.height - 16))
            setFrame(f, of: pid)
        }
    }

    private func endGroupMove() { dragStartFrames = [:] }

    private func frame(of id: UUID) -> PartFrame? {
        if let i = stack.cards[cardIndex].parts.firstIndex(where: { $0.id == id }) {
            return stack.cards[cardIndex].parts[i].frame
        }
        if let b = backgroundIndex, let i = stack.backgrounds[b].parts.firstIndex(where: { $0.id == id }) {
            return stack.backgrounds[b].parts[i].frame
        }
        return nil
    }

    private func setFrame(_ frame: PartFrame, of id: UUID) {
        if let i = stack.cards[cardIndex].parts.firstIndex(where: { $0.id == id }) {
            stack.cards[cardIndex].parts[i].frame = frame
        } else if let b = backgroundIndex, let i = stack.backgrounds[b].parts.firstIndex(where: { $0.id == id }) {
            stack.backgrounds[b].parts[i].frame = frame
        }
    }

    /// The current card's accent for button icons/labels — its highlightColor,
    /// or the app accent when unset.
    private var cardHighlight: Color {
        guard stack.cards.indices.contains(cardIndex),
              let hex = stack.cards[cardIndex].highlightColor else { return .accentColor }
        return Color(stackColor: hex)
    }

    /// The current card's highlightColor as a CSS color for rich-field links,
    /// or nil to keep the default link color.
    private var cardLinkColorHex: String? {
        stack.cards.indices.contains(cardIndex) ? stack.cards[cardIndex].highlightColor : nil
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
                    // Hidden parts stay editable, shown ghosted. (The ghosting
                    // lives inside EditablePart, on the visual only — dimming
                    // the whole EditablePart here kept its tap/drag gestures
                    // from receiving clicks, making hidden parts unselectable.)
                    EditablePart(
                        part: $part,
                        isSelected: selectedPartIDs.contains(part.id),
                        isSoleSelection: selectedPartIDs.count == 1 && selectedPartIDs.contains(part.id),
                        snap: snapContext,
                        guides: $guides,
                        revealButtons: revealButtons,
                        revealFields: revealFields,
                        locksSelection: part.isLocked && !selectLocked,
                        showsLockBadge: part.isLocked,
                        highlight: cardHighlight,
                        linkColorHex: cardLinkColorHex,
                        onSelect: { additive in selectPart(part.id, additive: additive) },
                        onOpenInspector: onOpenInspector,
                        onMoveBegan: { beginGroupMove(dragged: part.id) },
                        onMoveBy: { dx, dy in groupMove(dx: dx, dy: dy) },
                        onMoveEnded: { endGroupMove() }
                    )
                } else if part.isVisible {
                    PartView(
                        part: $part,
                        highlightRange: substringHighlight(for: part) ? findHighlightRange
                            : (selectionPartID == part.id ? selectionRange : nil),
                        highlight: cardHighlight,
                        linkColorHex: cardLinkColorHex,
                        onTap: { onMouseMessage("mouseUp", part) },
                        onMouseDown: { onMouseMessage("mouseDown", part) },
                        onFollowLink: onFollowLink,
                        onFieldMessage: { onMouseMessage($0, part) }
                    )
                }
            }
            // The `find` box. When the match is boxed inside the field text
            // (a locked plain field), skip the whole-field outline.
            .overlay {
                if findHighlightPartID == part.id, !substringHighlight(for: part) {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(-2)
                        .allowsHitTesting(false)
                }
            }
            // Top-aligned, and clipped to the part's frame: a locked field
            // whose text is taller/wider than its frame (the Tour's "Quit the
            // tour" carries ten trailing returns in a one-line field) shows
            // its first lines and clips the rest, exactly as HyperCard does —
            // instead of centering the oversized block so it floats above.
            .frame(width: part.frame.width, height: part.frame.height, alignment: .top)
            .clipped()
            .position(
                x: part.frame.x + part.frame.width / 2,
                y: part.frame.y + part.frame.height / 2
            )
        }
    }

    /// Whether `find`'s match should be boxed inside this part's text (only a
    /// locked plain field renders as static Text we can highlight per-range).
    private func substringHighlight(for part: Part) -> Bool {
        guard part.id == findHighlightPartID, findHighlightRange != nil else { return false }
        guard case .field(let field) = part.kind else { return false }
        return field.lockText && field.kind == .plain
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
    /// The only selected part — shows the resize handle (resize is single-part).
    var isSoleSelection = false
    let snap: SnapContext
    @Binding var guides: AlignmentGuides
    var revealButtons = false
    var revealFields = false
    /// Locked and not currently overridden — ignore all selection/move/resize.
    var locksSelection = false
    /// Show the lock badge (locked, regardless of the override).
    var showsLockBadge = false
    var highlight: Color = .accentColor
    var linkColorHex: String? = nil
    /// Select this part; `additive` (⌘/⇧-click) toggles it in the selection.
    var onSelect: (Bool) -> Void
    var onOpenInspector: () -> Void
    /// Group-drag lifecycle: began (snapshot selection), moved by a snapped
    /// delta, ended.
    var onMoveBegan: () -> Void = {}
    var onMoveBy: (CGFloat, CGFloat) -> Void = { _, _ in }
    var onMoveEnded: () -> Void = {}

    /// Whether this part's kind is being revealed (button/field tool
    /// highlighting), so transparent or hidden parts show their bounds.
    private var isRevealed: Bool {
        switch part.kind {
        case .button: return revealButtons
        case .field: return revealFields
        default: return false
        }
    }

    /// A distinct tint per kind, echoing HyperCard's separate tools.
    private var revealColor: Color {
        if case .button = part.kind { return .blue }
        return .green
    }

    @State private var frameAtGestureStart: PartFrame?

    private static let minSize: Double = 32

    var body: some View {
        PartView(part: $part, highlight: highlight, linkColorHex: linkColorHex, onTap: {})
            // Ghost a hidden part's visual only — the contentShape and
            // gestures below stay fully hittable so it can be selected.
            .opacity(part.isVisible ? 1 : 0.35)
            .allowsHitTesting(false)
            .contentShape(Rectangle())
            // A locked part ignores selection and drags; the click falls
            // through to whatever's beneath (or the card). Enable "Select
            // Locked Objects" in the Reveal menu to pick one and unlock it.
            .onTapGesture(count: 2) {
                guard !locksSelection else { return }
                onSelect(false)
                onOpenInspector()
            }
            .onTapGesture {
                guard !locksSelection else { return }
                onSelect(additiveSelectionModifierDown)
            }
            .gesture(moveGesture, including: locksSelection ? .subviews : .all)
            .background {
                // Reveal fill behind the part, so a transparent/empty one
                // still shows where it is.
                if isRevealed {
                    revealColor.opacity(0.12)
                }
            }
            .overlay(alignment: .topLeading) {
                if showsLockBadge {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.black.opacity(0.55), in: Circle())
                        .padding(2)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if isRevealed, !isSelected {
                    Rectangle()
                        .stroke(revealColor.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                if isSelected {
                    Rectangle()
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSoleSelection {
                    resizeHandle
                }
            }
    }

    /// Whether a selection modifier (⌘ or ⇧) is held right now, so a click adds
    /// to the selection rather than replacing it. macOS only — touch has none.
    private var additiveSelectionModifierDown: Bool {
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        return flags.contains(.command) || flags.contains(.shift)
        #else
        return false
        #endif
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
                    onMoveBegan()
                }
                guard let start = frameAtGestureStart else { return }
                let rawX = start.x + (value.location.x - value.startLocation.x)
                let rawY = start.y + (value.location.y - value.startLocation.y)
                // Snap the dragged part; the whole selection moves by the same
                // resulting delta (applied by the owner via onMoveBy).
                var lit = AlignmentGuides()
                let snappedX = snap.snapPosition(raw: rawX, length: start.width, axis: .horizontal, excluding: part.id, guides: &lit)
                let snappedY = snap.snapPosition(raw: rawY, length: start.height, axis: .vertical, excluding: part.id, guides: &lit)
                guides = lit
                onMoveBy(snappedX - start.x, snappedY - start.y)
            }
            .onEnded { _ in
                frameAtGestureStart = nil
                guides = AlignmentGuides()
                onMoveEnded()
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

/// Renders a button in one of HyperCard's styles. Hilite — a momentary press
/// (Auto Hilite) or a persistent hilite (imported/scripted, e.g. the Tour's
/// "BlackStripe" bar) — is a true inverse-video flip of the button's whole
/// rectangle, so it reads correctly over any background (including dark paint)
/// and flashes black↔white on click, as in HyperCard. Transparent has no
/// chrome (a hot-zone); check-box and radio show their glyph and don't flip.
struct CardButtonStyle: ButtonStyle {
    var style: ButtonStyleKind
    var autoHilite: Bool
    var hilite: Bool = false
    /// The button's icon/label color — the card's highlight (app accent default).
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        let pressed = autoHilite && configuration.isPressed && !style.isToggle
        let inverted = !style.isToggle && (hilite || pressed)
        return configuration.label
            .font(.body)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, style == .transparent ? 0 : 8)
            .background(background)
            .overlay(border)
            .compositingGroup()
            .shadow(color: style == .shadow ? .black.opacity(0.45) : .clear, radius: 0, x: 3, y: 3)
            // Inverse video: `.difference` against white flips every pixel in
            // the button's rect — its chrome, its label, and whatever shows
            // through behind it — the way a hilited HyperCard button inverts
            // the screen region it covers.
            .overlay { if inverted { shape.fill(.white).blendMode(.difference) } }
            .contentShape(Rectangle())
    }

    /// The un-inverted fill; the `.difference` overlay flips it when hilited.
    @ViewBuilder
    private var background: some View {
        switch style {
        case .transparent, .checkbox, .radio:
            Color.clear
        case .roundRect:
            shape.fill(Color.accentColor.opacity(0.12))
        case .opaque, .rectangle, .shadow:
            shape.fill(Color.cardSurface)
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

extension View {
    /// A field's border/background per its FieldStyle — shared by plain and
    /// rich fields. Transparent draws nothing (content floats over the card);
    /// opaque fills; rectangle adds a border; shadow adds a drop shadow.
    @ViewBuilder
    func fieldChrome(style: FieldStyle, showLines: Bool = false, lineHeight: CGFloat = 0, inset: CGFloat = 0) -> some View {
        self
            .background {
                ZStack {
                    if style != .transparent { Color.cardSurface }
                    if showLines { FieldBaselineLines(lineHeight: lineHeight, inset: inset) }
                }
            }
            .overlay {
                if style == .rectangle || style == .shadow {
                    RoundedRectangle(cornerRadius: 6).stroke(Color.fieldStroke, lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: style == .transparent ? 0 : 6))
            .shadow(
                color: style == .shadow ? .black.opacity(0.28) : .clear,
                radius: style == .shadow ? 4 : 0,
                x: 0, y: style == .shadow ? 2 : 0
            )
    }
}

/// HyperCard's Show Lines: evenly-spaced baseline rules across a field.
private struct FieldBaselineLines: View {
    let lineHeight: CGFloat
    let inset: CGFloat

    var body: some View {
        Canvas { context, size in
            guard lineHeight > 1 else { return }
            var y = lineHeight + 8 // below the first line of text (top padding)
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: inset, y: y))
                path.addLine(to: CGPoint(x: size.width - inset, y: y))
                context.stroke(path, with: .color(Color.fieldStroke), lineWidth: 0.5)
                y += lineHeight
            }
        }
        .allowsHitTesting(false)
    }
}

/// Renders a single part as its native SwiftUI control (D5). Unstyled parts
/// keep the native look; per-kind style properties come later.
struct PartView: View {
    @Binding var part: Part
    /// `find`'s matched character range to box within a locked plain field.
    var highlightRange: Range<Int>? = nil
    /// The card's accent — button icon/label tint and (as `linkColorHex`)
    /// rich-field link color.
    var highlight: Color = .accentColor
    var linkColorHex: String? = nil
    var onTap: () -> Void
    var onMouseDown: () -> Void = {}
    var onFollowLink: (FieldLink) -> Void = { _ in }
    /// Field-editing lifecycle messages (openField / closeField / exitField).
    var onFieldMessage: (String) -> Void = { _ in }

    @Environment(\.stackAssets) private var stackAssets
    @State private var isPressed = false
    /// Editable-field focus, for the openField/closeField messages.
    @FocusState private var fieldFocused: Bool
    /// The field's text when it gained focus — closeField only fires when the
    /// text actually changed; otherwise exitField (as in HyperCard 2.2).
    @State private var textAtOpen: String?

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
            .buttonStyle(CardButtonStyle(style: properties.style, autoHilite: properties.autoHilite, hilite: properties.hilite, tint: highlight))
            .simultaneousGesture(pressDetector)
        case .field(let properties):
            if properties.kind == .rich {
                // A rich field renders its Markdown, display-only, with
                // trapped links, at the field's base font and size.
                RichFieldView(
                    markdown: properties.text,
                    fontDesign: properties.format.fontDesign,
                    size: properties.format.size,
                    style: properties.style,
                    linkColorHex: linkColorHex,
                    onFollowLink: onFollowLink
                )
            } else {
                plainField(properties, fieldHeight: part.frame.height)
            }
            // (highlightRange is consumed by the locked branch of plainField)
        case .label(let properties):
            // Labels take presses too, like HyperCard's locked text:
            // mouseDown at touch-down, mouseUp on release inside.
            Text(properties.text)
                .font(.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(labelPressGesture)
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
            .simultaneousGesture(labelPressGesture)
        }
    }

    /// A plain (non-rich) field: an editable area, or — when locked — static
    /// text that sends mouseUp to its script. Honors Show Lines (baseline
    /// rules) and Wide Margins (extra inset).
    @ViewBuilder
    private func plainField(_ properties: FieldPart, fieldHeight: CGFloat = 0) -> some View {
        // Locked (display-only, e.g. imported) fields use tight HyperCard-like
        // margins so text fills the field as it did originally; editable
        // fields keep roomier insets for entry.
        let margin: CGFloat = properties.wideMargins ? 18 : (properties.lockText ? 3 : 8)
        // SwiftUI seats a text line's glyphs nearer the top of the line box
        // than HyperCard does, so locked text reads a bit high. Nudge it down
        // by a fraction of the field height — enough for a tall multi-row grid
        // to clear the rule above it, but capped so a short one-line field
        // (e.g. a 17pt-tall day-number box) isn't shoved out of view.
        // Locked prose starts near the top like HyperCard; the bigger nudge is
        // only for ruled grids (Show Lines), whose rows must clear their rule.
        // Fields with an imported textHeight own their vertical grid — they
        // get HyperCard's bare ~1px frame inset.
        let lockedNudge: CGFloat = properties.textHeight != nil ? 1 : (properties.showLines ? 16 : 4)
        let topPadding: CGFloat = properties.lockText ? min(lockedNudge, max(2, fieldHeight * 0.2)) : min(8, max(2, fieldHeight * 0.18))
        let bottomPadding: CGFloat = properties.lockText ? 2 : min(8, max(2, fieldHeight * 0.18))
        // Pre-formatted tabular text (several short, hard-broken lines, like a
        // calendar grid) should never soft-wrap — a row that's a hair too wide
        // must stay one line and clip, not reflow its last columns. Flowing
        // prose (a quote with no/long lines) still word-wraps.
        let preformatted = isPreformatted(properties.text)
        // A field only ~one line tall renders as a compact single-line control
        // even if flagged multi-line, so a short title/label (e.g. the 22pt
        // "Title" field) isn't clipped by a TextEditor's height/insets.
        let lineHeight = CGFloat(properties.format.size) * 1.3
        let effectivelyMultiline = properties.isMultiline && fieldHeight > lineHeight * 2
        Group {
            if properties.lockText {
                // Locked text is display-only and dispatches presses like a
                // label, so a field can drive a script. It renders ALL its
                // text (no tail-truncation "…"); overflow clips at the part
                // frame, as a HyperCard field clips silently. Imported fields
                // with a HyperCard textHeight render at that exact line
                // height (SwiftUI Text can't shrink line boxes), keeping
                // tightly-set stacks' vertical layout.
                Group {
                    if let exactLineHeight = properties.textHeight {
                        LockedFieldLabel(
                            text: properties.text,
                            format: properties.format,
                            textHeight: exactLineHeight,
                            preformatted: preformatted,
                            highlightRange: highlightRange
                        )
                        // Ideal height, so a last line that only partially
                        // fits still draws (the part frame clips it) rather
                        // than the label dropping it whole.
                        .fixedSize(horizontal: preformatted, vertical: true)
                    } else {
                        Text(highlightedText(properties.text))
                            .font(properties.format.font)
                            .underline(properties.format.isUnderline)
                            .multilineTextAlignment(properties.format.align.swiftUI)
                            .lineLimit(nil)
                            .fixedSize(horizontal: preformatted, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: lockedAlignment(properties.format.align))
                .contentShape(Rectangle())
                .gesture(lockedFieldPressGesture(properties, preformatted: preformatted))
            } else if effectivelyMultiline {
                TextEditor(text: fieldText)
                    .focused($fieldFocused)
                    .font(properties.format.font)
                    .underline(properties.format.isUnderline)
                    .multilineTextAlignment(properties.format.align.swiftUI)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if properties.text.isEmpty {
                            Text(properties.placeholder)
                                .font(properties.format.font)
                                .foregroundStyle(Color.placeholderTextColor)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                TextField(properties.placeholder, text: fieldText)
                    .focused($fieldFocused)
                    .textFieldStyle(.plain)
                    .font(properties.format.font)
                    .underline(properties.format.isUnderline)
                    .multilineTextAlignment(properties.format.align.swiftUI)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, margin)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .fieldChrome(
            style: properties.style,
            showLines: properties.showLines,
            lineHeight: properties.format.size * 1.4,
            inset: margin
        )
        // HyperCard's field-editing lifecycle: openField when the insertion
        // point arrives; on leaving, closeField if the text changed, else
        // exitField. (A card change tears the view down without a focus
        // callback, so scripts relying on closeField-at-card-close should
        // also handle closeCard — a known, documented limit.)
        .onChange(of: fieldFocused) { _, focused in
            guard case .field(let current) = part.kind else { return }
            if focused {
                textAtOpen = current.text
                onFieldMessage("openField")
            } else {
                let changed = textAtOpen != nil && textAtOpen != current.text
                textAtOpen = nil
                onFieldMessage(changed ? "closeField" : "exitField")
            }
        }
    }

    /// Whether text is short/tabular — every line is short (a calendar grid,
    /// a header like "week 26", a day label). Such text lays out with no
    /// soft-wrapping so each line stays intact and clips, as in HyperCard;
    /// flowing prose (any long line) still word-wraps.
    private func isPreformatted(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.allSatisfy { $0.count <= 40 }
    }

    /// The field text as an AttributedString, with `find`'s matched range
    /// given a highlight background — HyperCard boxes the found text; we tint
    /// the exact characters. The base font/style come from the `.font`/etc.
    /// modifiers, so only the background is set here.
    private func highlightedText(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let range = highlightRange else { return attributed }
        let characters = attributed.characters
        let count = characters.count
        let lower = max(0, min(range.lowerBound, count))
        let upper = max(lower, min(range.upperBound, count))
        guard lower < upper else { return attributed }
        let start = characters.index(characters.startIndex, offsetBy: lower)
        let end = characters.index(characters.startIndex, offsetBy: upper)
        attributed[start..<end].backgroundColor = .accentColor.opacity(0.35)
        return attributed
    }

    private func lockedAlignment(_ align: TextAlign) -> Alignment {
        switch align {
        case .left: .topLeading
        case .center: .top
        case .right: .topTrailing
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
                        .font(properties.format.font)
                        .underline(properties.format.isUnderline)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            VStack(spacing: 1) {
                if let asset = properties.iconAsset,
                   let data = stackAssets[asset],
                   let image = Image(assetData: data) {
                    // 1-bit icons stay crisp with nearest-neighbor scaling.
                    image.resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                } else if let symbol = properties.iconSymbol, !symbol.isEmpty {
                    // SF Symbol icon (the authoring library) — vector, scales to fit.
                    Image(systemName: symbol)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                if properties.showName {
                    Text(properties.title)
                        .font(properties.format.font)
                        .underline(properties.format.isUnderline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        // Imported bitmap-icon buttons label in black, as in
                        // 1-bit HyperCard; SF-symbol buttons keep the tint.
                        .foregroundStyle(properties.iconAsset != nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                }
            }
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

    /// The locked-field press: labelPressGesture plus, on release, recording
    /// which line/word the click landed on — `the clickLine`/`the clickText`
    /// the field's mouseUp script can read (HyperCard's list-field idiom).
    /// The gesture's view is the field's inner text box, so the location maps
    /// straight into the laid-out text.
    private func lockedFieldPressGesture(_ properties: FieldPart, preformatted: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isPressed {
                    isPressed = true
                    onMouseDown()
                }
            }
            .onEnded { value in
                isPressed = false
                guard (0...part.frame.width).contains(value.location.x),
                      (0...part.frame.height).contains(value.location.y) else { return }
                let margin: CGFloat = properties.wideMargins ? 18 : 3
                let hit = FieldClickHitTest.hit(
                    in: properties.text,
                    at: value.location,
                    textWidth: part.frame.width - margin * 2,
                    format: properties.format,
                    wraps: !preformatted,
                    textHeight: properties.textHeight
                )
                ClickRecord.shared.recordPending(line: hit.line, text: hit.text)
                onTap()
            }
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
    @Previewable @State var selection: Set<UUID> = []
    CardView(
        stack: $stack,
        cardIndex: 0,
        isEditing: true,
        selectedPartIDs: $selection
    )
    .padding()
    .onAppear { selection = [stack.cards[0].parts[2].id] }
}

#Preview("Field Text") {
    @Previewable @State var selection: Set<UUID> = []
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
    CardView(stack: .constant(stack), cardIndex: 0, selectedPartIDs: $selection)
        .padding()
}

#Preview("Button Styles") {
    @Previewable @State var selection: Set<UUID> = []
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
    CardView(stack: .constant(stack), cardIndex: 0, selectedPartIDs: $selection)
        .padding()
}
