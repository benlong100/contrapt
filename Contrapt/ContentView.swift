//
//  ContentView.swift
//  Contrapt
//

import Combine
import PencilKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import HyperTalk
#if canImport(UIKit)
import UIKit
#endif

/// The iOS Home "Stacks" launcher actions, supplied by the Home root so the
/// menu can be built inside ContentView's own toolbar.
struct HomeStackActions {
    var newStack: () -> Void
    var learnHyperTalk: () -> Void
    var open: () -> Void
    var importLegacy: () -> Void
    var setIconApp: () -> Void
}

/// The document view. Browse mode shows the current card with live parts;
/// button taps dispatch mouseUp through the interpreter. Edit mode makes
/// parts selectable, movable, and resizable, with a property inspector.
struct ContentView: View {
    @ObservedObject var document: StackDocument
    /// The document's location on disk, for sharing. Nil until first save.
    var fileURL: URL?
    /// iOS opens another stack (from `go stack "X"`) by layering it over Home;
    /// that's a RootView concern, so it's injected. nil on macOS, which opens
    /// a document window directly.
    var onOpenStackFile: ((URL, GoDestination?) -> Void)? = nil
    /// The iOS Home "Stacks" menu actions, injected by the Home root. When set,
    /// ContentView builds the Stacks menu inline in its own `.primaryAction`
    /// toolbar group — same construction as the working Add menu. (Hosting it as
    /// a `.topBarLeading` item instead made the menu unselectable on iPad — the
    /// whole menu highlighted and no row fired.)
    var homeStackActions: HomeStackActions? = nil
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openURL) private var openURL
    #if os(macOS)
    @Environment(\.openDocument) private var openDocument
    #endif
    @ObservedObject private var cardClipboard = CardClipboard.shared
    @ObservedObject private var partClipboard = PartClipboard.shared
    /// Scripted palette windows (the `palette` XCMD) rendered as floating
    /// panels over the stage. `paletteDrag` keeps each panel's dragged offset
    /// (keyed by name) so the user can reposition it.
    @ObservedObject private var paletteRegistry = DocumentScriptHost.PaletteRegistry.shared
    @State private var paletteDrag: [String: CGSize] = [:]

    @State private var currentCardIndex = 0
    @State private var isEditing = false
    /// The selected parts in edit mode. Copy/cut/paste/delete/nudge and group
    /// drag act on all of them; the inspector shows one only when exactly one
    /// is selected (`singleSelectedPartID`).
    @State private var selectedPartIDs: Set<UUID> = []
    /// The field `find` last matched, boxed on the card until the next edit.
    @State private var findHighlight: FindHighlight?
    /// The script selection's highlight (`select line 2 of field 1`).
    @State private var scriptSelection: FindHighlight?
    @State private var isInspectorPresented = false
    /// Edit-mode reveal overlays — HyperCard's button/field tool highlighting,
    /// so transparent or hidden parts are findable. Remembered across sessions.
    @AppStorage("revealButtons") private var revealButtons = false
    @AppStorage("revealFields") private var revealFields = false
    /// Transient part peek (browse mode, macOS): ⌘⌥ outlines buttons, ⌘⌥⇧
    /// outlines fields. Held only while the keys are down.
    @State private var peekingButtons = false
    @State private var peekingFields = false
    /// Temporarily lets locked parts be selected, so a locked one can be
    /// picked and unlocked. Transient per session.
    @State private var selectLocked = false
    /// HyperCard's background mode (Cmd-B): show only the background layer,
    /// hiding card-layer parts and paint. Transient per session.
    @State private var backgroundOnly = false
    /// The inspector's Card/Background/Stack selection — also the layer that
    /// newly-added parts (buttons, fields, images…) go onto.
    @State private var objectScope: ObjectScriptsInspector.Scope = .card
    @State private var messageBoxText: String?
    @State private var isMessageBoxVisible = false
    #if os(macOS)
    /// The hosting window, for key-window checks when routing Cmd-M.
    @State private var hostWindow: NSWindow?
    #endif
    @State private var scriptErrorText: String?
    @State private var undoFlushTask: Task<Void, Never>?
    @State private var isPhotoPickerPresented = false
    @State private var selectedPhoto: PhotosPickerItem?
    #if !os(macOS)
    /// Keyboard focus for the card area, so the Delete key can remove the
    /// selected part in edit mode (macOS uses a key monitor instead).
    @FocusState private var isCardFocused: Bool
    #endif
    #if os(macOS)
    /// The Mac uses a regular file picker so images don't have to go
    /// through Photos.
    @State private var isImageImporterPresented = false
    #endif
    #if os(iOS)
    @State private var isPaintingPresented = false
    @State private var paintDrawingToEdit = PKDrawing()
    @State private var paintTarget: PaintTarget = .card
    #endif
    /// The card area's size (what CardView's GeometryReader fills), recorded
    /// so Export Bitmaps can match the displayed Fill Window scale.
    @State private var cardAreaSize: CGSize = .zero
    /// Pending `send … in <time>` timers. Owned by the view so they survive
    /// navigation within the stack and are cancelled when the stack closes.
    @State private var pendingSends: [UUID: Task<Void, Never>] = [:]
    /// The scale the card is currently displayed at (Fill Window math —
    /// CardView computes the same); 1 when unmeasured.
    private var displayedCardScale: Double {
        let size = document.stack.cardSize
        guard cardAreaSize.width > 0, cardAreaSize.height > 0, size.width > 0, size.height > 0 else { return 1 }
        return min(cardAreaSize.width / size.width, cardAreaSize.height / size.height)
    }

    /// The button being linked, while the Link To panel floats over the card.
    @State private var linkingPartID: UUID?
    /// Where Link To started — the button's card — so applying the link
    /// returns there (the user flips to the destination to capture it, but
    /// their editing context is the card with the button).
    @State private var linkOriginIndex: Int?
    /// A `go stack "X"` whose stack isn't in the library yet — remembered
    /// while the locate picker is shown, so the pick can open it.
    @State private var pendingGoStack: PendingGoStack?
    @State private var isStackLocatorPresented = false
    /// True once a cross-stack `go stack "X"` has swapped a different stack
    /// into this window in place. Editing is blocked while it's set, so an
    /// edit can't be autosaved back over the document's own on-disk file.
    @State private var displayingForeignStack = false
    /// Set just before a programmatic cross-stack landing so the resulting
    /// `cardIndex` change doesn't also fire `openCard` — the swap sends its
    /// own `openStack`/`openCard` pair in order (see `openResolvedStack`).
    @State private var suppressNextOpenCard = false
    @State private var isGuidePresented = false
    /// Screen-flash (the Flash XCMD): an invert overlay pulsed N times.
    @State private var flashOpacity: Double = 0
    /// A pending `answer` / `ask` dialog and its text field's contents.
    @State private var scriptDialog: ScriptDialog?
    @State private var askFieldText = ""
    /// How many mouse-driven handlers are running. HyperCard runs one at a
    /// time; while one is active, further browse clicks are absorbed (they feed
    /// `the mouseClick` / `the clickLine`) rather than launching competing
    /// handlers.
    @State private var runningScriptCount = 0
    /// The visual effect for the current scripted card transition, if any.
    @State private var cardTransition: ScreenEffect?
    /// Stops the idle loop after an idle handler errors (else the error
    /// dialog would re-fire every tick); navigation re-arms it.
    @State private var idleSuspended = false
    /// The stack's scripted custom menus (`create menu` / `put … into menu`),
    /// rendered as an in-window strip (game stacks hide the real menubar).
    /// Session state, reset whenever a stack opens in this window.
    @State private var stackMenus: [HyperTalkMenu] = []
    /// `set the rect of card window` viewport — the classic big-card-small-
    /// window crop (the Hacker Crackdown trims its card's blank right/bottom
    /// margins this way). nil = show the whole card. Runtime-only state; a
    /// stack's openStack sets it each open.
    @State private var cardWindowViewport: CGSize?
    #if os(macOS)
    /// Window content size that hugs the card (or the stack's card-window
    /// viewport crop of it) + the stage padding, matching `cardStage`.
    private var windowHugTarget: CGSize? {
        guard !document.stack.cards.isEmpty else { return nil }
        let pad: CGFloat = document.stack.presentAtActualSize ? 6 : 16
        let size = cardWindowViewport ?? CGSize(width: document.stack.cardSize.width,
                                                height: document.stack.cardSize.height)
        return CGSize(width: size.width + pad * 2, height: size.height + pad * 2)
    }
    #endif
    /// Editing habit, not document data — persists across stacks.
    @AppStorage("snapToGuides") private var isSnappingEnabled = true

    /// The mutation choke point: every edit anywhere in the view tree —
    /// drags, typing, inspector fields, script effects — writes through
    /// this binding, which arranges undo and marks the document dirty.
    /// The restartable task ends the current coalescing burst after a
    /// quiet period, turning a whole drag or typing run into one undo step.
    private var stack: Binding<Stack> {
        Binding(
            get: { document.stack },
            set: { newValue in
                document.replaceStack(newValue, undoManager: undoManager)
                undoFlushTask?.cancel()
                undoFlushTask = Task {
                    try? await Task.sleep(for: .seconds(0.9))
                    guard !Task.isCancelled else { return }
                    document.flushPendingUndo(with: undoManager)
                }
            }
        )
    }

    /// The card and its selection/edit affordances. Split from `body` (with
    /// `decoratedStage`) so each modifier chain stays small enough for the
    /// compiler to type-check quickly — the whole chain at once overruns the
    /// budget on iOS.
    /// A CardView for the current card, optionally limited to one layer (so
    /// browse-mode transitions animate the card layer over a static background).
    private func cardView(includeBackground: Bool, includeCard: Bool) -> some View {
        CardView(
            stack: stack,
            cardIndex: cardIndex,
            isEditing: isEditing,
            isSnappingEnabled: isSnappingEnabled,
            selectedPartIDs: $selectedPartIDs,
            findHighlightPartID: findHighlight?.partID,
            findHighlightRange: findHighlight?.range,
            selectionPartID: scriptSelection?.partID,
            selectionRange: scriptSelection?.range,
            revealButtons: revealButtons,
            revealFields: revealFields,
            peekButtons: peekingButtons && !isEditing,
            peekFields: peekingFields && !isEditing,
            selectLocked: selectLocked,
            includeBackground: includeBackground,
            includeCard: includeCard,
            onMouseMessage: sendMouseMessage,
            onOpenInspector: { isInspectorPresented = true },
            onOpenScript: openPartScript,
            onFollowLink: followLink
        )
    }

    /// HyperCard button families: clicking an autoHilite member leaves it
    /// hilited (CardView set it) and clears every OTHER same-family button on
    /// the same layer. Card and background families are distinct.
    private func clearFamilySiblings(of part: Part) {
        guard case .button(let button) = part.kind, button.family > 0, button.autoHilite else { return }
        func clear(_ parts: inout [Part]) {
            for index in parts.indices where parts[index].id != part.id {
                guard case .button(var sibling) = parts[index].kind,
                      sibling.family == button.family else { continue }
                sibling.hilite = false
                parts[index].kind = .button(sibling)
            }
        }
        let cardIndex = currentCardIndex
        guard document.stack.cards.indices.contains(cardIndex) else { return }
        if document.stack.cards[cardIndex].parts.contains(where: { $0.id == part.id }) {
            clear(&document.stack.cards[cardIndex].parts)
        } else if let backgroundIndex = document.stack.backgrounds.firstIndex(where: {
            $0.id == document.stack.cards[cardIndex].backgroundID
        }) {
            clear(&document.stack.backgrounds[backgroundIndex].parts)
        }
    }

    /// The Flash XCMD: invert the card `times` times via the overlay. Each
    /// pulse is a brief on/off, serialized in one task.
    private func flashScreen(times: Int) {
        Task { @MainActor in
            for _ in 0..<times {
                flashOpacity = 1
                try? await Task.sleep(nanoseconds: 70_000_000)
                flashOpacity = 0
                try? await Task.sleep(nanoseconds: 70_000_000)
            }
        }
    }

    /// HyperCard's ⌘⌥/⌘⌥⇧-click shortcut: select the clicked object, enter
    /// edit mode, and open the inspector on it — so its script shows with the
    /// Edit toolbar's Done button to return to browsing. Blocked on a foreign
    /// stack (a swapped-in sibling) for the same autosave reason the Edit
    /// button is.
    private func openPartScript(_ part: Part) {
        guard !displayingForeignStack else { return }
        objectScope = stack.cards[cardIndex].parts.contains { $0.id == part.id } ? .card : .background
        selectedPartIDs = [part.id]
        findHighlight = nil
        scriptSelection = nil
        SelectionSession.shared.clear()
        isEditing = true
        isInspectorPresented = true
    }

    /// ⌘⌥C / ⌘⌥S / ⌘⌥B: open the card / stack / background script. Clears any
    /// part selection so the inspector shows the object-scripts view at the
    /// chosen scope, entering edit mode so Done is available. Guarded on a
    /// foreign (cross-stack-swapped) stack, like the Edit button.
    private func openObjectScript(_ scope: ObjectScriptsInspector.Scope) {
        guard !displayingForeignStack else { return }
        selectedPartIDs = []
        objectScope = scope
        findHighlight = nil
        scriptSelection = nil
        SelectionSession.shared.clear()
        isEditing = true
        isInspectorPresented = true
    }

    private var cardStage: some View {
        VStack(spacing: 0) {
            // The scripted custom-menu strip (`create menu` / `put … into
            // menu`). In-window because game stacks hide the real menubar;
            // an item click runs `doMenu "<item>"` so handlers can trap it
            // and menuMessages route, exactly like a real menu choice.
            if !stackMenus.isEmpty, !isEditing {
                customMenuStrip
            }
            cardStageBody
        }
    }

    /// One SwiftUI Menu per scripted menu; separators and disabled items honor
    /// the script's state.
    private var customMenuStrip: some View {
        HStack(spacing: 14) {
            ForEach(stackMenus, id: \.name) { menu in
                Menu(menu.name) {
                    ForEach(Array(menu.items.enumerated()), id: \.offset) { _, item in
                        if item.name == "-" {
                            Divider()
                        } else {
                            Button {
                                performCustomMenuItem(item.name)
                            } label: {
                                if item.checkMark { Label(item.name, systemImage: "checkmark") }
                                else { Text(item.name) }
                            }
                            .disabled(!item.enabled)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!menu.enabled)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }

    /// Runs the clicked item as a `doMenu` statement in the current card's
    /// context — trapping handlers and menuMessages behave as in HyperCard.
    /// Says WHAT the file dialog is hunting for — "Where is Sean's World II
    /// Help?", as real HyperCard asks. One message modifier serves both
    /// importers on this view; pendingGoStack tells us which dialog is up.
    private var fileDialogMessageText: Text {
        if let pending = pendingGoStack {
            return Text("Where is \u{201C}\(pending.name)\u{201D}? Choose the folder that contains it.")
        }
        return Text("Choose an image.")
    }

    private func performCustomMenuItem(_ itemName: String) {
        let host = makeHost()
        let path = scriptPath(cardAt: cardIndex, part: nil)
        let quoted = itemName.replacingOccurrences(of: "\"", with: "")
        Task { @MainActor in
            do {
                _ = try await HyperTalk.execute(messageLine: "doMenu \"\(quoted)\"", along: path, host: host)
            } catch {
                scriptErrorText = error.localizedDescription
            }
        }
    }

    /// A floating palette window: a titled panel whose buttons sit at their
    /// authored rects (normalized to the palette's bounding box) and dispatch
    /// their HyperTalk command when clicked. Draggable by its title bar.
    @ViewBuilder
    private func palettePanel(_ window: DocumentScriptHost.PaletteRegistry.Window) -> some View {
        let buttons = window.buttons
        let minX = buttons.map(\.left).min() ?? 0
        let minY = buttons.map(\.top).min() ?? 0
        let width = (buttons.map(\.right).max() ?? 0) - minX
        let height = (buttons.map(\.bottom).max() ?? 0) - minY
        let base = CGSize(width: Double(window.loc?.x ?? 24), height: Double(window.loc?.y ?? 48))
        let drag = paletteDrag[window.name] ?? .zero
        VStack(spacing: 0) {
            Text(window.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.25))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            paletteDrag[window.name] = CGSize(width: drag.width + value.translation.width,
                                                              height: drag.height + value.translation.height)
                        }
                )
            ZStack(alignment: .topLeading) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                    Button {
                        performPaletteCommand(button.command)
                    } label: {
                        paletteButtonLabel(button)
                            .frame(width: button.right - button.left, height: button.bottom - button.top)
                    }
                    .buttonStyle(.bordered)
                    .position(x: button.left - minX + (button.right - button.left) / 2,
                              y: button.top - minY + (button.bottom - button.top) / 2)
                }
            }
            .frame(width: max(width, 1), height: max(height, 1))
            .padding(4)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.4)))
        .fixedSize()
        .offset(x: base.width + drag.width, y: base.height + drag.height)
    }

    /// A palette button's face: its decoded ICON/cicn/ICN# icon when it has
    /// one (crisp nearest-neighbor, like card button icons), otherwise the
    /// command-derived text label.
    @ViewBuilder
    private func paletteButtonLabel(_ button: PaletteButtonDefinition) -> some View {
        if let asset = button.iconAsset, let data = document.assets[asset],
           let image = Image(assetData: data) {
            image.resizable().interpolation(.none).aspectRatio(contentMode: .fit)
        } else {
            Text(button.label)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    /// Runs a palette button's command as a HyperTalk statement in the current
    /// card's context — `doMenu "Next"`, a bare `paletteHandlerHome` message, etc.
    private func performPaletteCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let host = makeHost()
        let path = scriptPath(cardAt: cardIndex, part: nil)
        Task { @MainActor in
            do {
                _ = try await HyperTalk.execute(messageLine: trimmed, along: path, host: host)
            } catch {
                scriptErrorText = error.localizedDescription
            }
        }
    }

    private var cardStageBody: some View {
        Group {
            if document.stack.cards.isEmpty {
                ContentUnavailableView("No Cards", systemImage: "rectangle.on.rectangle.slash")
            } else {
                // Browse transitions animate the *whole* card (background and
                // card layers together), as HyperCard does — so a card's paint
                // and cover buttons that mask shared background parts stay in
                // place throughout the effect, in both the outgoing and incoming
                // frames. (An earlier split drew a static background and wiped
                // only the card layer, which briefly exposed masked-out
                // background buttons.) The ZStack is a stable overlap container.
                ZStack {
                    if isEditing {
                        // Background mode (HyperCard's Cmd-B) hides the card
                        // layer, leaving the background alone to edit/view.
                        cardView(includeBackground: true, includeCard: !backgroundOnly)
                    } else {
                        cardView(includeBackground: true, includeCard: true)
                            .id(cardIndex)
                            .transition(cardTransition?.transition ?? .identity)
                    }
                }
                // The card area CardView's GeometryReader fills — recorded so
                // Export Bitmaps can match the displayed (Fill Window) scale.
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { cardAreaSize = $0 }
                // The Flash XCMD: a white overlay pulsed with the difference
                // blend inverts the card's colors, like HyperCard's screen
                // flash. Non-hittable; opacity is driven by flashScreen().
                .overlay {
                    Color.white
                        .opacity(flashOpacity)
                        .blendMode(.difference)
                        .allowsHitTesting(false)
                }
                // `set the rect of card window`: show the card 1:1 through a
                // smaller viewport, cropping its right/bottom — HyperCard's
                // big-card-small-window idiom (browse mode only; editing shows
                // the whole card).
                .modifier(CardWindowCrop(
                    viewport: isEditing ? nil : cardWindowViewport,
                    cardSize: CGSize(width: document.stack.cardSize.width,
                                     height: document.stack.cardSize.height)))
                // Actual-size stacks hug the card (small margin for the card
                // shadow); otherwise the usual breathing room.
                .padding(document.stack.presentAtActualSize ? 6 : 16)
                #if os(macOS)
                // Classic HyperCard browse cursor: the pointing finger over
                // the card. Edit mode keeps the arrow; text fields being
                // edited override with their own I-beam.
                .pointerStyle(isEditing ? nil : .link)
                #endif
            }
        }
        .environment(\.stackAssets, document.assets)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backdropColor)
        // In edit mode, Delete removes the selected part and the arrow keys
        // nudge it (1px, or 10px with Shift). A local key monitor handles it on
        // macOS (SwiftUI's onKeyPress never gets the key while the card's part
        // gestures own focus); it defers to any field being edited so the keys
        // work normally in text there.
        #if os(macOS)
        .background(
            EditKeyCatcher(
                isEnabled: isEditing && !selectedPartIDs.isEmpty,
                onDelete: { deleteSelectedParts() },
                onNudge: { dx, dy in moveSelectedPart(dx: dx, dy: dy) }
            )
        )
        #else
        .focusable(isEditing)
        .focusEffectDisabled()
        .focused($isCardFocused)
        .onKeyPress { press in
            guard isEditing, !selectedPartIDs.isEmpty else { return .ignored }
            if press.key == .delete || press.key == .deleteForward {
                deleteSelectedParts()
                return .handled
            }
            let step: CGFloat = press.modifiers.contains(.shift) ? 10 : 1
            switch press.key {
            case .leftArrow: moveSelectedPart(dx: -step, dy: 0)
            case .rightArrow: moveSelectedPart(dx: step, dy: 0)
            case .upArrow: moveSelectedPart(dx: 0, dy: -step)
            case .downArrow: moveSelectedPart(dx: 0, dy: step)
            default: return .ignored
            }
            return .handled
        }
        .onChange(of: selectedPartIDs) { _, newValue in
            if isEditing, !newValue.isEmpty { isCardFocused = true }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { isCardFocused = false }
        }
        #endif
    }

    /// The card stage plus its pickers, overlays, alerts, and inspector.
    private var decoratedStage: some View {
        cardStage
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
        #if os(macOS)
        .fileImporter(isPresented: $isImageImporterPresented, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let image = PlatformImage(data: data) else { return }
            addImagePart(data: data, imageSize: image.pixelSize)
        }
        #endif
        .sheet(isPresented: $isGuidePresented) {
            HyperTalkGuideView()
        }
        #if os(iOS)
        // Painting is iPad-only (finger/Pencil); macOS imports art as images.
        .platformFullScreenCover(isPresented: $isPaintingPresented) {
            PaintEditor(
                title: paintTarget == .card ? "Paint on Card" : "Paint on Background",
                cardSize: document.stack.cardSize,
                initialDrawing: paintDrawingToEdit
            ) { finished in
                savePaint(finished)
            }
        }
        #endif
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            selectedPhoto = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = PlatformImage(data: data) else { return }
                addImagePart(data: data, imageSize: image.pixelSize)
            }
        }
        // The overlay animations are scoped to their own containers, NOT the
        // whole stage: a broad `.animation(value: isMessageBoxVisible)` here
        // would also animate a card `.id` swap happening in the same
        // transaction (openCard's `put … into message` opens the box just as a
        // navigation changes the card), cross-fading the card and flashing the
        // other one through it.
        .overlay(alignment: .bottom) {
            ZStack {
                if isMessageBoxVisible {
                    MessageBoxView(output: messageBoxText,
                                   onCommand: runMessageBoxCommand,
                                   onDismiss: { isMessageBoxVisible = false })
                        // Republish the scene value from inside the box: its
                        // field grabs focus on appear, and focused-value
                        // resolution follows the focused branch — without
                        // this, ⌘M's menu item can read nil (disabled) while
                        // typing here, and macOS hands ⌘M to Window ▸ Minimize.
                        .focusedSceneValue(\.messageBoxVisible, $isMessageBoxVisible)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.default, value: isMessageBoxVisible)
        }
        .overlay(alignment: .top) {
            ZStack {
                if linkingPartID != nil {
                    linkToPanel
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: linkingPartID)
        }
        .overlay(alignment: .topLeading) {
            // Scripted palette windows float over the stage, each a draggable
            // button panel. Only shown in browse mode (edit mode owns the card
            // for part manipulation) and only when the palette has buttons.
            if !isEditing {
                ForEach(paletteRegistry.windows.filter { $0.visible && !$0.buttons.isEmpty }) { window in
                    palettePanel(window)
                }
            }
        }
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
        .alert(
            scriptDialog?.prompt ?? "",
            isPresented: Binding(get: { scriptDialog != nil }, set: { _ in }),
            presenting: scriptDialog
        ) { dialog in
            switch dialog.kind {
            case .answer(let buttons):
                ForEach(buttons, id: \.self) { button in
                    Button(button) {
                        scriptDialog = nil
                        dialog.complete(button)
                    }
                }
            case .ask:
                TextField("", text: $askFieldText)
                Button("OK") {
                    let text = askFieldText
                    scriptDialog = nil
                    dialog.complete(text)
                }
                Button("Cancel", role: .cancel) {
                    scriptDialog = nil
                    dialog.complete(nil)
                }
            case .network:
                Button("Allow Once") {
                    scriptDialog = nil
                    dialog.complete("once")
                }
                Button("Allow Always") {
                    scriptDialog = nil
                    dialog.complete("always")
                }
                Button("Don’t Allow", role: .cancel) {
                    scriptDialog = nil
                    dialog.complete("deny")
                }
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            Group {
                if let id = singleSelectedPartID, let partBinding = partBinding(for: id) {
                    PartInspector(
                        part: partBinding,
                        layerName: partLayerName(for: id),
                        onLinkTo: { linkingPartID = id; linkOriginIndex = currentCardIndex },
                        onDeselect: { selectedPartIDs = [] }
                    ) {
                        deletePart(id: id)
                    }
                } else if selectedPartIDs.count > 1 {
                    MultipleSelectionInspector(
                        count: selectedPartIDs.count,
                        onDeselect: { selectedPartIDs = [] },
                        onDelete: { deleteSelectedParts() }
                    )
                } else {
                    ObjectScriptsInspector(stack: stack, cardIndex: cardIndex, scope: $objectScope)
                }
            }
            .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        }
    }

    var body: some View {
        decoratedStage
        // Register the stack's embedded outline fonts (its own TrueType faces,
        // e.g. a Klingon/Star Trek font) so fields in those families render
        // their real glyphs. Idempotent; re-runs when a new stack swaps in.
        .task(id: document.stack.id) {
            FontResource.registerEmbeddedFonts(document.stack.fonts, assets: document.assets)
        }
        .onChange(of: cardIndex) { oldIndex, newIndex in
            // The script selection doesn't survive leaving the card — this
            // catches UI navigation too, not just scripted `go`.
            if scriptSelection != nil {
                scriptSelection = nil
                SelectionSession.shared.clear()
            }
            // A cross-stack swap drives its own openStack+openCard in order;
            // don't double-fire openCard for the index change it causes.
            if suppressNextOpenCard { suppressNextOpenCard = false; return }
            idleSuspended = false // a new card re-arms the idle loop
            sendCloseThenOpenCard(from: oldIndex, to: newIndex)
        }
        #if os(macOS)
        // Size the window to hug the card AFTER it's actually on screen (the
        // existing WindowBinder below captures `hostWindow`). The earlier
        // attempt called window.setFrame from inside a representable's update
        // at launch and crashed in AppKit's restoration/toolbar layout.
        .task(id: windowHugTarget) {
            guard let target = windowHugTarget else { return }
            // Let launch/state restoration settle; wait for a visible window.
            for _ in 0..<40 {
                if let window = hostWindow, window.isVisible { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let window = hostWindow, window.isVisible else { return }
            let frameForContent = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: target))
            var frame = window.frame
            frame.origin.y += frame.height - frameForContent.height // anchor top
            frame.size = frameForContent.size
            window.setFrame(frame, display: true, animate: false)
        }
        #endif
        // HyperCard's `idle` message: sent repeatedly while nothing else runs
        // (alarm buzzers, cursor resets, the nocheat optionKey trap). Paused
        // in edit mode, while any handler/dialog is active, and after an idle
        // error (navigation re-arms).
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !isEditing, !isSendingSystemMessage, runningScriptCount == 0,
                      scriptDialog == nil, !idleSuspended,
                      !document.stack.cards.isEmpty else { continue }
                let host = makeHost()
                let path = scriptPath(cardAt: cardIndex, part: nil)
                isSendingSystemMessage = true
                do {
                    try await HyperTalk.send("idle", along: path, host: host)
                } catch {
                    // One report, then stop idling until the next navigation.
                    idleSuspended = true
                    scriptErrorText = error.localizedDescription
                }
                isSendingSystemMessage = false
            }
        }
        .task {
            // Remember this stack so other stacks' `go stack "<name>"` can
            // find it later.
            if let fileURL {
                StackLibrary.shared.register(url: fileURL)
                // If we were opened by `go card N of stack "<name>"`, land on
                // that card before the open messages fire.
                if let card = PendingStackNavigation.shared.consume(name: StackLibrary.name(for: fileURL)),
                   let index = cardIndexFor(card) {
                    suppressNextOpenCard = (index != cardIndex)
                    currentCardIndex = index
                }
            }
            // openStack then openCard in order, as one task. Two separate
            // sendSystemMessage calls would drop the second (the guard against
            // overlapping system messages), so the opening card's openCard —
            // e.g. the Manhole's wait/dissolve/`go next` — never ran on open.
            sendOpenSequence(toCardAt: cardIndex)
        }
        // A `go stack "X"` whose stack isn't in the library yet: locate it once.
        // Accepts a classic HyperCard stack too (often extension-less, hence
        // `.data`), so a multi-file game's sibling can be granted access by hand
        // when the sandbox blocked auto-discovering it.
        // A `go stack "X"` whose stack isn't known yet: ask for the FOLDER that
        // contains it. Under the App Sandbox, a folder grant (unlike a single
        // file) lets us enumerate and register every stack inside, so a
        // multi-file game resolves all its rooms from one prompt — and the
        // grant persists across launches.
        .fileImporter(isPresented: $isStackLocatorPresented, allowedContentTypes: [.folder]) { result in
            guard case .success(let folder) = result, let pending = pendingGoStack else { return }
            pendingGoStack = nil
            StackLibrary.shared.grantFolder(folder)
            if let url = StackLibrary.shared.url(forName: pending.name) {
                openResolvedStack(url, card: pending.card)
            } else {
                scriptErrorText = "Couldn't find a stack named \"\(pending.name)\" in that folder."
            }
        }
        .fileDialogMessage(fileDialogMessageText)
        .toolbar { mainToolbar }
        // ⌘↑ also jumps to the first card (the Go menu advertises ⌘1); a hidden
        // shortcut keeps the arrow binding without a duplicate menu item.
        // ⌘⌥C/S/B open the card/stack/background scripts (HyperCard's author
        // shortcuts), like peek-clicking a part opens its script.
        .background {
            Group {
                Button("", action: goFirst)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("") { openObjectScript(.card) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Button("") { openObjectScript(.stack) }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Button("") { openObjectScript(.background) }
                    .keyboardShortcut("b", modifiers: [.command, .option])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .focusedValue(\.cardNavigation, cardNavigation)
        .focusedSceneValue(\.cardActions, cardActions)
        .focusedSceneValue(\.partActions, partActions)
        .focusedSceneValue(\.stackFullScreen, fullScreenBinding)
        .focusedSceneValue(\.guidePresented, $isGuidePresented)
        .focusedSceneValue(\.messageBoxVisible, $isMessageBoxVisible)
        #if os(macOS)
        // Cmd-M arrives via the AppDelegate's key monitor (not menu dispatch —
        // see contraptToggleMessageBox); only the key window's stack responds.
        .background(WindowBinder { hostWindow = $0 })
        // ⌘⌥ outlines buttons, ⌘⌥⇧ outlines fields (classic HyperCard's peek).
        .background(ModifierPeekReader { peekingButtons = $0; peekingFields = $1 })
        .onReceive(NotificationCenter.default.publisher(for: .contraptToggleMessageBox)) { _ in
            guard hostWindow?.isKeyWindow == true else { return }
            isMessageBoxVisible.toggle()
        }
        #endif
        .focusedSceneValue(\.websiteExport, WebsiteExport { directory, actualSize in
            try WebsiteExporter.export(stack: document.stack, assets: document.assets, into: directory, actualSize: actualSize)
        })
        .focusedSceneValue(\.stackBitmaps, StackBitmaps(
            export: { directory in
                // A Fill Window stack exports its bitmaps at the size the
                // window shows them (never below stored size), so the art can
                // be edited at seen-size; actual-size stacks export 1:1.
                try BitmapExporter.export(stack: document.stack, assets: document.assets, into: directory,
                                          pixelScale: document.stack.presentAtActualSize ? 1 : max(1, displayedCardScale))
            },
            replace: { directory in
                let replacement = try BitmapExporter.replacements(for: document.stack, from: directory)
                for (name, data) in replacement.newAssets { document.assets[name] = data }
                document.replaceStack(replacement.stack, undoManager: undoManager)
                return replacement
            }
        ))
        // The stack closing cancels its pending `send … in <time>` timers —
        // the ruling: pending sends survive navigation, die with the stack.
        .onDisappear {
            for task in pendingSends.values { task.cancel() }
            pendingSends.removeAll()
        }
        // Full-screen (presentation) mode: hide the app chrome and let the
        // padding color own the space around the card.
        .toolbar(isPresentingFullScreen ? .hidden : .automatic)
        #if os(macOS)
        .background(
            StackPresentation(
                isPresenting: isPresentingFullScreen,
                paddingColor: Color(stackColor: document.stack.paddingColor),
                onExit: exitFullScreen
            )
        )
        // Original-size stacks make the window content hug the card (with the
        // scene's .windowResizability(.contentSize)); other stacks stay
        // flexible around a comfortable default.
        .frame(
            minWidth: actualSizeWindow ? cardWindowSize.width : 900,
            idealWidth: actualSizeWindow ? cardWindowSize.width : 1000,
            maxWidth: actualSizeWindow ? cardWindowSize.width : .infinity,
            minHeight: actualSizeWindow ? cardWindowSize.height : 640,
            idealHeight: actualSizeWindow ? cardWindowSize.height : 700,
            maxHeight: actualSizeWindow ? cardWindowSize.height : .infinity
        )
        #else
        .overlay(alignment: .topTrailing) {
            if isPresentingFullScreen {
                Button("Exit Full Screen", systemImage: "arrow.down.right.and.arrow.up.left") {
                    exitFullScreen()
                }
                .labelStyle(.iconOnly)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
                .padding()
            }
        }
        #endif
    }

    /// Presentation is on when the stack asks for it, we're browsing (edit
    /// mode needs the chrome), and there's a card to show.
    private var isPresentingFullScreen: Bool {
        document.stack.isFullScreen && !isEditing && !document.stack.cards.isEmpty
    }

    /// Original-size stacks pin the window to the card (macOS). Not while
    /// full-screen (which owns the whole screen).
    private var actualSizeWindow: Bool {
        document.stack.presentAtActualSize && !isPresentingFullScreen
    }

    /// The window content size for an actual-size stack: the card plus a thin
    /// margin for its shadow.
    private var cardWindowSize: CGSize {
        CGSize(width: document.stack.cardSize.width + 12, height: document.stack.cardSize.height + 12)
    }

    private var backdropColor: Color {
        // Full screen uses the stack's scriptable paddingColor. Windowed: a
        // modern theme tints the surround with its padding color; Classic keeps
        // the Mac-gray "desktop," as in HyperCard.
        if isPresentingFullScreen { return Color(stackColor: document.stack.paddingColor) }
        return ResolvedTheme(named: document.stack.theme).paddingColor ?? Color.cardDesktop
    }

    /// A binding to the stack's full-screen flag, published to the scene so
    /// the View menu's toggle can drive it (via @FocusedBinding). Writes go
    /// through the undo choke point, like every other edit.
    private var fullScreenBinding: Binding<Bool> {
        Binding(
            get: { document.stack.isFullScreen },
            set: { stack.wrappedValue.isFullScreen = $0 }
        )
    }

    private func exitFullScreen() {
        if document.stack.isFullScreen { stack.wrappedValue.isFullScreen = false }
    }

    // MARK: - Link To

    /// A floating panel over the card while linking a button. Navigation
    /// stays live (both here and in the toolbar), so the user flips to the
    /// destination card, then captures it with "This Card" — HyperCard's
    /// Link To flow.
    @ViewBuilder
    private var linkToPanel: some View {
        VStack(spacing: 12) {
            Text("Link To")
                .font(.headline)
            Text("Go to the card you want, then link to it.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("Previous", systemImage: "chevron.left") { goToPreviousCard() }
                    .labelStyle(.iconOnly)
                Text("\(cardIndex + 1) of \(document.stack.cards.count)")
                    .font(.callout).monospacedDigit().fixedSize()
                Button("Next", systemImage: "chevron.right") { goToNextCard() }
                    .labelStyle(.iconOnly)
            }
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { linkingPartID = nil; linkOriginIndex = nil }
                Button("This Stack") { applyLink("go to first card") }
                Button("This Card") {
                    applyLink("go to card id \(document.stack.cards[cardIndex].scriptID)")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 12)
        .shadow(radius: 12)
    }

    /// Writes a generated navigation handler to the linking button, found
    /// anywhere in the stack (it lives on a different card than the one the
    /// user navigated to) — then returns to the button's card, since that's
    /// where the user is editing (as HyperCard's Link To did).
    private func applyLink(_ command: String) {
        defer {
            linkingPartID = nil
            if let origin = linkOriginIndex, document.stack.cards.indices.contains(origin) {
                currentCardIndex = origin
            }
            linkOriginIndex = nil
        }
        guard let id = linkingPartID else { return }
        let script = "on mouseUp\n  \(command)\nend mouseUp"
        var updated = document.stack
        for cardIdx in updated.cards.indices {
            if let partIdx = updated.cards[cardIdx].parts.firstIndex(where: { $0.id == id }) {
                updated.cards[cardIdx].parts[partIdx].script = script
                stack.wrappedValue = updated
                return
            }
        }
        for bgIdx in updated.backgrounds.indices {
            if let partIdx = updated.backgrounds[bgIdx].parts.firstIndex(where: { $0.id == id }) {
                updated.backgrounds[bgIdx].parts[partIdx].script = script
                stack.wrappedValue = updated
                return
            }
        }
    }

    // MARK: - Script dispatch

    @State private var isSendingSystemMessage = false

    /// The main toolbar, extracted into a builder so the body expression stays
    /// small enough for the compiler to type-check quickly (especially on iOS,
    /// where the Cards menu keeps the editing group inline).
    @ToolbarContentBuilder private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            #if os(iOS)
            // Home's Stacks launcher. Kept in .primaryAction (not .topBarLeading)
            // because a leading toolbar Menu selects its rows but never fires
            // their actions on iPad; the primary-action group triggers reliably.
            if let actions = homeStackActions {
                Menu("Stacks", systemImage: "square.stack") {
                    Button("New Stack", systemImage: "doc.badge.plus", action: actions.newStack)
                    Button("Learn HyperTalk", systemImage: "graduationcap", action: actions.learnHyperTalk)
                    Divider()
                    Button("Open…", systemImage: "folder", action: actions.open)
                    Button("Import HyperCard Stack…", systemImage: "tray.and.arrow.down", action: actions.importLegacy)
                    Button("Set HyperCard App for Icons…", systemImage: "app.badge", action: actions.setIconApp)
                }
            }
            #endif
            if isEditing {
                editingToolbarTools
            }
            #if os(macOS)
            Button("Home", systemImage: "house") {
                openHome()
            }
            #endif
            // On macOS the guide opens from the Help menu (see GuideCommand);
            // iOS has no menu bar, so it stays in the toolbar.
            #if !os(macOS)
            Button("HyperTalk Guide", systemImage: "book") {
                isGuidePresented = true
            }
            #endif
            if let fileURL {
                ShareLink(item: fileURL) {
                    Label("Share Stack", systemImage: "square.and.arrow.up")
                }
            }
            #if os(iOS)
            // macOS exports from File ▸ Export as Website…; iOS has no menu bar,
            // so it lives in the toolbar and shares the site as a .zip. The size
            // choice is a submenu rather than a confirmationDialog — a second
            // confirmationDialog in this scene collides with the Stacks menu's
            // popover on iPad.
            Menu("Export as Website", systemImage: "globe") {
                Button("Original Size") { exportWebsite(actualSize: true) }
                Button("Scaled to Fit") { exportWebsite(actualSize: false) }
            }
            #endif
            Button("Message Box", systemImage: "text.and.command.macwindow") {
                isMessageBoxVisible.toggle()
            }
            Button(isEditing ? "Done" : "Edit") {
                if isEditing {
                    selectedPartIDs = []
                    isInspectorPresented = false
                } else {
                    // Entering edit mode opens the inspector and clears any
                    // lingering find box (a browse-mode artifact).
                    isInspectorPresented = true
                    findHighlight = nil
                    scriptSelection = nil
                    SelectionSession.shared.clear()
                }
                isEditing.toggle()
            }
            // Editing is blocked while a cross-stack `go` has swapped a foreign
            // stack into this window — an edit would be autosaved over this
            // document's own file.
            .disabled(displayingForeignStack)
        }
        ToolbarItemGroup(placement: cardNavigationPlacement) {
            Button("Previous Card", systemImage: "chevron.left") {
                goToPreviousCard()
            }
            Spacer()
            Menu {
                Button("First Card", systemImage: "backward.end") { goFirst() }
                Button("Last Card", systemImage: "forward.end") { goLast() }
            } label: {
                Text("Card \(cardIndex + 1) of \(document.stack.cards.count)")
                    .font(.callout)
                    .monospacedDigit()
                    .fixedSize()
            }
            Spacer()
            Button("Next Card", systemImage: "chevron.right") {
                goToNextCard()
            }
        }
    }

    /// The edit-mode toolbar buttons, extracted so the toolbar builder stays
    /// small enough for the compiler to type-check quickly (especially on iOS,
    /// where the Cards menu is inline).
    @ViewBuilder private var editingToolbarTools: some View {
        Menu("Add Part", systemImage: "plus") {
            // The target layer follows the inspector's Card/Background tab.
            Section("Adding to \(newPartLayerName)") {
                Button("Button", systemImage: "hand.tap") {
                    addPart(.button(ButtonPart(title: "New Button")))
                }
                Button("Field", systemImage: "character.textbox") {
                    // Multiline by default — HyperCard fields wrap; a
                    // single-line field is the (rarer) opt-out in the inspector.
                    addPart(.field(FieldPart(text: "", placeholder: "", isMultiline: true)))
                }
                Button("Label", systemImage: "textformat") {
                    addPart(.label(LabelPart(text: "New Label")))
                }
                Button("Image…", systemImage: "photo") {
                    #if os(macOS)
                    isImageImporterPresented = true
                    #else
                    isPhotoPickerPresented = true
                    #endif
                }
            }
        }
        // On macOS these live in the Edit menu (see CardCommands) to keep the
        // toolbar uncluttered; iOS has no menu bar, so the toolbar menu stays.
        #if !os(macOS)
        Menu("Cards", systemImage: "rectangle.stack") {
            Button("New Card", systemImage: "rectangle.badge.plus") {
                addCard()
            }
            Button("New Background", systemImage: "rectangle.on.rectangle.badge.plus") {
                addBackground()
            }
            Divider()
            Button("Cut Card", systemImage: "scissors") {
                cutCard()
            }
            .disabled(!canDeleteCurrentCard)
            Button("Copy Card", systemImage: "doc.on.doc") {
                copyCard()
            }
            Button("Paste Card", systemImage: "doc.on.clipboard") {
                pasteCard()
            }
            .disabled(cardClipboard.payload == nil)
            Divider()
            Button("Delete Card", systemImage: "trash", role: .destructive) {
                deleteCurrentCard()
            }
            .disabled(!canDeleteCurrentCard)
        }
        #endif
        Menu("Arrange", systemImage: "square.3.layers.3d") {
            Button("Bring to Front", systemImage: "arrow.up.to.line") { arrangeSelectedPart(.front) }
            Button("Bring Closer", systemImage: "chevron.up") { arrangeSelectedPart(.closer) }
            Button("Send Farther", systemImage: "chevron.down") { arrangeSelectedPart(.farther) }
            Button("Send to Back", systemImage: "arrow.down.to.line") { arrangeSelectedPart(.back) }
        }
        .disabled(singleSelectedPartID == nil)
        // HyperCard's button/field tool highlighting: outline all buttons or
        // fields so transparent and hidden ones are findable while editing.
        Menu("Reveal", systemImage: "eye") {
            Toggle("Show Buttons", isOn: $revealButtons)
            Toggle("Show Fields", isOn: $revealFields)
            // Locked parts are always selectable; this override also lets them
            // be moved and resized without unlocking first.
            Toggle("Move Locked Objects", isOn: $selectLocked)
            Divider()
            // HyperCard's background mode (Cmd-B): see the background alone.
            Toggle("Background Only", isOn: $backgroundOnly)
        }
        .onChange(of: backgroundOnly) { _, hidingCard in
            if hidingCard {
                // A card-layer part that's now hidden shouldn't stay selected,
                // and (as in HyperCard) editing now targets the background.
                let cardPartIDs = Set(stack.cards[cardIndex].parts.map(\.id))
                selectedPartIDs.subtract(cardPartIDs)
                objectScope = .background
            } else {
                objectScope = .card
            }
        }
        // Painting is an iPad capability (finger/Pencil); the Mac imports
        // finished art as images instead. See PaintEditor.
        #if os(iOS)
        Menu("Paint", systemImage: "paintbrush") {
            Button("Paint on Card", systemImage: "rectangle") {
                openPaintEditor(target: .card)
            }
            Button("Paint on Background", systemImage: "rectangle.on.rectangle") {
                openPaintEditor(target: .background)
            }
        }
        #endif
        Toggle(isOn: $isSnappingEnabled) {
            Label("Snap to Guides", systemImage: "grid")
        }
        .toggleStyle(.button)
        Button("Inspector", systemImage: "slider.horizontal.3") {
            isInspectorPresented = true
        }
    }

    /// A file URL as a classic Mac colon path (`Users:me:Stacks:Game`), for
    /// `the long name of this stack`. HyperCard long names are colon paths;
    /// stacks parse the folder from them, so a value with colons matters more
    /// than the exact disk name. Drops the leading slash and the `.contrapt`
    /// extension, turning the remaining path separators into colons.
    private static func classicColonPath(_ url: URL) -> String {
        let trimmed = url.deletingPathExtension().path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.replacingOccurrences(of: "/", with: ":")
    }

    private func makeHost(cardIndex: Binding<Int>? = nil) -> DocumentScriptHost {
        DocumentScriptHost(
            stack: stack,
            // closeCard runs with the OUTGOING card as context (HyperCard sends
            // it before the current card changes); callers pass a fixed index so
            // `this card` / `cd field …` resolve against the card being left.
            currentCardIndex: cardIndex ?? $currentCardIndex,
            // The document's path as a classic colon path, for `the long name
            // of this stack` (stacks parse the folder out of it).
            stackPath: fileURL.map(Self.classicColonPath) ?? "",
            onMessage: { text in
                // `put` with no destination opens the message box, as in
                // HyperCard.
                messageBoxText = text
                isMessageBoxVisible = true
            },
            // `answer` / `ask` present a modal and suspend the script until
            // the user responds, resuming the interpreter's continuation.
            onAnswer: { prompt, buttons in
                await withCheckedContinuation { continuation in
                    scriptDialog = ScriptDialog(prompt: prompt, kind: .answer(buttons: buttons)) { result in
                        continuation.resume(returning: result ?? buttons.first ?? "OK")
                    }
                }
            },
            onAsk: { prompt, initial in
                await withCheckedContinuation { continuation in
                    askFieldText = initial
                    scriptDialog = ScriptDialog(prompt: prompt, kind: .ask) { result in
                        continuation.resume(returning: result)
                    }
                }
            },
            // `answer file` presents an open panel and suspends the script
            // until the user picks a file or cancels.
            onAnswerFile: { prompt, type in
                await presentOpenPanel(prompt: prompt, type: type)
            },
            // A scripted `go`: play the first queued effect as an animated
            // card swap, or cut instantly when there's none.
            onNavigate: { index, effects in
                guard let effect = effects.first else {
                    cardTransition = nil
                    currentCardIndex = index
                    return
                }
                // Set the transition first so the *outgoing* card carries it
                // (a true crossfade needs both cards animating); swap on the
                // next runloop tick, inside the animation.
                cardTransition = effect
                DispatchQueue.main.async {
                    withAnimation(effect.animation) { currentCardIndex = index }
                }
            },
            // `find` boxes the matched field (or clears the box on a miss).
            onFind: { highlight in
                findHighlight = highlight
            },
            // `select …` highlights a field range (clears on navigation).
            onSelection: { scriptSelection = $0 },
            // `go home` opens the Home stack (macOS; iOS front door is Home).
            onGoHome: { openHome() },
            // `click at h,v` routes a mouseUp to the part under the point.
            onClickPart: { part in sendMouseMessage("mouseUp", to: part) },
            // `go stack "X"` resolves via the Stack Library and opens it.
            onGoStack: { name, card in goToStack(named: name, card: card) },
            // `doMenu "Copy/Cut/Paste Card"` shares the Edit menu's actions.
            onCardMenu: { item in
                switch item {
                case "copy card": copyCard()
                case "cut card": cutCard()
                case "paste card": pasteCard()
                default: break
                }
            },
            // `play` reads its imported sound (WAV) bytes from the document.
            assetData: { document.assets[$0] },
            onAssetWrite: { name, data in document.assets[name] = data },
            assetsSnapshot: { document.assets },
            onPresentPrint: { pdf, title in PrintService.present(pdf: pdf, jobTitle: title) },
            onFlash: { count in flashScreen(times: count) },
            // The stack you're editing is trusted to reach the network; a stack
            // you're only browsing must ask first.
            isAuthoring: { isEditing },
            // A network-consent prompt for an untrusted stack reaching a host it
            // hasn't been granted — suspends the script until the user chooses.
            onNetworkConsent: { host in
                await withCheckedContinuation { (continuation: CheckedContinuation<(allow: Bool, always: Bool), Never>) in
                    scriptDialog = ScriptDialog(
                        prompt: "“\(document.stack.name)” wants to connect to \(host).",
                        kind: .network
                    ) { choice in
                        switch choice {
                        case "always": continuation.resume(returning: (true, true))
                        case "once": continuation.resume(returning: (true, false))
                        default: continuation.resume(returning: (false, false))
                        }
                    }
                }
            },
            // `send … in <time>` — this view owns the pending timers, so they
            // survive navigation within the stack and die when it closes.
            onScheduleSend: { message, arguments, target, seconds in
                scheduleTimedSend(message, arguments: arguments, to: target, afterSeconds: seconds)
            },
            // `set the rect of card window` — the big-card-small-window crop.
            cardWindowViewport: $cardWindowViewport,
            // `create menu` … — the scripted menu bar strip.
            menuBar: $stackMenus
        )
    }

    /// A pending `send … in <time>`: sleep, then dispatch along the target's
    /// path with a fresh host (hosts are per-dispatch). A target gone by fire
    /// time is dropped silently; stack close cancels via onDisappear.
    private func scheduleTimedSend(_ message: String, arguments: [String], to target: HyperTalkObject, afterSeconds: Double) {
        let id = UUID()
        pendingSends[id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, afterSeconds) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            pendingSends[id] = nil
            let host = makeHost()
            guard let path = host.scriptLayers(for: target) else { return }
            _ = try? await HyperTalk.send(message, arguments: arguments, along: path, host: host)
        }
    }

    /// Resolves `go stack "<name>"` through the Stack Library and opens it;
    /// if the name isn't known yet, prompts the user to locate it once.
    private func goToStack(named name: String, card: GoDestination?) {
        if let url = StackLibrary.shared.url(forName: name) {
            openResolvedStack(url, card: card)
        } else {
            pendingGoStack = PendingGoStack(name: name, card: card)
            isStackLocatorPresented = true
        }
    }

    /// Navigates to a resolved stack file. In browse mode it swaps the target
    /// into THIS window in place — faithful to HyperCard's single window, and
    /// essential for multi-file games (the Manhole's rooms span six files that
    /// link with `go … of stack "X"`). In edit mode it opens a separate
    /// document/layer instead, so an edit can't be autosaved over this file.
    private func openResolvedStack(_ url: URL, card: GoDestination?) {
        StackLibrary.shared.register(url: url)

        // Editing: keep the old behavior — a separate window (macOS) or layer
        // (iOS) — so the displayed-vs-saved document stays one and the same.
        guard !isEditing else {
            if let card {
                PendingStackNavigation.shared.set(name: StackLibrary.name(for: url), card: card)
            }
            #if os(macOS)
            Task { try? await openDocument(at: url) }
            #else
            onOpenStackFile?(url, card)
            #endif
            return
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }

        // Load the target into the live document, in place. A classic STAK is
        // imported on the fly (same processing as a file import); a `.contrapt`
        // (or legacy JSON) is decoded directly. Both bypass undo, so autosave
        // won't write the swapped stack back over this document's own file.
        let head = Array(data.prefix(8))
        let isClassic = head.count >= 8 && String(bytes: head[4..<8], encoding: .ascii) == "STAK"
        if isClassic {
            let actualSize = StackLibrary.shared.actualSize(forName: StackLibrary.name(for: url))
            guard let imported = try? LegacyStackImporter.importedStack(
                from: url, iconApp: HyperCardAppReference.url(), presentAtActualSize: actualSize) else { return }
            // Correct the card index to the incoming stack's bounds BEFORE
            // publishing the swap, so the view never re-renders with the new
            // (possibly smaller) stack and the old index (an out-of-range crash).
            if currentCardIndex >= imported.stack.cards.count {
                currentCardIndex = max(0, imported.stack.cards.count - 1)
            }
            document.present(stack: imported.stack, assets: imported.assets)
        } else {
            document.load(data)
        }
        displayingForeignStack = (fileURL == nil) || (url != fileURL)

        // Register the new stack's siblings so onward room-to-room navigation
        // resolves, and drop the previous stack's back trail (its card ids are
        // meaningless here).
        StackLibrary.shared.registerSiblings(of: url, actualSize: StackLibrary.shared.actualSize(forName: StackLibrary.name(for: url)))
        CardBackStack.shared.ids.removeAll()
        VisitHistory.shared.ids.removeAll()

        // Land on the requested card (first card when unspecified) and send the
        // open messages in order. Suppress the openCard that the index change
        // would otherwise trigger, so it fires exactly once, after openStack.
        let newCount = document.stack.cards.count
        let target = min(max(0, card.flatMap(cardIndexFor) ?? 0), max(0, newCount - 1))
        suppressNextOpenCard = (target != cardIndex)
        currentCardIndex = target
        sendOpenSequence(toCardAt: target)
    }

    /// Navigation between cards: send `closeCard` to the card being LEFT, then
    /// `openCard` to the card arriving — in that order, as one guarded task
    /// (two `sendSystemMessage` calls would drop the second). closeCard runs
    /// with the outgoing card as context so `this card` / its card fields
    /// resolve correctly (e.g. The Hacker Crackdown's closeCard re-enables the
    /// "Prior" button when you leave the title card).
    private func sendCloseThenOpenCard(from oldIndex: Int, to newIndex: Int) {
        guard !isEditing else { return }
        // A navigation that lands while a system message is still running —
        // an auto-advance card whose openCard `go`es to the next (its visual
        // effect defers the index change a runloop turn) — must still get its
        // openCard. Queue it and fire when the in-flight send finishes, rather
        // than dropping it (which stalled chained `on openCard / go next card`
        // intro sequences after one hop).
        guard !isSendingSystemMessage else {
            pendingCardOpen = (from: oldIndex, to: newIndex)
            return
        }
        guard oldIndex >= 0, oldIndex < document.stack.cards.count else {
            sendSystemMessage("openCard", toCardAt: newIndex); return
        }
        isSendingSystemMessage = true
        let closeHost = makeHost(cardIndex: .constant(oldIndex))
        let closePath = scriptPath(cardAt: oldIndex, part: nil)
        let openHost = makeHost()
        let openPath = scriptPath(cardAt: newIndex, part: nil)
        Task { @MainActor in
            defer { isSendingSystemMessage = false; flushPendingCardOpen() }
            do {
                // A closeCard error shouldn't block arriving at the new card.
                do { try await HyperTalk.send("closeCard", along: closePath, host: closeHost) }
                catch { scriptErrorText = error.localizedDescription }
                try await HyperTalk.send("openCard", along: openPath, host: openHost)
            } catch {
                scriptErrorText = error.localizedDescription
            }
        }
    }

    /// A card arrival whose openCard was deferred because a system message was
    /// in flight (chained auto-advance). Carries the transition it represents.
    @State private var pendingCardOpen: (from: Int, to: Int)?

    /// Sends a queued openCard once the current system message finishes, so an
    /// `on openCard / go next card` chain continues card by card.
    private func flushPendingCardOpen() {
        guard let pending = pendingCardOpen else { return }
        pendingCardOpen = nil
        sendCloseThenOpenCard(from: pending.from, to: pending.to)
    }

    /// Sends `openStack` then `openCard` to a card as one ordered task — used
    /// when a cross-stack swap lands on a card. (`sendSystemMessage` guards
    /// against overlapping system messages, so two separate calls would drop
    /// the second; this runs both inside one guarded task.)
    /// A freshly opened stack starts in the browse tool, whatever a previous
    /// stack's scripts chose.
    private func resetChosenTool() {
        DocumentScriptHost.PaintSession.shared.tool = "browse"
        // A fresh stack starts with no scripted palette windows open.
        DocumentScriptHost.PaletteRegistry.shared.reset()
    }

    private func sendOpenSequence(toCardAt index: Int) {
        resetChosenTool()
        guard !isEditing, !isSendingSystemMessage else { return }
        // Stale per-stack session state mustn't leak into the next stack; its
        // openStack re-establishes what it wants (crop, custom menus).
        cardWindowViewport = nil
        stackMenus = []
        isSendingSystemMessage = true
        let host = makeHost()
        let path = scriptPath(cardAt: index, part: nil)
        Task { @MainActor in
            defer { isSendingSystemMessage = false; flushPendingCardOpen() }
            do {
                try await HyperTalk.send("openStack", along: path, host: host)
                try await HyperTalk.send("openCard", along: path, host: host)
            } catch {
                scriptErrorText = error.localizedDescription
            }
        }
    }

    struct PendingGoStack {
        let name: String
        let card: GoDestination?
    }

    /// Crops the (fixed-size) card to the stack's card-window viewport,
    /// top-left anchored, as HyperCard crops a card larger than its window.
    /// No viewport = pass through untouched (the normal scale-to-fit path).
    struct CardWindowCrop: ViewModifier {
        let viewport: CGSize?
        let cardSize: CGSize

        func body(content: Content) -> some View {
            if let viewport {
                content
                    .frame(width: cardSize.width, height: cardSize.height)
                    .frame(width: min(viewport.width, cardSize.width),
                           height: min(viewport.height, cardSize.height),
                           alignment: .topLeading)
                    .clipped()
            } else {
                content
            }
        }
    }

    /// Runs a line typed into the message box in the current card's
    /// context; bare expressions display their value as output.
    private func runMessageBoxCommand(_ line: String) {
        let host = makeHost()
        let path = scriptPath(cardAt: cardIndex, part: nil)
        Task { @MainActor in
            do {
                if let value = try await HyperTalk.execute(messageLine: line, along: path, host: host) {
                    messageBoxText = value
                }
            } catch {
                scriptErrorText = error.localizedDescription
            }
        }
    }

    /// The HyperCard message path for an object on the given card:
    /// part → card → background → stack.
    private func scriptPath(cardAt index: Int, part: Part?) -> [ScriptLayer] {
        guard document.stack.cards.indices.contains(index) else { return [] }
        let card = document.stack.cards[index]
        var layers: [ScriptLayer] = []
        if let part {
            let kind = part.kind.word
            // A part on this card is a card part; otherwise it belongs to the
            // shared background. Addressed by permanent id so `me` / `the
            // target` survive renames.
            let domain: HyperTalkObject.PartDomain = card.parts.contains(where: { $0.id == part.id }) ? .card : .background
            let object = HyperTalkObject.part(kind: kind, domain: domain, reference: .id(String(part.scriptID)), onCard: nil)
            layers.append(ScriptLayer(name: "\(kind) \"\(part.name)\" script", source: part.script, object: object))
        }
        layers.append(ScriptLayer(name: "card \"\(card.name)\" script", source: card.script, object: .thisCard))
        if let background = document.stack.backgrounds.first(where: { $0.id == card.backgroundID }) {
            layers.append(ScriptLayer(name: "background script", source: background.script, object: .thisBackground))
        }
        layers.append(ScriptLayer(name: "stack script", source: document.stack.script, object: .thisStack))
        return layers
    }

    /// Dispatches a mouse message (mouseDown/mouseUp) from a press on a
    /// part, or on the card itself when `part` is nil. All pointing devices
    /// — finger, Pencil, trackpad, mouse — arrive through the same gestures.
    /// A link tapped in a rich field: card links navigate here (like `go`);
    /// web links hand off to the system browser. The app never fetches.
    private func followLink(_ link: FieldLink) {
        switch link {
        case .card(let reference):
            let cards = document.stack.cards
            let target: Int?
            if let number = Int(reference), (1...cards.count).contains(number) {
                target = number - 1
            } else if let index = cards.firstIndex(where: {
                $0.name.caseInsensitiveCompare(reference) == .orderedSame
            }) {
                target = index
            } else {
                target = nil // an unknown reference is ignored (no navigation)
            }
            if let target, target != cardIndex {
                // Following a card link pushes the source card, so a script
                // can `pop card` back to it (as an automatic `push card`).
                CardBackStack.shared.ids.append(String(cards[cardIndex].scriptID))
                currentCardIndex = target
            }
        case .external(let url):
            openURL(url)
        }
    }

    private func sendMouseMessage(_ message: String, to part: Part?) {
        // HyperCard button families: the clicked member hilited in CardView;
        // its same-layer family siblings clear here, before the mouseUp
        // handler runs (so scripts read the settled state).
        if message == "mouseUp", let part { clearFamilySiblings(of: part) }
        // A click on a locked field records `the clickLine`/`the clickText`
        // before its mouseUp runs. The gesture computed the raw hit; the
        // layer qualifier (card vs bkgnd) is decided here.
        if message == "mouseUp", let part, case .field(let field) = part.kind,
           let pending = ClickRecord.shared.takePending() {
            let layer = stack.cards[cardIndex].parts.contains(where: { $0.id == part.id }) ? "card" : "bkgnd"
            ClickRecord.shared.line = "line \(pending.line) of \(layer) field id \(part.scriptID)"
            ClickRecord.shared.text = pending.text
            if let chunk = pending.chunk, !chunk.isEmpty {
                ClickRecord.shared.chunk =
                    "char \(chunk.lowerBound + 1) to \(chunk.upperBound) of \(layer) field id \(part.scriptID)"
            } else {
                ClickRecord.shared.chunk = ""
            }
            // Auto Select (the list-field idiom): the click selects its whole
            // line — visible highlight plus the selected* readers — before the
            // field's mouseUp handler runs (which typically reads
            // `the selectedText` / `the selectedLine`).
            if field.autoSelect, let range = Self.rangeOfLine(pending.line, in: field.text) {
                let session = SelectionSession.shared
                session.partID = part.id
                session.scriptID = part.scriptID
                session.layer = layer
                session.range = range
                scriptSelection = FindHighlight(partID: part.id, range: range)
            }
        }
        // HyperCard runs one handler at a time. If a script is already running,
        // this click is absorbed: its clickLine/clickLoc are recorded above and
        // `the mouseClick` is armed, so a `repeat until the mouseClick` loop in
        // the running handler (deleteHCLine's list idiom) sees it — but no
        // competing handler is dispatched.
        guard runningScriptCount == 0 else {
            if message == "mouseUp" { ClickRecord.shared.clickPending = true }
            return
        }
        // Launching a fresh handler: the launching click must not satisfy its
        // own mouseClick loop, so leave the flag clear.
        ClickRecord.shared.clickPending = false
        let host = makeHost()
        let path = scriptPath(cardAt: cardIndex, part: part)
        runningScriptCount += 1
        Task { @MainActor in
            defer { runningScriptCount -= 1 }
            do {
                try await HyperTalk.send(message, along: path, host: host)
            } catch {
                scriptErrorText = error.localizedDescription
            }
        }
    }

    /// The character range of 1-based line `number` in `text` (newline
    /// excluded), for Auto Select's line selection. Nil when out of range.
    private static func rangeOfLine(_ number: Int, in text: String) -> Range<Int>? {
        guard number >= 1 else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard number <= lines.count else { return nil }
        var start = 0
        for index in 0..<(number - 1) { start += lines[index].count + 1 }
        return start..<(start + lines[number - 1].count)
    }

    /// System messages go to the card and up. Suppressed while editing,
    /// and while another system message is running (so an openCard that
    /// navigates can't cascade within one dispatch).
    private func sendSystemMessage(_ message: String, toCardAt index: Int) {
        guard !isEditing, !isSendingSystemMessage else { return }
        isSendingSystemMessage = true
        let host = makeHost()
        let path = scriptPath(cardAt: index, part: nil)
        Task { @MainActor in
            defer { isSendingSystemMessage = false; flushPendingCardOpen() }
            do {
                try await HyperTalk.send(message, along: path, host: host)
            } catch {
                scriptErrorText = error.localizedDescription
            }
        }
    }

    // MARK: - Editing

    /// The selected part may live on the current card or its background.
    /// The lone selected part's id, or nil when zero or several are selected —
    /// drives the single-part inspector, resize, link, and arrange.
    private var singleSelectedPartID: UUID? {
        selectedPartIDs.count == 1 ? selectedPartIDs.first : nil
    }

    /// Which layer the selected part lives on, for the inspector's "Kind:
    /// Card Button" / "Kind: Background Field" line.
    private func partLayerName(for id: UUID) -> String? {
        let current = document.stack
        if current.cards[cardIndex].parts.contains(where: { $0.id == id }) { return "Card" }
        let card = current.cards[cardIndex]
        if let backgroundIndex = current.backgrounds.firstIndex(where: { $0.id == card.backgroundID }),
           current.backgrounds[backgroundIndex].parts.contains(where: { $0.id == id }) {
            return "Background"
        }
        return nil
    }

    private func partBinding(for id: UUID) -> Binding<Part>? {
        let index = cardIndex
        let current = document.stack
        if let partIndex = current.cards[index].parts.firstIndex(where: { $0.id == id }) {
            return stack.cards[index].parts[partIndex]
        }
        let card = current.cards[index]
        if let backgroundIndex = current.backgrounds.firstIndex(where: { $0.id == card.backgroundID }),
           let partIndex = current.backgrounds[backgroundIndex].parts.firstIndex(where: { $0.id == id }) {
            return stack.backgrounds[backgroundIndex].parts[partIndex]
        }
        return nil
    }

    /// Nudges the selected part by (dx, dy) card points, clamping its origin to
    /// the card the way loading does (a sliver always stays reachable). Routes
    /// through the stack binding, so a run of arrow presses coalesces into one
    /// undo step like a drag.
    private func moveSelectedPart(dx: CGFloat, dy: CGFloat) {
        guard !selectedPartIDs.isEmpty else { return }
        let size = document.stack.cardSize
        for id in selectedPartIDs {
            guard let binding = partBinding(for: id) else { continue }
            var frame = binding.wrappedValue.frame
            frame.x = min(max(frame.x + dx, 0), max(0, size.width - 16))
            frame.y = min(max(frame.y + dy, 0), max(0, size.height - 16))
            binding.wrappedValue.frame = frame
        }
    }

    private func addPart(_ kind: PartKind) {
        let size: (width: Double, height: Double) = switch kind {
        case .button: (160, 56)
        case .field, .label: (320, 56)
        case .image: (320, 320) // images arrive via addImagePart instead
        }
        let cardSize = document.stack.cardSize
        let script = if case .button = kind {
            "on mouseUp\n  \nend mouseUp"
        } else {
            ""
        }
        let part = Part(
            id: UUID(),
            name: defaultName(for: kind),
            frame: PartFrame(
                x: (cardSize.width - size.width) / 2,
                y: (cardSize.height - size.height) / 2,
                width: size.width,
                height: size.height
            ),
            script: script,
            kind: kind
        )
        appendNewPart(part)
    }

    /// Appends a newly-created part to the card or the current card's shared
    /// background, per the New Parts layer selector, and selects it.
    private func appendNewPart(_ part: Part) {
        var part = part
        var updated = document.stack
        part.scriptID = updated.claimScriptID()
        appendPartToActiveLayer(part, in: &updated)
        stack.wrappedValue = updated
        selectedPartIDs = [part.id]
    }

    /// Appends an already-prepared part to the layer the inspector targets —
    /// the current card's shared background when the Background tab is active,
    /// otherwise the current card. Shared by New Part and Paste so both follow
    /// the selected layer.
    private func appendPartToActiveLayer(_ part: Part, in updated: inout Stack) {
        let card = updated.cards[cardIndex]
        if objectScope == .background,
           let backgroundIndex = updated.backgrounds.firstIndex(where: { $0.id == card.backgroundID }) {
            updated.backgrounds[backgroundIndex].parts.append(part)
        } else {
            updated.cards[cardIndex].parts.append(part)
        }
    }

    /// The layer new parts land on, per the inspector's tab (Stack acts as
    /// Card, since parts can't live on the stack).
    private var newPartLayerName: String {
        objectScope == .background ? "Background" : "Card"
    }

    #if os(iOS)
    /// Which paint layer is being edited: the current card's own, or the
    /// shared background's (visible on every card using that background).
    enum PaintTarget {
        case card
        case background
    }

    private var currentBackgroundIndex: Int? {
        let backgroundID = document.stack.cards[cardIndex].backgroundID
        return document.stack.backgrounds.firstIndex { $0.id == backgroundID }
    }

    /// Opens paint mode on the chosen layer, loading its existing strokes
    /// (paintings stay editable — the stroke data lives in the stack).
    private func openPaintEditor(target: PaintTarget) {
        paintTarget = target
        let drawingAsset: String? = switch target {
        case .card:
            document.stack.cards[cardIndex].paintDrawingAsset
        case .background:
            currentBackgroundIndex.flatMap { document.stack.backgrounds[$0].paintDrawingAsset }
        }
        if let drawingAsset,
           let data = document.assets[drawingAsset],
           let existing = try? PKDrawing(data: data) {
            paintDrawingToEdit = existing
        } else {
            paintDrawingToEdit = PKDrawing()
        }
        isPaintingPresented = true
    }

    /// Stores the finished drawing twice — the editable PencilKit data and
    /// a rendered PNG for display — and points the target layer at both.
    /// An empty drawing clears the layer.
    private func savePaint(_ drawing: PKDrawing) {
        var updated = document.stack
        var drawingName: String?
        var imageName: String?
        if !drawing.strokes.isEmpty {
            let cardSize = document.stack.cardSize
            let bounds = CGRect(x: 0, y: 0, width: cardSize.width, height: cardSize.height)
            guard let png = drawing.image(from: bounds, scale: 2).pngDataCrossPlatform else { return }
            drawingName = document.storeAsset(drawing.dataRepresentation(), preferredExtension: "drawing")
            imageName = document.storeAsset(png)
        }
        switch paintTarget {
        case .card:
            updated.cards[cardIndex].paintDrawingAsset = drawingName
            updated.cards[cardIndex].paintImageAsset = imageName
        case .background:
            guard let backgroundIndex = currentBackgroundIndex else { return }
            updated.backgrounds[backgroundIndex].paintDrawingAsset = drawingName
            updated.backgrounds[backgroundIndex].paintImageAsset = imageName
        }
        stack.wrappedValue = updated
    }

    /// Builds the static-website .zip and hands it to the system share sheet.
    /// Presented directly through UIKit (not a SwiftUI `.sheet`) so it doesn't
    /// stack another presentation onto the Home scene, which collides with the
    /// Stacks toolbar menu's popover on iPad.
    private func exportWebsite(actualSize: Bool) {
        do {
            let data = try WebsiteExporter.zipData(stack: document.stack, assets: document.assets, actualSize: actualSize)
            let name = WebsiteExporter.folderName(for: document.stack)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".zip")
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url)
            presentShareSheet(for: url)
        } catch {
            // Best-effort: a failed export simply presents nothing.
        }
    }

    /// Presents a `UIActivityViewController` for `url` from the topmost view
    /// controller, anchoring the popover at screen center on iPad.
    private func presentShareSheet(for url: URL) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              var top = window.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(activity, animated: true)
    }
    #endif

    /// Imports picked image data as an asset and places an image part
    /// sized to fit, centered on the current card.
    private func addImagePart(data: Data, imageSize: CGSize) {
        let assetName = document.storeAsset(data)
        let cardSize = document.stack.cardSize
        // Bring the image in at its natural pixel size, only shrinking it to
        // fit the card when it's larger — never scaling a small image up.
        let scale = min(1, min(cardSize.width / imageSize.width, cardSize.height / imageSize.height))
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let part = Part(
            id: UUID(),
            name: defaultName(for: .image(ImagePart(assetName: assetName))),
            frame: PartFrame(
                x: (cardSize.width - width) / 2,
                y: (cardSize.height - height) / 2,
                width: width,
                height: height
            ),
            script: "",
            kind: .image(ImagePart(assetName: assetName))
        )
        appendNewPart(part)
    }

    private func defaultName(for kind: PartKind) -> String {
        let base = switch kind {
        case .button: "Button"
        case .field: "Field"
        case .label: "Label"
        case .image: "Image"
        }
        let existing = document.stack.cards[cardIndex].parts.count
        return "\(base) \(existing + 1)"
    }

    /// Z-order changes for the selected part, within its own layer (later
    /// in the array = nearer the front). Part order is also part number, so
    /// this changes ordinals too — as in HyperCard.
    enum ArrangeAction { case front, closer, farther, back }

    private func arrangeSelectedPart(_ action: ArrangeAction) {
        guard let id = singleSelectedPartID else { return }
        var updated = document.stack
        let index = cardIndex
        if reorder(&updated.cards[index].parts, id: id, action: action) {
            stack.wrappedValue = updated
            return
        }
        let card = updated.cards[index]
        if let backgroundIndex = updated.backgrounds.firstIndex(where: { $0.id == card.backgroundID }),
           reorder(&updated.backgrounds[backgroundIndex].parts, id: id, action: action) {
            stack.wrappedValue = updated
        }
    }

    private func reorder(_ parts: inout [Part], id: UUID, action: ArrangeAction) -> Bool {
        guard let i = parts.firstIndex(where: { $0.id == id }) else { return false }
        switch action {
        case .front:
            parts.append(parts.remove(at: i))
        case .back:
            parts.insert(parts.remove(at: i), at: 0)
        case .closer:
            if i < parts.count - 1 { parts.swapAt(i, i + 1) }
        case .farther:
            if i > 0 { parts.swapAt(i, i - 1) }
        }
        return true
    }

    private func deletePart(id: UUID) {
        var updated = document.stack
        let index = cardIndex
        updated.cards[index].parts.removeAll { $0.id == id }
        let card = updated.cards[index]
        if let backgroundIndex = updated.backgrounds.firstIndex(where: { $0.id == card.backgroundID }) {
            updated.backgrounds[backgroundIndex].parts.removeAll { $0.id == id }
        }
        stack.wrappedValue = updated
        selectedPartIDs.remove(id)
    }

    /// Deletes every selected part (one undo step).
    private func deleteSelectedParts() {
        guard !selectedPartIDs.isEmpty else { return }
        var updated = document.stack
        let index = cardIndex
        updated.cards[index].parts.removeAll { selectedPartIDs.contains($0.id) }
        let card = updated.cards[index]
        if let backgroundIndex = updated.backgrounds.firstIndex(where: { $0.id == card.backgroundID }) {
            updated.backgrounds[backgroundIndex].parts.removeAll { selectedPartIDs.contains($0.id) }
        }
        stack.wrappedValue = updated
        selectedPartIDs = []
    }

    // MARK: - Cut / Copy / Paste Part

    /// The selected parts, wherever they live (card or background layer), in
    /// each layer's z-order (card parts after background parts).
    private func selectedParts() -> [Part] {
        guard !selectedPartIDs.isEmpty else { return [] }
        let card = document.stack.cards[cardIndex]
        let background = document.stack.backgrounds.first { $0.id == card.backgroundID }
        let bgParts = (background?.parts ?? []).filter { selectedPartIDs.contains($0.id) }
        let cardParts = card.parts.filter { selectedPartIDs.contains($0.id) }
        return bgParts + cardParts
    }

    private func copySelectedParts() {
        let parts = selectedParts()
        guard !parts.isEmpty else { return }
        var assets: [String: Data] = [:]
        for part in parts {
            if case .image(let image) = part.kind, let data = document.assets[image.assetName] {
                assets[image.assetName] = data
            }
        }
        partClipboard.payload = PartClipboard.Payload(parts: parts, assets: assets)
    }

    private func cutSelectedParts() {
        guard !selectedPartIDs.isEmpty else { return }
        copySelectedParts()
        deleteSelectedParts()
    }

    /// Pastes the clipboard's parts onto the current card, preserving their
    /// relative layout. If any source part is still on this card the group is
    /// nudged down-right so it doesn't hide the originals; on a different card
    /// the positions are kept (as in HyperCard). Fresh ids avoid collisions.
    private func pastePart() {
        guard let payload = partClipboard.payload, !payload.parts.isEmpty else { return }
        for (name, data) in payload.assets where document.assets[name] == nil {
            document.assets[name] = data
        }
        // Offset the whole group when any source part is still on this card.
        let offset = payload.parts.contains { partBinding(for: $0.id) != nil }
        var updated = document.stack
        var newIDs: Set<UUID> = []
        for source in payload.parts {
            var part = source
            if offset { part.frame.x += 20; part.frame.y += 20 }
            part.id = UUID()
            part.scriptID = updated.claimScriptID()
            appendPartToActiveLayer(part, in: &updated)
            newIDs.insert(part.id)
        }
        stack.wrappedValue = updated
        selectedPartIDs = newIDs
    }

    /// Duplicates the selected parts in place — fresh copies nudged down-right,
    /// without touching the clipboard (as macOS's Duplicate does).
    private func duplicateSelectedPart() {
        let parts = selectedParts()
        guard !parts.isEmpty else { return }
        var updated = document.stack
        var newIDs: Set<UUID> = []
        for source in parts {
            var copy = source
            copy.id = UUID()
            copy.scriptID = updated.claimScriptID()
            copy.frame.x += 20
            copy.frame.y += 20
            appendPartToActiveLayer(copy, in: &updated)
            newIDs.insert(copy.id)
        }
        stack.wrappedValue = updated
        selectedPartIDs = newIDs
    }

    /// Part-editing actions published to the Edit menu on macOS. The flags are
    /// only true in edit mode, so the menu falls back to text editing (and
    /// card operations) otherwise.
    private var partActions: PartActions {
        PartActions(
            cut: cutSelectedParts,
            copy: copySelectedParts,
            paste: pastePart,
            duplicate: duplicateSelectedPart,
            delete: deleteSelectedParts,
            canCopy: isEditing && !selectedPartIDs.isEmpty,
            canPaste: isEditing && partClipboard.payload != nil
        )
    }

    private func addCard() {
        let current = document.stack.cards[cardIndex]
        var card = Card(
            id: UUID(),
            name: "Card \(document.stack.cards.count + 1)",
            backgroundID: current.backgroundID,
            script: "",
            parts: []
        )
        var updated = document.stack
        card.scriptID = updated.claimScriptID()
        updated.cards.insert(card, at: cardIndex + 1)
        stack.wrappedValue = updated
        currentCardIndex = cardIndex + 1
        selectedPartIDs = []
    }

    /// New Background: a fresh background plus a card on it — HyperCard's
    /// distinction from New Card (which reuses the current background).
    private func addBackground() {
        var updated = document.stack
        var background = Background(
            id: UUID(),
            name: "Background \(updated.backgrounds.count + 1)",
            script: "",
            parts: []
        )
        background.scriptID = updated.claimScriptID()
        updated.backgrounds.append(background)
        var card = Card(
            id: UUID(),
            name: "Card \(updated.cards.count + 1)",
            backgroundID: background.id,
            script: "",
            parts: []
        )
        card.scriptID = updated.claimScriptID()
        updated.cards.insert(card, at: cardIndex + 1)
        stack.wrappedValue = updated
        currentCardIndex = cardIndex + 1
        selectedPartIDs = []
    }

    // MARK: - Cut / Copy / Paste Card

    private func copyCard() {
        let card = document.stack.cards[cardIndex]
        let background = document.stack.backgrounds.first { $0.id == card.backgroundID }
        var assets: [String: Data] = [:]
        for name in referencedAssetNames(card: card, background: background) {
            if let data = document.assets[name] { assets[name] = data }
        }
        cardClipboard.payload = CardClipboard.Payload(card: card, background: background, assets: assets)
    }

    private func cutCard() {
        copyCard()
        deleteCurrentCard()
    }

    private func pasteCard() {
        guard let payload = cardClipboard.payload else { return }

        // Bring over any assets the card/background reference but the target
        // doesn't have yet (UUID names never collide).
        for (name, data) in payload.assets where document.assets[name] == nil {
            document.assets[name] = data
        }

        var updated = document.stack
        var backgroundID = payload.card.backgroundID

        // If the source background isn't in this stack, insert a copy with
        // fresh part identities but the same UUID so the card can find it.
        if let background = payload.background,
           !updated.backgrounds.contains(where: { $0.id == background.id }) {
            var copy = background
            copy.scriptID = updated.claimScriptID()
            copy.parts = copy.parts.map { freshIdentity($0, in: &updated) }
            updated.backgrounds.append(copy)
            backgroundID = copy.id
        }

        var card = payload.card
        card.id = UUID()
        card.scriptID = updated.claimScriptID()
        card.backgroundID = backgroundID
        card.parts = card.parts.map { freshIdentity($0, in: &updated) }
        updated.cards.insert(card, at: cardIndex + 1)

        stack.wrappedValue = updated
        currentCardIndex = cardIndex + 1
        selectedPartIDs = []
    }

    /// A copy of a part with a new UUID and a freshly claimed scriptID.
    private func freshIdentity(_ part: Part, in stack: inout Stack) -> Part {
        var part = part
        part.id = UUID()
        part.scriptID = stack.claimScriptID()
        return part
    }

    private func referencedAssetNames(card: Card, background: Background?) -> Set<String> {
        var names: Set<String> = []
        func collect(_ paintDrawing: String?, _ paintImage: String?, _ parts: [Part]) {
            if let paintDrawing { names.insert(paintDrawing) }
            if let paintImage { names.insert(paintImage) }
            for part in parts {
                if case .image(let image) = part.kind { names.insert(image.assetName) }
            }
        }
        collect(card.paintDrawingAsset, card.paintImageAsset, card.parts)
        if let background {
            collect(background.paintDrawingAsset, background.paintImageAsset, background.parts)
        }
        return names
    }

    /// Whether the current card may be deleted: more than one card exists,
    /// the card isn't protected, and deleting it wouldn't remove a
    /// protected background (its last card).
    private var canDeleteCurrentCard: Bool {
        guard document.stack.cards.count > 1 else { return false }
        guard !document.stack.cards[cardIndex].cantDelete else { return false }
        let backgroundID = document.stack.cards[cardIndex].backgroundID
        let othersShareBackground = document.stack.cards.enumerated()
            .contains { $0.offset != cardIndex && $0.element.backgroundID == backgroundID }
        if !othersShareBackground,
           let background = document.stack.backgrounds.first(where: { $0.id == backgroundID }),
           background.cantDelete {
            return false
        }
        return true
    }

    private func deleteCurrentCard() {
        guard canDeleteCurrentCard else { return }
        stack.wrappedValue.cards.remove(at: cardIndex)
        currentCardIndex = min(cardIndex, document.stack.cards.count - 1)
        selectedPartIDs = []
    }

    // MARK: - Navigation

    /// The card prev/next controls sit in the bottom bar on iOS; macOS has
    /// no bottom bar, so they join the main toolbar.
    private var cardNavigationPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .bottomBar
        #else
        .automatic
        #endif
    }

    /// Clamped so a shorter reopened stack can't strand the index.
    private var cardIndex: Int {
        min(currentCardIndex, document.stack.cards.count - 1)
    }

    /// Resolves a `go card N of stack "X"` destination to a card index in this
    /// (the just-opened) stack, for the cases that name an initial card. Other
    /// destinations (next/previous/home/back/another stack) yield nil.
    private func cardIndexFor(_ destination: GoDestination) -> Int? {
        let cards = document.stack.cards
        guard !cards.isEmpty else { return nil }
        switch destination {
        case .first: return 0
        case .last: return cards.count - 1
        case .number(let n): return (1...cards.count).contains(n) ? n - 1 : nil
        case .named(let name): return cards.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            return cards.firstIndex { String($0.scriptID) == wanted }
        case .inBackground(let inner, let background):
            let indices: [Int]
            if let background {
                indices = cards.indices.filter {
                    backgroundName(ofCardAt: $0)?.caseInsensitiveCompare(background) == .orderedSame
                }
            } else {
                // Unnamed (`of bkgnd` / `of this bkgnd`) — the current card's.
                let wanted = cards[cardIndex].backgroundID
                indices = cards.indices.filter { cards[$0].backgroundID == wanted }
            }
            guard !indices.isEmpty else { return nil }
            switch inner {
            case .first: return indices.first
            case .last: return indices.last
            case .number(let n): return (1...indices.count).contains(n) ? indices[n - 1] : nil
            default: return indices.first
            }
        default: return nil
        }
    }

    private func backgroundName(ofCardAt index: Int) -> String? {
        let backgroundID = document.stack.cards[index].backgroundID
        return document.stack.backgrounds.first { $0.id == backgroundID }?.name
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

    private func goFirst() { currentCardIndex = 0 }
    private func goLast() { currentCardIndex = max(0, document.stack.cards.count - 1) }

    /// Opens the Home stack (seeding it on first use) as a document.
    /// macOS-only: SwiftUI's openDocument action isn't available on iOS,
    /// where the document browser is the front door.
    private func openHome() {
        #if os(macOS)
        let url = HomeStack.ensureSeeded()
        Task { try? await openDocument(at: url) }
        #endif
    }

    /// Presents `answer file`'s open panel and returns the chosen file's path,
    /// or nil on cancel. macOS only; other platforms have no NSOpenPanel, so
    /// the script sees a cancelled dialog. The classic `type` (e.g. "STAK") is
    /// advisory — the panel accepts any file, as the import flow does, and the
    /// handler validates afterwards.
    @MainActor
    private func presentOpenPanel(prompt: String, type: String?) async -> String? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if !prompt.isEmpty { panel.message = prompt }
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url?.path : nil
        #else
        return nil
        #endif
    }

    /// Within-stack navigation actions published to the Go menu.
    private var cardNavigation: CardNavigation {
        CardNavigation(
            goFirst: goFirst, goLast: goLast,
            goPrevious: goToPreviousCard, goNext: goToNextCard
        )
    }

    /// Card-management actions published to the Edit menu on macOS (where the
    /// toolbar's Cards menu is omitted to keep the toolbar clean).
    private var cardActions: CardActions {
        CardActions(
            newCard: addCard,
            newBackground: addBackground,
            cutCard: cutCard,
            copyCard: copyCard,
            pasteCard: pasteCard,
            deleteCard: deleteCurrentCard,
            canDeleteCard: canDeleteCurrentCard,
            canPasteCard: cardClipboard.payload != nil
        )
    }
}

