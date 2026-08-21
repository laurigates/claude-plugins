#!/usr/bin/env bash
# shellcheck disable=SC2016  # file-level: backticked tool names in the planted fixtures are literal markdown, not command substitution
# Regression test for scripts/lint-mcp-tool-references.sh
#
# Issue #2437: agent-patterns-plugin:multi-model-delegation and
# testing-plugin:test-analyze documented PAL's MCP tools with a hardcoded
# `mcp__pal__*` prefix. The callable prefix is derived from the name the server
# is REGISTERED under (this repo registers PAL as `pal-mcp-server`), so every
# documented lookup returned "No matching deferred tools found".
#
# SEMANTIC, not syntactic: every case EXECUTES a copy of the real linter
# against a planted fixture tree and asserts on its verdict. A grep of the
# linter for the string `mcp__pal__` would pass against a denylist whose triple
# indexing is off by one (the array is read three entries at a time), which is
# exactly the shape that would silently disable the entry.
#
# Two halves are weighted equally with detection:
#
#   NARROWNESS — a checker that flagged every `mcp__pal` occurrence would flag
#   the FIX (`mcp__pal-mcp-server__chat`) and get reverted. And because
#   `mcp__pal__` is the CORRECT callable prefix for any repo that registers the
#   server under the key `pal`, the entry is PATH-SCOPED: it must NOT fire on a
#   skill outside the artifact families that carry the #2437 defect.
#
#   COVERAGE — the linter's walk is not repo-wide (see its header). The files it
#   DOES claim to read (skill files, bundled `*.workflow.js`, the compiled
#   git-repo-agent prompts) must actually be opened.
#
# Exit codes: 0 all assertions pass, 1 otherwise.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
linter="$repo_root/scripts/lint-mcp-tool-references.sh"

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

# Build a throwaway repo root holding a copy of the linter plus fixture skills.
# The linter resolves its scan root as `dirname "$0"/..`, so the copy must live
# under <fixture>/scripts/.
#
# Two skill directories are planted:
#   demo-plugin/skills/multi-model-delegation  — INSIDE the pal entry's scope
#   demo-plugin/skills/other-demo              — OUTSIDE it
make_fixture() {
  local dir
  dir="$(mktemp -d)"
  [ -n "$dir" ] || { printf 'mktemp -d failed\n' >&2; exit 1; }
  mkdir -p "$dir/scripts" \
           "$dir/demo-plugin/skills/multi-model-delegation" \
           "$dir/demo-plugin/skills/other-demo"
  cp "$linter" "$dir/scripts/lint-mcp-tool-references.sh"
  printf '%s' "$dir"
}

# Runs the fixture's linter copy. Sets FIXTURE_EXIT and FIXTURE_OUT.
# The output is deliberately NOT returned on stdout: a command substitution
# runs in a subshell, so an exit code assigned there never reaches the caller.
FIXTURE_EXIT=0
FIXTURE_OUT=""
run_fixture() {
  local dir="$1"
  FIXTURE_OUT="$(bash "$dir/scripts/lint-mcp-tool-references.sh" 2>&1)"
  FIXTURE_EXIT=$?
}

# Same, but from a caller cwd that is NOT the fixture root. Pins the cwd fix:
# discovery used to run in a `(cd "$repo_root" && find .)` subshell while the
# grep ran in the caller's cwd, so any invocation from elsewhere opened no file
# and still exited 0 (the #2219/#2290 silent-no-scan class).
run_fixture_from() {
  local dir="$1" from="$2"
  FIXTURE_OUT="$(cd "$from" && bash "$dir/scripts/lint-mcp-tool-references.sh" 2>&1)"
  FIXTURE_EXIT=$?
}

printf '=== lint-mcp-tool-references regression (#2437) ===\n'

# ---------------------------------------------------------------------------
# GUARD INTEGRITY 1: the real repository is clean.
# On its own this is vacuous (a linter that scanned nothing also exits 0), so
# every detection case below plants a defect and requires it to be CAUGHT.
# ---------------------------------------------------------------------------
real_out="$(bash "$linter" 2>&1)"
real_exit=$?
if [ "$real_exit" -eq 0 ]; then
  ok "real repo passes the linter"
