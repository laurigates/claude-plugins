#!/usr/bin/env bash
# shellcheck disable=SC2015  # file-level: `[ -n ] && [ -d ] || die` is a guard, not if-then-else (must precede the first command)
# Regression test for the two false detectors in scripts/infra-compliance-check.sh (#2555).
#
# Both defects reported a CLEAN repo as non-compliant, or a non-compliant one as
# clean, and neither could be seen from the live corpus alone:
#
#   1. Security posture — the token pattern carried a bare `sk-` alternative (an
#      OpenAI key prefix) which matches the literal `task-`. Every hit in this
#      repo was a YAML COMMENT naming a taskwarrior path, a test script, or a
#      release tarball, in two workflows that reference no secret at all.
#
#   2. Filters — the check grepped the WHOLE file, comments included, so it
#      failed in both directions: a cron-only workflow whose prose mentions
#      `pull_request: closed` was flagged ⚠️, while a `pull_request` workflow
#      that deliberately has no `paths:` PASSED because its comments explaining
#      that decision contain the string `paths:`.
#
#      Making the TRIGGER read structural is only half of it: a `paths:` match
#      that is not scoped to the pull_request trigger itself is still satisfied
#      by a filter on a different trigger (fixture F) or by one inside a
#      `run: |` body (fixture G).
#
# A "zero findings on the live corpus" assertion passes vacuously if the
# detector is deleted, so every case below is fixture-driven and PAIRED: each
# negative control (must NOT fire) sits beside a positive control (must fire).
# That includes BOTH loose alternatives of the token regex — `sk-` and
# `Bearer ` — since deleting either one silently drops real detections.
#
# The trigger read has THREE reachable states, not two: `yq` present and
# usable, `yq` absent (the comment-stripped grep fallback), and `yq` PRESENT
# BUT FAILING — whose stderr the check discards, so a swallowed failure must
# not be mistaken for a `false` answer. Every filter case runs through all
# three.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
CHECK="$repo_root/scripts/infra-compliance-check.sh"

pass_count=0
fail_count=0

assert() {
  # assert <description> <condition-result-string "true"/"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

assert_eq() {
  # assert_eq <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    fail_count=$((fail_count + 1))
  fi
}

TMP_ROOT="$(mktemp -d)"
# Guard the sandbox root before anything writes into it: an empty value would
# make every later path absolute-from-root (scripts/check-git-sandbox-guards.sh).
[ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ] || { echo "FAIL: could not create sandbox" >&2; exit 1; }
trap 'rm -rf "$TMP_ROOT"' EXIT

# new_fixture <name> -> prints the fixture root, with .github/workflows/ created
new_fixture() {
  local dir="$TMP_ROOT/$1"
  mkdir -p "$dir/.github/workflows"
  printf '%s\n' "$dir"
}

# make_shim <dir> <name> -> prints a PATH dir carrying only the coreutils the
# script needs, so `yq` can be hidden or replaced without touching the rest of
# the environment.
make_shim() {
  local shim="$1/$2"
  mkdir -p "$shim"
  local t
  for t in bash grep sed awk find sort basename dirname jq bc wc tr date cat env; do
    if command -v "$t" >/dev/null 2>&1; then
      ln -sf "$(command -v "$t")" "$shim/$t" 2>/dev/null || true
    fi
  done
  printf '%s\n' "$shim"
}

# run_check <fixture-dir> [--no-yq|--broken-yq] -> prints the report; empty on
# non-zero exit.
#
# THREE branches, not two. `command -v yq` only proves a binary is on PATH:
# the mikefarah Go binary and the python-yq jq wrapper take different flags,
# and either can fail on a malformed workflow. A yq that is PRESENT but
# UNUSABLE must not read as "no pull_request trigger" (#2555 finding 6), so
# every filter case below runs on all three.
run_check() {
  local dir="$1" mode="${2:-}"
  case "$mode" in
    --no-yq)
      # Force the comment-stripping fallback branch by hiding yq behind an
      # empty PATH shim dir.
      local shim
      shim="$(make_shim "$dir" .no-yq-shim)"
      PATH="$shim" bash "$CHECK" --project-dir "$dir" 2>/dev/null
      ;;
    --broken-yq)
      # yq IS on PATH and its invocation fails — a different flavour's flag
      # parsing, or a workflow it cannot parse. Its stderr is what the check
      # discards with 2>/dev/null, which is precisely why a swallowed failure
      # must not be mistaken for a `false` answer.
      local shim
      shim="$(make_shim "$dir" .broken-yq-shim)"
      cat > "$shim/yq" <<'SHIM'
