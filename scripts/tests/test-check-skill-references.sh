#!/usr/bin/env bash
# shellcheck disable=SC2016  # file-level: backticked skill IDs in the planted fixtures are literal markdown, not command substitution
# Regression test for scripts/check-skill-references.sh
#
# The linter resolves every `<name>-plugin:<artifact>` citation against the
# skills and agents on disk. Two genuine dead citations motivated it:
# `configure-plugin:multi-repo-discipline` cited a nonexistent
# `agent-patterns-plugin:agent-coworker-detection`, and
# `.claude/rules/skill-argument-handling.md` cited `project-plugin:refocus`
# after the skill was renamed to `project-plugin:project-refocus`.
#
# SEMANTIC, not syntactic: every case EXECUTES a copy of the real linter
# against a planted fixture tree and asserts on its verdict. Grepping the
# linter for a regex would pass against an extractor that matches nothing --
# and a checker that scans zero files exits 0 exactly like a clean tree.
#
# Detection is the cheap half. Three others are weighted equally:
#
#   NARROWNESS — the first run of this linter against the real tree produced 9
#   false positives out of 11 findings. All were extractor artifacts: the prose
#   word "Cross-plugin:" yielded a phantom `ross-plugin:`, and a bare
#   `<plugin>:` prefix with no name (`**testing-plugin:**`, and the shell line
#   `echo "macos-plugin: not Darwin"`) registered as a dead ID. Both shapes are
#   pinned below; a checker that re-admits them gets reverted rather than used.
#
#   COVERAGE — the walk is not repo-wide (see the linter's COVERAGE header).
#   `.claude/rules/*.md` must be scanned (a dead ID in an always-loaded rule
#   misroutes every session) and `docs/**` must NOT be (ADR-0007 cites the
#   pre-rename `git-plugin:commit`, which is correct for an immutable record).
#
#   NON-VACUITY — a broken discovery walk finds zero skills and then resolves
#   every citation against an empty ground truth, passing everything. The
#   linter must fail loudly on an empty truth set instead.
#
# Exit codes: 0 all assertions pass, 1 otherwise.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
linter="$repo_root/scripts/check-skill-references.sh"

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

# Base fixture: one real skill and one real agent, so ground truth is non-empty
# and the clean-tree control is meaningful. The linter resolves its scan root as
# `dirname "$0"/..`, so the copy must live under <fixture>/scripts/.
make_fixture() {
  local dir
  dir="$(mktemp -d)"
  [ -n "$dir" ] || {
    printf 'mktemp -d failed\n' >&2
    exit 1
  }
  mkdir -p "$dir/scripts" \
    "$dir/demo-plugin/skills/real-skill" \
    "$dir/demo-plugin/agents" \
    "$dir/.claude/rules" \
    "$dir/docs/adrs"
  cp "$linter" "$dir/scripts/check-skill-references.sh"
  chmod +x "$dir/scripts/check-skill-references.sh"
  printf -- '---\nname: real-skill\n---\n\nBody.\n' \
    >"$dir/demo-plugin/skills/real-skill/SKILL.md"
  printf -- '---\nname: real-agent\n---\n\nBody.\n' \
    >"$dir/demo-plugin/agents/real-agent.md"
  # Slash-command fixtures. `demo-thing/` is the `<ns>-<name>` shape
  # (`/demo:thing`); `widget-make/` puts a SECOND namespace (`widget`) inside
  # demo-plugin, the shape check-docs-index.sh Check 7 resolves through
  # directory-prefix ownership (`/code:lint` -> code-quality-plugin/skills/code-lint).
  mkdir -p "$dir/demo-plugin/skills/demo-thing" "$dir/demo-plugin/skills/widget-make"
  printf -- '---\nname: demo-thing\n---\n\nBody.\n' \
    >"$dir/demo-plugin/skills/demo-thing/SKILL.md"
  printf -- '---\nname: widget-make\n---\n\nBody.\n' \
    >"$dir/demo-plugin/skills/widget-make/SKILL.md"
  printf '%s' "$dir"
}

fixture="$(make_fixture)"
trap 'rm -rf "$fixture"' EXIT

# run_case <label> <expect: flag|clean> <relative-path> <file-body>
# Plants one file, runs the linter, asserts the verdict, then removes the file
# so cases stay independent.
run_case() {
  local label="$1" expect="$2" rel="$3" body="$4" out status
  mkdir -p "$fixture/$(dirname "$rel")"
  printf '%s\n' "$body" >"$fixture/$rel"
  out="$("$fixture/scripts/check-skill-references.sh" 2>&1)"
  status=$?
  rm -f "$fixture/$rel"

  case "$expect" in
    flag)
      if [ "$status" -ne 0 ]; then
        ok "$label"
      else
        bad "$label" "expected a finding, linter exited 0: $out"
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

