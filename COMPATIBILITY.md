# HyperCard Compatibility Status

What works, what doesn't yet, and what's known broken — kept honest by
measurement rather than folklore. Two instruments stand behind every claim
here:

- **The corpus.** 4,842 real classic stacks (the Internet Archive's
  `hypercardstacks` collection plus Apple's bundled stacks), 156,942
  scripts. Every one is batch-imported and parsed on each sweep; their
  `openStack`/`openCard` handlers are also *run* headlessly against the
  real app host (the runtime sweep).
- **The oracle.** Real HyperCard 2.3 running in a Basilisk II emulator,
  driven by a probe stack, so language semantics are checked against the
  genuine article, not memory.

Plus 878 automated tests on the language package alone. Dates below are
the last time each number was measured.

---

## Supported and known working

### The language (HyperTalk)

The core is complete and oracle-verified: handlers, functions, custom
messages with parameters, and the full message path (part → card →
background → stack → Home library, including `start using`); all control
flow (block and single-line `if`, all five `repeat` forms, `exit`/`next`/
`pass`); chunk expressions (char/word/item/line — read, write, and
delete); containers, globals, `it`, `the selection`; the operator set
with HyperCard's precedence and string-typed value semantics;
`numberFormat`; 1904-epoch dates and `convert`; `sort` (containers and
cards); `find` (word modes); `select`; mark/unmark; lock/unlock screen;
visual effects; `play` (including bare note runs); `ask`/`answer`
(including `answer file`); `click`, `drag`, `type`; `doMenu`; enable/
disable; `idle`; the modifier-key functions; `send … to <object>`; `do`;
`the target`/`me`.

**Parse coverage, measured:** 99.5% of the corpus's 156,942 scripts parse
clean (2026-10-18). The 765 residual failing scripts are triaged, not
mysterious: CompileIt's 68K-pointer dialect, prose typed into script
slots, and verified author bugs real HyperCard would also reject.

### Objects, properties, and the app

- Buttons (all classic styles, families 0–15, autoHilite, icons), fields
  (shared background fields with per-card content — HyperCard's real
  storage model — scrolling, lockText, wideMargins, per-chunk
  textStyle/textFont/textSize runs including `group`/clickText), cards,
  backgrounds, marked cards, and `part`-generic addressing by z-order.
- Property breadth: geometry (`rect`/`loc`/`topLeft`/`botRight`/
  `width`/`height`, settable), `scroll` of field, `icon`, `hilite`,
  `enabled`, `visible`, `style`, `the number of …` counts across every
  object class, card geometry (`the rect of this card`), and benign
  defaults for the era's environment properties (`cantModify`,
  `freeSize`, `userLevel`, …).
- Custom menus: the full verb set (`create`/`delete`/`put into`/
  `enable`/`disable`/`reset`), menu and menuItem property objects,
  `menuMessage` routing, rendered as an in-window menu strip.
- File I/O: `open`/`read`/`write`/`close file` with faithful semantics
  (`the result` carries "eof"; classic colon paths map into the app
  sandbox).
- Painting from scripts: `drag` with the paint tools draws real pixels
  (line/pencil/brush/eraser, rect/roundRect/oval, bucket fill via
  `click at`), with the paint globals (`lineSize`, `pattern`, `filled`,
  `centered`, `brush`, `multiple`).
- Printing: `print card`/`print all|marked|N cards`/`print field` render
  real PDFs; `open printing … close printing` batches.
