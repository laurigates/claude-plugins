#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks and $PRE_SHA are literal markdown/workflow text, never expansions
# Regression test for scripts/check-split-content-preservation.py and its call
# site in the "Publish split commits" step of .github/workflows/skill-splitter.yml.
#
# Why (#3016): the splitter moves whole sections out of a SKILL.md into
# references/*.md. Before this check, the publish step verified only the
# commit subjects and that every changed path sat inside a selected skill
# directory. A split that dropped a table row, lost a section heading, or
# paraphrased a moved paragraph passed both and went up for review as a
# "refactor". That made a weaker splitter model impossible to evaluate: the
# replay #3016 asks for needs a deterministic signal that nothing was lost.
#
# THE SEMANTIC INVARIANT: across a skill directory's markdown files, every
# non-blank line of the base revision is still present at the head (as a
# multiset), and every heading text survives as a heading at some level. The
# one tolerated change is a line that carried a direction word ("see the table
# above") and was rewritten into a near-identical line, which is what the
# splitter prompt tells the model to do.
#
# Guards:
#   A. a faithful split (section moved to references/, link line added) is OK
#   B. a moved section that drops one table row is ERROR line_missing
#   C. a section moved without its heading is ERROR section_missing
#   D. a section re-levelled in the reference file (### -> ##) is OK
#   E. a positional pointer rewritten to a link is OK and counted as rewritten
#   F. a content line rewritten with no direction word is ERROR line_missing
#   G. dropping one of two identical lines is ERROR (multiset, not set)
#   H. deleting lines from a pre-existing REFERENCE.md is ERROR
#   I. an empty range is OK and still reports the lines it checked
#   J. a skill dir with no markdown at the base is ERROR skill_not_found
#   K. failing and passing output satisfy the structured-output contract
#   L. the workflow runs the check before it publishes, against $PRE_SHA
#   M. a missing --base or skill dir is a usage error (exit 2)
#
# SKILL_SPLITTER_WORKFLOW overrides the workflow under test, so L can be shown
# red against the pre-#3016 file.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
check="$repo_root/scripts/check-split-content-preservation.py"
contract="$repo_root/scripts/check-structured-output-contract.sh"
workflow="${SKILL_SPLITTER_WORKFLOW:-$repo_root/.github/workflows/skill-splitter.yml}"

# A sandbox repo must not inherit a parent git's location (#1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then echo "mktemp -d failed" >&2; exit 1; fi
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
ko() { echo "  FAIL: $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/      /'; fail=$((fail + 1)); }
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else ko "$1" "expected: $3 / actual: $2"; fi; }
assert_has() { if grep -qF -- "$3" <<<"$2"; then ok "$1"; else ko "$1" "missing: $3"; fi; }
val() { grep -m1 "^$2=" <<<"$1" | cut -d= -f2-; }

SKILL=a-plugin/skills/demo

# new_repo <name>: a repo holding the base skill, committed once.
new_repo() {
  local r="$tmp/$1"
  mkdir -p "$r/$SKILL"
  git -C "$r" init -q
  git -C "$r" config user.name test
  git -C "$r" config user.email test@example.invalid
  git -C "$r" config commit.gpgsign false
  cat > "$r/$SKILL/SKILL.md" <<'MD'
---
name: demo
description: Demo skill. Use when testing.
---

# Demo

## Quick start

Run `demo --fast` to begin.

## Full flag reference

| Flag | Meaning |
|------|---------|
| `--fast` | Skip checks |
| `--deep` | Run every check |
| `--deep` | Run every check |

See the table above for every flag.

### Edge cases

Use `--force` only on a scratch tree.
MD
  git -C "$r" add -A
  git -C "$r" commit -q -m base
  printf '%s\n' "$r"
}

