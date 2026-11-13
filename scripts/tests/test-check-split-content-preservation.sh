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
# above") and whose pointer, and nothing else, was replaced by a new markdown
# link, which is what the splitter prompt tells the model to do. A line that
# merely contains a direction word ("Requires Node 18 or later") gets no
# tolerance for a change of content, however textually close the new line is.
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
#   L. the workflow runs the pre-split revision's copy of the check, isolated
#      (python3 -I), against $PRE_SHA, before it publishes; and the required
#      compliance job lists this test in its always-on --only set
#   M. a missing --base or skill dir is a usage error (exit 2)
#   N. a content change in a line with a direction word is ERROR, including a
#      change that also adds a link (number, negation, adjective, dropped or
#      added qualifier)
#   O. a direction-word line replaced by a dissimilar line is ERROR
#   P. one added line cannot account for two rewrites (COUNT=1 left over)
#   Q. the pointer rewrites the prompt asks for (anchor, file link, link text
#      reusing the line's own words) are OK and counted
#   R. a pointer dropped with no link in its place is ERROR
#
# SKILL_SPLITTER_WORKFLOW overrides the workflow under test, so L can be shown
# red against the pre-#3016 file. PLUGIN_PR_CHECKS_WORKFLOW does the same for
# the always-on compliance list that must run this test.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
check="$repo_root/scripts/check-split-content-preservation.py"
contract="$repo_root/scripts/check-structured-output-contract.sh"
workflow="${SKILL_SPLITTER_WORKFLOW:-$repo_root/.github/workflows/skill-splitter.yml}"
pr_checks="${PLUGIN_PR_CHECKS_WORKFLOW:-$repo_root/.github/workflows/plugin-pr-checks.yml}"

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

# rewrite_probe <name> <base line> <head line> [<head line 2>]: a repo whose
# base SKILL.md ends with <base line>, then a head where that appended line is
# replaced by the head line(s). Literal replacement, so no sed escaping is
# involved. PROBE_DROP_EARLIER=1 also deletes earlier copies of <base line>.
rewrite_probe() {
  local r base_line="$2"
  r=$(new_repo "$1")
  printf '\n%s\n' "$base_line" >> "$r/$SKILL/SKILL.md"
  git -C "$r" add -A && git -C "$r" commit -q -m "probe base"
  shift 2
  python3 - "$r/$SKILL/SKILL.md" "$base_line" "$@" <<'PY'
import os, sys
p, old, *new = sys.argv[1:]
text = open(p, encoding="utf-8").read()
head, sep, tail = text.rpartition("\n" + old + "\n")
assert sep, old
if os.environ.get("PROBE_DROP_EARLIER") == "1":
    head = "\n".join(l for l in head.split("\n") if l != old)
open(p, "w", encoding="utf-8").write(head + "\n" + "".join(n + "\n" for n in new) + tail)
PY
  commit "$r"
  printf '%s\n' "$r"
}

# --- N: a content change inside a line that carries a direction word ---------
# DIRECTION_RE matches common words (later, here, following). The rewrite
# tolerance must not let a change of meaning through just because the changed
# line contains one of them and the new line is textually close.
n=0
while IFS='|' read -r before after; do
  n=$((n + 1))
  r=$(rewrite_probe "n$n" "$before" "$after")
  out=$(run "$r" --base "$(git -C "$r" rev-parse HEAD~1)" "$SKILL"); rc=$?
  assert_eq "N$n content change exits 1: $before" "$rc" "1"
  assert_has "N$n names the original line" "$out" "MSG=$before"
  assert_eq "N$n nothing counted as rewritten" "$(val "$out" LINES_REWRITTEN)" "0"