else
  bad "real repo passes the linter" "exit=$real_exit
$real_out"
fi

# ---------------------------------------------------------------------------
# CASE 1: the bare `mcp__pal__` prefix in a scoped skill body is an ERROR.
# ---------------------------------------------------------------------------
fx="$(make_fixture)"
cat >"$fx/demo-plugin/skills/multi-model-delegation/SKILL.md" <<'EOF'
---
name: demo
---
Run `mcp__pal__listmodels` once at the start of the consult.
EOF
run_fixture "$fx"
out="$FIXTURE_OUT"
if [ "$FIXTURE_EXIT" -eq 1 ] && printf '%s' "$out" | grep -q 'multi-model-delegation/SKILL.md'; then
  ok "bare mcp__pal__ prefix in a scoped skill body is flagged"
else
  bad "bare mcp__pal__ prefix in a scoped skill body is flagged" "exit=$FIXTURE_EXIT
$out"
fi
if printf '%s' "$out" | grep -q 'pal-mcp-server'; then
  ok "the finding names the derived-prefix fix"
else
  bad "the finding names the derived-prefix fix" "$out"
fi
# Message wording is pinned so a gratuitous reword is a deliberate, tested act.
if printf '%s' "$out" | grep -qF 'Tool:  mcp__pal__ (not exposed by its MCP server)'; then
  ok "the ERROR block's Tool: line keeps its wording"
else
  bad "the ERROR block's Tool: line keeps its wording" "$out"
fi
rm -rf "$fx"

# ---------------------------------------------------------------------------
# CASE 2: the prefix in `allowed-tools` frontmatter is an ERROR.
# The reported defect lived in frontmatter as well as the body.
# ---------------------------------------------------------------------------
fx="$(make_fixture)"
cat >"$fx/demo-plugin/skills/multi-model-delegation/SKILL.md" <<'EOF'
---
name: demo
allowed-tools: Read, mcp__pal__chat, mcp__pal__consensus
---
Body with no tool names.
EOF
run_fixture "$fx"
out="$FIXTURE_OUT"
if [ "$FIXTURE_EXIT" -eq 1 ]; then
  ok "bare mcp__pal__ prefix in allowed-tools is flagged"
else
  bad "bare mcp__pal__ prefix in allowed-tools is flagged" "exit=$FIXTURE_EXIT
$out"
fi
rm -rf "$fx"

# ---------------------------------------------------------------------------
# CASE 3 (NARROWNESS — load-bearing): the CORRECT registered-name prefix must
# pass. Without this, the obvious "flag anything containing mcp__pal" fix would
# flag its own remedy and be reverted.
# ---------------------------------------------------------------------------
fx="$(make_fixture)"
cat >"$fx/demo-plugin/skills/multi-model-delegation/SKILL.md" <<'EOF'
---
name: demo
allowed-tools: Read, mcp__pal-mcp-server__chat, mcp__pal-mcp-server__listmodels
---
PAL's tools are reachable as `mcp__<server-name>__<tool>`; with the common
registration `pal-mcp-server` that is `mcp__pal-mcp-server__chat`.
EOF
run_fixture "$fx"
out="$FIXTURE_OUT"
if [ "$FIXTURE_EXIT" -eq 0 ]; then
  ok "the mcp__pal-mcp-server__ prefix is NOT flagged"
else
  bad "the mcp__pal-mcp-server__ prefix is NOT flagged" "exit=$FIXTURE_EXIT
$out"
fi
rm -rf "$fx"

# ---------------------------------------------------------------------------
# CASE 4 (NARROWNESS — the path scope): `mcp__pal__` is the CORRECT callable
# prefix for a repo that registers the server under the key `pal`, so the entry
# is scoped to the artifacts that carry the #2437 defect. A skill outside that
# scope must NOT be flagged — otherwise the guard hardcodes exactly the
# assumption the fix tells readers not to make.
# ---------------------------------------------------------------------------
fx="$(make_fixture)"
cat >"$fx/demo-plugin/skills/other-demo/SKILL.md" <<'EOF'
---
name: other-demo
allowed-tools: Read, mcp__pal__chat
---
This repo registers the server under the key `pal`, so `mcp__pal__chat` is the
correct callable name here.
EOF
run_fixture "$fx"
out="$FIXTURE_OUT"
if [ "$FIXTURE_EXIT" -eq 0 ]; then
  ok "mcp__pal__ outside the entry's path scope is NOT flagged"
