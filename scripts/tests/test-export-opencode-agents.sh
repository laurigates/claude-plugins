#!/usr/bin/env bash
# Regression test for scripts/export-opencode-agents.py and the post-rulesync
# OpenCode export pipeline (#2094).
#
# The cutover retired the rulesync `claudecode -> opencode` conversion. Two
# classes of regression are possible afterwards and neither raises an error:
#
#   1. Skills get re-added to the export. OpenCode reads SKILL.md natively and
#      the marketplace corpus reaches it through the adapter, so a flattened
#      copy is not a fallback — it is ~34,000 standing tokens per turn on top
#      of the adapter's ~600 (measured, adapters/CUTOVER.md §8), and OpenCode
#      merges both surfaces rather than picking one.
#   2. rulesync (or any bunx/npm step) comes back. The export is offline and
#      dependency-free by design; a network step in it fails in CI and in the
#      sandbox, and only sometimes.
#
# Guards:
#   A. every source agent is projected, with OpenCode's frontmatter shape
#   B. Claude-Code-only keys (model/tools/maxTurns/color/dates) are dropped
#   C. the prompt body survives verbatim
#   D. an agent with no description is SKIPPED and reported, never emitted bare
#   E. the export emits agents/ and hooks, and NO skills/ tree
#   F. no rulesync / bunx / npx step survives anywhere in the export pipeline
#   G. install-opencode.sh still carries the cross-scope duplicate guard
#   H. plugin filter: the exporter's trailing names, and export-/install-opencode.sh
#      --plugin, select only those plugins' agents and hook plugins; a plugin with
#      no agents or hooks is STATUS=OK (not a warning, not an abort); an unknown
#      name exits 2 before anything is written
#   I. a second positional argument (a plugin name without --plugin) exits 2
#      instead of being ignored; the project scope is a directory literally
#      named .opencode, so a global dir named work.opencode stays global
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
exporter="$repo_root/scripts/export-opencode-agents.py"
export_sh="$repo_root/scripts/export-opencode.sh"
install_sh="$repo_root/scripts/install-opencode.sh"

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

if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "SKIP: PyYAML not available"
  exit 0
fi

fixture="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 1; }
if [ -z "$fixture" ] || [ ! -d "$fixture" ]; then echo "bad temp dir" >&2; exit 1; fi
# Canonical root: TEST H compares an install path printed by the script.
fixture="$(cd -P -- "$fixture" && pwd -P)" || { echo "cannot resolve" >&2; exit 1; }
trap 'rm -rf "$fixture"' EXIT

# --- fixture marketplace -----------------------------------------------------
mkdir -p "$fixture/src/demo-plugin/agents"
cat > "$fixture/src/demo-plugin/agents/reviewer.md" <<'MD'
---
name: reviewer
model: opus
color: "#7B1FA2"
description: Reviews code. Use when a change needs a second pass.
tools: Glob, Grep, Read, Bash(git diff *)
maxTurns: 20
created: 2026-01-24
modified: 2026-06-28
---

# Reviewer Agent

Body line one.

| a | b |
|---|---|
| 1 | 2 |
MD

# No description — OpenCode routes subagents by description, so emitting this
# bare would produce an agent the model can never select.
cat > "$fixture/src/demo-plugin/agents/nameless.md" <<'MD'
---
name: nameless
model: opus
---

# Nameless
MD

echo "=== TEST A/B/C/D: agent projection ==="
agent_out="$(python3 "$exporter" "$fixture/src" "$fixture/out" 2>&1)"
agent_rc=$?

assert "reviewer.md is emitted" \
  "$([ -f "$fixture/out/agents/reviewer.md" ] && echo true || echo false)"
assert "frontmatter is exactly {description, mode: subagent, name}" \
  "$(python3 - "$fixture/out/agents/reviewer.md" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
end = t.find("\n---\n", 3)
fm = yaml.safe_load(t[4:end])
print("true" if fm == {
    "description": "Reviews code. Use when a change needs a second pass.",
    "mode": "subagent",
    "name": "reviewer",
} else "false")
PY
)"
# Guard integrity: the assertion above is an equality, so it already excludes
# the dropped keys — but assert them by name so a future shape change that
# loosens the comparison cannot silently readmit them.
assert "Claude-Code-only keys are dropped (model/tools/maxTurns/color/dates)" \
  "$(python3 - "$fixture/out/agents/reviewer.md" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
fm = yaml.safe_load(t[4:t.find("\n---\n", 3)])
dropped = {"model", "tools", "maxTurns", "color", "created", "modified"}
print("true" if not (dropped & set(fm)) else "false")
PY
)"
assert "prompt body survives verbatim" \
  "$(python3 - "$fixture/out/agents/reviewer.md" <<'PY'
import sys
t = open(sys.argv[1]).read()
body = t[t.find("\n---\n", 3) + 5:]
print("true" if body.strip().startswith("# Reviewer Agent")
      and "| 1 | 2 |" in body else "false")
