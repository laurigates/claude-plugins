#!/usr/bin/env bash
# Class-level regression test for issue #2219, mechanism 2:
# "a guard that scanned zero units must not silently report OK".
#
# The defect: every guard that prunes agent-worktree clones with a BARE
# `*/.claude/worktrees/*` glob against an ABSOLUTE scan base silently scans ZERO
# files when the scan root is ITSELF an agent worktree. The root's own path
# contains `/.claude/worktrees/`, so every descendant matches the prune and the
# whole tree is skipped — while the guard still exits 0.
#
# Why that matters here specifically: worktree-isolated subagents are this repo's
# normal way of doing plugin work, so "an agent verifies its own change locally"
# is the COMMON path, and it was structurally incapable of failing. A guard that
# did not run and a guard that found nothing were indistinguishable.
#
# Per-guard tests own the detailed behaviour (see test-check-agent-model.sh TEST G
# for the guard-integrity half). This file pins the CLASS invariant across every
# affected guard at once, so a new guard copying the old prune idiom is caught.
#
# Guards covered:
#   scripts/check-agent-model.sh
#   scripts/check-unused-bash-grant.sh
#   scripts/check-version-pin-coverage.sh
#   scripts/check-workflow-js-model.sh   (corpus legitimately empty — see below)
#   scripts/run-skill-script-tests.sh    (the test runner — same prune, same bug)
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

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

# Whole-LINE match. Required for NEGATIVE assertions over KEY=VALUE output:
# `contains` is an unanchored substring test, so asserting "does not report
# FILES_SCANNED=0" against a guard that legitimately emits BOTH
# `FILES_SCANNED=1` and `TEMPLATE_FILES_SCANNED=0` matches inside the SECOND
# key and fires on correct behaviour. A here-string (not a pipe) keeps this
# safe under `set -o pipefail` — `grep -q` closes stdin on first match and a
# piped writer would take SIGPIPE (141). See shell-pipefail-grep-q.md.
contains_line() { grep -qxF -- "$2" <<<"$1" && echo true || echo false; }
lacks_line() { [ "$(contains_line "$1" "$2")" = false ] && echo true || echo false; }

# The same trap runs in the POSITIVE direction, which is why every KEY=VALUE
# assertion below uses contains_line, not just the negative ones: an unanchored
# `SCANNED=1` is satisfied by any `*_SCANNED=1` sibling key, so a guard that
# discovered nothing in its OWN corpus could still pass on a sibling counter.
# These guards keep gaining keys (TEMPLATE_FILES_SCANNED, EXEMPTED_CALLS, …), so
# anchoring both polarities is what keeps the suite honest as they grow.

