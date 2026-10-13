# Contrapt — Extensions beyond HyperCard 2.4

This is the running log of everything Contrapt adds to, or deliberately changes
from, its **HyperCard 2.4 baseline** — so we don't lose track as we head into
the "HyperCard, forward" work (see `PORT-ROADMAP.md` → Priority 4).

Scope note: the HyperTalk **language core** is a deliberately faithful port of
2.4 (handlers, control flow, chunks, containers, operators, dates/convert, sort,
find, visual effects, etc., oracle-verified in `Scripts/ORACLE.md`). This file
lists only the **additions** and the **deliberate divergences** — not the
faithful parts.

Status tags: **shipped** · **partial** · **planned** (tracked in the roadmap).

---

## Language (HyperTalk extensions)
- **Associative arrays + JSON** — *shipped*. Structured data via `a["key"]`,
  nestable `data["a"]["b"]`, on any expression and as a `put` destination
  (auto-creates). `the keys of <array>` (return-delimited), `the number of
  elements of <array>`. String elements still support chunks (`item 2 of
  data["list"]`). **JSON bridge:** `JSONDecode(text)` → array (objects → named
  keys, arrays → "1".."n"), `JSONEncode(array[, "pretty"])` → text. **Iterate:**
  `repeat for each key K in <array>` / `… element E in <array>`. **Text↔array:**
  `split <var> [by <delim>]` / `combine <var> [by <delim>]` (delimiter defaults
  to comma). Carried in the "everything is text" model as a reserved-encoding
  string, so it works in the app and the web export; arrays render as readable
  JSON when shown in a field or the message box, while variables keep the array
  (round-trips).
- **HTTP verbs (`url` container)** — *shipped (web transport needs a wasm
  rebuild)*. The network unlock the arrays were the substrate for. A `url`
  container addresses a web resource: **GET** by reading it (`put url "https://…"
  into x`, or inline `url "…"` in any expression — e.g. `JSONDecode(url "…")`),
  **PUT** by writing it (`put <data> into url "…"`), **POST** via `post <data>
  to url "…"` (reply lands in `it`), and **DELETE** via `delete url "…"`.
  Transport/HTTP errors go to `the result` (empty on success). Arrays sent as a
  body are serialized to JSON automatically. **Request control (modal globals,
  like `itemDelimiter`):** `set the httpHeaders to <array>` (name→value) or to
  classic `Name: value` lines; `set the httpTimeout to <seconds>`. **Response
  read-back:** `the httpStatus` (the last status code) and `the
  httpResponseHeaders` (an array). Runs through a host hook (`httpRequest`,
  carrying headers + timeout, returning body/status/headers/error) so the same
  scripts work in the app and the web export. **Transport:** the app uses
  `URLSession` behind a **per-stack/per-host consent** prompt (Allow Once /
  Allow Always / Don't Allow, remembered per stack; the stack you're *editing*
  is trusted and never prompts). The web export uses the browser's `fetch`,
  **subject to the server's CORS policy** (a page can't proxy around it) and
  governed by the browser's own permission model rather than an in-page prompt;
  the `fetch` bridge is wired in the player and the engine's EngineInteraction —
  the exported runtime picks it up on the next wasm rebuild.

