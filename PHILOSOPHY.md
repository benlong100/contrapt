# What Contrapt Is

**Contrapt asks one question: what if HyperCard had simply kept going?**

Not "what would a modern tool inspired by HyperCard look like" — that
question has been answered well by others. Contrapt is HyperCard itself,
preserved and carefully modernized: the real stack model, the real
HyperTalk, the real gentle slope from user to tinkerer to programmer,
continued as if development had never stopped.

That framing decides what gets built, so it's written down here.

## The three claims

These are the things Contrapt does that its relatives structurally can't,
and they are the measure of every proposed feature:

1. **It opens the shoebox.** Real HyperCard stacks — the ones on a
   forgotten floppy or a CD-ROM in the attic — import and run again.
   Contrapt is a preservation tool and a creation tool in one binary.
   The import fidelity work (WOBA bitmaps, resource forks, sounds,
   icons, fonts, XCMD shims, the message path) is not a legacy
   checkbox; it is half the point.

2. **The web is a first-class target, not a bolt-on.** A stack exports
   as a self-contained little website running the *same interpreter*
   compiled to WebAssembly — not a transpilation, not a viewer that
   approximates. "Your stack is a little website, running the real
   engine" is a true, demonstrable sentence. The north-star constraint
   that follows: **write once, run everywhere** — language features live
   in the shared interpreter and land in the native app and the web
   export at the same time, or they don't land.

3. **Restraint is the feature.** HyperCard's gentle slope — the reason a
   teacher, a kid, a poet could build something real — came from a small,
   readable, English-like surface. Growing that surface is how you lose
   it. Contrapt guards it deliberately, and bets that the AI co-author
   (explain this script, write this handler) becomes the modern on-ramp
   *rather than more language*.

## The restraint bar

Every proposed language addition must pass this test: **does it extend an
idiom HyperCard already had, or grow a new one?** "Would this be useful"
is never sufficient — everything is useful; that's how languages bloat.

In practice:
- Prefer property shapes (`the title of url "…"`) over new syntax classes.
- Prefer containers and chunk expressions over new data machinery.
- Prefer one readable verb over a configurable API.
- When a modern capability genuinely needs new surface (arrays, `url`,
  `stackData`), keep it English-like and record it in
  [EXTENSIONS.md](EXTENSIONS.md) — that file is the honest ledger of
  everywhere Contrapt goes beyond HyperCard 2.4.

## Contrapt and LiveCode

LiveCode (née Runtime Revolution, née MetaCard) is HyperCard's spiritual
successor that moved on. It asks: *what would a serious cross-platform
RAD tool descended from xTalk look like?* Contrapt asks: *what if
HyperCard had simply kept going?* Different projects that happen to rhyme.

Where LiveCode is genuinely ahead — and it's ahead by a lot: it is a
decades-deep professional platform, with true native cross-platform
binaries, real mobile deployment, database and enterprise connectivity, a
huge standard library, and an actual ecosystem with support. Contrapt
does none of that today, and isn't trying to in the near term.

Credit where due: some of Contrapt's modern touches — associative
arrays, `the httpHeaders`, `put url "…" into …` — consciously echo
idioms LiveCode shipped first. We converged on good answers they found
before us.

What Contrapt claims instead is exactly the three things above: LiveCode
can't open your 1994 stack, its web story has never been "the real engine
in a page," and it long ago traded the small surface for a big one (a
reasonable trade for its goals — just not ours).

**The one-liner:** *LiveCode is HyperCard's cousin that became a
professional RAD tool; Contrapt is HyperCard brought back — it runs the
original stacks, and turns them into websites that run the real engine.*

## Where the plans live

- [PORT-ROADMAP.md](PORT-ROADMAP.md) — compatibility inventory and the
  "HyperCard, forward" sequence.
- [EXTENSIONS.md](EXTENSIONS.md) — the ledger of additions beyond
  HyperCard 2.4, each with its rationale.
- [DECISIONS.md](DECISIONS.md) — design decisions and their reasons.
