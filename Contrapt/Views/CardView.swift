//
//  CardView.swift
//  Contrapt
//

import SwiftUI
import HyperTalk

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
    /// Transient browse-mode "peek": outline every button (⌘⌥) or field (⌘⌥⇧)
    /// on the card, the way classic HyperCard did, so hidden/transparent parts
    /// are findable. Drawn over everything and never hittable.
    var peekButtons = false
    var peekFields = false
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
    /// HyperCard's ⌘⌥-click (button) / ⌘⌥⇧-click (field) shortcut: while the
    /// peek is active, clicking an object of the peeked kind opens its script.
    var onOpenScript: (Part) -> Void = { _ in }
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

    /// The stack's resolved theme (Classic = the existing platform look). Drives
    /// the card chrome here and, via the environment, the nested part views.
    private var theme: ResolvedTheme { ResolvedTheme(named: stack.theme) }

    var body: some View {
        GeometryReader { proxy in
            // A cross-stack swap replaces `stack` before the parent corrects
            // `cardIndex`, so for one frame the index can point past the new
            // (smaller) stack. Render nothing rather than hard-crash on the
            // out-of-range subscript (every helper below indexes cards[cardIndex]).
            if cardIndex >= 0, cardIndex < stack.cards.count {
                cardBody(proxy: proxy)
            }
        }
        .environment(\.stackTheme, theme)
        .themedColorScheme(theme.colorScheme)
    }

    @ViewBuilder
    private func cardBody(proxy: GeometryProxy) -> some View {
        Group {
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

    private var currentCard: Card? {
        stack.cards.indices.contains(cardIndex) ? stack.cards[cardIndex] : nil
    }

    /// HyperCard's authentic layering: background paint, background parts,
    /// card paint, card parts. The two layers can be rendered separately so a
    /// `visual effect` transitions only the card layer, leaving a shared
    /// background static (as in HyperCard) — see `includeBackground`/`includeCard`.
    private var cardCanvas: some View {
        // Does this card (or its background) carry an AddColor color layer?
        // When so, the color draws beneath and the 1-bit paint multiplies over
        // it so white reveals the color; plain stacks are untouched.
        let bgColor = backgroundIndex.map { stack.backgrounds[$0].colorElements } ?? []
        let cardColor = stack.cards.indices.contains(cardIndex) ? stack.cards[cardIndex].colorElements : []
        let hasColor = !bgColor.isEmpty || !cardColor.isEmpty
        return ZStack(alignment: .topLeading) {
            if includeBackground { cardSurface }
            // The whole AddColor layer (background then card) sits behind ALL
            // the 1-bit art AND the live parts, as HyperCard composites it — so
            // field text and buttons stay legible on top of the color.
            if includeBackground { colorLayer(bgColor) }
            if includeCard { colorLayer(cardColor) }
            if includeBackground, let backgroundIndex {
                // `hide background picture` blanks the paint layer only.
                if stack.backgrounds[backgroundIndex].showPicture {
                    paintLayer(assetName: stack.backgrounds[backgroundIndex].paintImageAsset, multiplyOverColor: hasColor)
                }
                partViews(for: backgroundParts(backgroundIndex))
            }
            if includeCard {
                // `hide [card] picture` — the dark-room/curtain idiom.
                if stack.cards[cardIndex].showPicture {
                    paintLayer(assetName: stack.cards[cardIndex].paintImageAsset, multiplyOverColor: hasColor)
                }
                // Hilited TRANSPARENT buttons invert the art beneath them, as
                // real HyperCard flips the pixels (not a black slab). Drawn
                // here — above the paint, below the parts — because live
                // blend modes get flattened by intermediate layers.
                transparentHiliteInversions(hasColor: hasColor)
                partViews(for: $stack.cards[cardIndex].parts)
                guideLines
            }
            if peekButtons { peekOverlay(frames: peekFrames(buttons: true), color: .blue) }
            if peekFields { peekOverlay(frames: peekFrames(buttons: false), color: .green) }
        }
    }

    /// The inverted-art rectangles for every hilited transparent button on
    /// either layer: the card's paint stack, color-inverted, clipped to the
    /// button's frame. Direct drawing — no blend-mode reliance.
    @ViewBuilder
    private func transparentHiliteInversions(hasColor: Bool) -> some View {
        let cardParts = stack.cards.indices.contains(cardIndex) ? stack.cards[cardIndex].parts : []
        let bgParts = backgroundIndex.map { stack.backgrounds[$0].parts } ?? []
        let hilitedFrames = (bgParts + cardParts).compactMap { part -> PartFrame? in
            guard part.isVisible, case .button(let button) = part.kind,
                  button.style == .transparent, button.hilite else { return nil }
            return part.frame
        }
        ForEach(hilitedFrames.indices, id: \.self) { index in
            invertedArt(at: hilitedFrames[index], hasColor: hasColor)
        }
    }

    /// The card's art (surface + both paint layers), inverted and clipped to
    /// `frame`, positioned over it.
    private func invertedArt(at frame: PartFrame, hasColor: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            theme.surface
            if let backgroundIndex, stack.backgrounds[backgroundIndex].showPicture {
                paintLayer(assetName: stack.backgrounds[backgroundIndex].paintImageAsset, multiplyOverColor: hasColor)
            }
            if stack.cards.indices.contains(cardIndex), stack.cards[cardIndex].showPicture {
                paintLayer(assetName: stack.cards[cardIndex].paintImageAsset, multiplyOverColor: hasColor)
            }
        }
        .frame(width: stack.cardSize.width, height: stack.cardSize.height, alignment: .topLeading)
        .offset(x: -frame.x, y: -frame.y)
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipped()
        .colorInvert()
        .offset(x: frame.x, y: frame.y)
        .allowsHitTesting(false)
    }

    /// Background parts as seen from the current card: a non-sharedText
    /// background field carries THIS card's text/runs from the overlay
    /// (HyperCard's storage model — one shared part, text per card). Edits
    /// route text back into the overlay and everything else (geometry,
    /// options) into the shared background part.
    private func backgroundParts(_ backgroundIndex: Int) -> Binding<[Part]> {
        Binding(
            get: {
                stack.backgrounds[backgroundIndex].parts.map { part in
                    guard case .field(var props) = part.kind, !props.sharedText else { return part }
                    let content = stack.cards[cardIndex].backgroundFieldContent[part.id.uuidString]
                    props.text = content?.text ?? ""
                    props.styleRuns = content?.styleRuns ?? []
                    var shown = part
                    shown.kind = .field(props)
                    return shown
                }
            },
            set: { newParts in
                for (i, newPart) in newParts.enumerated() {
                    guard i < stack.backgrounds[backgroundIndex].parts.count else { break }
                    if case .field(var props) = newPart.kind, !props.sharedText {
                        let key = newPart.id.uuidString
                        var content = stack.cards[cardIndex].backgroundFieldContent[key] ?? BackgroundFieldContent()
                        content.text = props.text
                        content.styleRuns = props.styleRuns
                        stack.cards[cardIndex].backgroundFieldContent[key] = content
                        // The shared part stores no per-card text.
                        props.text = ""
                        props.styleRuns = []
                        var shared = newPart
                        shared.kind = .field(props)
                        stack.backgrounds[backgroundIndex].parts[i] = shared
                    } else {
                        stack.backgrounds[backgroundIndex].parts[i] = newPart
                    }
                }
            }
        )
    }

    /// Outlines the given frames — the ⌘⌥ (buttons) / ⌘⌥⇧ (fields) peek.
    /// Distinct tints echo HyperCard's separate button/field tools.
    private func peekOverlay(frames: [PartFrame], color: Color) -> some View {
        ForEach(frames.indices, id: \.self) { i in
            let frame = frames[i]
            Rectangle()
                .stroke(color.opacity(0.9), lineWidth: 1)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
                .allowsHitTesting(false)
        }
    }

    /// Frames of every button (or field) part on this card (background first,
    /// then card), regardless of visibility — what the peek outlines.
    private func peekFrames(buttons: Bool) -> [PartFrame] {
        func matches(_ part: Part) -> Bool {
            switch part.kind {
            case .button: return buttons
            case .field: return !buttons
            default: return false
            }
        }
        var frames: [PartFrame] = []
        if let backgroundIndex { frames += stack.backgrounds[backgroundIndex].parts.filter(matches).map(\.frame) }
        frames += stack.cards[cardIndex].parts.filter(matches).map(\.frame)
        return frames
    }

    /// A rendered paint layer, if the object has one.
    @ViewBuilder
    private func paintLayer(assetName: String?, multiplyOverColor: Bool = false) -> some View {
        if let assetName,
           let data = stackAssets[assetName],
           let image = Image(assetData: data) {
            image
                .resizable()
                .interpolation(.none) // keep 1-bit paint crisp when scaled up
                .frame(width: stack.cardSize.width, height: stack.cardSize.height)
                // AddColor compositing: the 1-bit art multiplies over the color
                // layer behind it — white (×color = color) reveals the color,
                // black stays black. Only when the card/bg carries color, so
                // plain stacks are untouched.
                .blendMode(multiplyOverColor ? .multiply : .normal)
                .allowsHitTesting(false)
        }
    }

    /// The AddColor/Color Tools color layer: filled rectangles and decoded
    /// PICTs at their card-coordinate bounds, drawn beneath the 1-bit paint.
    /// Button/field tint elements are not yet drawn. Hidden elements are
    /// skipped. Non-color cards pass an empty array and draw nothing.
    @ViewBuilder
    private func colorLayer(_ elements: [ColorElement]) -> some View {
        if !elements.isEmpty {
            ZStack(alignment: .topLeading) {
                ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                    if !element.hidden, element.kind == .rect || element.kind == .picture {
                        colorElementView(element)
                            .frame(width: max(0, element.right - element.left),
                                   height: max(0, element.bottom - element.top))
                            .offset(x: element.left, y: element.top)
                    }
                }
            }
            .frame(width: stack.cardSize.width, height: stack.cardSize.height, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func colorElementView(_ element: ColorElement) -> some View {
        switch element.kind {
        case .rect:
            Rectangle().fill(Color(stackColor: element.color))
        case .picture:
            if let asset = element.pictureAsset, let data = stackAssets[asset],
               let image = Image(assetData: data) {
                image.resizable().interpolation(.none)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var cardSurface: some View {
        let surface = RoundedRectangle(cornerRadius: 8)
            .fill(theme.surface)
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
            .onChanged { value in
                MouseState.shared.location = value.location
                if !isCardPressed {
                    isCardPressed = true
                    MouseState.shared.isDown = true
                    ClickRecord.shared.clickLocation = value.location
                    onMouseMessage("mouseDown", nil)
                }
            }
            .onEnded { value in
                isCardPressed = false
                MouseState.shared.isDown = false
                MouseState.shared.location = value.location
                if (0...stack.cardSize.width).contains(value.location.x),
                   (0...stack.cardSize.height).contains(value.location.y) {
                    onMouseMessage("mouseUp", nil)
                }
            }
    }

    private var backgroundIndex: Int? {
        guard let card = currentCard else { return nil }
        return stack.backgrounds.firstIndex { $0.id == card.backgroundID }
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
    /// then snapshot every selected part's starting frame. Option-drag (macOS)
    /// is the classic duplicate-drag: the selection is copied in place first,
    /// the copies become the selection and the drag moves THEM — the originals
    /// stay put.
    private func beginGroupMove(dragged id: UUID) {
        if !selectedPartIDs.contains(id) { selectedPartIDs = [id] }
        #if os(macOS)
        if NSEvent.modifierFlags.contains(.option) {
            duplicateSelectionInPlace()
        }
        #endif
        var frames: [UUID: PartFrame] = [:]
        for pid in selectedPartIDs {
            // Locked parts are selectable but pinned — they sit out a group
            // drag (unless the Move Locked Objects override is on).
            if !selectLocked, isLocked(pid) { continue }
            if let f = frame(of: pid) { frames[pid] = f }
        }
        dragStartFrames = frames
    }

    /// Whether the part with this id carries the layout lock.
    private func isLocked(_ id: UUID) -> Bool {
        if let i = stack.cards[cardIndex].parts.firstIndex(where: { $0.id == id }) {
            return stack.cards[cardIndex].parts[i].isLocked
        }
        if let b = backgroundIndex, let i = stack.backgrounds[b].parts.firstIndex(where: { $0.id == id }) {
            return stack.backgrounds[b].parts[i].isLocked
        }
        return false
    }

    /// Duplicates every selected part at its exact position, each on the layer
    /// (card or background) it lives on, and selects the copies — the
    /// option-drag copy. New ids and scriptIDs, so scripts address the copy
    /// separately.
    private func duplicateSelectionInPlace() {
        var copies: Set<UUID> = []
        for pid in selectedPartIDs {
            if let i = stack.cards[cardIndex].parts.firstIndex(where: { $0.id == pid }) {
                var copy = stack.cards[cardIndex].parts[i]
                copy.id = UUID()
                copy.scriptID = stack.claimScriptID()
                stack.cards[cardIndex].parts.append(copy)
                copies.insert(copy.id)
            } else if let b = backgroundIndex,
                      let i = stack.backgrounds[b].parts.firstIndex(where: { $0.id == pid }) {
                var copy = stack.backgrounds[b].parts[i]
                copy.id = UUID()
                copy.scriptID = stack.claimScriptID()
                stack.backgrounds[b].parts.append(copy)
                copies.insert(copy.id)
            }
        }
        if !copies.isEmpty { selectedPartIDs = copies }
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
              let hex = stack.cards[cardIndex].highlightColor else { return theme.accent }
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
                    // A disabled part (HyperCard's `disable`) grays out and
                    // takes no clicks in browse mode.
                    .disabled(!part.isEnabled)
                    .opacity(part.isEnabled ? 1 : 0.5)
                }
            }
            // The `find` box. A locked plain field highlights the match inside
            // its text; an editable plain field gets a box positioned over the
            // exact matched substring (laid out the way the field renders);
            // anything else falls back to the whole-field outline.
            .overlay(alignment: .topLeading) {
                if findHighlightPartID == part.id, !substringHighlight(for: part) {
                    if let box = editableFindBox(for: part) {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: box.width + 6, height: box.height + 4)
                            .offset(x: box.minX - 3, y: box.minY - 2)
                            .allowsHitTesting(false)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .padding(-2)
                            .allowsHitTesting(false)
                    }
                }
            }
            // Top-aligned, and clipped to the part's frame: a locked field
            // whose text is taller/wider than its frame (the Tour's "Quit the
            // tour" carries ten trailing returns in a one-line field) shows
            // its first lines and clips the rest, exactly as HyperCard does —
            // instead of centering the oversized block so it floats above.
            .frame(width: part.frame.width, height: part.frame.height, alignment: .top)
            .clipped()
            // ⌘⌥/⌘⌥⇧-click to open a script: while peeking the part's kind, a
            // transparent catcher above the part swallows the click and opens
            // its script instead of running the button/field (HyperCard's
            // author shortcut). Only in browse mode — edit mode double-clicks
            // the part for the inspector already.
            .overlay {
                if !isEditing, peekMatches(part) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onOpenScript(part) }
                }
            }
            .position(
                x: part.frame.x + part.frame.width / 2,
                y: part.frame.y + part.frame.height / 2
            )
        }
    }

    /// Whether the active peek (⌘⌥ buttons / ⌘⌥⇧ fields) targets this part's
    /// kind — so a click opens its script.
    private func peekMatches(_ part: Part) -> Bool {
        switch part.kind {
        case .button: return peekButtons
        case .field: return peekFields
        default: return false
        }
    }

    /// Whether `find`'s match should be boxed inside this part's text (only a
    /// locked plain field renders as static Text we can highlight per-range).
    private func substringHighlight(for part: Part) -> Bool {
        guard part.id == findHighlightPartID, findHighlightRange != nil else { return false }
        guard case .field(let field) = part.kind else { return false }
        return field.lockText && field.kind == .plain
    }

    /// The find box's frame over an *editable* plain field's matched
    /// substring, in part coordinates — computed with the same CoreText
    /// layout the click hit-test uses, then offset by the field's insets
    /// (mirroring plainField's margin/padding math). Nil falls back to the
    /// whole-field outline.
    private func editableFindBox(for part: Part) -> CGRect? {
        guard let range = findHighlightRange,
              case .field(let field) = part.kind,
              field.kind == .plain, !field.lockText else { return nil }
        let margin: CGFloat = field.wideMargins ? 10 : 8
        // The same no-wrap heuristic plainField applies (short hard lines
        // render preformatted), plus the Don't Wrap option.
        let preformatted = field.text.split(separator: "\n", omittingEmptySubsequences: false)
            .allSatisfy { $0.count <= 40 }
        guard var box = FieldClickHitTest.matchRect(
            of: range, in: field.text,
            textWidth: part.frame.width - margin * 2,
            format: field.format,
            wraps: !(preformatted || field.dontWrap),
            textHeight: field.textHeight
        ) else { return nil }
        box.origin.x += margin
        // Both editors top-anchor with the same inset (see plainField's
        // lock-independent alignment).
        box.origin.y += min(4, max(2, part.frame.height * 0.2))
        return box
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
            // A locked part stays SELECTABLE (so you can inspect it, edit its
            // script, or unlock it) — the lock only pins its position and size.
            // "Move Locked Objects" in the Reveal menu overrides the pin.
            .onTapGesture(count: 2) {
                onSelect(false)
                onOpenInspector()
            }
            .onTapGesture {
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
                // The resize knob honors the lock too — a locked part is
                // selectable but pinned.
                if isSoleSelection, !locksSelection {
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
    /// An icon button fills its frame with the icon and gets no title padding —
    /// classic icon buttons are often tiny hot-zones (17×16) whose 8pt padding
    /// would otherwise squeeze the icon to nothing.
    var hasIcon: Bool = false
    /// The button's custom fill/edge colors; nil keeps the themed default.
    var fillColor: Color? = nil
    var borderColor: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        // The chrome reads the stack theme, which only resolves inside a View
        // (not in a ButtonStyle struct) — hence the dedicated label view.
        let pressed = autoHilite && configuration.isPressed && !style.isToggle
        let inverted = !style.isToggle && (hilite || pressed)
        return CardButtonLabel(label: configuration.label, style: style,
                               inverted: inverted, tint: tint, hasIcon: hasIcon,
                               fillColor: fillColor, borderColor: borderColor)
    }
}

/// The themed chrome of a card button — fill, border, and inverse-video hilite.
/// Separated from CardButtonStyle so `@Environment(\.stackTheme)` resolves.
private struct CardButtonLabel<Label: View>: View {
    @Environment(\.stackTheme) private var theme
    let label: Label
    let style: ButtonStyleKind
    let inverted: Bool
    let tint: Color
    let hasIcon: Bool
    var fillColor: Color? = nil
    var borderColor: Color? = nil

    var body: some View {
        label
            .font(.body)
            // Inverse video flips ink↔paper: a hilited button shows light label
            // on a black fill (and vice versa), classic 1-bit HyperCard.
            .foregroundStyle(inverted ? theme.surface : tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, (style == .transparent || hasIcon) ? 0 : 8)
            .background(background)
            .overlay(border)
            .compositingGroup()
            .shadow(color: style == .shadow ? .black.opacity(0.45) : .clear, radius: 0, x: 3, y: 3)
            .contentShape(Rectangle())
    }

    /// The fill. Hilited (inverse video) fills solid ink — a direct fill rather
    /// than a `.difference` blend, which escaped the part's clip and inflated a
    /// thin hilited "divider" button to its content height.
    @ViewBuilder
    private var background: some View {
        if inverted {
            if style == .transparent {
                // The inverted artwork is drawn by the card canvas beneath
                // this button (transparentHiliteInversions) — live blend
                // modes get flattened by intermediate layers, so the button
                // itself paints nothing here.
                Color.clear
            } else {
                // Hilite stays a true inverse-video flip, custom fill or not.
                shape.fill(theme.ink)
            }
        } else if let fillColor {
            // A custom fill paints any style with a background; transparent
            // and the toggle glyphs stay unfilled.
            switch style {
            case .transparent, .checkbox, .radio:
                Color.clear
            case .roundRect, .opaque, .rectangle, .shadow:
                shape.fill(fillColor)
            }
        } else {
            switch style {
            case .transparent, .checkbox, .radio:
                Color.clear
            case .roundRect:
                shape.fill(theme.accent.opacity(0.12))
            case .opaque, .rectangle, .shadow:
                shape.fill(theme.surface)
            }
        }
    }

    @ViewBuilder
    private var border: some View {
        switch style {
        case .transparent, .opaque, .checkbox, .radio:
            EmptyView()
        case .roundRect, .rectangle, .shadow:
            shape.stroke(borderColor ?? theme.accent.opacity(0.5), lineWidth: 1)
        }
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: style == .roundRect ? 8 : 0)
    }
}

/// Applies VoiceOver labeling to a part per its shared accessibility role.
/// Editable fields and buttons keep their native behavior (just a spoken name,
/// important for icon-only buttons); static text and images become a single
/// labeled element so the card is navigable and readable aloud.
private struct PartAccessibilityModifier: ViewModifier {
    let info: AccessibilityInfo

    func body(content: Content) -> some View {
        switch info.role {
        case .button:
            // The Button already carries the button trait; the label gives
            // icon-only buttons a spoken name.
            content.accessibilityLabel(info.label)
        case .textField:
            // Keep the native text-field element; just name it.
            content.accessibilityLabel(info.label)
        case .staticText:
            content
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel(info.label.isEmpty ? info.value : info.label)
                .accessibilityValue(info.label.isEmpty ? "" : info.value)
        case .image:
            content
                .accessibilityElement()
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel(info.label)
        }
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
    /// The composed font (design, size, bold, italic). Serif is real
    /// Palatino, not the system serif: imported classic stacks (New York,
    /// Palatino, Times) depend on its QuickDraw-era widths for their line
    /// breaks — New York runs wider and overflows their fields. Must match
    /// FieldClickHitTest.platformFont, which lays the same text out.
    var font: Font {
        var font: Font
        if let embeddedFontName {
            // An embedded outline font (the stack's own TrueType) — render its
            // real glyphs at the point size. Registered when the stack opened.
            font = Font.custom(embeddedFontName, fixedSize: size)
        } else if fontDesign == .serif {
            font = Font.custom("Palatino", size: size)
        } else {
            font = Font.system(size: size, design: fontDesign.swiftUI)
        }
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
    /// opaque fills; rectangle adds a border; shadow adds a drop shadow. The
    /// fill/border colors come from the stack theme (Classic = the platform
    /// semantic colors used before).
    func fieldChrome(style: FieldStyle, showLines: Bool = false, lineHeight: CGFloat = 0, inset: CGFloat = 0, borderColor: Color? = nil) -> some View {
        modifier(FieldChromeModifier(style: style, showLines: showLines, lineHeight: lineHeight, inset: inset, borderColor: borderColor))
    }
}

private struct FieldChromeModifier: ViewModifier {
    @Environment(\.stackTheme) private var theme
    let style: FieldStyle
    let showLines: Bool
    let lineHeight: CGFloat
    let inset: CGFloat
    /// A custom border color (the field's borderColor property); nil = theme.
    var borderColor: Color? = nil

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if style != .transparent { theme.surface }
                    if showLines { FieldBaselineLines(lineHeight: lineHeight, inset: inset, color: theme.border) }
                }
            }
            .overlay {
                if style == .rectangle || style == .shadow || style == .scrolling {
                    RoundedRectangle(cornerRadius: 6).stroke(borderColor ?? theme.border, lineWidth: 1)
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
    var color: Color = .fieldStroke

    var body: some View {
        Canvas { context, size in
            guard lineHeight > 1 else { return }
            var y = lineHeight + 8 // below the first line of text (top padding)
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: inset, y: y))
                path.addLine(to: CGPoint(x: size.width - inset, y: y))
                context.stroke(path, with: .color(color), lineWidth: 0.5)
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
    /// `the scroll of field` plumbing for a locked scrolling field: the
    /// position the script sets, and the live offset while the user scrolls
    /// (written back to the model when the gesture settles).
    @State private var fieldScrollPosition = ScrollPosition()
    @State private var liveScrollOffset: CGFloat = 0
    /// The locked scrolling field's content height, measured so the scroll bar
    /// only shows when there's actually something to scroll.
    @State private var lockedContentHeight: CGFloat = 0
    /// Editable-field focus, for the openField/closeField messages.
    @FocusState private var fieldFocused: Bool
    /// The field's text when it gained focus — closeField only fires when the
    /// text actually changed; otherwise exitField (as in HyperCard 2.2).
    @State private var textAtOpen: String?

    var body: some View {
        partContent
            .modifier(PartAccessibilityModifier(info: accessibility))
    }

    /// How this part is announced to VoiceOver — the shared rules in
    /// HyperTalk's `Accessibility`, applied by PartAccessibilityModifier.
    private var accessibility: AccessibilityInfo {
        switch part.kind {
        case .button(let b):
            return Accessibility.part(kind: "button", name: part.name, title: b.title)
        case .field(let f):
            return Accessibility.part(kind: "field", name: part.name, text: f.text,
                                      placeholder: f.placeholder, locked: f.lockText)
        case .label(let l):
            return Accessibility.part(kind: "label", text: l.text)
        case .image:
            return Accessibility.part(kind: "image", name: part.name)
        }
    }

    @ViewBuilder private var partContent: some View {
        switch part.kind {
        case .button(let properties):
            // The Button's action is HyperCard's mouseUp: it fires on
            // release inside. Toggle styles flip their hilite as well.
            Button {
                if properties.family > 0, properties.autoHilite {
                    // A family member hilites on click (its same-layer
                    // siblings clear in the mouse dispatch) — HyperCard's
                    // radio-group behavior, any style.
                    setHilite(true)
                } else if properties.style.isToggle {
                    toggleHilite()
                }
                onTap()
            } label: {
                buttonLabel(properties)
            }
            .buttonStyle(CardButtonStyle(
                style: properties.style, autoHilite: properties.autoHilite, hilite: properties.hilite,
                // The button's textColor overrides the card highlight for the
                // title/symbol tint; hilite's inverse video ignores both.
                tint: properties.textColor.map(Color.init(stackColor:)) ?? highlight,
                hasIcon: properties.iconAsset != nil || !(properties.iconSymbol ?? "").isEmpty,
                fillColor: properties.fillColor.map(Color.init(stackColor:)),
                borderColor: properties.borderColor.map(Color.init(stackColor:))))
            // Pin the button to its exact part size and clip, so a thin part
            // (a 2px hilited "divider" rule) can't inflate to the button's
            // intrinsic/min content height. The compositingGroup flattens the
            // styled button BEFORE the frame+clip, which is what actually
            // bounds it under the card's scaleEffect — verified by preview:
            // a plain .clipped() here leaks at upscale (Fill Window) and the
            // divider renders fat.
            .compositingGroup()
            .frame(width: part.frame.width, height: part.frame.height)
            .clipShape(Rectangle())
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
                    textColorHex: properties.textColor,
                    borderColorHex: properties.borderColor,
                    lineHeight: properties.textHeight,
                    onFollowLink: onFollowLink
                )
            } else {
                plainField(properties, fieldHeight: part.frame.height, fieldWidth: part.frame.width)
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
    private func plainField(_ properties: FieldPart, fieldHeight: CGFloat = 0, fieldWidth: CGFloat = 0) -> some View {
        // Locked (display-only, e.g. imported) fields use tight HyperCard-like
        // margins so text fills the field as it did originally; editable
        // fields keep roomier insets for entry.
        // Horizontal inset is lock-independent, so toggling Lock Text doesn't
        // shift the text sideways. HyperCard sets field text just a few px in;
        // the roomier editable inset was the only thing that differed, and the
        // tight value is what imported stacks are tuned to.
        // Wide Margins: +7px/side over the base 3 — calibrated against real
        // HyperCard (Basilisk): the What is HyperCard? Stacks card (Palatino
        // 14, 356px field, wideMargins) reproduces HC's soft-wrap breaks at
        // interiors 332–340; 10/side is the center. The old 18 wrapped ~9%
        // early (an extra line per paragraph).
        let margin: CGFloat = properties.wideMargins ? 10 : 3
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
        // The vertical start is lock-independent so toggling Lock Text doesn't
        // shift the text (both anchor to the top, as HyperCard sets field text).
        // Only imported ruled grids / exact-textHeight fields keep their special
        // display-only nudge — and that's a locked-only concern.
        let usesSpecialLockedNudge = properties.lockText && (properties.textHeight != nil || properties.showLines)
        let topPadding: CGFloat = usesSpecialLockedNudge
            ? min(lockedNudge, max(2, fieldHeight * 0.2))
            : min(4, max(2, fieldHeight * 0.2))
        let bottomPadding: CGFloat = properties.lockText ? 2 : min(8, max(2, fieldHeight * 0.18))
        // Pre-formatted tabular text (several short, hard-broken lines, like a
        // calendar grid) should never soft-wrap — a row that's a hair too wide
        // must stay one line and clip, not reflow its last columns. Flowing
        // prose (a quote with no/long lines) still word-wraps.
        let preformatted = isPreformatted(properties.text)
        // Multiple Lines decides the editor outright: a multiline field is a
        // TextEditor (Return inserts a return, text wraps — HyperCard field
        // behavior), a single-line field is the compact TextField. The old
        // "~one line tall renders compact even if flagged multiline" height
        // heuristic silently overrode the author's setting — a 56pt default
        // field or a larger font failed it, and Return then select-all'd via
        // NSTextField instead of inserting a newline. A deliberately short
        // multiline field may clip a little vertically; that's the author's
        // call now, not a guess.
        let effectivelyMultiline = properties.isMultiline
        Group {
            if properties.lockText {
                // Locked text is display-only and dispatches presses like a
                // label, so a field can drive a script. It renders ALL its
                // text (no tail-truncation "…"); overflow clips at the part
                // frame, as a HyperCard field clips silently (a scrolling
                // field scrolls it instead). Imported fields with a HyperCard
                // textHeight render at that exact line height (SwiftUI Text
                // can't shrink line boxes), keeping tightly-set stacks'
                // vertical layout. Don't Wrap keeps each hard line whole and
                // clips it, like the preformatted heuristic.
                let unwrapped = preformatted || properties.dontWrap
                // QuickDraw centered/right alignment (trailing spaces COUNT —
                // the pad-to-sit-left idiom) is emulated inside
                // LockedFieldLabel via per-line indents; the no-textHeight
                // Text path keeps native alignment (imported fields always
                // carry a textHeight, so the idiom lands on the label path).
                let lockedText = Group {
                    if let exactLineHeight = properties.textHeight {
                        LockedFieldLabel(
                            text: properties.text,
                            format: properties.format,
                            textHeight: exactLineHeight,
                            preformatted: unwrapped,
                            highlightRange: highlightRange,
                            wrapWidth: fieldWidth > 0 ? max(1, fieldWidth - 2 * margin) : nil,
                            styleRuns: properties.styleRuns,
                            textColor: properties.textColor.map { PlatformColor(Color(stackColor: $0)) }
                        )
                        // Ideal height, so a last line that only partially
                        // fits still draws (the part frame clips it) rather
                        // than the label dropping it whole.
                        .fixedSize(horizontal: unwrapped, vertical: true)
                    } else {
                        Text(styledText(properties, highlight: highlightRange))
                            .multilineTextAlignment(properties.format.align.swiftUI)
                            .lineLimit(nil)
                            .fixedSize(horizontal: unwrapped, vertical: true)
                    }
                }
                Group {
                    if properties.style == .scrolling {
                        // `the scroll of field`: the model's scroll offset
                        // drives the view; a user scroll writes back when the
                        // gesture settles (not per-tick — the stack binding
                        // registers undo on every write).
                        ScrollView(.vertical) {
                            lockedText
                                .frame(maxWidth: .infinity, alignment: lockedAlignment(properties.format.align))
                                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                                    lockedContentHeight = $0
                                }
                        }
                        // The bar only when there's real overflow to scroll (a
                        // couple of px of slack so rounding can't summon it).
                        .scrollIndicators(lockedContentHeight > fieldHeight - topPadding - bottomPadding + 2 ? .automatic : .hidden)
                        .scrollPosition($fieldScrollPosition)
                        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, offset in
                            liveScrollOffset = offset
                        }
                        .onScrollPhaseChange { _, newPhase in
                            guard newPhase == .idle,
                                  case .field(var f) = part.kind,
                                  abs(f.scroll - liveScrollOffset) > 0.5 else { return }
                            f.scroll = max(0, liveScrollOffset)
                            part.kind = .field(f)
                        }
                        .onAppear {
                            if properties.scroll > 0 { fieldScrollPosition.scrollTo(y: properties.scroll) }
                        }
                        .onChange(of: properties.scroll) { _, newOffset in
                            guard abs(newOffset - liveScrollOffset) > 0.5 else { return }
                            fieldScrollPosition.scrollTo(y: newOffset)
                        }
                    } else {
                        lockedText
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: lockedAlignment(properties.format.align))
                .contentShape(Rectangle())
                .gesture(lockedFieldPressGesture(properties, preformatted: unwrapped))
            } else if effectivelyMultiline {
                TextEditor(text: fieldText)
                    .focused($fieldFocused)
                    .font(properties.format.font)
                    .foregroundStyle(properties.textColor.map(Color.init(stackColor:)) ?? Color.primary)
                    .underline(properties.format.isUnderline)
                    .multilineTextAlignment(properties.format.align.swiftUI)
                    .scrollContentBackground(.hidden)
                    // Only a scrolling-style field shows a scroll bar (HyperCard:
                    // other styles clip). macOS with a mouse otherwise pins a
                    // persistent scroller track on every editor — and TextEditor
                    // ignores .scrollIndicators there, so an AppKit seam switches
                    // the scroller off directly (see TextEditorScrollerHider).
                    .scrollIndicators(properties.style == .scrolling ? .automatic : .hidden)
                    .background {
                        #if os(macOS)
                        if properties.style != .scrolling {
                            TextEditorScrollerHider()
                        }
                        #endif
                    }
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
                    .foregroundStyle(properties.textColor.map(Color.init(stackColor:)) ?? Color.primary)
                    .underline(properties.format.isUnderline)
                    .multilineTextAlignment(properties.format.align.swiftUI)
                    // Top-anchor like the locked label so toggling Lock Text
                    // doesn't move the text (HyperCard top-sets field text).
                    .frame(maxHeight: .infinity, alignment: lockedAlignment(properties.format.align))
            }
        }
        .padding(.horizontal, margin)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .fieldChrome(
            style: properties.style,
            showLines: properties.showLines,
            lineHeight: properties.format.size * 1.4,
            inset: margin,
            borderColor: properties.borderColor.map(Color.init(stackColor:))
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

    /// The field text as an AttributedString for the SwiftUI Text path (a
    /// locked field with no imported textHeight): base font/underline over the
    /// whole string, each styled-text run's font/underline over its span, and
    /// `find`'s matched range tinted. Carries the font itself (not via the
    /// `.font` modifier) so per-run fonts apply. Outline isn't expressible
    /// here — such fields almost always carry a textHeight and take the
    /// LockedFieldLabel path, which does render it.
    private func styledText(_ properties: FieldPart, highlight: Range<Int>? = nil) -> AttributedString {
        var attributed = AttributedString(properties.text)
        attributed.font = properties.format.font
        if properties.format.isUnderline { attributed.underlineStyle = .single }
        // The field's whole-text color (the textColor property), when set.
        if let hex = properties.textColor {
            attributed.foregroundColor = Color(stackColor: hex)
        }

        let characters = attributed.characters
        func range(_ lo: Int, _ hi: Int) -> Range<AttributedString.Index>? {
            let count = characters.count
            let lower = max(0, min(lo, count)), upper = max(lower, min(hi, count))
            guard lower < upper else { return nil }
            return characters.index(characters.startIndex, offsetBy: lower)
                ..< characters.index(characters.startIndex, offsetBy: upper)
        }
        for (index, run) in properties.styleRuns.enumerated() {
            let hi = index + 1 < properties.styleRuns.count ? properties.styleRuns[index + 1].start : characters.count
            guard let span = range(run.start, hi) else { continue }
            attributed[span].font = run.format.font
            attributed[span].underlineStyle = run.format.isUnderline ? .single : nil
        }
        if let highlight, let span = range(highlight.lowerBound, highlight.upperBound) {
            attributed[span].backgroundColor = .accentColor.opacity(0.35)
        }
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
            // The glyph tracks the label's font size (HyperCard's mark is as
            // tall as the text, not the system default), and the gap is tight,
            // so the title gets the width the imported frame budgeted for it —
            // otherwise an oversized symbol + wide gap truncated the name.
            HStack(spacing: 4) {
                Image(systemName: toggleGlyph(properties))
                    .font(properties.format.font)
                    .imageScale(.small)
                if properties.showName {
                    Text(properties.title)
                        .font(properties.format.font)
                        .underline(properties.format.isUnderline)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            let iconImage: Image? = {
                guard let asset = properties.iconAsset, let data = stackAssets[asset] else { return nil }
                return Image(assetData: data)
            }()
            let hasSymbol = !(properties.iconSymbol ?? "").isEmpty
            // A lost icon (iconMissing) with no replacement: label it when it has
            // a title, else draw a placeholder glyph — so it isn't invisible.
            let lostIcon = properties.iconMissing && iconImage == nil && !hasSymbol
            let fallbackLabel = lostIcon && !properties.title.isEmpty
            VStack(spacing: 1) {
                if let iconImage {
                    // 1-bit icons stay crisp with nearest-neighbor scaling.
                    iconImage.resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                } else if let symbol = properties.iconSymbol, !symbol.isEmpty {
                    // SF Symbol icon (the authoring library) — vector, scales to fit.
                    Image(systemName: symbol)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if lostIcon && properties.title.isEmpty {
                    // No title to fall back on — a dashed placeholder marks the
                    // button whose imported icon went missing.
                    Image(systemName: "questionmark.square.dashed")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.secondary)
                }
                if properties.showName || fallbackLabel {
                    Text(properties.title)
                        .font(properties.format.font)
                        .underline(properties.format.isUnderline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        // HyperCard button titles are black (1-bit) — imported
                        // buttons (bitmap icon or plain title) label in the
                        // label color. Only the authoring library's SF-symbol
                        // buttons keep the tint as a clickable affordance. A
                        // custom textColor overrides either.
                        .foregroundStyle(properties.textColor.map { AnyShapeStyle(Color(stackColor: $0)) }
                                         ?? (hasSymbol ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)))
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

    private func setHilite(_ on: Bool) {
        guard case .button(var properties) = part.kind else { return }
        properties.hilite = on
        part.kind = .button(properties)
    }

    /// The pointer's card location from a part gesture's part-local point.
    private func trackMouse(_ local: CGPoint) {
        MouseState.shared.location = CGPoint(x: part.frame.x + local.x, y: part.frame.y + local.y)
    }

    private var pressDetector: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                trackMouse(value.location)
                if !isPressed {
                    isPressed = true
                    MouseState.shared.isDown = true
                    ClickRecord.shared.clickLocation = MouseState.shared.location
                    onMouseDown()
                }
            }
            .onEnded { value in
                isPressed = false
                MouseState.shared.isDown = false
                trackMouse(value.location)
            }
    }

    /// The locked-field press: labelPressGesture plus, on release, recording
    /// which line/word the click landed on — `the clickLine`/`the clickText`
    /// the field's mouseUp script can read (HyperCard's list-field idiom).
    /// The gesture's view is the field's inner text box, so the location maps
    /// straight into the laid-out text.
    private func lockedFieldPressGesture(_ properties: FieldPart, preformatted: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                trackMouse(value.location)
                if !isPressed {
                    isPressed = true
                    MouseState.shared.isDown = true
                    ClickRecord.shared.clickLocation = MouseState.shared.location
                    onMouseDown()
                }
            }
            .onEnded { value in
                isPressed = false
                MouseState.shared.isDown = false
                trackMouse(value.location)
                guard (0...part.frame.width).contains(value.location.x),
                      (0...part.frame.height).contains(value.location.y) else { return }
                let margin: CGFloat = properties.wideMargins ? 10 : 3
                let hit = FieldClickHitTest.hit(
                    in: properties.text,
                    at: value.location,
                    textWidth: part.frame.width - margin * 2,
                    format: properties.format,
                    wraps: !preformatted,
                    textHeight: properties.textHeight,
                    styleRuns: properties.styleRuns
                )
                ClickRecord.shared.recordPending(line: hit.line, text: hit.text, chunk: hit.chunk)
                onTap()
            }
    }

    private var labelPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                trackMouse(value.location)
                if !isPressed {
                    isPressed = true
                    MouseState.shared.isDown = true
                    ClickRecord.shared.clickLocation = MouseState.shared.location
                    onMouseDown()
                }
            }
            .onEnded { value in
                isPressed = false
                MouseState.shared.isDown = false
                trackMouse(value.location)
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
        // Mixed widths: wide push buttons, plus narrow checkbox/radio sized
        // like a real Home-prefs card (title must not truncate behind the
        // glyph — "Text Arrows" fits a ~110px checkbox).
        let styles: [(ButtonStyleKind, String, Bool, Double)] = [
            (.roundRect, "Round Rect", false, 300),
            (.rectangle, "Rectangle", false, 300),
            (.checkbox, "Text Arrows", false, 110),
            (.checkbox, "Blind Typing", true, 110),
            (.radio, "Browsing", false, 110),
            (.radio, "Scripting", true, 110),
        ]
        var parts: [Part] = []
        for (i, entry) in styles.enumerated() {
            parts.append(Part(
                id: UUID(), name: entry.1,
                frame: PartFrame(x: 64, y: Double(60 + i * 70), width: entry.3, height: 28),
                script: "",
                kind: .button(ButtonPart(title: entry.1, style: entry.0, hilite: entry.2))
            ))
        }
        s.cards[0].parts = parts
        return s.sanitized()
    }()
    CardView(stack: .constant(stack), cardIndex: 0, selectedPartIDs: $selection)
        .padding()
}