- **Web-page readers (`the title/text/links of url "…"`)** — *shipped*. The
  idiom layer above the raw `url` container: the web a gatherer meets is HTML,
  not JSON. `the title of url "…"` reads the page's title; `the text of url
  "…"` its readable text (scripts/styles/head chrome stripped, entities
  decoded, block elements as line breaks); `the links of url "…"` its link
  targets, one per line, resolved absolute against the fetched address (so
  `line 2 of the links of url …` chunk-composes). Each read fetches through
  the same GET as the `url` container (same consent prompt and CORS reality;
  errors → `the result`). Parsing is keyed on the `url` keyword, so `the
  title of button 1` and property-of-indirect-object idioms keep their
  meaning. The extractor (`HTMLPage`) is a small pure-Swift reader in the
  package — not a browser — shared by the app and the web export. No new
  syntax class: property-of-object, pointed at a page.

- **Scripted card creation + data→cards merge (`make a card`)** — *shipped*.
  `make a card [using background "Entry"]` appends a card at the end of the
  stack (current card's background when unspecified), without navigating;
  `it` gets the new card's number. The merge form — `make a card for each
  element of <array> [using background <ref>]` — creates one card per
  element and fills each card's fields by key name (an element's key
  "Title" lands in field "Title"; keys with no matching field are ignored,
  scalar elements make empty cards); `it` gets the count. This is the verb
  that turns gathered data into a *stack*: `JSONDecode(url …)` → `make a
  card for each element` → a browsable deck, three readable lines. Built
  from existing vocabulary (`for each element of`, `using`, backgrounds);
  `make` only becomes a command before `[a] card`, so custom `make`
  handlers still dispatch. HyperCard itself had no scripted New Card
  (menu only) — this is the forward-looking completion of `delete card`.
  **Blank-template scaffolding:** merging into a background that has NO
  fields yet creates one background field per data key (named by the key,
  stacked; a `text` key gets the tall multiline slot) and then fills them —
  so `make a card for each element of FeedItems(url "…")` works with zero
  setup. A background that already has any field is never touched: the
  author's design wins, and unmatched keys are ignored as before.
  **One-card fill (`put <array> into [this] card`):** the same fill without
  making a card — `put stories[1] into this card` / `into card 3`
  distributes the array's keys into same-named fields on that card
  (unmatched keys ignored; no navigation; a non-array errors). Only a bare
  card ref ending the line is a card target, so `put x into card field 1`
  keeps its field meaning. The dashboard idiom: one designed card, fields
  named after the feed's keys, refreshed with two readable lines.

- **Feed and table readers (`FeedItems(…)`, `CSVItems(…)`)** — *shipped*.
  Function-level (like `JSONDecode` — no new grammar), returning the same
  array shape `make a card for each element` fills fields from.
  `FeedItems(url "…")` parses RSS 2.0 and Atom into items with the keys
  `title`/`link`/`date`/`text` (CDATA unwrapped, the body read like `the
  text of url` — HTML stripped, entities decoded; Atom link prefers
  `rel="alternate"`), **plus whatever other simple tags the feed carries**
  (`author`, `category`, `guid`, `dc:creator` → `creator`, … — keyed by
  local name, first value wins). Discovery is a message-box one-liner, no
  menu needed: `the keys of FeedItems(url "…")[1]` lists what a particular
  feed provides, one per line (same recipe for `CSVItems` headers and
  `JSONDecode` shapes; a bare `items[1]` shows the whole item as JSON). `CSVItems(url "…")` parses comma-separated tables:
  the header row names the keys (blank → "column N", duplicates suffixed),
  each data row is one element; quoted fields carry commas, newlines, and
  `""` quotes. A feed is practically a background waiting for cards:
  `make a card for each element of FeedItems(url "…") using background
  "Story"` is a one-line news stack.

- **Timed send (`send <msg> [to <object>] in <time>`)** — *shipped (web
  delivery rides the next wasm rebuild)*. LiveCode's idiom, credited: the
  dispatch happens later — `send "refresh" to this card in 2 minutes` makes
  an information stack ambient (a dashboard that keeps itself fresh by
  rescheduling in its own handler). Units: seconds (the bare default),
  ticks, minutes (`wait` now accepts minutes too). The message, its
  arguments, the target, and the delay all evaluate at SCHEDULE time (the
  sender's context won't exist later); targets resolve to stable ids.
  **Lifetime rule:** pending sends survive navigation within the stack and
  are cancelled when the stack closes; a target deleted before the timer
  fires is dropped silently. App: the document view owns the timers (so
  closing the window cancels). Web: the page owns setTimeout — closing the
  tab IS the stack closing — firing into the engine's `deliverScheduled`.

- **Persistent stack data (`stackData`)** — *shipped (web transport needs a
  wasm rebuild)*. A per-stack key-value store that survives between runs,
  modeled as an associative array so it reuses all the array machinery:
  `put 500 into stackData["highScore"]`, `put stackData["highScore"] into x`,
  nesting `stackData["prefs"]["theme"]`, `the keys of stackData`, `the number of
  elements of stackData`, `repeat for each key k in stackData`, `JSONEncode
  (stackData)`. The store is private to each stack (keyed by stack identity).
  Storage is the host's: the app writes a per-stack file in Application Support;
  the web export uses `localStorage`. Leaves the stack file itself untouched —
  which is what lets it work for the immutable web export. A host without
  storage (the default) simply doesn't remember.

## Appearance
- **Built-in themes (`the theme of this stack`)** — *shipped (app pending a
  build; web live-switch pending a wasm rebuild)*. A small curated set of themes a
  stack can adopt — **Classic** (default), **Modern Light**, **Dark** —
  selectable per stack and scriptable: `set the theme of this stack to "dark"`.
  The catalog is one shared, unit-tested `ThemeSpec` (in the HyperTalk package)
  that both runtimes consume — the app maps it to SwiftUI colors/fonts, the web
  export to CSS variables. **Classic follows the system** (keeps today's look and
  OS light/dark), so it's a true no-op; Modern Light/Dark apply a fixed palette,
  corner rounding, a non-inverse button hilite, and a modern sans font. The
  `theme` property round-trips in `stack.json` and surfaces in the web engine's
  `CardState` so a runtime `set the theme` re-applies live. **App:** a
  `ResolvedTheme` SwiftUI Environment value drives the card surface, button
  chrome/hilite, field chrome, default accent, and the desktop surround; modern
  themes also force the card subtree's light/dark appearance so text stays
  legible. A **Theme picker** sits in the inspector's Presentation section.
  **Web:** the exported CSS is driven by `--surface`/`--ink`/`--accent`/
  `--border`/`--padding` variables (classic defaults = the original look), set by
  an `applyTheme()` the player calls at load (`stack.theme`) and on each update
  (`CardState.theme`). Classic touches nothing — it resolves to the exact
  pre-existing colors.
- **Accessibility / VoiceOver** — *shipped (app pending a build; web live on the
  next export)*. Parts are announced to assistive technology by one shared,
  unit-tested rule set (`Accessibility.part(...)` in the HyperTalk package):
  buttons get a spoken name (name → title → "Button", vital for icon-only
  buttons) and the button role/trait; locked fields and labels become a single
  static-text element whose content is read; editable fields keep their native
  text-field behavior with a spoken name; images get a name/alt. **App:** a
  `PartAccessibilityModifier` applies the SwiftUI traits/labels per role. **Web:**
  the player's DOM mirrors the rules — `role="button"` + `tabindex` + `aria-label`
  on buttons (with **Enter/Space keyboard activation**), `role="textbox"` +
  `aria-label` on editable fields, and `alt` on images. *Deliberately not doing
  Dynamic Type:* a card is a fixed-pixel, absolutely-positioned medium (like an
  image), so reflowing text would overflow frames — VoiceOver/semantics are the
  accessibility that fits.

## Authoring
- **AI co-author — "Explain" (read-side)** — *shipped (app; pending a build)*.
  In the script editor (inline and expanded), an **Explain** button runs the
  current script through Apple's **on-device** model (FoundationModels) and
  shows a plain-language, handler-by-handler walkthrough — the "gentle slope"
  on-ramp for learning HyperTalk. Private, offline, no API key; the result sheet
  degrades gracefully when Apple Intelligence is off/unavailable. Prompt
  construction is shared/tested (`HyperTalk.CoAuthor`); the model call sits
  behind a `CoAuthoring` protocol so an **opt-in cloud** provider can power the
  write-side (generate/revise HyperTalk) later — the on-device model is
  deliberately used only for explaining, since Apple documents it as unsuited to
  code generation. Authoring-only: nothing here ships in a stack or the web
  export.
- **AI co-author — "Write with AI" (write-side)** — *shipped (app; pending a
  build)*. In the script editor, **Write with AI** takes a plain-language
  request ("beep twice when clicked") and the **opt-in cloud** model (your own
  Claude API key, stored in the Keychain; set in Settings/⌘,) returns the
  **complete updated script** for the object. Every result is **sanitized**
  (strips stray Markdown fences) and **parse-checked with `HyperTalk.check`**
  before you can Apply — invalid code is flagged, never silently applied; Apply
  then replaces the script in place (one clear before/after). Behind the same
  `CoAuthoring` protocol as Explain; cloud because the on-device model isn't
  suited to code generation. Sends the object's script + your request to
  Anthropic only when invoked. Still authoring-only (never in a stack/web
  export). Default model: Claude Sonnet 4.6. **Auto-repair:** if the generated
  script fails the parse check, the parse error is fed back to the model for one
  corrective pass before the preview is shown — so a stray non-HyperTalk line
  (e.g. `set field "x" to …`) is usually fixed automatically. The write-side
  instructions also steer toward real idioms (`put <value> into field "Name"`;
  `set` only for properties).

## Fields & parts
- **Rich-text fields** — *shipped*. A field mode (`FieldKind.rich`) that renders
  its contents as **Markdown** — styling plus **trappable links** — in a web
  view, alongside the classic plain field. Display-oriented, local content.
  (`RichTextFieldView`, `MarkdownHTML`.)
- **Per-card `highlightColor`** — *shipped*. A scriptable accent color:
  `set the highlightColor of this card to "#FF3B30"` (a color name or
  `#RRGGBB`). Tints rich-field links and button icon/label accents.
