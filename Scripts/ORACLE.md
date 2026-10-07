# The Basilisk Oracle

Differential testing of Contrapt's HyperTalk interpreter against **real
HyperCard 2.3** running in Basilisk II on this machine.

## How it works
- A **Probe stack** inside the emulator polls `probe-in.txt` on the shared
  folder (`/Applications/Basilisk II/BasiliskShared/`) from its `idle`
  handler, evaluates each line, and writes answers to `probe-out.txt`
  incrementally. Its script lives in `probe-script.txt` there (v3).
- `Scripts/oracle-diff.sh [corpus]` writes a job (line 1 = fresh id, then one
  test per line, CR endings, Mac Roman), waits for the reply, runs the same
  tests through Contrapt's interpreter (env-gated package test
  `oracleEvaluateExpressions` in `OracleDiffTests.swift`, on MockHost), and
  prints every mismatch.
- Corpus format (`Scripts/oracle-corpus.txt`): one **expression** per line,
  or `@stmt | stmt | …` for **statements** that must `put … into probeResult`.
  `#` comments. Statement results must stay single-line.

## Running it
1. Basilisk running, Probe stack open (idle must fire — click its card once
   after any dialog).
2. `./Scripts/oracle-diff.sh` — 0 mismatches = Contrapt matches real HC on
   all ~300 corpus lines.

## Gotchas
- An expression that **errors in real HC** pops a dialog in the guest and
  stops the batch (no try/catch in HyperTalk); the incremental output file
  shows exactly where it died. Dismiss the dialog, click the card, rerun.
  Vet new corpus lines for error risk first.
- Pasting a new probe script into the guest: copy from SimpleText **inside
  the guest**; a stray box character (a linefeed) sometimes sneaks in —
  delete it in the script editor.
- The guest's named-format `convert` (long/abbreviated date) is
  intermittently flaky under emulation; such lines are commented
  env-dependent in the corpus — don't chase them.

## What's been established (committed fixes, each oracle-verified)
Batches 1–5 (2026-10-07, commits 2164b97 → 5e54654): banker's rounding;
trailing-delimiter chunk rules; pi as 20-digit constant; numberFormat applied
only at number→text boundaries (put, `&`, length, chunk counts) with full
precision between operations; middle-of-even = higher index; empty contained
in nothing; numToChar(13) = return; tab not a word separator; HC's numeric
lexicon (no `1e3`/`+3`, `- 3` ok); `-.5` formatting; float mod floors / int
mod truncates; unary minus binds tighter than `^`; sign-space arithmetic;
**`delete <chunk>` implemented** (was a silent no-op); **1904 epoch** for
seconds/convert (was 1970); current-century two-digit-year pivot; weekday in
the abbreviated date. Offline pins: `OracleVerifiedTests.swift`.

Known deliberate divergences (commented in the corpus): `not ""` and
number-vs-noncanonical-string comparisons error in real HC (Contrapt is
permissive); container `sort` errors in HC 2.3 (Contrapt superset); custom
`numberFormat` inside `do` is ignored by HC (Contrapt no-ops it too).