/// A pending script dialog: `answer` shows a row of buttons, `ask` shows a
/// text field with OK/Cancel. `complete` resumes the suspended interpreter
/// — with the button label for `answer`, or the entered text (nil if
/// cancelled) for `ask`.
struct ScriptDialog: Identifiable {
    let id = UUID()
    let prompt: String
    let kind: Kind
    let complete: (String?) -> Void

    enum Kind {
        case answer(buttons: [String])
        case ask
        /// A network-consent prompt. `complete` is called with "once",
        /// "always", or "deny" (nil is treated as deny).
        case network
    }
}

/// Bridges the focused document's navigation to app-level menu commands
/// (the Go menu). Nil when no document is focused, which disables the menu.
struct CardNavigation {
    var goFirst: () -> Void
    var goLast: () -> Void
    var goPrevious: () -> Void
    var goNext: () -> Void
}

/// An in-app clipboard for whole cards. Carries the card, its background,
/// and the asset bytes both reference, so Paste works within a document
/// and across windows. Asset names are UUIDs, so re-inserting them can't
/// collide.
final class CardClipboard: ObservableObject {
    static let shared = CardClipboard()

    struct Payload {
        let card: Card
        let background: Background?
        let assets: [String: Data]
    }

    @Published var payload: Payload?
}