- **Button colors (`fillColor` / `borderColor` / `textColor`)** — *shipped (app
  pending a build)*. Any button can carry a custom fill (styles with a
  background: opaque, rectangle, shadow, roundRect), edge color (styles with a
  border), and title color (tints the title and an SF-symbol icon), as a color
  name or `#RRGGBB`. Set in the inspector (each with Reset back to the themed
  default) or by script — in both runtimes:
  `set the fillColor of card button "Go" to "#FF3B30"`,
  `set the borderColor of btn 2 to "blue"` (`edgeColor` is a synonym),
  `set the textColor of button "Go" to "white"` (setting `empty` restores the
  default). Hilite stays a true inverse-video flip, custom colors or not. The
  colors round-trip in `stack.json` and render statically in the web export (a
  live web `set` needs the wasm rebuild + player state pass).
- **Field colors (`textColor` / `borderColor`)** — *shipped*. A field can
  color its whole text and its border (for the styles that draw one:
  rectangle, shadow, scrolling) — inspector pickers with Reset, or by script
  in both runtimes: `set the textColor of field "Notes" to "navy"`,
  `set the borderColor of cd fld 1 to "#333333"` (`edgeColor` synonym; `empty`
  restores the themed default). Applies across editable, locked, imported
  exact-lineheight, **and rich** fields (the rich renderer colors the Markdown
  body; links keep the card's highlightColor); outline-styled runs keep their
  classic white-on-black look. Round-trips in `stack.json`; renders statically
  in the web export. (Per-run text color would be a StyleRun extension —
  this is whole-field.)
- **Rich-field leading via `textHeight`** — *shipped*. HyperCard's per-field
  `textHeight` (line height in points, already imported and scriptable) now
  also drives a rich field's leading — CSS line-height in the renderer, a
  "Line Height" control in the rich inspector (0 = automatic). `set the
  textHeight of field "X" to 20` re-renders live.
- **SF Symbol button icons** — *shipped*. New buttons can use a built-in SF
  Symbol as their icon (the authoring library), distinct from imported 1-bit
  ICON/cicn art.
- **Image parts** — *shipped*. Native image parts (PNG/asset) in addition to the
  1-bit paint layer.

## Media & assets
- **Bitmap export / import round-trip** — *shipped*. Export each card's and
  background's paint layer as PNGs to a folder, edit in any modern image editor,
  and re-import the changed files (`BitmapExporter`). Lets current tools edit
  stack art.
- **Embedded TrueType (`sfnt`) font rendering** — *shipped*. A stack's bundled
  TrueType faces (e.g. the Klingon `Klinzhai`, the Star-Trek `Koshgarian`)
  render with their **real glyphs**, registered with CoreText at open; a family
  the OS already provides falls back to the system face (real bold/italic).
- **Classic font-name mapping** — *shipped*. Chicago/Geneva/Palatino/etc. map to
  the nearest modern system design, width-calibrated so old line breaks hold.
- **AddColor / Color Tools color layer** — *partial (PICT backgrounds now
  render)*. `HCcd`/`HCbg` color resources decode at import; `rect` fills render
  beneath the 1-bit art (multiply compositing). **PICT-backed color backgrounds
  now draw** via Contrapt's own QuickDraw decoder (`PICTBitmap`, in the HyperTalk
  package): PICT v2 **PackBitsRect** (indexed/paletted) and **DirectBitsRect**
  (direct RGB) — the forms modern macOS no longer renders through
  NSPICTImageRep. v1 / vector PICTs fall back to the system renderer. Still
  deferred: button/field **tints** (types 1/2, parsed but not drawn), and the
  web/engine color parity. (`moov` video stays separate — see `quicktime-movies`.)

