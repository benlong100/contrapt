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
  (round-trips). *Next (Priority 4 #2):* HTTP verbs — the network unlock these
  arrays were the substrate for.

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
- **AddColor / Color Tools color layer** — *partial*. `HCcd`/`HCbg` color
  resources decode at import; `rect` fills render beneath the 1-bit art
  (multiply compositing). PICT-backed color and button/field tints are deferred
  (`moov`/PICT need a QuickDraw decoder — see `quicktime-movies` note and the
  roadmap).

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
