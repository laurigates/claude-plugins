#!/usr/bin/env bash
# shellcheck disable=SC2016
# SC2016 is the point, not a slip: the workflow fixtures below are single-quoted
# so `$VAR` and `$GITHUB_REPOSITORY` reach the guard as LITERAL text. TEST H
# asserts exactly that a `--label "$VAR"` stays UNRESOLVED, which double quotes
# would expand away. File-level and ahead of the first command per
# .claude/rules/shell-scripting.md -- placed lower it degrades to a
# next-statement directive.
# Regression test for scripts/check-workflow-labels.sh.
#
# The bug this guards: `gh issue create --label "<unknown>"` exits 1 with
# `could not add label: '<x>' not found`, on the LAST line of a job, after all
# the real work succeeded. Three scheduled audits ran red for up to five months
# on exactly this (scheduled-audits 0/6 since 2026-03-01, fleet-drift 0/3,
# workflow-model-audit 0/6) because six labels were never created.
#
# The load-bearing cases are B and F: B replays the real failing shape (a create
# with an unprovisioned label) and requires the guard to flag it; F replays it
# with the backslash continuations every real call site actually uses. Without
# those two, every "clean" assertion here would also pass against a guard that
# parses nothing.
#
# Cases K-M cover the second way a label step kills a job: it EXISTS but 422s.
# `color: 5319e7` unquoted resolves as a YAML 1.2 float (-> 53190000000), so
# `gh label create` rejects it and -- because the label step runs FIRST -- every
# later step is skipped and the audit never runs (observed 2026-09-01 on
# scheduled-audits.yml's docs-index job). L is the load-bearing counter-case:
# the SAME token inside a `run:` block is correct, because a block scalar is
# never number-resolved, and flagging it would report the working call site in
# golden-set-evaluation.yml as a defect.
#
# Cases D and E pin the read/create distinction that an earlier revision got
# wrong: `gh issue list --label <unknown>` returns empty and exits 0 (harmless),
# and prose like "omit the --label flag" is not a call site at all. Counting
# either produced false positives that would have made the guard unusable.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-workflow-labels.sh"

pass_count=0
fail_count=0

assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

is_true() { [ "$1" = "true" ] && echo true || echo false; }
contains() { printf '%s' "$1" | grep -q -- "$2" && echo true || echo false; }