## Distribution & format
- **Web export** — *shipped*. A stack exports to a **self-contained static
  website** that runs the *same* HyperTalk interpreter (compiled to wasm) — the
  foundation of "write once, run everywhere." (`WebsiteExporter`.)
- **`.contrapt` stack format** — *shipped*. A flat, store-only zip of
  `stack.json` + `assets/*` — inspectable without the app, friendlier to modern
  tooling than the classic resource-fork/block-chain format (which is still
  imported).
- **PDF printing** — *shipped*. `print card`/`print field`/batched printing
  render real PDFs (this is a faithful verb, but the PDF/modern-print path is
  new plumbing). Noted here because it's a modern output path.

## Deliberate language divergences from HyperCard 2.4
(Documented in `Scripts/ORACLE.md`; everything else in the language is
oracle-verified to match.)
- **Permissive comparisons** — `not ""` and number-vs-noncanonical-string
  comparisons do **not** error (real HC errors on these).
- **Container `sort` superset** — Contrapt accepts container-sort forms that
  HC 2.3 rejects.
- **`numberFormat` inside `do`** — no-op'd (HC effectively ignores it too).
- **`delete <chunk>`** — implemented (was a silent no-op in some HC builds).
- **Self-deletion allowed** — HyperCard refuses to delete an object whose
  script is currently executing (or any container of it); Contrapt permits it
  (the running script is a value snapshot, so nothing dangles — later
  references to the deleted object's parts simply fail by name). Corpus
  evidence says no working classic stack depends on the guard (it only fired
  on already-broken paths), and permissiveness enables the natural
  "Delete This Card" button on the card itself.

## Backward-compatibility niceties (not 2.4 features, but accepted)
These make real old stacks run; listed so they're not mistaken for gaps:
- Spelling variants accepted (`hilite`/`highlite`/`highlight`, …).
- Tolerant parsing of common author constructs and modifiers
  (`doMenu "X" without dialog`, `show window … at`, indirect objects via
  chunk, dynamic property set no-op, etc. — see `PORT-ROADMAP.md`).

---

## Planned additions (not yet built)
Tracked in `PORT-ROADMAP.md` → **Priority 4 — HyperCard, forward**. Headline
items: structured data (associative arrays + JSON), HTTP/JSON verbs, persistent
& shared stack data, reskin/responsive/accessibility, an AI co-author,
components/custom parts, and iPad + Pencil authoring. North star: keep HyperTalk
readable; everything lands in both the app and the web export.