#!/usr/bin/env bash
echo "Error: unknown shorthand flag: 'r' in -r" >&2
exit 1
SHIM
      chmod +x "$shim/yq"
      PATH="$shim" bash "$CHECK" --project-dir "$dir" 2>/dev/null
      ;;
    *)
      bash "$CHECK" --project-dir "$dir" 2>/dev/null
      ;;
  esac
}

# filters_of <report> <workflow-file-name> -> the Filters cell, or the literal
# string ROW_MISSING when the workflow never reached the table at all.
filters_of() {
  local report="$1" name="$2" cell
  cell="$(printf '%s\n' "$report" \
    | awk -F'[[:space:]]*\\|[[:space:]]*' -v n="$name" '$2 == n { print $6; exit }')"
  if [ -z "$cell" ]; then
    printf 'ROW_MISSING\n'
  else
    printf '%s\n' "$cell"
  fi
}

# has_security_row <report> <workflow-file-name>
has_security_row() {
  printf '%s\n' "$1" | grep -qE '^\| (🔴|🟡) \| '"$2"' \|'
}

##########
# Security: the `sk-` false positive (#2555 finding 1)
##########

sec_neg="$(new_fixture security-negative)"
cat > "$sec_neg/.github/workflows/taskwarrior-refs.yml" <<'YAML'
name: "Task: refs"
# Reproduces the three real hits: every one is a YAML comment, and this file
# references no secret at all.
#   taskwarrior-plugin/skills/task-add/
#   scripts/tests/test-task-id-stability.sh
#   task-3.4.2.tar.gz
on:
  workflow_dispatch:
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: echo "task-list tools"
YAML

# The `Bearer ` half of the same length-anchored regex. Both shapes below
# matched the ORIGINAL `Bearer [A-Za-z0-9]` alternative and must not match the
# length-anchored one: an interpolated secret (the correct way to pass a token)
# and a short literal.
cat > "$sec_neg/.github/workflows/bearer-interpolated.yml" <<'YAML'
name: "Bearer: interpolated"
on:
  workflow_dispatch:
jobs:
  call:
    runs-on: ubuntu-latest
    steps:
      - run: |
          curl -H "Authorization: Bearer ${{ secrets.GITHUB_TOKEN }}" https://example.test/
          curl -H "Authorization: Bearer x" https://example.test/
YAML

report="$(run_check "$sec_neg")"
echo "=== security: task- is not a token ==="
assert "negative fixture reached the workflow table (guard integrity)" \
  "$([ "$(filters_of "$report" 'taskwarrior-refs.yml')" != "ROW_MISSING" ] && echo true || echo false)"
assert "a file whose only 'sk-' is inside 'task-' raises NO security row" \
  "$(has_security_row "$report" 'taskwarrior-refs.yml' && echo false || echo true)"
assert "an interpolated / short 'Bearer ' value raises NO security row" \
  "$(has_security_row "$report" 'bearer-interpolated.yml' && echo false || echo true)"
assert "negative fixture reports no security findings at all" \
  "$(printf '%s\n' "$report" | grep -q 'No security issues found.' && echo true || echo false)"

sec_pos="$(new_fixture security-positive)"
cat > "$sec_pos/.github/workflows/openai-key.yml" <<'YAML'
name: "Leak: openai"
on:
  workflow_dispatch:
jobs:
  leak:
    runs-on: ubuntu-latest
    steps:
      - run: echo "sk-abcdefghijklmnopqrstuvwxyz0123456789ABCD"
YAML
cat > "$sec_pos/.github/workflows/github-pat.yml" <<'YAML'
name: "Leak: pat"
on:
  workflow_dispatch:
jobs:
  leak:
    runs-on: ubuntu-latest
    steps:
      - run: echo "ghp_abcdefghijklmnopqrstuvwxyz0123456789"