else
  bad "mcp__pal__ outside the entry's path scope is NOT flagged" "exit=$FIXTURE_EXIT
$out"
fi
rm -rf "$fx"

# ---------------------------------------------------------------------------
# CASE 5: a blockquote citing the broken form is TEACHING, not using it.
# ---------------------------------------------------------------------------
fx="$(make_fixture)"
cat >"$fx/demo-plugin/skills/multi-model-delegation/SKILL.md" <<'EOF'
---
name: demo
---
> Gotcha: `mcp__pal__chat` resolves to nothing here — the prefix is derived
> from the name the server is registered under.
EOF
run_fixture "$fx"
out="$FIXTURE_OUT"
if [ "$FIXTURE_EXIT" -eq 0 ]; then
  ok "a blockquote citing the broken prefix is not flagged"
else
  bad "a blockquote citing the broken prefix is not flagged" "exit=$FIXTURE_EXIT
$out"
fi
rm -rf "$fx"

# ---------------------------------------------------------------------------
# CASE 6 (COVERAGE): a REFERENCE.md sidecar is scanned too.
# ---------------------------------------------------------------------------
fx="$(make_fixture)"
printf -- '---\nname: demo\n---\nclean body\n' \
  >"$fx/demo-plugin/skills/multi-model-delegation/SKILL.md"
printf 'Call `mcp__pal__thinkdeep` for the deep dig.\n' \
  >"$fx/demo-plugin/skills/multi-model-delegation/REFERENCE.md"
run_fixture "$fx"
out="$FIXTURE_OUT"
if [ "$FIXTURE_EXIT" -eq 1 ] && printf '%s' "$out" | grep -q 'REFERENCE.md'; then
  ok "REFERENCE.md sidecars are scanned"
else
  bad "REFERENCE.md sidecars are scanned" "exit=$FIXTURE_EXIT
$out"
fi
rm -rf "$fx"

# ---------------------------------------------------------------------------
# CASE 7 (COVERAGE): a bundled `*.workflow.js` carries the same tool names in
# its comments and agent prompts. The #2437 fix had to correct one BY HAND
# because the walk could not see it.
# ---------------------------------------------------------------------------
fx="$(make_fixture)"
printf -- '---\nname: demo\n---\nclean body\n' \
  >"$fx/demo-plugin/skills/multi-model-delegation/SKILL.md"
mkdir -p "$fx/demo-plugin/skills/multi-model-delegation/workflows"
cat >"$fx/demo-plugin/skills/multi-model-delegation/workflows/demo.workflow.js" <<'EOF'
/* `mcp__pal__planner` is NOT available inside a workflow. */
EOF
run_fixture "$fx"
out="$FIXTURE_OUT"
if [ "$FIXTURE_EXIT" -eq 1 ] && printf '%s' "$out" | grep -q 'demo.workflow.js'; then
  ok "bundled *.workflow.js files are scanned"
else
  bad "bundled *.workflow.js files are scanned" "exit=$FIXTURE_EXIT
$out"
fi
rm -rf "$fx"

# ---------------------------------------------------------------------------
# CASE 8 (COVERAGE): the COMPILED git-repo-agent prompts are derived from the
# SKILL.md files above and ship in a wheel, so a source fix that was never
# recompiled (`just compile-prompts`) must still be caught.
# ---------------------------------------------------------------------------
fx="$(make_fixture)"
printf -- '---\nname: demo\n---\nclean body\n' \
  >"$fx/demo-plugin/skills/multi-model-delegation/SKILL.md"
mkdir -p "$fx/git-repo-agent/src/git_repo_agent/prompts/generated"
printf 'Call `mcp__pal__planner` with model "gemini-2.5-pro".\n' \
  >"$fx/git-repo-agent/src/git_repo_agent/prompts/generated/test_runner_skills.md"
