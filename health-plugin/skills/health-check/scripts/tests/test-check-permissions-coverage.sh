#!/usr/bin/env bash
# shellcheck disable=SC2015 # `cmd && pass || fail` is the deliberate assertion idiom here
# Tests for check-permissions-coverage.sh (health-check 1d).
# The 1d check used to be prose that matched only the legacy `Bash(<tool>:*)`
# rule form, so a project whose rules use the `Bash(<tool> *)` form this repo
# teaches read every tool as MISSING. The script must accept both forms plus
# bare `Bash` / `Bash(*)`, read user, project and project-local settings, scan
# justfile/Makefile/.pre-commit-config.yaml, and keep the OK (0) / WARN (1-3) /
# ERROR (4+) thresholds.
#
# Accuracy repairs (cases J-M), each failing against the first version:
#   J  ~/.claude/settings.local.json was read as coverage for every project,
#      though Claude Code reads it only in a session started in the home
#      directory (permissions docs, "When your local settings file needs trust").
#   K  every leading VAR=value was dropped before matching, though the docs say
#      an allow rule does not match past an assignment other than the
#      known-safe ones (only NODE_ENV is named).
#   L  words inside multi-line quoted strings, here-documents and `x=$(...)`
#      substitutions were read as tools, so a real justfile reported dozens of
#      MISSING rows (undo, try, add, last) and STATUS=ERROR.
#   M  under macOS /bin/bash 3.2 the script stopped at `declare -A` with no
#      STATUS line and exit 0.
# Tool stubs on PATH make the run independent of what the host has installed.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# CHECK_PERMISSIONS_COVERAGE_SCRIPT runs the suite against another copy.
check_script="${CHECK_PERMISSIONS_COVERAGE_SCRIPT:-${script_dir}/../check-permissions-coverage.sh}"
repo_root="$(cd "${script_dir}/../../../../.." && pwd)"
contract_script="${repo_root}/scripts/check-structured-output-contract.sh"

