#!/bin/zsh
# Differential test: real HyperCard (Basilisk II probe stack) vs Contrapt's
# interpreter. Usage: Scripts/oracle-diff.sh [expressions-file]
# One HyperTalk expression per line; blank lines and #-comments skipped.
# Requires: Basilisk running with the Probe stack open (see memory basilisk-oracle).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHARED="/Applications/Basilisk II/BasiliskShared"
CORPUS="${1:-$ROOT/Scripts/oracle-corpus.txt}"
WORK="$(mktemp -d)"

# Strip comments/blanks into the working expression list.
grep -v '^\s*#' "$CORPUS" | grep -v '^\s*$' > "$WORK/exprs.txt"
COUNT=$(wc -l < "$WORK/exprs.txt" | tr -d ' ')
JOB=$(date +%s)
echo "oracle-diff: job $JOB, $COUNT expressions"

# --- Real HyperCard (oracle): CR-terminated job file, poll for the reply.
{ printf "%s\r" "$JOB"; tr "\n" "\r" < "$WORK/exprs.txt"; } | iconv -f UTF-8 -t MACROMAN > "$SHARED/probe-in.txt"
for i in {1..60}; do
  sleep 1
  if [ -s "$SHARED/probe-out.txt" ] && \
     [ "$(head -c 20 "$SHARED/probe-out.txt" | tr '\r' '\n' | head -1)" = "$JOB" ]; then
    break
  fi
  [ $i -eq 60 ] && { echo "oracle TIMED OUT (Probe stack open? expression error dialog in guest?)"; exit 1; }
done
iconv -f MACROMAN -t UTF-8 < "$SHARED/probe-out.txt" | tr '\r' '\n' | tail -n +2 > "$WORK/oracle.txt"

# --- Contrapt interpreter, via the env-gated package test.
( cd "$ROOT/HyperTalk" && CONTRAPT_ORACLE_IN="$WORK/exprs.txt" \
    CONTRAPT_ORACLE_OUT="$WORK/contrapt.txt" \
    swift test --filter oracleEvaluateExpressions > /dev/null 2>&1 )

# --- Diff, line by line.
MISMATCH=0
i=1
while IFS= read -r expr; do
  o=$(sed -n "${i}p" "$WORK/oracle.txt")
  c=$(sed -n "${i}p" "$WORK/contrapt.txt")
  if [ "$o" != "$c" ]; then
    MISMATCH=$((MISMATCH+1))
    printf 'MISMATCH %s\n  oracle   : %s\n  contrapt : %s\n' "$expr" "$o" "$c"
  fi
  i=$((i+1))
done < "$WORK/exprs.txt"
echo "----"
echo "$MISMATCH mismatches of $COUNT (details above; work dir $WORK)"
