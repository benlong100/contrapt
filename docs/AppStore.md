# App Store submission kit

Everything needed for TestFlight and review, in one place. Paste-ready.

## Review notes (the 2.5.2 story)

Paste into App Review Information → Notes:

> Contrapt is a document-based creativity app: users build interactive
> "stacks" of cards containing buttons, text fields, labels, images, and
> drawings, and attach small scripts to them in HyperTalk, a simple
> educational scripting language.
>
> Regarding Guideline 2.5.2: all scripts are executed exclusively by an
> interpreter we wrote ourselves, contained entirely within the app
> binary. The app does not download or execute native code, does not use
> JavaScriptCore or any web runtime, and has no networking code at all.
> Scripts are data inside the user's own documents. In line with the
> guideline's provision for educational products, the complete source of
> every script is always viewable and editable by the user: tap Edit,
> then double-tap any object, or open the Inspector. There is no way to
> hide, lock, or obfuscate a script.
>
> The scripting language can only perform actions within the open
> document: navigate between cards, read and write the document's own
> text fields, show text in an on-screen message box, and play a system
> sound. It has no access to the network, file system, contacts, location,
> or any personal data. Runaway scripts (infinite loops) are terminated
> automatically.
>
> The app includes a built-in tutorial (available from the launch screen:
> "Learn HyperTalk") that demonstrates all functionality.

## App Privacy answers

- **Data collection: none.** The app has no networking code, no
  analytics, no third-party SDKs, no accounts. Select "Data Not
  Collected" for every category.
- Documents sync via the user's own iCloud Drive through the system
  document infrastructure; the app never sees credentials or operates
  any server.

## Export compliance

`ITSAppUsesNonExemptEncryption` is set to `false` in the Info.plist —
the app contains no encryption beyond what the OS provides. This
suppresses the per-build compliance questionnaire.

## Store listing draft

- **Name:** Contrapt
- **Subtitle (30 chars):** `Build little apps from cards` (28)
- **Description:**

> Remember when making software felt like play?
>
> Contrapt is a construction set for little apps. Lay out cards. Drop on
> buttons, fields, labels, photos — or paint right on the card. Then give
> anything a script in HyperTalk, a friendly language that reads the way
> you'd say it:
>
>     on mouseUp
>       put "Hello," && field "Name" into field "Greeting"
>       go to next card
>     end mouseUp
>
> Tap Edit and double-tap anything — in your stacks or anyone else's —
> and read exactly how it works. Change it. Break it. Undo. That gentle
> slope from using to tinkering to building is the whole point.
>
> • A real scripting language with a live command line (the Message Box)
> • A script editor with syntax coloring, auto-indent, and friendly errors
> • Paint with Apple Pencil, place photos, snap layouts to guides
> • Share stacks as single files — AirDrop them, send them, post them
> • A built-in tutorial stack that teaches by being read
> • Free, open source, no accounts, no ads, no data collection. Ever.
>
> Made in loving tribute to Bill Atkinson's HyperCard, which showed the
> world that ordinary people could build software.

- **Keywords (100 chars):**
  `hypercard,hypertalk,stack,maker,tinker,build,script,coding,kids,learn,creative,cards,retro` (93)
- **Category:** Education (primary), Productivity (secondary)
- **Age rating:** 4+ (no objectionable content; scripts can't reach
  anything outside the document)

## TestFlight checklist

No screenshots needed for any of this — those are release-only.

1. Archive (Product → Archive) and upload via Xcode Organizer
2. Internal testing (your own devices): available minutes after
   processing, no review, no metadata
3. External group ("HyperCard folks"): needs a one-time beta review —
   provide only a beta description, feedback email, and "what to test."
   Use the "scripts are always viewable" sentence from the review notes
   in the beta description

## Release-only items (later)

- Screenshots: 13" iPad required set — suggest: tutorial card 1, edit
  mode with inspector open, the script editor full-screen with colored
  HyperTalk, paint mode, the Message Box answering `2 + 3`
- Full listing: description, keywords, category, age rating (drafted
  above)

## Known review risks and answers

- *"App executes code"* → the notes above; offer a review call if flagged
- *"Minimum functionality"* → the tutorial stack demonstrates depth
- *Icon/name confusion* → no known conflicts (cleared 2026-09-23; see
  DECISIONS.md N1)