run_fixture "$fx"
out="$FIXTURE_OUT"
if [ "$FIXTURE_EXIT" -eq 1 ] && printf '%s' "$out" | grep -q 'prompts/generated/test_runner_skills.md'; then
  ok "compiled git-repo-agent prompts are scanned"
else
  bad "compiled git-repo-agent prompts are scanned" "exit=$FIXTURE_EXIT
$out"
fi
rm -rf "$fx"

# ---------------------------------------------------------------------------
# GUARD INTEGRITY 2: the pre-existing #1429 entry still fires, WITH its fix
# text, and from a path OUTSIDE the pal entry's scope (its own scope is `*`).
# Adding a third field to each denylist entry shifts every index; if the triple
# pairing broke, this is the assertion that catches it.
# ---------------------------------------------------------------------------
fx="$(make_fixture)"
cat >"$fx/demo-plugin/skills/other-demo/SKILL.md" <<'EOF'
---
name: other-demo
---
Resolve the thread with `mcp__github__resolve_review_thread`.
EOF
run_fixture "$fx"
out="$FIXTURE_OUT"
if [ "$FIXTURE_EXIT" -eq 1 ] && printf '%s' "$out" | grep -q 'resolveReviewThread'; then
  ok "the pre-existing #1429 denylist entry still fires with its fix text"
else
  bad "the pre-existing #1429 denylist entry still fires with its fix text" "exit=$FIXTURE_EXIT
$out"
fi

# ---------------------------------------------------------------------------
# CASE 9 (cwd): the same fixture, run from an unrelated working directory,
# must produce the identical verdict. Discovery once ran in a subshell that
# entered the scan root while the grep did not, so an invocation from anywhere
# else opened no file and still exited 0.
# ---------------------------------------------------------------------------
run_fixture_from "$fx" "/"
out="$FIXTURE_OUT"
if [ "$FIXTURE_EXIT" -eq 1 ] && printf '%s' "$out" | grep -q 'other-demo/SKILL.md'; then
  ok "the same defect is detected when run from an unrelated cwd"
else
  bad "the same defect is detected when run from an unrelated cwd" "exit=$FIXTURE_EXIT
$out"
fi
rm -rf "$fx"

# ---------------------------------------------------------------------------
# CASE 10: the fixed skill itself. The linter proves the broken form is gone;
# this asserts the POSITIVE half — the skill explains where the prefix comes
# from, names the authoritative command, and does NOT tell a reader that a
# "No matching deferred tools found" result proves the prefix was wrong.
# ---------------------------------------------------------------------------
skill="$repo_root/agent-patterns-plugin/skills/multi-model-delegation/SKILL.md"
if [ -f "$skill" ]; then
  if grep -q 'registered under' "$skill"; then
    ok "multi-model-delegation documents the prefix as derived from the registration"
  else
    bad "multi-model-delegation documents the prefix as derived from the registration" \
      "expected prose naming the registered-under key"
  fi
  if grep -q 'claude mcp list' "$skill"; then
    ok "multi-model-delegation names the command that confirms the registration"
  else
    bad "multi-model-delegation names the command that confirms the registration" \
      "expected 'claude mcp list'"
  fi
  # Problem 5: `.mcp.json` is not the only registration scope.
  if grep -q 'claude mcp add -s user' "$skill"; then
    ok "multi-model-delegation names the user-scope registration too"
  else
    bad "multi-model-delegation names the user-scope registration too" \
      "expected the ~/.claude.json user-scope path to be named"
  fi
  # Problem 4: the issue's own evidence is that the CORRECT prefix also missed.
  if grep -q 'has two causes' "$skill"; then
    ok "multi-model-delegation splits the two causes of a ToolSearch miss"
  else
    bad "multi-model-delegation splits the two causes of a ToolSearch miss" \
      "expected the correct-prefix-also-misses case to be documented"
  fi
  if grep -q 'stdin open until the response arrives' "$skill"; then
    ok "multi-model-delegation records the reporter's stdio workaround caveat"
  else
    bad "multi-model-delegation records the reporter's stdio workaround caveat" \
      "expected the stdin-stays-open trap"
  fi
else
  bad "multi-model-delegation SKILL.md exists" "$skill not found"
fi

printf '\nPASSED=%d FAILED=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
