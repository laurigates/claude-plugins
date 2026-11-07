#!/usr/bin/env bash
# Regression test for scripts/check-workflow-gh-wildcard-grants.sh.
#
# The defect this guards (#2769): four workflow Claude steps granted whole gh
# command groups -- `Bash(gh pr *)`, `Bash(gh issue *)`, `Bash(gh label *)`,
# `Bash(gh run *)` -- where their prompts ran one or two verbs, so the grant
# reached `gh pr merge`, `gh issue edit` and every other publishing verb.
#
# Fixtures B-D replay the shipped grants verbatim: the claude-code-action
# `claude_args` form (obsidian-cli-changelog, research-radar) and the
# `run:`-block CLI form (auto-resolve-conflicts), which a scan of
# claude-code-action steps alone would miss.
#
# The load-bearing counter-cases are E, F and G: verb-level grants, a read-only
# `gh api *`, and a `--disallowedTools` deny list must all pass, or every
# "is flagged" assertion would also hold for a guard that flags everything.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="${CHECK_WORKFLOW_GH_WILDCARD_GRANTS:-$repo_root/scripts/check-workflow-gh-wildcard-grants.sh}"

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
contains() { grep -qF -- "$2" <<<"$1" && echo true || echo false; }
lacks() { [ "$(contains "$1" "$2")" = false ] && echo true || echo false; }
validates() {
  printf '%s\n' "$1" | bash "$repo_root/scripts/check-structured-output-contract.sh" --validate >/dev/null 2>&1 \
    && echo true || echo false
}