- Multi-file stack sets: `go … of stack "X"` opens sibling files
  in-place in the same window (The Manhole's six files play through).
- The card-window viewport idiom: `set the rect/width/height of card
  window` crops a big card in a small window, as stacks like The Hacker
  Crackdown expect.
- Palettes: PLTE resources import and show as floating button panels;
  `palette`, `the windows`, window visible/loc/rect scripting.
- Sound: `play` with imported `snd ` resources and note runs;
  `the sound` reports "done" reliably.
- Full-screen presentation, `hide menubar`, screen `flash`.

### Importing classic stacks

STAK files in both 1.x and 2.x layouts import with: real card sizes
(640×480 and friends, not just 512×342), WOBA 1-bit card/background art,
part geometry down to 1-pixel rules, per-card background-field text
(both 1.x direct entries and 2.x content sections, including part-less
body cards), icons by HyperCard's real search path (stack fork → Home →
HyperCard app; ICON, color cicn, ICN#), embedded `snd ` sounds, fonts,
script-preserved part IDs (so `button id N` keeps working), duplicate
CARD ids tolerated, text metrics calibrated against real HyperCard
(line breaks on Apple's own stacks reproduce), and AddColor (HCcd/HCbg)
rect color overlays.

### XCMDs and XFCNs

Executing 68K code resources is permanently out of scope (it would mean
emulating the 68K ISA plus the Toolbox ABI). Instead, popular externals
are shimmed natively, chosen by corpus frequency: PopMenu/HPopUpMenu,
FileName, NewFileName, FontExists, Flash/Flasher/FlashRect,
SpeakText/Speak, AddColor (and the Color Tools family: ColorizeHC …),
ShowBookmark, cardNumber, and Apple Service Source's sslistopen/
ssopencard family. Unrecognized externals no-op rather than error (as
HyperCard does when the resource is missing).

### Beyond HyperCard

Contrapt also extends the language for the modern world — associative
arrays and JSON, the `url` container and HTTP verbs, web-page readers,
`FeedItems`/`CSVItems`, `make a card for each element`, timed `send`,
rich-field links, `stackData` persistence, themes, `ask … with ai`, and
a self-contained web export that runs the same interpreter in the
browser. Those are catalogued separately in [EXTENSIONS.md](EXTENSIONS.md);
this page is about classic compatibility.

---

## Not implemented (or partial)

- **68K XCMD/XFCN execution** — out of scope, by design. The shim
  registry above is the path; new shims get added when real stacks
  surface a need.
- **QuickTime movies** (`QTMovie`, `playMovie`) — researched and
  deferred: no playable movie exists anywhere in the corpus (the one
  embedded `moov` is a header-only atom). The viable slice — playing a
  user-picked external file in a floating window — is designed but not
  built.
- **AddColor, the rest** — rect overlays and PICT v2 bitmap backgrounds
  decode and draw; PICT v1 opcodes, button/field tint elements, and
  color in the web export remain.
- **Paint tools, the exotic ones** — spray can, lasso, select, and the
  paint text tool don't draw from scripts; patterns beyond white/black
  approximate to black; scripted paint goes to the card layer only
  (`editBkgnd` is ignored for painting).
- **Classic text styles shadow/condense/extend** — shadow folds into
  outline on import; condense/extend are dropped.
- **Custom user properties** (`set the myThing of card …`) — deferred:
  no stack in the 4,842 uses them.
- **True layout reflow / Dynamic Type** — a HyperCard card is a fixed
  pixel canvas; Contrapt scales it uniformly (plus VoiceOver semantics),
  but doesn't reflow parts. Deliberate.
- **Deliberate no-ops** (correct behavior for a sandboxed, single-app
  port, not gaps): `dial`, serial port verbs, AppleEvents to other
  programs, `trace`/`debug`/`checkpoint`, `print <document> with <app>`.
- **Web-export niches** — symbol icons render untinted; the rich-field
  web view and message box don't follow stack themes; `visual effect`
  ignores reduce-motion preferences.

---

## Known bugs and rough edges

The runtime sweep (every stack's open handlers executed headlessly) is
the honest bug list. The first full pass (2026-10-18) found 2,076
runtime errors in 248 distinct classes across the 4,842 stacks; three
fix rounds followed (XCMD shims, card geometry properties, popup
`selectedText`, coercion forms). The post-fix re-sweep (2026-11-06)
measures **1,426 errors in 241 classes**. Of those:

- **430 “errors” are poll-loop timeouts** — stacks busy-waiting for a
  click in `openStack` — which is correct behavior under a headless
  audit, not a bug.
- A large share are **author bugs surfacing at run time** (144
  unterminated quotes, 33 unterminated handlers, references to cards
  and fields that never shipped) — real HyperCard rejects these too.
- The long tail is genuine but narrow: one or two stacks per error
  class. These get fixed in ranked order, each with a regression test
  citing the stack that proved it.

Specific known issues:

- **Printing is implemented but not yet verified against physical
  printers** — PDFs render correctly in tests; the dialog path needs
  real-hardware confirmation.
- **Re-import may be needed** after fidelity fixes land (families,
  icons, shared background fields): a stack imported with an older
  build keeps its old model until re-imported.

### Deliberate divergences from HyperCard 2.4

Documented choices, not accidents (full list in EXTENSIONS.md):

- Permissive comparisons — `not ""` and number-vs-string comparisons
  don't error (real HC errors).
- Container `sort` accepts forms HC 2.3 rejects.
- `delete <chunk>` actually works (a silent no-op in some HC builds).
- Objects may delete themselves from their own scripts (HyperCard
  refuses; no working classic stack depends on the refusal).
- A step budget stops `repeat forever` from freezing the app.

---

*To reproduce the numbers:* parse sweep —
`CONTRAPT_AUDIT=1 swift test --package-path HyperTalk --filter
corpusParseAudit`; runtime sweep — `TEST_RUNNER_CONTRAPT_RUNTIME=1
xcodebuild test -scheme ContraptTests -destination 'platform=macOS'`
(add `TEST_RUNNER_CONTRAPT_RUNTIME_FILTER=<substring>` to narrow it to
matching stack paths). Both write ranked reports. The corpus itself is copyrighted and not in
the repo.
