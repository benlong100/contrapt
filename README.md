# HyperPad *(working title)*

A modern, open-source reimagining of HyperCard for iPad — in tribute to
Bill Atkinson, whose extraordinary work showed that ordinary people could
build software.

Stacks of cards. Buttons, fields, labels, images, and paint. Every object
carries a script in **HyperTalk** — the real thing, not a lookalike:

```
on mouseUp
  if field "Name" is empty then
    put "Hello, stranger!" into field "Greeting"
  else
    put "Hello," && field "Name" & "!" into field "Greeting"
  end if
end mouseUp
```

Tap Edit, double-tap anything, and read how it works. That gentle slope
from user to tinkerer to programmer is the whole point.

## What works today

- **Browse and build**: cards on a fixed logical canvas, native SwiftUI
  controls as parts, drag/resize with alignment guides and grid snapping,
  a property inspector, full undo
- **HyperTalk**: handlers, the message path (part → card → background →
  stack), custom messages with parameters, `put`/`go`/`beep`, block and
  single-line `if`, all five `repeat` forms, authentic string-typed
  values and operators — plus a step budget so `repeat forever` can't
  freeze anything
- **The Message Box**: output and a live command line in the current
  card's context
- **A real script editor**: live syntax coloring, structural auto-indent
  on every return, check-before-run with friendly line-numbered errors,
  full-screen mode
- **Media**: PencilKit paint per card, photo-library images, `beep`
- **Exchange**: a stack is one flat, store-only zip — `stack.json` plus
  `assets/` — openable by any zip tool anywhere. Hostile files are
  sanitized on open; scripts from strangers run inside the interpreter
  sandbox
- **A built-in tutorial stack** that teaches by being read

## Architecture

| Piece | What it is |
|-------|------------|
| `HyperTalk/` | The language: tokenizer, parser, tree-walking interpreter, syntax scanner, re-indenter. A standalone Swift package, pure Foundation, ~80 tests (`swift test`) |
| `HyperPad/Model/` | The document: Codable stack model, zip container, sanitization |
| `HyperPad/Views/` | SwiftUI: card renderer, edit mode, inspectors, script editor, paint |
| `HyperPad/Scripting/` | The host bridge — the only door between scripts and the world |

Scripts reach the app through one small protocol (`HyperTalkHost`); the
interpreter is the sandbox. Design decisions and their reasons live in
[DECISIONS.md](DECISIONS.md).

## Building

Open `HyperPad.xcodeproj` in Xcode 26+ and run on an iPad (or iPad
simulator) with iPadOS 26+. The `HyperTalk` package tests run from the
command line: `cd HyperTalk && swift test`.

## Status

Pre-release, under active development. The name is a working title.
Planned: sound assets, a native macOS app, and an importer for original
HyperCard stacks.

## License

MIT — see [LICENSE](LICENSE). Free forever, in the spirit of the thing
it honors.
