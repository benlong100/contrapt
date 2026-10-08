# Contrapt → Complete HyperCard Port: Gap Roadmap

Status inventory (2026-10-07), from the code's own no-op/absent-object records,
the backlog, and the oracle work (`Scripts/ORACLE.md`). Statuses:
**done** (oracle/test-verified where possible) · **partial** · **no-op**
(accepted & ignored, invisible to scripts) · **missing** (errors or absent).

## Language core — DONE
Handlers/functions/messages & path (+Home library, `start using`), control
flow, chunks (read/write/delete, oracle-verified), containers, globals/`it`,
operators & precedence (oracle-verified), numberFormat semantics, 1904-epoch
dates & convert, sort (containers + cards), find (word modes), select,
mark/unmark, lock/unlock screen, visual effects, play (incl. bare notes),
ask/answer (+file), click/doMenu basics, enable/disable, card-window crop.

## Priority 1 — real scripts break or silently misbehave without these
1. **`the scroll of field`** — DONE 2026-10-07 (284bab0): FieldPart.scroll
   persisted; host get/set (clamp ≥ 0); locked scrolling fields follow the
   script and write user scrolls back on gesture end. Follow-ups live in
   item 11 (web parity) and item 10b (import HyperCard's persisted scroll —
   small; most stacks reset it in openCard).
2. **File I/O** — DONE 2026-10-07 (7d9be5b): all four verbs with HC-faithful
   semantics (read→it + result "eof"; write at mark/eof/N; failures via the
   result). Classic colon paths map to Application Support/HyperTalk Files in
   the sandbox. Follow-up: optionally resolve reads from user-granted folders
   so stacks can read data files shipped beside them.
3. **Custom menus** — DONE 2026-10-07 (e929cbf): full verb set (create/
   delete/put-into/enable/disable/reset), menu + menuItem as property
   objects (name/enabled/checkMark/menuMessage, exists, counts, text),
   doMenu menuMessage routing, in-window strip above the card. Verified
   against Adventures of Sean 2's real setUpMenus (File[9] Sean[2]).
   Follow-ups: web-player strip (item 11); standard File/Edit/Go default
   menus if a stack ever deletes-from rather than creates.
4. **Script error line numbers** — VERIFIED CORRECT 2026-10-07: tokenizer
   counts every continuation/comment/string form exactly (LineNumberTests),
   runtime errors report the editor line, and import preserves raw line
   counts (landmark distances match the STAK bytes). The historical drift
   is unreproducible — if it resurfaces, capture the object + both line
   numbers and reopen.
4b. **XCMD/XFCN native shims** — the #1 beta-tester request. Full support
   (executing 68K code resources) is explicitly OUT OF SCOPE: it means
   emulating the 68K ISA plus the Toolbox ABI the XCMDs call back into.
   Instead: a shim registry — calls to a recorded external name route through
   the host (`callExternal(name, params)`); registered names run native Swift,
   unregistered keep today's no-op. Pick the list with data, not folklore:
   (a) scan the corpus stacks' resource forks for XCMD/XFCN names, rank by
   frequency; (b) have RuntimeAudit log externals hit at runtime. Expected
   first shims: pop-up menu (Pop/HPopUpMenu — returns the chosen item),
   Flash, FileName/FileExists/NewFileName (panels), SpeakText (AVSpeech),
   sound players (alias to our engine), maybe AddColor (visual, Color Tools).
   Each shim is small; the registry + ranking scan is the real deliverable.
   STATUS 2026-10-07 (ebe60cb): registry live (host callExternal hook at both
   dispatch sites); corpus scan ranked FileName×11, PopMenu×9, NewFileName×9,
   HyPict×9, FontExists×5, long tail. Shipped shims: PopMenu/PopUpMenu,
   FileName, NewFileName, FontExists. Next candidates: HyPict (with P2
   picture work), Flash, ShowList, SysEnv — add as beta stacks surface them.