fx="$(mktemp -d)"
[ -n "$fx" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fx"' EXIT

# mkwf <name> <body> -- build a throwaway repo containing one workflow.
mkwf() {
  local dir="$fx/$1"
  mkdir -p "$dir/.github/workflows"
  printf '%s\n' "$2" > "$dir/.github/workflows/w.yml"
  printf '%s' "$dir"
}

# --- TEST A: the real repo -----------------------------------------------------
echo "=== TEST A: real repo has every attached label provisioned ==="
out="$(bash "$checker" 2>&1)"; rc=$?
assert "real repo exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "real repo STATUS=OK" "$(contains "$out" 'STATUS=OK')"
# Guard integrity: a checker that inspected nothing would also print STATUS=OK.
assert "real repo scanned a non-zero number of workflows" \
  "$([ "$(contains "$out" 'WORKFLOWS_SCANNED=0')" = false ] && echo true || echo false)"
assert "real repo is not marked SCANNED_EMPTY" "$(contains "$out" 'SCANNED_EMPTY=false')"
assert "real repo found real attach sites" \
  "$([ "$(contains "$out" 'ATTACH_SITES=0')" = false ] && echo true || echo false)"
assert "real repo INVALID_COLOR_COUNT=0" "$(contains "$out" 'INVALID_COLOR_COUNT=0')"
# Without this, every "colour is fine" assertion below would also hold for a
# checker that never looked at a colour.
assert "real repo inspected real colour sites" \
  "$([ "$(contains "$out" 'COLOR_SITES=0')" = false ] && echo true || echo false)"

# --- TEST B: an unprovisioned label is flagged (the real failure) --------------
echo "=== TEST B: create with an unprovisioned label FAILS ==="
d="$(mkwf b 'on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: gh issue create --title x --label "blueprint-health,maintenance"')"
out="$(bash "$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "B exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "B STATUS=FAIL" "$(contains "$out" 'STATUS=FAIL')"
assert "B names the missing label" "$(contains "$out" 'LABEL=blueprint-health')"
assert "B does not flag the allowlisted co-label" \
  "$([ "$(contains "$out" 'LABEL=maintenance')" = false ] && echo true || echo false)"
assert "B emits the remedy" "$(contains "$out" 'gh label create')"

# --- TEST C: provisioning in the same workflow clears it ----------------------
echo "=== TEST C: an in-workflow gh label create clears the finding ==="
d="$(mkwf c 'on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: gh label create blueprint-health --color 0E8A16 --force
      - run: gh issue create --title x --label "blueprint-health,maintenance"')"
out="$(bash "$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "C exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "C STATUS=OK" "$(contains "$out" 'STATUS=OK')"

# --- TEST D: a LIST is not a create (read/create scoping) ---------------------
echo "=== TEST D: gh issue list --label <unknown> is not flagged ==="
d="$(mkwf d 'on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: EXISTING=$(gh issue list --label "never-created" --state open --json number --jq length)')"
out="$(bash "$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "D exits 0 (list on an unknown label exits 0 in gh too)" \
  "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "D records zero attach sites" "$(contains "$out" 'ATTACH_SITES=0')"

# --- TEST E: prose mentioning --label is not a call site ----------------------
echo "=== TEST E: prose is not parsed as a label ==="
d="$(mkwf e 'on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo "read-only gh tools (e.g. gh issue list --label LABEL, gh pr list)"
          echo "Note: If the labels do not exist, omit the --label flag."')"
out="$(bash "$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "E exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "E does not invent a label named LABEL" \
  "$([ "$(contains "$out" 'LABEL=LABEL')" = false ] && echo true || echo false)"
assert "E does not invent a label named flag" \
  "$([ "$(contains "$out" 'LABEL=flag')" = false ] && echo true || echo false)"

# --- TEST F: backslash continuations are folded (the real call shape) ---------
echo "=== TEST F: --label on a continued line is still attributed to the create ==="
d="$(mkwf f 'on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: |
          gh issue create \
            --title "Monthly audit" \
            --body-file /tmp/body.md \
            --label "fleet-drift,maintenance"')"
out="$(bash "$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "F exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "F names the continued-line label" "$(contains "$out" 'LABEL=fleet-drift')"

# --- TEST G: the allowlist is honored, and is newline-separated ---------------
echo "=== TEST G: allowlist honored; entries may contain spaces ==="
d="$(mkwf g 'on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: gh issue create --title x --label "autorelease: pending"')"
out="$(CHECK_WORKFLOW_LABELS_ALLOWLIST='autorelease: pending' bash "$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "G exits 0 with a space-containing allowlist entry" \
  "$(is_true "$([ $rc -eq 0 ] && echo true)")"
# The same label must FAIL when the allowlist does not carry it -- otherwise G
# would pass against a guard that allowlists everything.
out="$(CHECK_WORKFLOW_LABELS_ALLOWLIST='something-else' bash "$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "G fails when the entry is absent from the allowlist" \
  "$(is_true "$([ $rc -eq 1 ] && echo true)")"

# --- TEST H: an unresolvable value is reported, and gated by --strict ---------
echo "=== TEST H: --label \"\$VAR\" is UNRESOLVED, fatal only under --strict ==="
d="$(mkwf h 'on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: gh issue create --title x --label "$LABEL_NAME"')"
out="$(bash "$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "H exits 0 without --strict" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "H counts the unresolved value" "$(contains "$out" 'UNRESOLVED_COUNT=1')"
out="$(bash "$checker" --strict --project-dir "$d" 2>&1)"; rc=$?
assert "H exits 1 under --strict" "$(is_true "$([ $rc -eq 1 ] && echo true)")"

# --- TEST I: an unknown argument is rejected, never swallowed ----------------
echo "=== TEST I: unknown argument exits 2 ==="
out="$(bash "$checker" --not-a-real-flag 2>&1)"; rc=$?
assert "I exits 2" "$(is_true "$([ $rc -eq 2 ] && echo true)")"
assert "I names the offending flag" "$(contains "$out" 'unknown argument')"

# --- TEST J: explicit file arguments (pre-commit style) ----------------------
echo "=== TEST J: explicit file arguments scope the scan ==="
d="$(mkwf j 'on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: gh issue create --title x --label "docs-index"')"
out="$(bash "$checker" --project-dir "$d" -- "$d/.github/workflows/w.yml" 2>&1)"; rc=$?
assert "J exits 1 on the named file" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "J scanned exactly one workflow" "$(contains "$out" 'WORKFLOWS_SCANNED=1')"

# --- TEST K: an unquoted colour that YAML resolves as a number is flagged -----
# The verbatim shape that broke scheduled-audits.yml on 2026-09-01.
echo "=== TEST K: unquoted color: 5319e7 in a with: block FAILS ==="
d="$(mkwf k 'on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - uses: ./.github/actions/script-to-issue
        with:
          label: docs-index
          color: 5319e7')"
out="$(bash "$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "K exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "K reports one invalid colour" "$(contains "$out" 'INVALID_COLOR_COUNT=1')"
assert "K names the file and line" "$(contains "$out" 'INVALID_COLOR=.github/workflows/w.yml:9')"
# The rendered number is the evidence: it is what GitHub answered 422 to, and it
# is the half a reader cannot reconstruct from the source text alone.
assert "K reports what gh would actually receive" "$(contains "$out" 'SENT=53190000000')"
assert "K reports the source spelling" "$(contains "$out" 'SOURCE=5319e7')"

# --- TEST L: the SAME token inside a run: block is correct -------------------
# Counter-case. A block scalar is opaque to the resolver, so gh receives the
# literal text. This is golden-set-evaluation.yml's shape and it works.
echo "=== TEST L: --color 5319e7 inside a run: block is NOT flagged ==="
d="$(mkwf l 'on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - name: Ensure the label exists
        run: |
          gh label create golden-set-eval \
            --repo "$GITHUB_REPOSITORY" \
            --color 5319e7 \
            --description "tier-2 sweep"
      - run: gh issue create --title x --label "golden-set-eval"')"
out="$(bash "$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "L exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "L flags no colour" "$(contains "$out" 'INVALID_COLOR_COUNT=0')"
# Non-vacuity: L must actually have inspected that colour, not skipped the file.
assert "L still counted the colour site" "$(contains "$out" 'COLOR_SITES=1')"

# --- TEST M: the resolver's edges, both polarities ---------------------------
# Each row is one scalar shape. The invalid ones are the coercion classes; the
# valid ones stop the fix degrading into "flag every colour".
echo "=== TEST M: colour resolution edges ==="
m_case() { # m_case <label> <raw> <expect-flagged> [expected-sent]
  local d out rc
  d="$(mkwf "m_$1" "on: push
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - uses: ./.github/actions/script-to-issue
        with:
          label: x
          color: $2")"
  out="$(bash "$checker" --project-dir "$d" 2>&1)"; rc=$?
  if [ "$3" = "flagged" ]; then
    assert "M $1 ($2) is flagged" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
    [ -n "${4:-}" ] && assert "M $1 sends $4" "$(contains "$out" "SENT=$4")"
  else
    assert "M $1 ($2) is not flagged" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
    assert "M $1 was still inspected" "$(contains "$out" 'COLOR_SITES=1')"
  fi
}
# Quoting is the remedy, so the quoted form must be accepted.
m_case quoted '"5319e7"' clean
# Leading zeros collapse under the integer rule: 000000 (black) -> 0.
m_case black '000000' flagged '0'
m_case leadzero '002200' flagged '2200'
# A hex letter outside [0-9e] makes the scalar unresolvable -> stays a string.
m_case letters '0e8a16' clean
# Resolves to an int but restringifies identically, so gh gets a valid colour.
# Flagging this would be a false positive on a config that works.
m_case alldigits '123456' clean
m_case garbage 'zzzzzz' flagged

echo ""
echo "=== RESULTS ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