done <<'CASES'
Requires Node 18 or later.|Requires Node 16 or later.
Never run `deploy --force` here in production.|Always run `deploy --force` here in production.
The following flags are mandatory.|The following flags are optional.
Requires Node 18 or later.|Requires Node 16 or [later](#later).
Use the flags below only on a scratch tree.|Use the [flags](#flags) on a scratch tree.
Pin the version shown above before you deploy.|Pin the version shown in [Versions](#versions) only before you deploy.
CASES

# --- O: a direction-word line replaced by a dissimilar line ------------------
r=$(rewrite_probe o "Pin the version shown above before you deploy." "Deploying is optional.")
out=$(run "$r" --base "$(git -C "$r" rev-parse HEAD~1)" "$SKILL"); rc=$?
assert_eq "O dissimilar replacement exits 1" "$rc" "1"
assert_has "O names the original line" "$out" "MSG=Pin the version shown above before you deploy."

# --- P: one added line cannot account for two rewrites -----------------------
# The base carries the pointer line twice (once from new_repo, once appended);
# the head rewrites it once and drops the other copy.
r=$(PROBE_DROP_EARLIER=1 rewrite_probe p "See the table above for every flag." "See the [Full flag reference](#full-flag-reference) table for every flag.")
out=$(run "$r" --base "$(git -C "$r" rev-parse HEAD~1)" "$SKILL"); rc=$?
assert_eq "P two rewrites into one added line exits 1" "$rc" "1"
assert_has "P reports the unabsorbed copy" "$out" "COUNT=1 MSG=See the table above for every flag."
assert_eq "P exactly one rewrite counted" "$(val "$out" LINES_REWRITTEN)" "1"

# --- Q: pointer rewrites the splitter prompt asks for stay tolerated ---------
q=0
while IFS='|' read -r before after; do
  q=$((q + 1))
  r=$(rewrite_probe "q$q" "$before" "$after")
  out=$(run "$r" --base "$(git -C "$r" rev-parse HEAD~1)" "$SKILL"); rc=$?
  assert_eq "Q$q pointer rewrite exits 0: $after" "$rc" "0"
  assert_eq "Q$q counted as rewritten" "$(val "$out" LINES_REWRITTEN)" "1"
done <<'CASES'
See the Kill switches table above.|See the [Kill switches](#kill-switches) table.
The table below lists every exit code.|[references/exit-codes.md](references/exit-codes.md) lists every exit code.
Use the preceding section's flags (see above).|Use the [Flags](#flags) section's flags (see [Flags](#flags)).
The following flags are mandatory.|The [flags](#flags) are mandatory.
CASES

# --- R: a pointer dropped without a link in its place ------------------------
r=$(rewrite_probe r "Pin the version shown above before you deploy." "Pin the version shown before you deploy.")
out=$(run "$r" --base "$(git -C "$r" rev-parse HEAD~1)" "$SKILL"); rc=$?
assert_eq "R pointer dropped with no link exits 1" "$rc" "1"

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
# The split step can Write/Edit without committing, and the scope check reads
# only commits, so the working-tree checker is not trustworthy: run the copy
# from the pre-split revision, isolated from the working tree.
assert_has "L the checker is the pre-split revision's copy" "$publish" 'git show "$PRE_SHA:scripts/check-split-content-preservation.py" > "$checker"'
assert_has "L the extracted checker runs isolated" "$publish" 'python3 -I "$checker" --base "$PRE_SHA"'
if grep -qE 'python3( -[A-Za-z]+)* (\./)?scripts/check-split-content-preservation\.py' <<<"$publish"; then ko "L the working-tree checker is not run"; else ok "L the working-tree checker is not run"; fi
# Case L is the only guard on that wiring, and "Test: Skill scripts" has no
# .github/workflows/** path, so a PR editing only skill-splitter.yml would never
# run it unless the always-on compliance job lists it (as it does for the
# sibling test-select-split-candidates.sh).
assert_has "L the always-on compliance job runs this test" "$(cat "$pr_checks")" "--only 'scripts/tests/test-check-split-content-preservation.sh'"

# --- M: usage errors ---------------------------------------------------------
run "$r" "$SKILL" >/dev/null; rc=$?
assert_eq "M missing --base exits 2" "$rc" "2"
run "$r" --base "$base" >/dev/null; rc=$?
assert_eq "M no skill dir exits 2" "$rc" "2"
run "$r" --base no-such-rev "$SKILL" >/dev/null; rc=$?
assert_eq "M unknown revision exits 2" "$rc" "2"

echo "PASSED=$pass FAILED=$fail"
[ "$fail" -eq 0 ]
