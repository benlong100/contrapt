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
    windows`). Small environment verbs are DONE (2026-10-08): `dial`
    (no-op, no telephony), AppleEvents (put/send to program, request, reply,
    answer program — all no-op, no app reachable), and debugger/`trace`
    (`trace`/`debug`/`checkpoint` fall through to no-op message sends,
    `set traceDelay` accepted) — none of these are gaps; a sandboxed
    single-app port can't do more and no-op is the correct behavior.
    REMAINING here: `answer file` on iOS (app-only, needs fileImporter
    mid-continuation), serial (no device — already no-ops), and the bigger
    app-side media features below. Deliberate divergences stay (documented in
    ORACLE.md): permissive comparisons, container-sort superset, HC 2.3 quirks.
    XCMD shims — IN PROGRESS: shipped PopMenu/HPopUpMenu, FileName,
    NewFileName, FontExists (earlier), and 2026-10-08 Flash/Flasher/FlashRect
    (screen-invert overlay, host onFlash closure) + SpeakText/Speak (AVSpeech).
    Shimmed names are always treated as externals (builtinExternals) so they
    work even when the stack omits the XCMD resource.
    PICT display via Picture/HyPict XCMD — DO NOT BUILD (evidence, 2026-10-08):
    NO stack in ANY on-disk batch (3rd batch + Basilisk shared + the 116-stack
    Oct 8 batch) calls Picture or HyPict. The old "HyPict 9 / Picture 7" ranking
    counted XCMD RESOURCE presence, not call sites — misleading. The real
    picture/color features actually present (still niche): AddColor/Color Tools
    color overlays (HCcd/HCbg/ADDc — 2 Oct 8 stacks) and QuickTime movie XCMDs
    (qtMovie/playMovie — KlingonDictionary, USGS). See [[backlog]].
    QuickTime movies — RESEARCHED + DEFERRED (2026-10-09): no `.mov` files in
    the corpus; the one embedded `moov` (QuickTime Logo Movie) is a 1704-byte
    HEADER atom only (no mdat → unplayable); Service Source plays user-picked
    external movies (none shipped). Real XCMD contract: `QTMovie openMovie,
    <window>, <path>, <loc>, …` → a movie in a named window, controlled via
    window props/messages (dithering, mouseDownMsg, movieIdle). Only viable
    build: shim `QTMovie openMovie`/`playMovie` to play a user-picked .mov/.mp4
    in an AVKit window modeled like the palette windows. Full research note in
    memory: quicktime-movies.md.
    AddColor/Color Tools — PARTIAL (2026-10-09, commits 3ab02de + eb93621):
    HCcd/HCbg decode + ColorElement model + import, and a CardView color layer
    that draws `rect` fills beneath the 1-bit paint via .blendMode(.multiply).
    DEFERRED: PICT color backgrounds (NSPICTImageRep renders blank on modern
    macOS — needs a hand-written QuickDraw decoder, swift-CLI verifiable) and
    button/field tint elements and web parity. No confirmed-good color stack in
    the corpus to validate the visible result. See [[backlog]].
    `go next/previous background` — DONE (2026-10-08): the first card of the
    adjacent background (stack order, wrapping), resolved to a concrete card by
    a host `adjacentBackgroundCardNumber(forward:)` query so no new
    GoDestination case was needed. Surfaced by the Oct 8 parser sweep.
    Palettes & external windows — DONE (2026-10-08): increment 1 shipped the
    scripting layer (PaletteRegistry: `the windows`, `there is a window`,
    visible/loc/rect, show/hide/close). Increment 2 adds the visible panels:
    PLTE resources decode at import into `stack.palettes` (ResourceFork.palettes
    → parsePalette: 22-byte header, u16 count, per-button rect+iconID+command);
    `palette "name"` attaches those buttons to the registered window; ContentView
    renders each visible palette as a draggable floating panel whose buttons sit
    at their authored rects and dispatch their command (doMenu/bare message).
    Button icons resolve from the stack's ICON/cicn/ICN# resources (the PLTE
    per-button iconID) via the same search path as card buttons; a button with
    no icon falls back to a command-derived text label (`doMenu "Prev"` →
    "Prev", `paletteHandlerHome` → "Home").

## Method
Work top-down; for each feature: implement → unit tests → add oracle corpus
lines where the guest can exercise it (file I/O and menus partially can) →
real-stack smoke test → commit. The oracle keeps semantics honest; this list
keeps coverage honest.

## Corpus runtime sweep (2026-10-08) — remaining backlog
Ran RuntimeAudit over 164 stacks (openStack + first-card-of-each-background
openCard). Fixed in bulk: chunk keywords as plain variables (item/word/line/
char — ~70 hits), `select text in` (26), `with menuMsg a,b,c` comma list.
Dropped corpus runtime errors 162 → 92 (incl. ordinal-card grammar). Remaining, ranked by DISTINCT stacks:
- ~~Ordinal-card object/property expressions~~ DONE 2026-10-08: `in bkgnd`
  is now an of-synonym in parseOfBackground (`the first card in bg "X"`), and
  an ordinal/`this` card scope (`of first cd`, `of this cd`) no longer eats a
  following token as a card name — so `… of first cd is true` parses. Plus
  trailing comma in function calls (`foo(a,b,)` — empty final arg). Journal +
  Tubers fully cleared (96→92). (Bare card-object-as-value, `put the first
  card`, still unhandled — no corpus stack uses it.)
- Fixed 2026-10-08 (72→70): relative-card `of bg` scope, `find … in the
  foundField/selectedField`, `the textHeight of field` get/set, mouse function
  forms (`mouse()`/`mouseClick()`/`mouseH/V/Loc()`), paint-text globals
  (`the textHeight`/`textSize`/`textFont`/`textStyle`/`textAlign`).
- STILL OPEN (all 1 stack unless noted):
  * Custom user properties — investigated 2026-10-08: the Haiku Master
    `verse` case was a MISDIAGNOSIS — `cd fld verse of cd haiku` is a
    bareword-named FIELD with a card scope, not a user property. Fixed the
    real bug: the field-name parse suppressed bare `<word> of <object>`
    property reads so `verse` stops at the name and `of cd haiku` is the card
    scope (Haiku cleared, 70→69). NO corpus stack actually uses custom user
    properties, so that feature is deferred as unneeded (revisit only if a
    future stack genuinely sets/gets a user-defined property).
  * `put`/`select` into a BUTTON (New Features) — invalid HyperTalk that HC
    tolerates via lazy per-handler compile; a parse error kills our whole
    script. Skipped (semantically invalid).
  * Per-stack one-offs: Star Trek TNG (`found '.'`), Phone # Converter
    (incomplete expr), HyperCard 10th Anniversary (kitchen-sink: hide_all,
    unclosed paren, custom command, missing field), Car Care (missing bg —
    data). Low ROI.
  * External deps: Readymade Buttons/Fields call `wrongStack()` (a Home-stack
    function); not our bug.
  * Not bugs: openStack poll-loop timeouts (Sean, Clinton Issues, Cruel
    Fairy).
- Not bugs: [9] "timed out (poll loop?)" = openStack busy-waits (Sean,
  Clinton Issues, Cruel Fairy) — expected, the audit's wall-clock guard.
Re-run anytime: `touch /tmp/contrapt-runtime-audit`, run corpusRuntimeAudit.

## Corpus sweep CONCLUDED (2026-10-08) — 162 → 68
Final pass fixed bare `convert` (dispatches to a user `on convert` handler,
shadowing the built-in; Phone # Converter). The remaining ~68 errors are NOT
Contrapt gaps — verified each category:
- Author bugs in the original stacks: Star Trek TNG (`& episodeNum &.` stray
  ampersand; an unterminated string literal) — real HyperCard would reject
  these too.
- Invalid HyperTalk: New Features `put`/`select` into a BUTTON (HC tolerates
  only via lazy per-handler compile; semantically invalid).
- Power-Tools template stacks (Readymade Buttons/Fields): XCMD-heavy, not
  standalone-runnable, depend on Home functions (`wrongStack`, popObject…).
- Kitchen-sink demo (HyperCard 10th Anniversary): undefined handlers
  (hide_all), non-English command (primaparte), author typos, data refs.
- Data/runtime, not parse: Car Care `go` to a nonexistent background.
- NOT BUGS: openStack poll-loops (Sean, Clinton Issues, Cruel Fairy) — the
  audit's wall-clock guard firing on intentional wait loops.
Broad compatibility gaps are closed. Re-run after new imports:
`touch /tmp/contrapt-runtime-audit`, run corpusRuntimeAudit.

## Parser sweep (2026-10-09) — full corpus, 395 stacks
Ran the PARSE audit across all on-disk stacks (280 local + 115 Basilisk
shared; ~18k scripts, ~99.5% clean). FIXED (commit ccdbda8):
- `doMenu "X" [, menu] [with|without dialog]` — modifiers consumed (13×, top gap).
- `show/hide window "X" at "h,v"` — position consumed, shows at registered loc.
- `there is a background <bareword>` — variable name consumed, not left before `then`.
Local errors 75 → 58, then → 50 with the indirect-object fix (commit 20c4ee5):
- Indirect object via chunk — DONE: `the scroll of last item of fieldList`,
  a property of the field NAMED by a chunk value (Power Tools, Car Care, 10th
  Anniv). Parses to `.indirect(.chunk(…))`, resolved at run time.
- Dynamic property set — DONE (commit 103bc60): `set (TheProperty) of window
  X to …` / `set "thePercent" of window X …` — a computed property name on an
  unmodeled window; parsed and no-op'd (50 → 48).
REMAINING real gaps (harder; not yet done):
- `there is no card picture` existence (Clip Art — 1 stack).
The rest of the 48 are author bugs (unterminated quotes/parens, stray `.`).
Fast re-run: `CONTRAPT_AUDIT=1 CONTRAPT_CORPUS="<root>" swift test
--package-path HyperTalk --filter corpusParseAudit` (~5s for 280 stacks).
## Priority 4 — HyperCard, forward (new-stack authoring; 2026-10-09)
Goal: not just play old stacks but make HyperCard a living tool for building
little apps — local and for the web. North-star constraint: **write once, run
everywhere** (the shared interpreter drives both the native app and the
self-contained web export). Two guardrails hold throughout:
- **Keep HyperTalk readable** — arrays/JSON/HTTP must still read like English;
  that's the line between "HyperCard reborn" and "another scripting language."
- **Security/permissions** — once a stack can reach the network, untrusted
  stacks need a sandbox/consent story, especially in web export. Design early.

Sequencing is by dependency + leverage. Phase A is LANGUAGE work: it lives in
the shared interpreter, so it's `swift test`-verifiable (fast lane, no app
build) AND lands in app + web at once. Phase B is app-side / build-gated.

Phase A — the substrate (do first):
1. **Structured data: associative arrays + JSON.** — DONE 2026-10-09 (commits
   1a1fe75 arrays, 04c7ca0 JSON/iteration). Bracket syntax `a["k"]` /
   `data["a"]["b"]` (chosen over property-style); `the keys of` / `the number of
   elements of`; `JSONDecode`/`JSONEncode`; `repeat for each key|element`;
   `split`/`combine`. Carried as a reserved-encoding string (sentinel + JSON of
   ordered pairs) so the "everything is text" interpreter needed no retype and
   it lands in app + web; arrays render as readable JSON at visible sinks,
   variables keep the encoding (round-trip). 11 ArrayTests; suite 623; sweep
   unchanged (48). See EXTENSIONS.md.
2. **HTTP/JSON verbs** (`put url "…" into x`, async requests, JSONDecode/
   traversal). The transformative unlock — retires most XCMD use cases. Host
   hook: URLSession (app) / fetch (web). Depends on #1 being pleasant.
   - **Increment 1 — language layer: DONE 2026-10-09.** `url` container: GET
     (read, incl. inline `url "…"` in expressions like `JSONDecode(url "…")`),
     PUT (`put <data> into url "…"`), `post <data> to url "…"` (reply→`it`),
     `delete url "…"`. Errors→`the result`; array bodies auto-JSON. Host hook
     `httpRequest(method:url:body:headers:)` (default: "not available"), MockHost
     canned responses. 9 NetworkTests; suite 631; sweep unchanged (48). See
     EXTENSIONS.md.
   - **Increment 2 — language-side request/response control: DONE 2026-10-10.**
     `set the httpHeaders to <array-or-lines>`, `set the httpTimeout to
     <seconds>` (modal globals); `the httpStatus` and `the httpResponseHeaders`
     (array) read-back. Host hook widened to carry headers + timeout and return
     status + headers. 7 more NetworkTests (16 total); suite 638; sweep 48. See
     EXTENSIONS.md.
   - **Increment 2 — app transport: DONE 2026-10-10 (app build + wasm rebuild
     still Ben's to run).** DocumentScriptHost `httpRequest` via `URLSession`
     honoring headers/timeout, behind a **per-stack/per-host consent** prompt
     (Allow Once / Allow Always / Don't Allow via a new `ScriptDialog.network`;
     remembered in `NetworkConsentStore` — "always" persists in UserDefaults,
     "once"/deny for the session; the stack being authored, `isEditing`, is
     trusted and never prompts). Outgoing-network entitlement already set
     (`ENABLE_OUTGOING_NETWORK_CONNECTIONS`). Web side: `EngineInteraction.http
     Request` bridge + `WebHost` delegation + the player's `window.ContraptHttp`
     `fetch` helper (**honors CORS**, AbortController timeout); 4 NetworkWebTests
     (suite 642). **Remaining (Ben):** build the app target; bind the wasm
     entry's EngineInteraction.httpRequest → `window.ContraptHttp.request`
     (mirroring how `answer`/`ask` bind to `window.ContraptDialogs`) and rebuild
     WebEngine.zip.
3. **Persistent + shared stack data** — a stack that remembers between runs
   (file / localStorage), then optional multi-user. Small after #1–#2.

Phase B — the experience (app-side, build-gated):
4. **Reskin / theming + responsive layout + accessibility** — leans on the
   import strength; modernizes old stacks and makes new ones web-respectable
   (VoiceOver, Dynamic Type, resize a fixed 512×342 card).
5. **AI co-author** — the modern "gentle slope": describe a card, explain a
   handler, natural-language → HyperTalk, "make this resizable." Fits because
   HyperTalk is near-English.
6. **Components / reusable custom parts; finish color; audio/video/camera;
   iPad + Pencil (touch authoring).**

Extensibility (the modern XCMD) is considered SOLVED by this plan: built-in
HTTP/JSON (#2) covers most cases; a JS/WASM extension API that runs in BOTH app
and web is the true plugin path; native Swift plugins are a later app-only tier
for device features. (Embedding Python/Java was REJECTED — it forks the
write-once/run-everywhere runtime story.)