/// Bridges the focused document's part-editing actions (Cut/Copy/Paste/Delete
/// on the selected part) to the Edit menu on macOS. `canCopy`/`canPaste` are
/// only true in edit mode with a selection, so the standard text and card
/// actions take over otherwise.
struct PartActions {
    var cut: () -> Void
    var copy: () -> Void
    var paste: () -> Void
    var duplicate: () -> Void
    var delete: () -> Void
    var canCopy: Bool
    var canPaste: Bool
}

/// An in-app clipboard for one or more parts, carrying any asset bytes they
/// reference (image parts) so Paste works across cards and windows. Asset
/// names are UUIDs, so re-inserting them can't collide.
final class PartClipboard: ObservableObject {
    static let shared = PartClipboard()

    struct Payload {
        let parts: [Part]
        let assets: [String: Data]
    }

    @Published var payload: Payload?
}

/// Bridges the focused document's card-management actions to the Edit menu
/// (macOS). Nil when no document is focused, which disables the commands.
struct CardActions {
    var newCard: () -> Void
    var newBackground: () -> Void
    var cutCard: () -> Void
    var copyCard: () -> Void
    var pasteCard: () -> Void
    var deleteCard: () -> Void
    var canDeleteCard: Bool
    var canPasteCard: Bool
}

