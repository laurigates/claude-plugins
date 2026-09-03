#!/usr/bin/env bash
# Regression test for scripts/check-dead-tool-grants.sh.
#
# The bug: LS, BashOutput, KillShell and MultiEdit were granted in 40 files'
# allowed-tools:/tools: frontmatter. None appears in the current tool docs
# (verified 2026-09-03 against https://code.claude.com/docs/en/tools, which
# lists 45 tools including their successors). Two ALWAYS-LOADED authoring rules
# were minting them, so the count grew with every skill written from them.
#
# The negative cases carry as much weight as the positives: this guard scans a
# corpus where the retired names are legitimately DISCUSSED (the rules that
# document the removal, this file, and the guard itself). A checker that flagged
# every mention would be unusable and switched off.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
CHECK="$repo_root/scripts/check-dead-tool-grants.sh"

pass=0; fail=0
assert() { if [ "$2" = "true" ]; then pass=$((pass+1)); else echo "FAIL: $1" >&2; fail=$((fail+1)); fi; }
has() { printf '%s' "$1" | grep -qF -- "$2" && echo true || echo false; }

fx="$(mktemp -d)"; [ -n "$fx" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fx"' EXIT

mkskill() { # mkskill <dir> <name> <grant-line>
  mkdir -p "$fx/$1/x-plugin/skills/$2"
  printf -- '---\nname: %s\ndescription: Use when testing.\n%s\n---\n\n# %s\n\nBody.\n' \
    "$2" "$3" "$2" > "$fx/$1/x-plugin/skills/$2/SKILL.md"
}

# --- A: the real repo is clean, and non-vacuously so -------------------------
echo "=== A: the swept repo is clean ==="
out="$(bash "$CHECK" 2>&1)"; rc=$?
assert "A exits 0" "$([ $rc -eq 0 ] && echo true || echo false)"
assert "A STATUS=OK" "$(has "$out" 'STATUS=OK')"
# Guard integrity: a checker that opened nothing would also print STATUS=OK.
assert "A is not SCANNED_EMPTY" "$(has "$out" 'SCANNED_EMPTY=false')"
assert "A read real grant lines" \
  "$([ "$(has "$out" 'GRANT_LINES=0')" = false ] && echo true || echo false)"

# --- B: each retired name IS caught in a grant -------------------------------
echo "=== B: a retired name in a grant is an ERROR ==="
for pair in "LS|Glob" "BashOutput|Bash" "KillShell|TaskStop" "MultiEdit|Edit"; do
  name="${pair%%|*}"; succ="${pair##*|}"
  d="b-$name"
  mkskill "$d" "s" "allowed-tools: Read, Grep, $name, Write"
  out="$(bash "$CHECK" --project-dir "$fx/$d" 2>&1)"; rc=$?
  assert "B $name exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
  assert "B $name is named" "$(has "$out" "TOOL=$name")"
  # The finding must carry the successor, or it is a puzzle rather than a fix.
  assert "B $name names its successor $succ" "$(has "$out" "FIX=$succ")"
done

# --- C: the verbatim pre-sweep shapes ---------------------------------------
# Real lines from the corpus before the sweep.
echo "=== C: the verbatim pre-sweep grant lines ==="
mkskill c-agent "s" "tools: Glob, Grep, LS, Read, Edit, Write, Bash(npm *), TodoWrite"
out="$(bash "$CHECK" --project-dir "$fx/c-agent" 2>&1)"
assert "C agent tools: line is caught" "$(has "$out" 'TOOL=LS')"
mkskill c-ts "s" "allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, BashOutput, KillShell"
out="$(bash "$CHECK" --project-dir "$fx/c-ts" 2>&1)"
assert "C both names on one line are caught" \
  "$([ "$(has "$out" 'TOOL=BashOutput')" = true ] && [ "$(has "$out" 'TOOL=KillShell')" = true ] && echo true || echo false)"
assert "C reports both, not just the first" "$(has "$out" 'ISSUE_COUNT=2')"

# --- D: NEGATIVE cases - discussion is not a grant ---------------------------
# Without these the guard would flag the rules that document the removal, this
# test, and its own header - and would be turned off within a day.
echo "=== D: prose and near-misses are NOT flagged ==="
mkdir -p "$fx/d/x-plugin/skills/s"
cat > "$fx/d/x-plugin/skills/s/SKILL.md" <<'MD'
---
name: s
description: Use when testing.
allowed-tools: Read, Glob, Bash, Edit
---

# s

`LS` was removed in favour of `Glob`, and MultiEdit no longer exists.
Do not grant BashOutput or KillShell.

| Tool | Status |
|------|--------|
| LS | retired |
MD
out="$(bash "$CHECK" --project-dir "$fx/d" 2>&1)"; rc=$?
assert "D prose mentions are not flagged" "$([ $rc -eq 0 ] && echo true || echo false)"
assert "D STATUS=OK on a discussing file" "$(has "$out" 'STATUS=OK')"
# Non-vacuity: that file must actually have been read.
assert "D the discussing file was scanned" \
  "$([ "$(has "$out" 'FILES_SCANNED=0')" = false ] && echo true || echo false)"

# Substring near-misses must not trip it: LSP and Skill are live tools.
mkskill d2 "s" "allowed-tools: Read, LSP, Skill, Glob"
out="$(bash "$CHECK" --project-dir "$fx/d2" 2>&1)"; rc=$?
assert "D LSP is not mistaken for LS" "$([ $rc -eq 0 ] && echo true || echo false)"

# --- E: a walk that opened nothing is an ERROR, never clean ------------------
echo "=== E: an empty scan is loud ==="
mkdir -p "$fx/empty"
out="$(bash "$CHECK" --project-dir "$fx/empty" 2>&1)"; rc=$?
assert "E exits 1 on an empty corpus" "$([ $rc -eq 1 ] && echo true || echo false)"
assert "E says nothing_scanned" "$(has "$out" 'nothing_scanned')"

# --- F: unknown argument exits 2 (#2057) ------------------------------------
echo "=== F: unknown argument exits 2 ==="
out="$(bash "$CHECK" --nope 2>&1)"; rc=$?
assert "F exits 2" "$([ $rc -eq 2 ] && echo true || echo false)"
assert "F names the flag" "$(has "$out" 'unknown argument')"

echo ""
echo "PASSED=$pass"
echo "FAILED=$fail"
[ "$fail" -gt 0 ] && { echo "STATUS=FAIL"; exit 1; }
echo "STATUS=OK"