fx="$(mktemp -d)"
[ -n "$fx" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fx"' EXIT

# mkaction <name> <allowedTools> -- a claude-code-action step with claude_args.
mkaction() {
  local dir="$fx/$1"
  mkdir -p "$dir/.github/workflows"
  cat > "$dir/.github/workflows/w.yml" <<EOF
on: push
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --model opus
            --effort medium
            --allowedTools "$2"
          prompt: |
            Do the audit.
EOF
  printf '%s' "$dir"
}

# mkrun <name> <allowedTools> -- a run: block piping a prompt into the CLI.
mkrun() {
  local dir="$fx/$1"
  mkdir -p "$dir/.github/workflows"
  cat > "$dir/.github/workflows/w.yml" <<EOF
on: push
jobs:
  resolve:
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo "resolve" | npx @anthropic-ai/claude-code --print \\
            --model opus \\
            --effort medium \\
            --allowedTools "$2" \\
            -
EOF
  printf '%s' "$dir"
}

run_fixture() { bash "$checker" --project-dir "$1" 2>&1; }

# --- TEST A: the real repo ----------------------------------------------------
echo "=== TEST A: real repo is clean and was actually inspected ==="
out="$(bash "$checker" 2>&1)"; rc=$?
assert "A real repo exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "A real repo STATUS=OK" "$(contains "$out" 'STATUS=OK')"
assert "A real repo carries no REASON on OK" "$(lacks "$out" 'REASON=')"
assert "A real repo output satisfies the contract" "$(validates "$out")"
assert "A real repo scanned workflows" "$(lacks "$out" 'WORKFLOWS_SCANNED=0')"
assert "A real repo found allowlists" "$(lacks "$out" 'ALLOWLISTS=0')"

# --- TEST B: obsidian-cli-changelog's shipped grant (three groups) ------------
echo "=== TEST B: claude_args with gh pr/issue/label group wildcards ==="
d="$(mkaction b 'Read,Write,Bash(git push *),Bash(gh pr *),Bash(gh issue *),Bash(gh label *)')"
out="$(run_fixture "$d")"; rc=$?
assert "B exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "B STATUS=ERROR" "$(contains "$out" 'STATUS=ERROR')"
assert "B flags gh pr" "$(contains "$out" "GRANT='Bash(gh pr *)'")"
assert "B flags gh issue" "$(contains "$out" "GRANT='Bash(gh issue *)'")"
assert "B flags gh label" "$(contains "$out" "GRANT='Bash(gh label *)'")"
assert "B ISSUE_COUNT=3" "$(contains "$out" 'ISSUE_COUNT=3')"
assert "B REASON names the first finding" "$(contains "$out" 'REASON=gh_group_wildcard: ')"
assert "B REASON counts the rest" "$(contains "$out" '(+2 more)')"
assert "B output satisfies the contract" "$(validates "$out")"
assert "B does not flag git push" "$(lacks "$out" "GRANT='Bash(git push *)'")"

# --- TEST C: auto-resolve-conflicts' shipped grant, run: block form -----------
echo "=== TEST C: run-block CLI invocation with Bash(gh pr *) ==="
d="$(mkrun c 'Read,Edit,Bash(git commit *),Bash(gh pr *),Bash(jq *)')"
out="$(run_fixture "$d")"; rc=$?
assert "C exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "C flags gh pr in a run block" "$(contains "$out" "GRANT='Bash(gh pr *)'")"
assert "C names the line" "$(contains "$out" 'LINE=10')"
assert "C output satisfies the contract" "$(validates "$out")"

# --- TEST D: colon syntax, whole-CLI grant, and gh run group ------------------
echo "=== TEST D: Bash(gh issue:*), Bash(gh *) and Bash(gh run *) ==="
d="$(mkaction d 'Bash(gh issue:*),Bash(gh *),Bash(gh run *)')"
out="$(run_fixture "$d")"; rc=$?
assert "D exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "D flags colon form" "$(contains "$out" "GRANT='Bash(gh issue:*)'")"
assert "D flags whole CLI" "$(contains "$out" "GRANT='Bash(gh *)' MSG=grants the whole gh CLI")"
assert "D flags gh run" "$(contains "$out" "GRANT='Bash(gh run *)'")"
assert "D ISSUE_COUNT=3" "$(contains "$out" 'ISSUE_COUNT=3')"

# --- TEST E: verb-level grants pass (the narrowed shape) ----------------------
echo "=== TEST E: verb-level gh grants are clean ==="
d="$(mkaction e 'Read,Bash(gh pr comment *),Bash(gh issue create *),Bash(gh label create *),Bash(gh run view *),Bash(gh issue list *)')"
out="$(run_fixture "$d")"; rc=$?
assert "E exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "E STATUS=OK" "$(contains "$out" 'STATUS=OK')"
assert "E checked all six entries" "$(contains "$out" 'ENTRIES_CHECKED=6')"
assert "E output satisfies the contract" "$(validates "$out")"

# --- TEST F: gh api is out of scope ------------------------------------------
echo "=== TEST F: Bash(gh api *) is not a command group ==="
d="$(mkaction f 'Read,Bash(gh api *)')"
out="$(run_fixture "$d")"; rc=$?
assert "F exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"

# --- TEST G: a deny list is not a grant ---------------------------------------
echo "=== TEST G: --disallowedTools with a group wildcard is not flagged ==="
d="$(mkaction g 'Read,Bash(gh issue comment *)')"
printf '            --disallowedTools "Bash(gh issue *)"\n' >> "$d/.github/workflows/w.yml"
out="$(run_fixture "$d")"; rc=$?
assert "G exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "G counts one allowlist" "$(contains "$out" 'ALLOWLISTS=1')"

# --- TEST H: a YAML comment quoting a wildcard grant is not a grant ----------
echo "=== TEST H: commented-out --allowedTools is ignored ==="
d="$(mkaction h 'Read,Bash(gh pr comment *)')"
printf '          # was: --allowedTools "Bash(gh pr *)"\n' >> "$d/.github/workflows/w.yml"
out="$(run_fixture "$d")"; rc=$?
assert "H exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"

# --- TEST I: no allowlist anywhere is an error, not a pass --------------------
echo "=== TEST I: zero allowlists reports nothing_scanned ==="
mkdir -p "$fx/i/.github/workflows"
printf 'on: push\njobs:\n  x:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n' > "$fx/i/.github/workflows/w.yml"
out="$(run_fixture "$fx/i")"; rc=$?
assert "I exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "I TYPE=nothing_scanned" "$(contains "$out" 'TYPE=nothing_scanned')"
assert "I output satisfies the contract" "$(validates "$out")"

# --- TEST J: usage error ------------------------------------------------------
echo "=== TEST J: unknown flag exits 2 ==="
bash "$checker" --bogus >/dev/null 2>&1; rc=$?
assert "J exits 2" "$(is_true "$([ $rc -eq 2 ] && echo true)")"

total=$((pass_count + fail_count))
if [ "$fail_count" -gt 0 ]; then
  echo "FAILED: $fail_count of $total assertion(s)" >&2
  exit 1
fi
echo "PASS: check-workflow-gh-wildcard-grants ($total assertions)"
