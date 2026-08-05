#!/usr/bin/env bash
# fr-ddd-vocab.sh <RUN_DIR> — Step 4.5, pr mode only. Resolves which domain
# vocabulary the narrative pass will speak in, and materializes it as a brief.
#
# The vocabulary source is reported, never assumed. A narrative written in the
# repo's own ubiquitous language and one written in generic textbook DDD terms
# read almost identically and are worth very different amounts, so VOCAB is a
# labelled output in the same way HAS_GSTACK is: the reader is told which lens
# they got.
#
# Resolution order:
#   1. $SOURCE_ROOT/.lattice/standards/ddd-principles.md — the ddd-refiner's
#      output. Its glossary / bounded-context / invariant sections are extracted;
#      when it has none, its heading list is used instead, since the section
#      names themselves carry the repo's domain nouns.
#   2. No document — the tactical defaults, plus an instruction to take the
#      repo's nouns from the diff's own naming. Labelled atom-defaults so the
#      narrative can be discounted accordingly.
#
# Only the extracted brief is materialized; the orchestrator never reads the
# principles document, which runs to a thousand lines in a full refiner output.
#
# Output contract (stdout):
#   === FRESH-REVIEW DDD VOCAB ===
#   VOCAB: ddd-principles | atom-defaults
#   DDD_DOC: <path> | none
#   DDD_MODE: overlay | override | unknown | n/a
#   GLOSSARY: extracted | headings_only | defaults
#   BRIEF: <path>
#   BRIEF_LINES: <n>
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-ddd-vocab.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

BRIEF="$RUN_DIR/packet/ddd.md"
DOC="$SOURCE_ROOT/.lattice/standards/ddd-principles.md"

SECTION_RX='ubiquitous|glossary|bounded.?context|domain.?language|domain.?term|invariant|naming'

if [ -f "$DOC" ]; then
  VOCAB=ddd-principles
  DDD_MODE=$(sed -n '1,10p' "$DOC" | sed -nE 's/^mode:[[:space:]]*([a-z]+).*/\1/p' | head -1)
  [ -n "$DDD_MODE" ] || DDD_MODE=unknown

  awk -v rx="$SECTION_RX" '
    /^#{2,3} / {
      hdr = tolower($0)
      keep = (hdr ~ rx)
    }
    keep { print }
  ' "$DOC" > "$RUN_DIR/packet/.ddd-sections"

  if [ -s "$RUN_DIR/packet/.ddd-sections" ]; then
    GLOSSARY=extracted
    {
      echo "# Domain vocabulary brief"
      echo
      echo "SOURCE: $DOC (mode: $DDD_MODE)"
      echo
      echo "These are the sections of this repo's DDD principles that define what things"
      echo "are *called*. Speak in these terms. The full document is readable at the path"
      echo "above if a term here is unclear — but do not narrate its rules, narrate the change."
      echo
      cat "$RUN_DIR/packet/.ddd-sections"
    } > "$BRIEF"
  else
    GLOSSARY=headings_only
    {
      echo "# Domain vocabulary brief"
      echo
      echo "SOURCE: $DOC (mode: $DDD_MODE)"
      echo
      echo "This repo's DDD principles document has no glossary or bounded-context section."
      echo "Its section headings are below — they carry the shape of the domain. Read the"
      echo "document itself at the path above for the terms it uses in its examples."
      echo
      grep -E '^#{1,3} ' "$DOC" || true
    } > "$BRIEF"
  fi
  rm -f "$RUN_DIR/packet/.ddd-sections"
else
  VOCAB=atom-defaults
  DDD_MODE="n/a"
  GLOSSARY=defaults
  cat > "$BRIEF" <<'BRIEF_EOF'
# Domain vocabulary brief

SOURCE: none — this repo has no .lattice/standards/ddd-principles.md.

No project vocabulary has been defined, so you have two jobs instead of one:
take the *structural* terms from the tactical defaults below, and take the
*domain nouns* from the repo itself — the names the code already uses for the
things it manages. Prefer a noun the repo actually uses over a textbook one.

Structural terms available to you:

- **Aggregate** — a cluster of things that must be consistent together, changed
  as one unit through a single root. Name the root.
- **Entity** — a thing with an identity that persists across changes to it.
- **Value object** — a thing defined entirely by its attributes, with no identity.
- **Domain event** — a fact, in the past tense, that something happened.
- **Invariant / rule** — a condition the domain guarantees is always true.
- **Domain service** — a rule that spans several things and belongs to none.
- **Repository** — where aggregates are kept and found.
- **Bounded context** — a boundary inside which a term means exactly one thing.

Say plainly when a change is not a domain change at all. Tooling, CI, build, and
formatting changes have no domain meaning, and inventing one for them is worse
than reporting that the change is infrastructural.
BRIEF_EOF
fi

BRIEF_LINES=$(wc -l < "$BRIEF" | tr -d ' ')

{
  echo "VOCAB='$VOCAB'"
  echo "DDD_DOC='$([ -f "$DOC" ] && echo "$DOC" || echo none)'"
  echo "DDD_MODE='$DDD_MODE'"
  echo "GLOSSARY='$GLOSSARY'"
  echo "DDD_BRIEF='$BRIEF'"
} >> "$STATE"

printf '%s\n' "=== FRESH-REVIEW DDD VOCAB ===" \
  "VOCAB: $VOCAB" \
  "DDD_DOC: $([ -f "$DOC" ] && echo "$DOC" || echo none)" \
  "DDD_MODE: $DDD_MODE" \
  "GLOSSARY: $GLOSSARY" \
  "BRIEF: $BRIEF" \
  "BRIEF_LINES: $BRIEF_LINES" \
  "=== END ==="