struct CardNavigationKey: FocusedValueKey {
    typealias Value = CardNavigation
}

struct CardActionsKey: FocusedValueKey {
    typealias Value = CardActions
}

struct PartActionsKey: FocusedValueKey {
    typealias Value = PartActions
}

/// Carries a binding to the focused stack's full-screen flag, so the View
/// menu's toggle can read and flip it through @FocusedBinding.
struct StackFullScreenKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

/// Carries a binding to the focused stack's HyperTalk Guide sheet flag, so the
/// Help menu can open it (macOS, where it's not in the toolbar).
struct GuidePresentedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

/// Carries a binding to the focused stack's message-box visibility, so the Go
/// menu's Message Box item (⌘M) can toggle it.
struct MessageBoxVisibleKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

/// Exports the focused stack as a static website into a chosen directory.
/// Carried as a focused value so the File menu can drive it for whichever
/// stack window is frontmost.
struct WebsiteExport {
    /// Writes the site into the given directory (at 1:1 if `actualSize`);
    /// returns the created folder.
    let export: (URL, Bool) throws -> URL
}

struct WebsiteExportKey: FocusedValueKey {
    typealias Value = WebsiteExport
}

/// The focused stack's bitmap round trip — export the card/background paint
/// images as named PNGs, and replace them from an (externally upscaled)
/// folder of the same names. Carried as a focused value so the File menu can
/// drive it for whichever stack window is frontmost.
struct StackBitmaps {
    /// Writes the bitmaps into the given directory; returns the created folder.
    let export: (URL) throws -> URL
    /// Replaces bitmaps from files in the given directory; returns what matched.
    let replace: (URL) throws -> BitmapExporter.Replacement
}