5. **Per-chunk textStyle/textFont/textSize writes** — DONE 2026-10-07: real
   statement in both hosts with a shared run split/merge writer (set replaces
   the span's styles; plain clears; runs re-merge). `group` settable from
   script. Web-player RENDERING of runs remains in item 11.
6. **Runtime icon re-resolution** — DONE 2026-10-07: Stack.icons (id→asset)
   persisted at import (stack-fork icons pre-rendered; app icons on use);
   set the icon swaps the drawn glyph, unknown ids show the missing fallback.
   Needs re-import.

## Priority 2 — fidelity & authoring depth
7. Background fields as true shared parts — DONE 2026-10-07: all bg fields
   live once on Background.parts (sharedText flag imported); per-card text +
   style runs in Card.backgroundFieldContent (UUID-keyed overlay), exactly
   HyperCard's storage model. Host + engine text/chunk/property/find paths
   route through the overlay; property writes propagate (same part); counts
   are true. CardView binds bg fields through a per-card proxy. Old documents
   with per-card copies still resolve via the lookup fallback; re-import for
   the new model. Verified against The Hacker Crackdown (page field: shared
   part, differing per-card text, width write visible from every card).
8. Scripted painting — DONE 2026-10-07: `drag from…to…` is a real statement;
   paint tools draw on the current card's paint PNG via PaintRasterizer
   (pixel-level RGBA, crisp 1-bit look): line/pencil/brush/eraser strokes,
   rect/roundRect/oval (filled/hollow/centered), bucket flood fill via
   `click at`. Paint globals host-backed & session-wide (lineSize, pattern —
   1=white else black, filled, centered, brush, multiple), `reset paint`.
   Limits (noted): draws to the CARD layer only (editBkgnd ignored), spray/
   lasso/select/text tools don't draw, patterns beyond white/black
   approximate to black, PencilKit drawing asset not updated (re-editing
   paint by hand rebuilds the PNG from the drawing — scripted strokes on a
   hand-drawn layer would drop). Pixel-verified end-to-end test.
9. show/hide card+bg pictures — DONE 2026-10-07 (60c38e1): Card/Background
   .showPicture modeled+persisted, parser/host/CardView wired; Sean's title
   curtain lifts. Engine-host storage with the web batch (item 11).
10. Icon import breadth — DONE 2026-10-07: resolution follows HyperCard's
    resource path (stack fork → sibling "Home" stack → HyperCard app), each
    trying ICON, then cicn (full color decode: 1/2/4/8-bit indexed + mask),
    then ICN# (icon+mask). Pinned: Oblique Strategies' ICN# imports;
    synthetic cicn decodes red/white. Follow-up: nothing known — revisit if a
    stack ships SICN/ics# small icons.
11. Web-player parity batch — DONE 2026-10-07: enabled graying (+ clicks
    blocked), missing-icon placeholder (resource missing or asset 404),
    scrolling fields (overflow + stored scroll + live `set the scroll`),
    per-chunk style-run rendering (spans, locked fields), `show/hide picture`
    (real engine state + paint toggling), scripted menu strip (create menu →
    dropdown bar; doMenu dispatch), card-window viewport crop. Engine
    CardState carries enabled/scroll/showPicture/menus/viewport; wasm
    rebuilt (18 MB; stale .build had broken the build — rm -rf WasmPlayer/
    .build fixes toolchain/SDK module errors).
12. Printing — DONE 2026-10-07 (real PDF printing): `print [this] card`,
    `print all/marked/<n> cards`, `print [card|bkgnd] field <ref>`, and
    `open printing [with dialog]` … `close printing` batching across
    dispatches. Cards render offscreen (ImageRenderer over the real CardView,
    2x) into a one-page-per-card PDF at card size; field text paginates via
    CoreText (US Letter, 1" margins). The dialog is PDFKit's print operation
    (macOS) / UIPrintInteractionController (iOS), reached through an
    onPresentPrint closure — tests capture the PDF and assert page counts.
    `print <doc> with <app>` stays an accepted no-op. NOT YET LIVE-TESTED by
    Ben — print dialog behavior unverified on real hardware/printers.
13. `type`/`drag` input synthesis — DONE 2026-10-07: `type <expr>` inserts
    at the script selection (the `select after text of field` + `type` data-
    entry idiom; replaces a selected range, caret lands after; `with
    commandKey` accepted as a shortcut, unmodeled). `drag` with the button/
    field tool MOVES the part under the start point to the end point (the
    scripted-authoring idiom); paint tools draw (item 8); browse-tool drag
    stays a no-op (no OS-level synthesis). App + web hosts both. Note: shared
    tool/selection singletons mean tool-using tests run in serialized suites.

## Priority 3 — long tail / environment
14. Palettes & external windows (`palette`, tool/pattern windows, `the
    windows`), `answer file` on iOS, AppleEvents beyond no-op, XCMD shims for
    common ones (flash, speak?), debugger/`trace`, `dial`, serial. Deliberate
    divergences stay (documented in ORACLE.md): permissive comparisons,
    container-sort superset, HC 2.3 quirks.

## Method
Work top-down; for each feature: implement → unit tests → add oracle corpus
lines where the guest can exercise it (file I/O and menus partially can) →
real-stack smoke test → commit. The oracle keeps semantics honest; this list
keeps coverage honest.
