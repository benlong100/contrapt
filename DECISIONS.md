# Project Decisions

A modern, open-source reimagining of HyperCard for iPad, in tribute to Bill Atkinson.
Free on the App Store. This file records the founding decisions and their rationale.

*Last updated: 2026-09-23 (Phase 0)*

## Settled

### D1. License: MIT
Maximally permissive, zero App Store friction, fits the tribute spirit.
GPL was rejected due to its documented conflicts with App Store distribution
terms (e.g. VLC's removal).

### D2. Platform: iPad-first, iOS 26 minimum; native Mac as fast-follow
*(revised 2026-09-23 — originally iPad-only)*
iPad remains the v1 development focus, but a native macOS destination
(same SwiftUI codebase) is planned once browse + edit modes stabilize —
before public release. Rationale: the HyperCard-nostalgic audience is
Mac-centric, legacy stacks live on Macs (see N4), and a Mac with pointer +
hardware keyboard is arguably the better authoring environment.

Consequences:
- All code stays multiplatform-clean from now on: platform-agnostic colors
  and styles, `#if os` only at genuine chrome differences (e.g. `.bottomBar`
  toolbar placement).
- Apple Silicon Macs run the iPad app in compatibility mode in the interim.
- iPhone support remains later-and-viewer-only; authoring targets iPad/Mac.

### D3. Card layout: fixed logical card size, free-form placement
Faithful to HyperCard. Cards have a fixed logical size in points, objects are
placed at absolute coordinates, and the whole card scales to fit the screen.
Deterministic rendering across devices; simplest possible editor. Adaptive or
anchored layout is a possible v2 evolution (see Deferred).

### D4. Stack file format: flat zip archive
A stack is a single file — a zip archive containing a JSON manifest plus media
assets (like `.key` / `.docx`). Chosen over a file package because a single
flat file travels reliably through email, web servers, AirDrop, and non-Apple
systems, and this format is exchange-centric by design.

- The manifest carries a format version field from day one.
- Received stacks are treated as hostile input when parsed.

### D5. Widgets: native SwiftUI controls as the object palette
HyperCard's buttons and fields become real SwiftUI controls (`Button`,
`TextField`, `Toggle`, `Slider`, …) described as data in the document and
instantiated by the runtime. This inherits touch targets, accessibility,
Dynamic Type, dark mode, and platform styling for free, and keeps stacks
App Store-legal (widgets are data, not code).

### D6. Scripting: our own interpreter, scripts always user-viewable
A HyperTalk-style language executed by an interpreter we write ourselves
(no JavaScriptCore, no downloaded native code). Per App Store Guideline
2.5.2's carve-out, script source in any stack is always viewable and editable
by the user — which is also the HyperCard ethos. No locked/compiled-only
stacks in v1.

### D7. Distribution: free app, stacks exchanged as documents
No accounts, no cloud service of our own. Stacks are documents with a custom
UTType, exchanged via Files, iCloud Drive, AirDrop, Messages, and the web.
Scripts from untrusted stacks run inside the interpreter sandbox with
runaway protection (instruction budgets/timeouts) and capability gating for
anything sensitive.

### D9. Scripting language: HyperTalk-compatible core
Refines D6. The language is real HyperTalk at its core — original syntax and
message names (`on mouseUp`, `go to card 3`, `put x into field "Name"`) —
so that simple scripts from converted legacy stacks (N4) run unmodified,
and decades of HyperCard books and documentation remain valid learning
material. Modern additions are layered on without breaking old syntax.
This constrains Phase 3+ too: template stacks and editor examples use
authentic HyperTalk message names from the start.

### D8. Skinnable app chrome, following the Note-O-Tron pattern
The editor/app UI is skinnable, reusing the architecture from Note-O-Tron's
`Skin.swift`: a `SkinID` enum persisted as a raw string in `@AppStorage`, a
value-type `Skin` struct where every field is optional and `nil` means
"system default" (the default skin is `Skin()` — zero overhead, fully
native/Liquid Glass), a `SkinFont` abstraction for bundled + system fonts,
a `@CurrentSkin` property wrapper reading AppStorage directly (not the
environment — stale-value issues in split views/toolbars), and opt-in
`.skinned*` view modifiers.

Open question (decide by Phase 2): whether skins ever affect *stack*
rendering. Leaning: card appearance belongs to the stack author (document
data, travels in the file), not the viewer's skin — with one possible
exception, a "Classic" viewer skin rendering stacks in 1-bit original-Mac
style as a tribute option.

## Deferred (with decision gates)

### N1. Real product name — gate: first external distribution
"HyperPad" is a **working title only**. An existing app-creation product named
hyperPad (hyperpad.com) occupies this exact category, so the working title
must not be used publicly (public repo, TestFlight external, App Store,
marketing). The real name, trademark search, bundle ID, UTType identifier,
and file extension are all settled together at this gate — none of them lock
in before first external distribution.

### N2. Identifier hygiene
Bundle ID, iCloud container ID, UTType, and file extension all embed a name
and become permanent at first release. Leave as-is during development; choose
deliberately alongside N1.

### N3. Possible v2 ideas (explicitly out of scope for v1)
- Adaptive/anchored card layout for varying screen sizes
- iPhone viewer app
- "Protect my stack" author option (review-risk under 2.5.2; needs care)
- Any cloud/gallery service for sharing stacks

### N4. Legacy HyperCard stack import — gate: post-v1, after Mac target
A translator from original HyperCard `.stack` binaries to our format.
Old stacks store their data mostly in the data fork, so files that survived
migration to modern filesystems are usually intact. Prior art: Uli
Kusterer's `stackimport` (format parsing), Internet Archive's emulation.
Fidelity tiers, in order of feasibility:
1. Structure — cards, backgrounds, buttons, fields, text → clean conversion
2. Paint layers — 1-bit graphics → images
3. Scripts — carried over as-is; D9's HyperTalk-compatible core means
   simple handlers run unmodified, complex ones degrade to viewable source
The translator should be a standalone Swift package usable by both the Mac
and iPad apps.

## Roadmap reference

Phases: 0 decisions → 1 document model → 2 browse mode → 3 edit mode →
4 interpreter v1 → 5 message path → 6 media & paint → 7 exchange & hardening
→ 8 ship. Build a thin vertical slice first (place a button, script
`go to next card`, tap it in browse mode), then deepen.