YAML
# Positive control for the Bearer alternative. Deliberately carries NO other
# token shape (no `sk-`, no `ghp_`/`gho_`/`github_pat_`), so the row can only
# be attributed to `Bearer [A-Za-z0-9_.-]{20,}` — delete that alternative and
# this fixture goes quiet.
cat > "$sec_pos/.github/workflows/bearer-literal.yml" <<'YAML'
name: "Leak: bearer"
on:
  workflow_dispatch:
jobs:
  leak:
    runs-on: ubuntu-latest
    steps:
      - run: curl -H "Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123456789" https://example.test/
YAML

report="$(run_check "$sec_pos")"
echo "=== security: real token prefixes still fire (positive control) ==="
assert "a 40-char sk- token IS reported" \
  "$(has_security_row "$report" 'openai-key.yml' && echo true || echo false)"
assert "a ghp_ token IS reported" \
  "$(has_security_row "$report" 'github-pat.yml' && echo true || echo false)"
assert "a literal 'Bearer ' + 36 token chars IS reported" \
  "$(has_security_row "$report" 'bearer-literal.yml' && echo true || echo false)"

##########
# Filters: trigger-aware classification (#2555 finding 2)
##########

filters_fx="$(new_fixture filters)"

# A — a real pull_request trigger WITH a paths: filter.
cat > "$filters_fx/.github/workflows/a-filtered.yml" <<'YAML'
name: "A: filtered"
on:
  pull_request:
    paths:
      - 'src/**'
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: echo a
YAML

# B — a real pull_request trigger with NO paths: and no exemption marker.
cat > "$filters_fx/.github/workflows/b-unfiltered.yml" <<'YAML'
name: "B: unfiltered"
on:
  pull_request:
    types: [opened, synchronize]
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: echo b
YAML

# C — a real pull_request trigger with NO paths:, declared exempt.
cat > "$filters_fx/.github/workflows/c-exempt.yml" <<'YAML'
name: "C: exempt"
on:
  pull_request:
    # infra-compliance: paths-exempt (required check, #2258 — a path-filtered
    # workflow never reports its context)
    types: [opened, synchronize]
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: echo c
YAML

# D — cron only, whose COMMENTS mention BOTH `pull_request:` and `paths:`. Under
#     the grep-anywhere check this silently PASSED (✅) — the plugin-pr-checks.yml
#     false-negative shape, where the prose explaining the absence satisfied the
#     check.
cat > "$filters_fx/.github/workflows/d-cron-only.yml" <<'YAML'
name: "D: cron only"
# Deliberately a scheduled sweep rather than a `pull_request: closed` workflow.
# It structurally cannot carry a `paths:` filter.
on:
  schedule:
    - cron: '07 8 * * 1'
  workflow_dispatch:
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: echo d
YAML

# E — cron only, whose comment names `pull_request:` but NOT `paths:`. This is
#     the verbatim stranded-work-audit.yml shape, and the OTHER direction of the
#     same defect: the grep-anywhere check flagged it ⚠️ for a workflow that
#     structurally cannot carry a path filter.
cat > "$filters_fx/.github/workflows/e-cron-prose-only.yml" <<'YAML'
name: "E: cron, prose mentions the trigger"
# Deliberately a scheduled sweep rather than a `pull_request: closed` workflow.
on:
  schedule:
    - cron: '07 8 * * 1'
  workflow_dispatch:
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: echo e
YAML

# F — a real pull_request trigger with NO paths:, alongside a `push:` trigger
#     that DOES carry one, and no exemption marker. This is the shape the
#     trigger-aware rewrite still got wrong (#2555 finding 1): resolving the
#     TRIGGER structurally while matching `paths:` anywhere in the file leaves
#     the check satisfied by a filter belonging to a different trigger, so a
#     PR workflow with no path filter reads ✅. It is live in-repo —
#     validate-plugin-configs.yml has exactly this shape and reports N/A only
#     because of its paths-exempt marker.
cat > "$filters_fx/.github/workflows/f-split-paths.yml" <<'YAML'
name: "F: paths on the other trigger"
on:
  pull_request:
    types: [opened, synchronize]
  push:
    branches: [main]
    paths:
      - 'src/**'
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: echo f
YAML