# Build a fixture whose ROOT PATH is worktree-shaped, exactly like a real
# `<repo>/.claude/worktrees/agent-<id>` checkout.
fx="$(mktemp -d)"
[ -n "$fx" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fx"' EXIT

wt="$fx/repo/.claude/worktrees/agent-f00dcafe"

mkdir -p "$wt/demo-plugin/agents"
cat > "$wt/demo-plugin/agents/helper.md" <<'EOF'
---
name: helper
model: opus
description: Fixture agent.
tools: Read
---
Body.
EOF

mkdir -p "$wt/demo-plugin/skills/demo-skill"
cat > "$wt/demo-plugin/skills/demo-skill/SKILL.md" <<'EOF'
---
name: demo-skill
description: Fixture skill. Use when testing worktree-root discovery.
allowed-tools: Read, Bash
---
# Demo skill

Runs a real command so the Bash grant is legitimately used.

```bash
git status --short
```
EOF

echo "=== Guard discovery from a worktree-shaped scan root (#2219) ==="

# --- check-agent-model.sh ----------------------------------------------------
out="$(bash "$repo_root/scripts/check-agent-model.sh" --project-dir "$wt" 2>&1)"; rc=$?
assert "check-agent-model: exits 0 from a worktree-shaped root" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "check-agent-model: reports a NON-ZERO scan count" "$(contains_line "$out" 'AGENT_FILES_SCANNED=1')"
assert "check-agent-model: does not claim an empty corpus" \
  "$([ "$(contains "$out" 'No agent files found')" = false ] && echo true || echo false)"

# --- check-unused-bash-grant.sh ----------------------------------------------
# This one gates the #2255 --strict flip. Pre-fix it reported SKILLS_SCANNED=0 /
# ISSUE_COUNT=0 / STATUS=OK, which satisfies "expect ISSUE_COUNT=0" VACUOUSLY —
# a clean-looking reading of a corpus that was never opened.
out="$(bash "$repo_root/scripts/check-unused-bash-grant.sh" --project-dir "$wt" 2>&1)"; rc=$?
assert "check-unused-bash-grant: exits 0 from a worktree-shaped root" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "check-unused-bash-grant: reports a NON-ZERO scan count" "$(contains_line "$out" 'SKILLS_SCANNED=1')"
assert "check-unused-bash-grant: does not report SKILLS_SCANNED=0" \
  "$(lacks_line "$out" 'SKILLS_SCANNED=0')"

# The zero-scan discriminator: plugin dirs present but nothing discovered is a
# MISFIRE and must be loud, not a green "nothing to do".
mkdir -p "$fx/misfire/demo-plugin"
out="$(bash "$repo_root/scripts/check-unused-bash-grant.sh" --project-dir "$fx/misfire" 2>&1)"; rc=$?
assert "check-unused-bash-grant: plugin dirs but zero skills is ERROR, not OK" "$(contains_line "$out" 'STATUS=ERROR')"
assert "check-unused-bash-grant: misfire names the cause" "$(contains "$out" 'nothing_scanned')"
assert "check-unused-bash-grant: misfire exits non-zero" "$(is_true "$([ $rc -ne 0 ] && echo true)")"

# ...while a tree with NO plugin dirs at all is genuinely empty and stays green.
# A checker that errors on a legitimately empty corpus gets disabled, so this
# distinction is what keeps the loud case credible.
mkdir -p "$fx/genuinely-empty"
out="$(bash "$repo_root/scripts/check-unused-bash-grant.sh" --project-dir "$fx/genuinely-empty" 2>&1)"; rc=$?
assert "check-unused-bash-grant: no plugin dirs exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "check-unused-bash-grant: no plugin dirs marks SCANNED_EMPTY" "$(contains_line "$out" 'SCANNED_EMPTY=true')"
assert "check-unused-bash-grant: no plugin dirs stays STATUS=OK" "$(contains_line "$out" 'STATUS=OK')"

# --- check-version-pin-coverage.sh -------------------------------------------
if command -v uv >/dev/null 2>&1; then
  out="$(bash "$repo_root/scripts/check-version-pin-coverage.sh" --project-dir "$wt" 2>&1)"; rc=$?
  assert "check-version-pin-coverage: reports a NON-ZERO scan count" "$(contains_line "$out" 'FILES_SCANNED=1')"
  assert "check-version-pin-coverage: does not report FILES_SCANNED=0" \
    "$(lacks_line "$out" 'FILES_SCANNED=0')"
  # Invoked by a RELATIVE path on purpose: $BASH_SOURCE is then relative too, so
  # a script resolving its own directory AFTER cding into the scan root emits
  # "cd: scripts: No such file or directory". The absolute invocation above
  # cannot reproduce it, which is why this runs from $repo_root instead.
  err="$(cd "$repo_root" && bash scripts/check-version-pin-coverage.sh --project-dir "$wt" 2>&1 >/dev/null)"
  assert "check-version-pin-coverage: relative invocation prints nothing on stderr" \
    "$(is_true "$([ -z "$err" ] && echo true)")"
else
  echo "SKIP: uv not on PATH — check-version-pin-coverage needs it to parse markdown"
fi

# --- check-workflow-js-model.sh ----------------------------------------------
# This guard's corpus is legitimately empty today (zero bundled workflow .js), so
# an empty scan here is CORRECT and must stay exit 0. That is precisely why it
# needs the OPPOSITE treatment: emptiness is reported explicitly so a reader can
# tell "nothing to check" from "checked and clean" without re-deriving it.
out="$(bash "$repo_root/scripts/check-workflow-js-model.sh" --project-dir "$wt" 2>&1)"; rc=$?
assert "check-workflow-js-model: empty corpus still exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "check-workflow-js-model: empty corpus is marked SCANNED_EMPTY=true" "$(contains_line "$out" 'SCANNED_EMPTY=true')"
assert "check-workflow-js-model: empty corpus stays STATUS=OK" "$(contains_line "$out" 'STATUS=OK')"

# Guard integrity: with a real .js present under the SAME worktree-shaped root the
# guard must both discover it AND flag its defect. Without this, every assertion
# above would also pass against a guard that discovers nothing and reports nothing.
mkdir -p "$wt/demo-plugin/skills/demo-skill/workflows"
cat > "$wt/demo-plugin/skills/demo-skill/workflows/demo.workflow.js" <<'EOF'
export default async function ({ agent }) {
  await agent("do the thing", { model: 'sonnet', effort: 'low' });
}
EOF
out="$(bash "$repo_root/scripts/check-workflow-js-model.sh" --project-dir "$wt" --strict 2>&1)"; rc=$?
assert "check-workflow-js-model: discovers a .js under a worktree-shaped root" "$(contains_line "$out" 'FILES_SCANNED=1')"
assert "check-workflow-js-model: no longer reports SCANNED_EMPTY=true" "$(contains_line "$out" 'SCANNED_EMPTY=false')"
assert "check-workflow-js-model: flags the non-opus model" "$(contains "$out" 'non_opus_model')"
assert "check-workflow-js-model: --strict exits 1 on the defect" "$(is_true "$([ $rc -eq 1 ] && echo true)")"

# --- run-skill-script-tests.sh -----------------------------------------------
# The test RUNNER carries the same prune, so it fails the same way — and it fails
# worst: a collapse here means every skill-local and hook regression suite in the
# tree silently does not run. Its `--root` is the analogue of the others'
# `--project-dir`.
mkdir -p "$wt/demo-plugin/skills/demo-skill/scripts/tests"
cat > "$wt/demo-plugin/skills/demo-skill/scripts/tests/test-fixture-passes.sh" <<'EOF'
#!/usr/bin/env bash
echo "STATUS=OK"
exit 0
EOF
out="$(bash "$repo_root/scripts/run-skill-script-tests.sh" --root "$wt" 2>&1)"; rc=$?
assert "run-skill-script-tests: exits 0 from a worktree-shaped root" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "run-skill-script-tests: reports a NON-ZERO discovery count" "$(contains "$out" 'TOTAL=1')"
assert "run-skill-script-tests: does not collapse to an empty corpus" \
  "$([ "$(contains "$out" 'SCANNED_EMPTY=true')" = false ] && echo true || echo false)"

# Guard integrity: discovering the file is not the same as running it. Without
# this, every assertion above would also pass against a runner that listed tests
# and executed none — so plant a FAILING test and require it to be caught.
cat > "$wt/demo-plugin/skills/demo-skill/scripts/tests/test-fixture-fails.sh" <<'EOF'
#!/usr/bin/env bash
echo "assertion blew up"
exit 1
EOF
out="$(bash "$repo_root/scripts/run-skill-script-tests.sh" --root "$wt" 2>&1)"; rc=$?
assert "run-skill-script-tests: actually executes what it discovers" "$(contains "$out" 'assertion blew up')"
assert "run-skill-script-tests: a failure under a worktree-shaped root exits 1" \
  "$(is_true "$([ $rc -eq 1 ] && echo true)")"

echo ""
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