struct StackBitmapsKey: FocusedValueKey {
    typealias Value = StackBitmaps
}


extension FocusedValues {
    var cardNavigation: CardNavigation? {
        get { self[CardNavigationKey.self] }
        set { self[CardNavigationKey.self] = newValue }
    }

    var cardActions: CardActions? {
        get { self[CardActionsKey.self] }
        set { self[CardActionsKey.self] = newValue }
    }

    var partActions: PartActions? {
        get { self[PartActionsKey.self] }
        set { self[PartActionsKey.self] = newValue }
    }

    var stackFullScreen: Binding<Bool>? {
        get { self[StackFullScreenKey.self] }
        set { self[StackFullScreenKey.self] = newValue }
    }

    var guidePresented: Binding<Bool>? {
        get { self[GuidePresentedKey.self] }
        set { self[GuidePresentedKey.self] = newValue }
    }

    var messageBoxVisible: Binding<Bool>? {
        get { self[MessageBoxVisibleKey.self] }
        set { self[MessageBoxVisibleKey.self] = newValue }
    }

    var websiteExport: WebsiteExport? {
        get { self[WebsiteExportKey.self] }
        set { self[WebsiteExportKey.self] = newValue }
    }

    var stackBitmaps: StackBitmaps? {
        get { self[StackBitmapsKey.self] }
        set { self[StackBitmapsKey.self] = newValue }
    }
}

#Preview {
    ContentView(document: StackDocument())
}