# G — a real pull_request trigger with NO paths: anywhere in its `on:` block;
#     the only `paths:` in the file sits inside a `run: |` script body, which
#     the comment-stripped view keeps verbatim.
cat > "$filters_fx/.github/workflows/g-run-body-paths.yml" <<'YAML'
name: "G: paths inside a run body"
on:
  pull_request:
    types: [opened]
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: |
          cat > cfg.yml <<'CFG'
          paths:
            - 'src/**'
          CFG
          echo g
YAML

for branch in "" "--no-yq" "--broken-yq"; do
  case "$branch" in
    "")            label="yq" ;;
    "--no-yq")     label="fallback" ;;
    "--broken-yq") label="broken-yq" ;;
  esac
  report="$(run_check "$filters_fx" $branch)"
  echo "=== filters ($label) ==="

  assert_eq "[$label] A: pull_request + paths: -> ✅" \
    "✅" "$(filters_of "$report" 'a-filtered.yml')"
  assert_eq "[$label] B: pull_request, no paths:, no marker -> ⚠️" \
    "⚠️" "$(filters_of "$report" 'b-unfiltered.yml')"
  assert_eq "[$label] C: pull_request, no paths:, paths-exempt marker -> N/A" \
    "N/A" "$(filters_of "$report" 'c-exempt.yml')"
  assert_eq "[$label] D: cron-only whose COMMENTS name pull_request:/paths: -> N/A" \
    "N/A" "$(filters_of "$report" 'd-cron-only.yml')"
  assert_eq "[$label] E: cron-only whose comment names pull_request: only -> N/A" \
    "N/A" "$(filters_of "$report" 'e-cron-prose-only.yml')"
  assert_eq "[$label] F: pull_request without paths:, push WITH paths: -> ⚠️" \
    "⚠️" "$(filters_of "$report" 'f-split-paths.yml')"
  assert_eq "[$label] G: pull_request without paths:, paths: only in a run body -> ⚠️" \
    "⚠️" "$(filters_of "$report" 'g-run-body-paths.yml')"
done

##########
# --project-dir contract
##########

echo "=== --project-dir ==="
out="$(bash "$CHECK" --bogus-flag 2>/dev/null)"; rc=$?
assert_eq "an unknown argument exits 2" "2" "$rc"
assert "an unknown argument emits no report" \
  "$([ -z "$out" ] && echo true || echo false)"

bash "$CHECK" --project-dir "$TMP_ROOT/does-not-exist" >/dev/null 2>&1; rc=$?
assert_eq "--project-dir on a missing directory exits 2" "2" "$rc"

# The default (no-args) run must still produce a complete report and exit 0 —
# the contract scripts/tests/test-audit-scripts-exit.sh guards.
default_out="$(bash "$CHECK" 2>/dev/null)"; rc=$?
assert_eq "a default (repo-root) run still exits 0" "0" "$rc"
assert "a default run still emits the dashboard header" \
  "$(printf '%s\n' "$default_out" | grep -q 'Infrastructure Compliance Dashboard' && echo true || echo false)"

##########
# Checkout pin drift (the gate was inverted and half-blind)
##########
#
# It hardcoded `v4` as the good value. Every ref in this repo is `@v6`, so all
# 28 warned permanently, the report advised "update workflow action versions"
# on actions already at the newest major, and an actual DOWNGRADE to `@v4`
# scored a tick. `grep -m1` also read only the FIRST ref per file, so a stale
# pin in any later step was invisible.
#
# The replacement asks whether the repo's pins AGREE. The cases below pin both
# polarities, because "flag nothing" and "flag everything" both satisfy a
# one-sided test.

mk_ck() { # mk_ck <dir> <file> <ref>...
  local d="$1" f="$2"; shift 2
  mkdir -p "$d/.github/workflows"
  {
    printf 'name: t\non:\n  push:\njobs:\n  j:\n    runs-on: ubuntu-latest\n    steps:\n'
    for r in "$@"; do printf '      - uses: actions/checkout@%s\n' "$r"; done
  } > "$d/.github/workflows/$f"
}

# Row for a workflow in the rendered table: "| <file> | <checkout> | ... |"
ck_row() { printf '%s\n' "$1" | grep -E "^\| $2 \|" | head -1; }

