#!/usr/bin/env bash
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

echo ""
echo "=== RESULTS ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