printf 'test-check-skill-references\n'

# --- control: the base fixture alone must be clean -------------------------
if out="$("$fixture/scripts/check-skill-references.sh" 2>&1)"; then
  ok "control: fixture with only resolvable artifacts exits 0"
else
  bad "control: clean fixture" "$out"
fi

# --- detection --------------------------------------------------------------
run_case "detects a dead skill ID in a SKILL.md" flag \
  "demo-plugin/skills/other/SKILL.md" \
  'See `demo-plugin:no-such-skill` for details.'

run_case "detects a dead ID in an always-loaded rule (.claude/rules IS scanned)" flag \
  ".claude/rules/demo.md" \
  'Invoke `demo-plugin:no-such-skill` before editing.'

run_case "detects a dead ID in a REFERENCE.md" flag \
  "demo-plugin/skills/real-skill/REFERENCE.md" \
  'Related: `demo-plugin:no-such-skill`.'

# --- resolution: real artifacts must not be flagged -------------------------
run_case "a citation resolving to a real SKILL.md is clean" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'See `demo-plugin:real-skill` for details.'

run_case "a citation resolving to a real agent is clean" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'Dispatch `demo-plugin:real-agent` for this.'

# --- narrowness: the 9 false positives from the first real run --------------
# The GLUED form is the one that needs the left-boundary guard. With a space
# after the colon the non-empty-name guard already rejects it, so a spaced
# fixture passes even against a linter with no boundary check at all — it would
# assert nothing. Here `Cross-plugin:real-skill` yields the phantom
# `ross-plugin:real-skill` (unresolvable, so: a finding) the moment the
# boundary class is dropped or narrowed to `[^a-z0-9_-]`, which still admits
# the uppercase `C`.
run_case "prose 'Cross-plugin:<word>' does not yield a phantom ross-plugin ID" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'Cross-plugin:real-skill coordination is out of scope here.'

run_case "a bare '<plugin>:' prefix with no name is not a citation" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'The changelog carries `**testing-plugin:**` as a heading.'

run_case "a shell line echoing '<plugin>: message' is not a citation" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'test "$(uname -s)" = "Darwin" || { echo "macos-plugin: not Darwin"; exit 1; }'

# --- allowlist --------------------------------------------------------------
run_case "the my-plugin: authoring placeholder is allowed" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'Cite a skill as `my-plugin:code-reviewer` in your own plugin.'

run_case "a glob family form (bun-*) is allowed" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'The `typescript-plugin:bun-*` skills cover this.'

# --- coverage boundaries ----------------------------------------------------
run_case "docs/ is deliberately out of scope (ADRs cite pre-rename IDs)" clean \
  "docs/adrs/0007-demo.md" \
  'The command was `demo-plugin:no-such-skill` at the time of this decision.'

run_case "a blockquote callout may cite a dead ID as an example" clean \
  "demo-plugin/skills/other/SKILL.md" \
  '> Formerly `demo-plugin:no-such-skill`, now renamed.'

# --- references/ coverage (the 2026-10 split) -------------------------------
# Content moved out of SKILL.md into `references/*.md` was invisible to the
# original walk, which read only SKILL.md / REFERENCE.md. A sidecar is read out
# of context, so a dead pointer there costs the most.
run_case "detects a dead skill ID in a references/*.md sidecar" flag \
  "demo-plugin/skills/real-skill/references/usage.md" \
  'Chain with `demo-plugin:no-such-skill` afterwards.'

run_case "detects a dead slash command in a references/*.md sidecar" flag \
  "demo-plugin/skills/real-skill/references/usage.md" \
  '- `/demo:smartcommit` - Commit fixes with conventional messages'

run_case "detects a dead slash command in a REFERENCE-<topic>.md sidecar" flag \
  "demo-plugin/skills/real-skill/REFERENCE-shell.md" \
  'Then run `/demo:no-such-thing`.'

# --- slash commands: detection --------------------------------------------
run_case "detects a dead slash command in a SKILL.md" flag \
  "demo-plugin/skills/other/SKILL.md" \
  'If all clean, ready for `/demo:smartcommit`.'

run_case "detects a dead slash command in an always-loaded rule" flag \
  ".claude/rules/demo.md" \
  '| PRD workflow | `/demo:prd` |'

run_case "slash resolution is EXACT: a prefix of a real directory is dead" flag \
  "demo-plugin/skills/other/SKILL.md" \
  'Run `/demo:real` first.'

run_case "an unknown namespace is dead even when the name exists elsewhere" flag \
  "demo-plugin/skills/other/SKILL.md" \
  'Run `/nosuch:real-skill` first.'