pass_count=0
fail_count=0
pass() { echo "PASS: $1"; pass_count=$((pass_count + 1)); }
fail() { printf 'FAIL: %b\n' "$1" >&2; fail_count=$((fail_count + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run check-permissions-coverage tests"
  exit 0
fi
[ -f "$check_script" ] || { echo "FAIL: $check_script not found" >&2; exit 1; }

tmp_root="$(mktemp -d)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
  echo "FAIL: mktemp -d returned no directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp_root"' EXIT

# Stub executables for every tool the fixtures run, so "on PATH" never depends
# on the host (the script reports a first word that resolves to nothing as
# unresolved, not missing).
stub_bin="${tmp_root}/stub-bin"
mkdir -p "$stub_bin"
# (no jq stub: the script reads settings with the real jq)
for stub_tool in just ruff npm pytest cargo go shfmt terraform gh; do
  printf '#!/bin/sh\nexit 0\n' > "${stub_bin}/${stub_tool}"
  chmod +x "${stub_bin}/${stub_tool}"
done
[ -x "${stub_bin}/cargo" ] || { echo "FAIL: stub tools are not executable" >&2; exit 1; }

# new_case <name>: fresh home + project dirs, echoes the case root.
new_case() {
  mkdir -p "${tmp_root}/$1/home/.claude" "${tmp_root}/$1/proj/.claude"
  printf '%s' "${tmp_root}/$1"
}

# allow_rules <settings-file> <rule>...: write permissions.allow.
allow_rules() {
  local target="$1"; shift
  jq -n '{permissions: {allow: $ARGS.positional}}' --args "$@" > "$target"
}

run_check() {
  PATH="${stub_bin}:${PATH}" bash "$check_script" --home-dir "$1/home" --project-dir "$1/proj" "${@:2}"
}

validate_contract() {
  # $1 = label, $2 = captured output
  [ -f "$contract_script" ] || return 0
  local verdict
  if verdict=$(bash "$contract_script" --validate - <<<"$2" 2>&1); then
    pass "$1: output satisfies the structured-output contract"
  else
    fail "$1: contract --validate rejected the output:\n$verdict\n$2"
  fi
}

JUSTFILE_BODY=$'default:\n    @just --list\n\nlint:\n    ruff check .\n    npm run lint\n\ntest:\n    -pytest -x\n    cargo test && echo done\n'

# --- Case A: space-wildcard rules (the form this repo teaches) -> OK
c="$(new_case a)"
printf '%s' "$JUSTFILE_BODY" > "$c/proj/justfile"
allow_rules "$c/proj/.claude/settings.json" "Bash(just *)" "Bash(ruff *)" "Bash(npm run *)" "Bash(pytest *)" "Bash(cargo test *)"
out="$(run_check "$c")"; rc=$?
[ "$rc" -eq 0 ] && grep -q '^STATUS=OK$' <<<"$out" && grep -q '^TOOLS_MISSING=0$' <<<"$out" \
  && pass "space-wildcard rules cover every justfile tool" \
  || fail "case A expected STATUS=OK, TOOLS_MISSING=0, exit 0 (rc=$rc):\n$out"
grep -q '^=== PERMISSIONS COVERAGE ===$' <<<"$out" && grep -q '^=== END PERMISSIONS COVERAGE ===$' <<<"$out" \
  && pass "section header and footer present" || fail "case A missing section delimiters:\n$out"
grep -q '^REASON=' <<<"$out" && fail "case A emitted REASON= on OK:\n$out" || pass "no REASON= on OK"
validate_contract "case A" "$out"

# --- Case B: legacy colon-wildcard rules -> OK (the old prose's only form)
c="$(new_case b)"
printf '%s' "$JUSTFILE_BODY" > "$c/proj/justfile"
allow_rules "$c/proj/.claude/settings.json" "Bash(just:*)" "Bash(ruff:*)" "Bash(npm run:*)" "Bash(pytest:*)" "Bash(cargo test:*)"
out="$(run_check "$c")"
grep -q '^STATUS=OK$' <<<"$out" && pass "legacy :* rules are accepted" \
  || fail "case B expected STATUS=OK:\n$out"

# --- Case C: one tool missing -> WARN naming it; rules split across user and
# project-local files are both read.
c="$(new_case c)"
printf '%s' "$JUSTFILE_BODY" > "$c/proj/justfile"
allow_rules "$c/home/.claude/settings.json" "Bash(just *)" "Bash(ruff *)"
allow_rules "$c/proj/.claude/settings.local.json" "Bash(npm run *)" "Bash(pytest *)"
out="$(run_check "$c")"; rc=$?
[ "$rc" -eq 0 ] && grep -q '^STATUS=WARN$' <<<"$out" && grep -q '^ISSUE_COUNT=1$' <<<"$out" \
  && pass "one unmatched tool gives WARN with ISSUE_COUNT=1, exit 0" \
  || fail "case C expected WARN, ISSUE_COUNT=1, exit 0 (rc=$rc):\n$out"
grep -q 'SEVERITY=WARN TYPE=missing_permission TOOL=cargo FILE=justfile' <<<"$out" \
  && pass "the missing row names the tool and file" || fail "case C expected a cargo row:\n$out"
grep -q '^REASON=missing_permission: .*cargo test' <<<"$out" \
  && pass "REASON names the first missing command" || fail "case C REASON wrong:\n$out"
validate_contract "case C" "$out"

# --- Case D: a subcommand rule does not cover another subcommand
c="$(new_case d)"
printf 'build:\n    npm install\n' > "$c/proj/justfile"
allow_rules "$c/proj/.claude/settings.json" "Bash(npm run *)"
out="$(run_check "$c")"
grep -q 'TOOL=npm .*npm install' <<<"$out" && pass "Bash(npm run *) does not cover npm install" \
  || fail "case D expected npm install to be missing:\n$out"

# --- Case E: no settings at all -> every tool missing; 4+ -> ERROR, exit 1
c="$(new_case e)"
printf '%s' "$JUSTFILE_BODY" > "$c/proj/justfile"
out="$(run_check "$c")"; rc=$?
[ "$rc" -eq 1 ] && grep -q '^STATUS=ERROR$' <<<"$out" && grep -q '^TOOLS_MISSING=5$' <<<"$out" \
  && grep -q '^ISSUE_COUNT=5$' <<<"$out" \
  && pass "no-settings project with 5 tools gives ERROR, exit 1" \
  || fail "case E expected ERROR, 5 missing, exit 1 (rc=$rc):\n$out"
grep -q '^PROJECT_SETTINGS=MISSING$' <<<"$out" && pass "missing project settings reported" \
  || fail "case E expected PROJECT_SETTINGS=MISSING:\n$out"
grep -q '^REASON=.* (+4 more)$' <<<"$out" && pass "REASON carries the (+N more) tail" \
  || fail "case E expected (+4 more):\n$out"
validate_contract "case E" "$out"

# --- Case F: empty project -> OK, nothing scanned
c="$(new_case f)"
out="$(run_check "$c")"; rc=$?
[ "$rc" -eq 0 ] && grep -q '^STATUS=OK$' <<<"$out" && grep -q '^SCANNED_FILES=none$' <<<"$out" \
  && grep -q '^TOOLS_FOUND=0$' <<<"$out" \
  && pass "empty project is OK with SCANNED_FILES=none" \
  || fail "case F expected OK/none/0 (rc=$rc):\n$out"

# --- Case G: bare Bash and Bash(*) cover everything
for grant in "Bash" "Bash(*)"; do
  c="$(new_case "g-${grant//[^A-Za-z]/}")"
  printf '%s' "$JUSTFILE_BODY" > "$c/proj/justfile"
  allow_rules "$c/proj/.claude/settings.json" "$grant"
  out="$(run_check "$c")"
  grep -q '^STATUS=OK$' <<<"$out" && grep -q '^BASH_ALLOW_ALL=true$' <<<"$out" \
    && pass "'$grant' covers every tool" || fail "case G ($grant) expected OK:\n$out"
done

# --- Case H: Makefile TAB recipes and pre-commit entry: values are scanned;
# read-only commands and wrappers are handled.
c="$(new_case h)"
printf 'all:\n\t@echo building\n\ttimeout 60 go build ./...\n\n.PHONY: all\n' > "$c/proj/Makefile"
printf 'repos:\n  - repo: local\n    hooks:\n      - id: fmt\n        entry: "shfmt -d"\n        language: system\n' > "$c/proj/.pre-commit-config.yaml"
allow_rules "$c/proj/.claude/settings.json" "Bash(go build *)"
out="$(run_check "$c" --verbose)"
grep -q '^SCANNED_FILES=Makefile,.pre-commit-config.yaml$' <<<"$out" \
  && pass "Makefile and pre-commit config are scanned" || fail "case H SCANNED_FILES wrong:\n$out"
grep -q '^TOOL=go STATE=covered$' <<<"$out" \
  && pass "timeout wrapper is stripped before matching" || fail "case H go not covered:\n$out"
grep -q 'TOOL=shfmt FILE=.pre-commit-config.yaml' <<<"$out" \
  && pass "pre-commit entry tool reported missing" || fail "case H shfmt not reported:\n$out"
grep -q 'TOOL=echo' <<<"$out" && fail "case H counted read-only echo:\n$out" \
  || pass "read-only echo is not counted"

# --- Case I: unused project rule is informational only
c="$(new_case i)"
printf 'lint:\n    ruff check .\n' > "$c/proj/justfile"
allow_rules "$c/proj/.claude/settings.json" "Bash(ruff *)" "Bash(terraform plan *)"
out="$(run_check "$c" --verbose)"
grep -q '^STATUS=OK$' <<<"$out" && grep -q '^UNUSED_RULE_COUNT=1$' <<<"$out" \
  && grep -q '^UNUSED_RULE=Bash(terraform plan \*)$' <<<"$out" \
  && pass "unused project rule listed without changing STATUS" \
  || fail "case I expected OK with one UNUSED_RULE:\n$out"

# --- Case J: ~/.claude/settings.local.json covers only the home directory
c="$(new_case j)"
printf 'lint:\n    ruff check .\n' > "$c/proj/justfile"
allow_rules "$c/home/.claude/settings.local.json" "Bash(ruff *)"
out="$(run_check "$c")"
grep -q '^STATUS=WARN$' <<<"$out" && grep -q 'TYPE=missing_permission TOOL=ruff ' <<<"$out" \
  && pass "a rule only in ~/.claude/settings.local.json does not cover another project" \
  || fail "case J expected ruff missing for a non-home project:\n$out"
grep -q '^USER_LOCAL_SETTINGS=' <<<"$out" && fail "case J still reports USER_LOCAL_SETTINGS:\n$out" \
  || pass "no user-local settings row for a non-home project"
printf 'lint:\n    ruff check .\n' > "$c/home/justfile"
out="$(PATH="${stub_bin}:${PATH}" bash "$check_script" --home-dir "$c/home" --project-dir "$c/home")"
grep -q '^STATUS=OK$' <<<"$out" && grep -q '^PROJECT_LOCAL_SETTINGS=OK$' <<<"$out" \
  && pass "with the project at the home directory, its local file is read" \
  || fail "case J (home project) expected OK:\n$out"

# --- Case K: only a documented safe assignment is stripped before matching
c="$(new_case k)"
printf 'test:\n    NODE_ENV=test npm test\n    CGO_ENABLED=0 go build ./...\n' > "$c/proj/justfile"
allow_rules "$c/proj/.claude/settings.json" "Bash(npm test *)" "Bash(go build *)"
out="$(run_check "$c" --verbose)"
grep -q '^TOOL=npm STATE=covered$' <<<"$out" \
  && pass "NODE_ENV=test npm test matches Bash(npm test *)" || fail "case K npm not covered:\n$out"
grep -q 'TYPE=missing_permission TOOL=go .*: CGO_ENABLED=0 go build' <<<"$out" \
  && pass "an allow rule does not match past another assignment" \
  || fail "case K expected CGO_ENABLED=0 go build to be missing:\n$out"

# --- Case L: quoted multi-line strings, here-documents, comments and
# substitutions are not tools; an unknown first word is unresolved, not missing
c="$(new_case l)"
cat > "$c/proj/justfile" <<'JUSTFILE'
check:
    jq -r '
      .[] | last
    ' data.json
    echo "try: undo; then add or remove it"
    cat <<EOF > notes.txt
    install foo; remove bar
    EOF
    prs=$(gh pr list --json number --jq '.[].number')
    ruff check . # then install; deploy
    notarealtool-xyz --flag
JUSTFILE
allow_rules "$c/proj/.claude/settings.json" "Bash(jq *)" "Bash(ruff *)"
out="$(run_check "$c" --verbose)"; rc=$?
[ "$rc" -eq 0 ] && grep -q '^STATUS=OK$' <<<"$out" && grep -q '^TOOLS_MISSING=0$' <<<"$out" \
  && pass "string, heredoc, comment and substitution words are not reported" \
  || fail "case L expected STATUS=OK, TOOLS_MISSING=0 (rc=$rc):\n$out"
noise_hits=""
for noise_word in last undo 'then' add remove install pr deploy; do
  grep -qE "(^TOOL|TOOL)=${noise_word} " <<<"$out" && noise_hits+="${noise_word} "
done
[ -z "$noise_hits" ] && pass "no TOOL= row for any noise word" \
  || fail "case L reported noise words: ${noise_hits}\n$out"
grep -q '^TOOLS_UNRESOLVED=1$' <<<"$out" && grep -q '^TOOL=notarealtool-xyz STATE=unresolved FILE=justfile$' <<<"$out" \
  && pass "an unknown first word is listed as unresolved, outside STATUS" \
  || fail "case L expected one unresolved row:\n$out"
validate_contract "case L" "$out"

# --- Case M: bash older than 4 fails loudly instead of exiting 0 mid-run
old_bash=""
for candidate in /bin/bash /usr/bin/bash; do
  # shellcheck disable=SC2016 # the candidate shell expands it, not this one
  if [ -x "$candidate" ] && [ "$("$candidate" -c 'echo "${BASH_VERSINFO[0]}"')" -lt 4 ]; then
    old_bash="$candidate"; break
  fi
done
if [ -n "$old_bash" ]; then
  c="$(new_case m)"
  printf '%s' "$JUSTFILE_BODY" > "$c/proj/justfile"
  out="$(PATH="${stub_bin}:${PATH}" "$old_bash" "$check_script" --home-dir "$c/home" --project-dir "$c/proj")"; rc=$?
  [ "$rc" -eq 1 ] && grep -q '^STATUS=ERROR$' <<<"$out" && grep -q 'TYPE=bash_too_old' <<<"$out" \
    && pass "bash < 4 gives STATUS=ERROR TYPE=bash_too_old, exit 1" \
    || fail "case M expected bash_too_old ERROR, exit 1 (rc=$rc):\n$out"
  validate_contract "case M" "$out"
else
  echo "SKIP: case M needs a bash older than 4 (none at /bin/bash or /usr/bin/bash)"
fi

echo "PASSED=${pass_count} FAILED=${fail_count}"
[ "$fail_count" -eq 0 ]