# split <repo>: a faithful split, written as the splitter prompt asks.
split() {
  local r="$1"
  mkdir -p "$r/$SKILL/references"
  cat > "$r/$SKILL/SKILL.md" <<'MD'
---
name: demo
description: Demo skill. Use when testing.
---

# Demo

## Quick start

Run `demo --fast` to begin.

For every flag and the edge cases, see [references/flags.md](references/flags.md).
MD
  cat > "$r/$SKILL/references/flags.md" <<'MD'
# Demo - Flags

Every flag the demo CLI accepts.

## Full flag reference

| Flag | Meaning |
|------|---------|
| `--fast` | Skip checks |
| `--deep` | Run every check |
| `--deep` | Run every check |

See the [Full flag reference](#full-flag-reference) table for every flag.

### Edge cases

Use `--force` only on a scratch tree.
MD
}

commit() { git -C "$1" add -A && git -C "$1" commit -q -m "refactor(split): extract reference content from demo"; }
run() { local r="$1"; shift; (cd "$r" && python3 "$check" "$@" 2>&1); }

echo "=== check-split-content-preservation.py ==="

# --- A: faithful split ------------------------------------------------------
r=$(new_repo a); base=$(git -C "$r" rev-parse HEAD); split "$r"; commit "$r"
out=$(run "$r" --base "$base" "$SKILL/"); rc=$?
assert_eq "A faithful split exits 0" "$rc" "0"
assert_eq "A faithful split STATUS=OK" "$(val "$out" STATUS)" "OK"
assert_eq "A one skill checked" "$(val "$out" SKILLS_CHECKED)" "1"
pass_out="$out"

# --- B: a moved section drops a table row -----------------------------------
r=$(new_repo b); base=$(git -C "$r" rev-parse HEAD); split "$r"
sed -i.bak '/`--fast` | Skip checks/d' "$r/$SKILL/references/flags.md" && rm "$r/$SKILL/references/flags.md.bak"
commit "$r"
out=$(run "$r" --base "$base" "$SKILL"); rc=$?
assert_eq "B dropped row exits 1" "$rc" "1"
assert_eq "B dropped row STATUS=ERROR" "$(val "$out" STATUS)" "ERROR"
assert_has "B names line_missing" "$out" "TYPE=line_missing"
assert_has "B names the dropped row" "$out" '`--fast` | Skip checks'
assert_has "B names the base file and line" "$out" "FILE=$SKILL/SKILL.md LINE=16"
fail_out="$out"

# --- C: section moved without its heading -----------------------------------
r=$(new_repo c); base=$(git -C "$r" rev-parse HEAD); split "$r"
sed -i.bak '/^### Edge cases$/d' "$r/$SKILL/references/flags.md" && rm "$r/$SKILL/references/flags.md.bak"
commit "$r"
out=$(run "$r" --base "$base" "$SKILL"); rc=$?
assert_eq "C lost heading exits 1" "$rc" "1"
assert_has "C names section_missing" "$out" "TYPE=section_missing"
assert_has "C names the heading" "$out" "MSG=Edge cases"

# --- D: re-levelled heading --------------------------------------------------
r=$(new_repo d); base=$(git -C "$r" rev-parse HEAD); split "$r"
sed -i.bak 's/^### Edge cases$/## Edge cases/' "$r/$SKILL/references/flags.md" && rm "$r/$SKILL/references/flags.md.bak"
commit "$r"
out=$(run "$r" --base "$base" "$SKILL"); rc=$?
assert_eq "D re-levelled heading exits 0" "$rc" "0"

# --- E: positional pointer rewrite is tolerated and counted -----------------
# (case A already rewrote "the table above"; assert the count here)
assert_eq "E the pointer rewrite is counted" "$(val "$pass_out" LINES_REWRITTEN)" "1"

# --- F: content line rewritten without a direction word ---------------------
r=$(new_repo f); base=$(git -C "$r" rev-parse HEAD); split "$r"
sed -i.bak 's/Use `--force` only on a scratch tree./Use `--force` on any tree./' "$r/$SKILL/references/flags.md" && rm "$r/$SKILL/references/flags.md.bak"
commit "$r"
out=$(run "$r" --base "$base" "$SKILL"); rc=$?
assert_eq "F paraphrased content exits 1" "$rc" "1"
assert_has "F names the original line" "$out" 'MSG=Use `--force` only on a scratch tree.'

# --- G: one of two identical lines dropped ----------------------------------
r=$(new_repo g); base=$(git -C "$r" rev-parse HEAD); split "$r"
python3 - "$r/$SKILL/references/flags.md" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
i = lines.index("| `--deep` | Run every check |")
del lines[i]
open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
commit "$r"
out=$(run "$r" --base "$base" "$SKILL"); rc=$?
assert_eq "G dropped duplicate exits 1" "$rc" "1"
assert_has "G names the duplicate row" "$out" '`--deep` | Run every check'

# --- H: lines removed from a pre-existing REFERENCE.md ----------------------
r=$(new_repo h)
printf '# Demo reference\n\nKeep this paragraph.\n' > "$r/$SKILL/REFERENCE.md"
git -C "$r" add -A && git -C "$r" commit -q -m "add reference"
base=$(git -C "$r" rev-parse HEAD); split "$r"
printf '# Demo reference\n' > "$r/$SKILL/REFERENCE.md"
commit "$r"
out=$(run "$r" --base "$base" "$SKILL"); rc=$?
assert_eq "H trimmed REFERENCE.md exits 1" "$rc" "1"
assert_has "H names the REFERENCE.md line" "$out" "FILE=$SKILL/REFERENCE.md LINE=3"

# --- I: empty range ----------------------------------------------------------
r=$(new_repo i); base=$(git -C "$r" rev-parse HEAD)
out=$(run "$r" --base "$base" "$SKILL"); rc=$?
assert_eq "I empty range exits 0" "$rc" "0"
lines_checked=$(val "$out" LINES_CHECKED)
if [ -n "$lines_checked" ] && [ "$lines_checked" -gt 10 ] 2>/dev/null; then ok "I lines were checked ($lines_checked)"; else ko "I lines were checked" "LINES_CHECKED=$lines_checked"; fi

# --- J: unknown skill dir -----------------------------------------------------
out=$(run "$r" --base "$base" "a-plugin/skills/nope"); rc=$?
assert_eq "J unknown skill exits 1" "$rc" "1"
assert_has "J names skill_not_found" "$out" "TYPE=skill_not_found"

# --- K: structured-output contract -------------------------------------------
if printf '%s\n' "$fail_out" | bash "$contract" --validate - >/dev/null 2>&1; then ok "K failing output meets the contract"; else ko "K failing output meets the contract" "$(printf '%s\n' "$fail_out" | bash "$contract" --validate - 2>&1)"; fi
if printf '%s\n' "$pass_out" | bash "$contract" --validate - >/dev/null 2>&1; then ok "K passing output meets the contract"; else ko "K passing output meets the contract" "$(printf '%s\n' "$pass_out" | bash "$contract" --validate - 2>&1)"; fi

# --- L: workflow wiring ------------------------------------------------------
publish=$(awk '/- name: Publish split commits/{f=1} f&&/^  open-pr:/{exit} f' "$workflow")
check_line=$(grep -n 'check-split-content-preservation\.py' <<<"$publish" | head -1 | cut -d: -f1)
push_line=$(grep -n 'HEAD:refs/heads/' <<<"$publish" | head -1 | cut -d: -f1)
if [ -n "$check_line" ]; then ok "L the publish step runs the check"; else ko "L the publish step runs the check"; fi
if [ -n "$check_line" ] && [ -n "$push_line" ] && [ "$check_line" -lt "$push_line" ]; then ok "L the check runs before the branch is published"; else ko "L the check runs before the branch is published" "check line=$check_line push line=$push_line"; fi
assert_has "L the check compares against the pre-split HEAD" "$publish" '--base "$PRE_SHA"'

# --- M: usage errors ---------------------------------------------------------
run "$r" "$SKILL" >/dev/null; rc=$?
assert_eq "M missing --base exits 2" "$rc" "2"
run "$r" --base "$base" >/dev/null; rc=$?
assert_eq "M no skill dir exits 2" "$rc" "2"
run "$r" --base no-such-rev "$SKILL" >/dev/null; rc=$?
assert_eq "M unknown revision exits 2" "$rc" "2"

echo "PASSED=$pass FAILED=$fail"
[ "$fail" -eq 0 ]