# --- slash commands: resolution -------------------------------------------
run_case "the <ns>-<name> short form resolves (/demo:thing -> demo-thing/)" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'Run `/demo:thing` first.'

run_case "the <name> short form resolves (/demo:real-skill -> real-skill/)" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'Run `/demo:real-skill` first.'

run_case "a namespace owned by directory prefix resolves (/widget:make)" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'Run `/widget:make` first.'

run_case "the full plugin-qualified form resolves (/demo-plugin:real-skill)" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'Run `/demo-plugin:real-skill` first.'

# --- slash commands: narrowness (the classes seen on the real tree) --------
run_case "a URL with a port is not a slash command" clean \
  "demo-plugin/skills/other/SKILL.md" \
  "url: 'http://localhost:3000', base: https://example.com:8443/x"

# Pins the `/` in the boundary class: the `/user:token` after `//` is the only
# shape above that a letter-or-digit boundary alone would admit.
run_case "a URL carrying credentials is not a slash command" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'git clone https://user:token@example.com/repo.git'

# Pins the `.` in the boundary class (observed: a bpftrace probe spec).
run_case "a relative path with a colon is not a slash command" clean \
  "demo-plugin/skills/other/SKILL.md" \
  "sudo bpftrace -e 'uprobe:./myapp:main.handleReq { }'"

run_case "a container image reference is not a slash command" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'FROM ghcr.io/astral-sh/uv:python3.12-alpine and oven/bun:debian'

run_case "a ref path or refspec is not a slash command" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'show origin/main:openapi.yaml; push origin HEAD:refs/heads/x'

run_case "a volume mount is not a slash command" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'docker run -v ./data:/data:ro -v $HOME/cfg:/etc/cfg image'

run_case "colon-free built-ins (/help, /clear, /loop, /goal) are never matched" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'Use `/help`, `/clear`, `/loop 5m /demo:thing` or `/goal` as needed.'

run_case "a placeholder namespace (/ns:cmd, /plugin-name:skill-name) is allowed" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'A rename (`/ns:cmd` to `/ns-cmd`); the shape is `/plugin-name:skill-name`.'

run_case "a glob family form (/demo:derive-*) is allowed" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'Created on demand by the `/demo:derive-*` skills.'

run_case "a blockquote callout may name a dead slash command" clean \
  "demo-plugin/skills/other/SKILL.md" \
  '> Formerly `/demo:smartcommit`, since merged into `/demo:thing`.'

run_case "docs/ is out of scope for slash commands too" clean \
  "docs/adrs/0008-demo.md" \
  'At the time, the command was `/demo:smartcommit`.'

# A FILE-SCOPED allowlist entry exempts one file only. The real entry lets the
# blueprint upgrade skill name the removed `/blueprint:generate-commands`
# (it deletes that command's leftovers); any other file naming it is told to
# run something that does not exist.
run_case "a file-scoped exemption applies inside its file" clean \
  "blueprint-plugin/skills/blueprint-upgrade/references/deprecated-commands.md" \
  'Detection of output from the deprecated `/blueprint:generate-commands`.'

run_case "a file-scoped exemption does not leak to other files" flag \
  "demo-plugin/skills/other/SKILL.md" \
  'Run `/blueprint:generate-commands` for workflow automation.'

# --- non-vacuity ------------------------------------------------------------
empty="$(mktemp -d)" || { printf 'mktemp -d failed\n' >&2; exit 1; }
if [ -z "$empty" ] || [ ! -d "$empty" ]; then
  printf 'bad sandbox dir\n' >&2
  exit 1
fi
mkdir -p "$empty/scripts"
cp "$linter" "$empty/scripts/check-skill-references.sh"
chmod +x "$empty/scripts/check-skill-references.sh"
out="$("$empty/scripts/check-skill-references.sh" 2>&1)"
status=$?
if [ "$status" -ne 0 ] && grep -q 'discovery walk is broken' <<<"$out"; then
  ok "empty ground truth fails loudly instead of passing vacuously"
else
  bad "empty ground truth" "expected exit!=0 naming a broken walk, got $status: $out"
fi
rm -rf "$empty"

# --- cwd independence (the silent no-scan class of #2219/#2290) -------------
printf 'See `demo-plugin:no-such-skill`.\n' \
  >"$fixture/demo-plugin/skills/real-skill/REFERENCE.md"
out="$(cd / && "$fixture/scripts/check-skill-references.sh" 2>&1)"
status=$?
rm -f "$fixture/demo-plugin/skills/real-skill/REFERENCE.md"
if [ "$status" -ne 0 ]; then
  ok "scans correctly when invoked from an unrelated cwd"
else
  bad "cwd independence" "linter found nothing when run from /: $out"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