PY
)"
assert "description-less agent is SKIPPED, not emitted" \
  "$([ ! -f "$fixture/out/agents/nameless.md" ] && echo true || echo false)"
assert "the skip is reported (never silent) and non-zero" \
  "$(case "$agent_out" in *"SKIPPED_AGENTS=1"*"nameless.md"*) [ "$agent_rc" -ne 0 ] && echo true || echo false ;; *) echo false ;; esac)"

echo "=== TEST E: the export emits agents + hooks and NO skills tree ==="
export_out="$(bash "$export_sh" "$fixture/full" 2>&1)"
export_rc=$?
assert "export exits 0" "$([ "$export_rc" -eq 0 ] && echo true || echo false)"
assert "no skills/ tree is produced (#2094 — the adapter is the skill surface)" \
  "$([ ! -d "$fixture/full/skills" ] && echo true || echo false)"
# Guard integrity: without these, "no skills/" would also pass against an
# export that produced nothing at all.
assert "agents/ IS produced and non-empty" \
  "$([ "$(find "$fixture/full/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && echo true || echo false)"
assert "hook plugins ARE produced" \
  "$([ "$(find "$fixture/full/plugins" -name '*-hooks.js' 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && echo true || echo false)"
assert "the export reports skills as adapter-served" \
  "$(case "$export_out" in *"SKILLS=adapter"*) echo true ;; *) echo false ;; esac)"

echo "=== TEST F: no rulesync / bunx / npx step survives ==="
for pipeline_file in "$export_sh" "$exporter" "$install_sh"; do
  assert "$(basename "$pipeline_file") invokes no rulesync/bunx/npx step" \
    "$(grep -qE '(bunx|npx)[[:space:]]|rulesync@|rulesync convert' "$pipeline_file" && echo false || echo true)"
done

echo "=== TEST G: install keeps the cross-scope duplicate guard ==="
assert "install-opencode.sh still writes and checks the scope receipt" \
  "$(grep -q 'claude-plugins-opencode-receipt' "$install_sh" && grep -q 'DUPLICATE_SCOPE_DETECTED' "$install_sh" && echo true || echo false)"
# shellcheck disable=SC2016  # the $install_tmp is a literal to match in the file, not an expansion
assert "install-opencode.sh no longer copies a skills tree" \
  "$(grep -qE '\$install_tmp/skills' "$install_sh" && echo false || echo true)"

echo "=== TEST H: plugin filter ==="
mkdir -p "$fixture/src/other-plugin/agents"
printf -- '---\nname: helper\ndescription: Helps.\n---\n\n# Helper\n' > "$fixture/src/other-plugin/agents/helper.md"
pf_out="$(python3 "$exporter" "$fixture/src" "$fixture/out-pf" other-plugin 2>&1)"; pf_rc=$?
assert "exporter: a trailing plugin name exports only that plugin's agents" \
  "$([ "$pf_rc" -eq 0 ] && [ -f "$fixture/out-pf/agents/helper.md" ] && [ ! -e "$fixture/out-pf/agents/reviewer.md" ] \
     && grep -qx 'OUTPUT_AGENTS=1' <<<"$pf_out" && echo true || echo false)"
pf_out="$(python3 "$exporter" "$fixture/src" "$fixture/out-pf-none" absent-plugin 2>&1)"; pf_rc=$?
assert "exporter: a selection with no agents exports zero and exits 0" \
  "$([ "$pf_rc" -eq 0 ] && grep -qx 'OUTPUT_AGENTS=0' <<<"$pf_out" && echo true || echo false)"

pf_git="$(bash "$export_sh" "$fixture/pf-git" --plugin git-plugin 2>&1)"; pf_rc=$?
pf_git_agents="$(find "$fixture/pf-git/agents" -name '*.md' | wc -l | tr -d ' ')"
pf_src_agents="$(find "$repo_root/git-plugin/agents" -name '*.md' | wc -l | tr -d ' ')"
assert "export-opencode.sh --plugin git-plugin exports exactly git-plugin's agents" \
  "$([ "$pf_rc" -eq 0 ] && [ "$pf_git_agents" -gt 0 ] && [ "$pf_git_agents" = "$pf_src_agents" ] && echo true || echo false)"
assert "export-opencode.sh --plugin git-plugin emits only git-plugin's hook plugin" \
  "$([ "$(ls "$fixture/pf-git/plugins")" = "git-plugin-hooks.js" ] && echo true || echo false)"
assert "export-opencode.sh reports PLUGINS=git-plugin" \
  "$(grep -qx 'PLUGINS=git-plugin' <<<"$pf_git" && echo true || echo false)"
pf_none="$(bash "$export_sh" "$fixture/pf-none" --plugin macos-plugin 2>&1)"; pf_rc=$?
assert "export-opencode.sh: a plugin with no agents or hooks exits 0 with STATUS=OK" \
  "$([ "$pf_rc" -eq 0 ] && grep -qx 'STATUS=OK' <<<"$pf_none" && grep -qx 'OUTPUT_AGENTS=0' <<<"$pf_none" \
     && grep -qx 'OUTPUT_HOOK_PLUGINS=0' <<<"$pf_none" && echo true || echo false)"
bash "$export_sh" "$fixture/pf-bad" --plugin nope-plugin >/dev/null 2>&1; pf_rc=$?
assert "export-opencode.sh: an unknown plugin exits 2 and writes nothing" \
  "$([ "$pf_rc" -eq 2 ] && [ ! -e "$fixture/pf-bad" ] && echo true || echo false)"

pf_inst="$(cd "$fixture" && bash "$install_sh" "$fixture/inst-none" --plugin macos-plugin 2>&1)"; pf_rc=$?
assert "install-opencode.sh: a plugin with no agents or hooks installs nothing, STATUS=OK" \
  "$([ "$pf_rc" -eq 0 ] && grep -qx 'STATUS=OK' <<<"$pf_inst" && grep -qx 'INSTALLED_AGENTS=0' <<<"$pf_inst" \
     && grep -qx 'INSTALLED_HOOK_PLUGINS=0' <<<"$pf_inst" && echo true || echo false)"
pf_inst="$(cd "$fixture" && bash "$install_sh" "$fixture/inst-git" --plugin git-plugin 2>&1)"; pf_rc=$?
assert "install-opencode.sh --plugin git-plugin installs git-plugin's agents and hook plugin only" \
  "$([ "$pf_rc" -eq 0 ] && grep -qx "INSTALLED_AGENTS=$pf_src_agents" <<<"$pf_inst" \
     && grep -qx 'INSTALLED_HOOK_PLUGINS=1' <<<"$pf_inst" && echo true || echo false)"
# Project scope selected through OPENCODE_CONFIG (the recipes' target since
# they took plugin names instead of a positional target): the complementary
# scope is still the global ~/.config/opencode, not the project dir itself.
mkdir -p "$fixture/home/.config/opencode" "$fixture/proj"
touch "$fixture/home/.config/opencode/.claude-plugins-opencode-receipt"
pf_inst="$(cd "$fixture/proj" && HOME="$fixture/home" OPENCODE_CONFIG="$fixture/proj/.opencode" \
  bash "$install_sh" "$fixture/proj/.opencode" --plugin macos-plugin 2>&1)"
assert "install-opencode.sh: OPENCODE_CONFIG=<project>/.opencode still detects a global install" \
  "$(grep -qx "DUPLICATE_SCOPE_DETECTED=$fixture/home/.config/opencode" <<<"$pf_inst" && echo true || echo false)"
(cd "$fixture" && bash "$install_sh" "$fixture/inst-bad" --plugin nope-plugin >/dev/null 2>&1); pf_rc=$?
assert "install-opencode.sh: an unknown plugin exits 2 and writes nothing" \
  "$([ "$pf_rc" -eq 2 ] && [ ! -e "$fixture/inst-bad" ] && echo true || echo false)"

echo "=== TEST I: argument and scope strictness ==="
pf_err="$(bash "$export_sh" "$fixture/pos-export" git-plugin 2>&1)"; pf_rc=$?
assert "export-opencode.sh: a second positional exits 2 naming --plugin, writes nothing" \
  "$([ "$pf_rc" -eq 2 ] && [ ! -e "$fixture/pos-export" ] && grep -q 'unexpected argument: git-plugin (plugin names need --plugin)' <<<"$pf_err" && echo true || echo false)"
pf_err="$(cd "$fixture" && bash "$install_sh" "$fixture/pos-install" git-plugin 2>&1)"; pf_rc=$?
assert "install-opencode.sh: a second positional exits 2 naming --plugin, installs nothing" \
  "$([ "$pf_rc" -eq 2 ] && [ ! -e "$fixture/pos-install" ] && grep -q 'unexpected argument: git-plugin (plugin names need --plugin)' <<<"$pf_err" && echo true || echo false)"
# work.opencode is a GLOBAL config dir (OPENCODE_CONFIG), so the complementary
# scope is the project's .opencode, whose receipt must be reported.
mkdir -p "$fixture/home2" "$fixture/proj2/.opencode" "$fixture/configs"
touch "$fixture/proj2/.opencode/.claude-plugins-opencode-receipt"
pf_inst="$(cd "$fixture/proj2" && HOME="$fixture/home2" OPENCODE_CONFIG="$fixture/configs/work.opencode" \
  bash "$install_sh" "$fixture/configs/work.opencode" --plugin macos-plugin 2>&1)"
assert "install-opencode.sh: a global dir named work.opencode is not mistaken for a project scope" \
  "$(grep -qx "DUPLICATE_SCOPE_DETECTED=$fixture/proj2/.opencode" <<<"$pf_inst" && echo true || echo false)"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -eq 0 ]; then
  echo "STATUS=OK"
  exit 0
fi
echo "STATUS=FAIL"
exit 1
