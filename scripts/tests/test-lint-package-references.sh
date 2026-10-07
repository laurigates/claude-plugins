#!/usr/bin/env bash
# shellcheck disable=SC2016  # file-level: backticked package names in the planted fixtures are literal markdown
# Regression test for scripts/lint-package-references.sh
#
# The linter is a denylist of package names that are not published under that
# name on their registry (the `@langchain/deep-agents` dependency-confusion
# hazard). It had no test of its own until its walk was widened to the
# `references/*.md` sidecars the 2026-10 split moved skill content into, so the
# widening is pinned here together with the rest of its contract:
#
#   DETECTION   — SKILL.md, REFERENCE.md, and a references/*.md sidecar
#   NARROWNESS  — a blockquote callout may cite the broken name; docs/ is not
#                 scanned; the real package name is clean
#   CWD         — the verdict does not depend on where the linter is invoked
#                 from (discovery once ran in a subshell that entered the repo
#                 root while the grep did not, so it opened no file — #2219)
#
# SEMANTIC, not syntactic: every case EXECUTES a copy of the real linter
# against a planted fixture tree and asserts on its exit code AND on the file it
# names, so a linter that fires for the wrong file cannot pass.
#
# Exit codes: 0 all assertions pass, 1 otherwise.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
linter="$repo_root/scripts/lint-package-references.sh"

pass=0
fail=0

ok() {
  printf '  PASS: %s\n' "$1"
  pass=$((pass + 1))
}

bad() {
  printf '  FAIL: %s\n' "$1"
  printf '        %s\n' "${2:-}"
  fail=$((fail + 1))
}

# The linter resolves its scan root as `dirname "$0"/..`, so the copy must live
# under <fixture>/scripts/.
make_fixture() {
  local dir
  dir="$(mktemp -d)"
  [ -n "$dir" ] || {
    printf 'mktemp -d failed\n' >&2
    exit 1
  }
  mkdir -p "$dir/scripts" "$dir/demo-plugin/skills/demo" "$dir/docs"
  cp "$linter" "$dir/scripts/lint-package-references.sh"
  chmod +x "$dir/scripts/lint-package-references.sh"
  printf -- '---\nname: demo\n---\n\nClean body.\n' \
    >"$dir/demo-plugin/skills/demo/SKILL.md"
  printf '%s' "$dir"
}

fixture="$(make_fixture)"
trap 'rm -rf "$fixture"' EXIT

# run_case <label> <expect: flag|clean> <relative-path> <file-body> [cwd]
# Plants one file, runs the linter (from [cwd], default the fixture root),
# asserts the verdict, then removes the file so cases stay independent. A
# `flag` verdict must also NAME the planted file.
run_case() {
  local label="$1" expect="$2" rel="$3" body="$4" run_cwd="${5:-$fixture}" out status
  mkdir -p "$fixture/$(dirname "$rel")"
  printf '%s\n' "$body" >"$fixture/$rel"
  out="$(cd "$run_cwd" && "$fixture/scripts/lint-package-references.sh" 2>&1)"
  status=$?
  rm -f "$fixture/$rel"

  case "$expect" in
    flag)
      if [ "$status" -ne 0 ] && printf '%s' "$out" | grep -qF "$rel"; then
        ok "$label"
      else
        bad "$label" "expected a finding naming $rel, linter exited $status: $out"
      fi
      ;;
    clean)
      if [ "$status" -eq 0 ]; then
        ok "$label"
      else
        bad "$label" "expected no finding, linter exited $status: $out"
      fi
      ;;
  esac
}

printf 'test-lint-package-references\n'

# --- control ----------------------------------------------------------------
if out="$("$fixture/scripts/lint-package-references.sh" 2>&1)"; then
  ok "control: a fixture with no denylisted name exits 0"
else
  bad "control: clean fixture" "$out"
fi

# --- detection --------------------------------------------------------------
run_case "detects the denylisted name in a SKILL.md" flag \
  "demo-plugin/skills/demo/SKILL.md" \
  'npm install @langchain/deep-agents'

run_case "detects the denylisted name in a REFERENCE.md" flag \
  "demo-plugin/skills/demo/REFERENCE.md" \
  'import { createDeepAgent } from "@langchain/deep-agents";'

run_case "detects the denylisted name in a references/*.md sidecar" flag \
  "demo-plugin/skills/demo/references/install.md" \
  'bun add @langchain/deep-agents'

# --- narrowness -------------------------------------------------------------
run_case "the real package name is clean" clean \
  "demo-plugin/skills/demo/references/install.md" \
  'npm install deepagents'

run_case "a blockquote callout may cite the broken name" clean \
  "demo-plugin/skills/demo/references/install.md" \
  '> Not `@langchain/deep-agents`, which 404s on npm.'

run_case "docs/ is not scanned" clean \
  "docs/ledger.md" \
  'Fixed: skills cited `@langchain/deep-agents`.'

# --- cwd independence (#2219/#2290) -----------------------------------------
# Planted in SKILL.md, which the original walk always covered, so this case
# isolates the cwd defect from the references/ widening.
run_case "the same defect is detected when run from an unrelated cwd" flag \
  "demo-plugin/skills/demo/SKILL.md" \
  'npm install @langchain/deep-agents' \
  "/"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
