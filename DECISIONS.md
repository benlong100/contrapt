# Project Decisions

A modern, open-source reimagining of HyperCard for iPad, in tribute to Bill Atkinson.
Free on the App Store. This file records the founding decisions and their rationale.

*Last updated: 2026-09-23 (Phase 0)*

## Settled

### D1. License: MIT
Maximally permissive, zero App Store friction, fits the tribute spirit.
GPL was rejected due to its documented conflicts with App Store distribution
terms (e.g. VLC's removal).

### D2. Platform: iPad-only, iOS 26 minimum
Leanest possible v1: one screen class, latest SDK only (Liquid Glass and
current SwiftUI APIs for free, no back-compat testing). iPhone support comes
later as a stack *viewer* — authoring is designed for iPad.

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
- Mac support
- "Protect my stack" author option (review-risk under 2.5.2; needs care)
- Any cloud/gallery service for sharing stacks

## Roadmap reference

Phases: 0 decisions → 1 document model → 2 browse mode → 3 edit mode →
4 interpreter v1 → 5 message path → 6 media & paint → 7 exchange & hardening
→ 8 ship. Build a thin vertical slice first (place a button, script
`go to next card`, tap it in browse mode), then deepen.
