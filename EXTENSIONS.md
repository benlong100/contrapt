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