# --- A uniform repo agrees with itself, whatever the version ----------------
# This is the case that proves the gate cannot rot: an all-v4 repo is as clean
# as an all-v6 one, because agreement is the property being measured.
ck_uni="$TMP_ROOT/ck-uniform"
mk_ck "$ck_uni" "a.yml" v4
mk_ck "$ck_uni" "b.yml" v4
out="$(bash "$CHECK" --project-dir "$ck_uni" 2>/dev/null)"
assert "a uniformly-v4 repo raises no checkout warning" \
  "$(printf '%s' "$(ck_row "$out" a.yml)" | grep -q '⚠️' && echo false || echo true)"
# Guard integrity: without this, the assertion above also holds for a run that
# rendered no table at all.
assert "the uniform fixture reached the workflow table" \
  "$([ -n "$(ck_row "$out" a.yml)" ] && echo true || echo false)"

ck_uni6="$TMP_ROOT/ck-uniform6"
mk_ck "$ck_uni6" "a.yml" v6
mk_ck "$ck_uni6" "b.yml" v6
out="$(bash "$CHECK" --project-dir "$ck_uni6" 2>/dev/null)"
assert "a uniformly-v6 repo raises no checkout warning" \
  "$(printf '%s' "$(ck_row "$out" a.yml)" | grep -q '⚠️' && echo false || echo true)"

# --- A laggard among agreeing siblings IS flagged ---------------------------
# The pre-fix gate scored this file ✅, since v4 was its hardcoded good value.
ck_lag="$TMP_ROOT/ck-laggard"
mk_ck "$ck_lag" "a.yml" v6
mk_ck "$ck_lag" "b.yml" v6
mk_ck "$ck_lag" "c.yml" v6
mk_ck "$ck_lag" "old.yml" v4
out="$(bash "$CHECK" --project-dir "$ck_lag" 2>/dev/null)"
assert "a lone v4 among v6 siblings IS flagged" \
  "$(printf '%s' "$(ck_row "$out" old.yml)" | grep -q '⚠️' && echo true || echo false)"
assert "its agreeing siblings are NOT flagged" \
  "$(printf '%s' "$(ck_row "$out" a.yml)" | grep -q '⚠️' && echo false || echo true)"

# --- Every ref is read, not just the first ----------------------------------
# `grep -m1` reported v6 and a tick while a v3 sat two lines below.
ck_mix="$TMP_ROOT/ck-mixed"
mk_ck "$ck_mix" "a.yml" v6
mk_ck "$ck_mix" "b.yml" v6
mk_ck "$ck_mix" "d-mixed.yml" v6 v3
out="$(bash "$CHECK" --project-dir "$ck_mix" 2>/dev/null)"
assert "a file pinning two different versions IS flagged" \
  "$(printf '%s' "$(ck_row "$out" d-mixed.yml)" | grep -q '⚠️' && echo true || echo false)"
assert "the later ref is reported, not swallowed by the first" \
  "$(printf '%s' "$(ck_row "$out" d-mixed.yml)" | grep -q 'v3' && echo true || echo false)"

# --- No checkout at all is N/A, not a finding -------------------------------
ck_none="$TMP_ROOT/ck-none"
mkdir -p "$ck_none/.github/workflows"
printf 'name: t\non:\n  push:\njobs:\n  j:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n' \
  > "$ck_none/.github/workflows/a.yml"
out="$(bash "$CHECK" --project-dir "$ck_none" 2>/dev/null)"; rc=$?
assert_eq "a repo with no checkout still exits 0" "0" "$rc"
assert "a workflow with no checkout reports N/A" \
  "$(printf '%s' "$(ck_row "$out" a.yml)" | grep -q 'N/A' && echo true || echo false)"
assert "a workflow with no checkout is not flagged" \
  "$(printf '%s' "$(ck_row "$out" a.yml)" | grep -q '⚠️' && echo false || echo true)"

# --- The real repo is uniform, so the column is clean -----------------------
assert "the real repo raises no checkout warning" \
  "$(printf '%s' "$default_out" | grep -E '^\| [a-z-]+\.yml \|' | awk -F'|' '{print $3}' | grep -q '⚠️' && echo false || echo true)"

##########
# Summary
##########

echo ""
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=ERROR"
  exit 1
fi
echo "STATUS=OK"
exit 0
