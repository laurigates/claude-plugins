#!/usr/bin/env bash
# Verify every plugin agent .md file declares a task-shape tier model:
# `opus` (default), `fable` (hardest delegated reasoning), `sonnet` with an
# explicit `effort:` (bounded, checkable work), or `haiku` in the lean-reader
# shape (see below).
#
# Background: a subagent's output feeds back into the main loop as a tool
# result, so a weaker model's output needs a check a wrong answer cannot pass.
# The tiers in `.claude/rules/agent-development.md` (§ "Model Selection for
# Agents") encode where that check exists. The old opus-only minimum rested on
# Opus 4.8 at low effort beating Sonnet 4.6 at high effort, never re-measured on
# 5.5 (#3116). This guard only checks the shape of the pick; whether an agent's
# job fits its tier is judged in review.
#
# The sole sanctioned non-Opus subagent is the `agent-patterns-plugin`
# cold-read-gate haiku reader — the measurement instrument, not a delegate
# (`~/.claude/rules/agent-and-tool-selection.md` § "Sanctioned exception").
# It is a **skill-inline** `Agent(model: haiku)` dispatch, not an agent `.md`
# file, so no agent file needs the allowlist and AGENT_MODEL_ALLOWLIST is empty.
# (A haiku agent FILE is accepted by the lean-reader rule below, not the list.)
# The seam below stays for any future measurement-instrument agent file.
#
# Sibling guards reached the same exception by their own route: as of issue
# #2216, `scripts/check-workflow-js-model.sh` exempts a bundled harness's
# `agent(…, {label:'coldread:…', model:'haiku'})` call — keyed on the call's
# LABEL rather than on the file, because one harness holds both the cold reader
# and its ordinary opus delegates. Keep the two seams distinct: this script's
# unit is a whole agent FILE, so a file-granular allowlist is the right shape
# here; a call-granular label key is the right shape there.
#
# The lean Haiku reader (Haiku 5.5 re-evaluation, 2026-10): `model: haiku` is
# accepted on an agent FILE only when all three hold:
#   1. `omitClaudeMd: true` — the agent takes everything from its brief, so the
#      ~72k-token CLAUDE.md + rules chain is not loaded;
#   2. `tools:` lists only Read, Grep and Glob — no Skill tool (the ~33k skill
#      listing), no MCP schemas, and nothing that edits, runs, or publishes —
#      declared once, with no `mcpServers:`, `skills:` or `hooks:` key;
#   3. an explicit `effort:` — Haiku 5.5's cost lever, set rather than inherited.
# Measured first-request size: ~3k tokens against ~124k for a default subagent.
# A read-only, context-free reader is the one shape where a weaker model's
# output re-entering the main loop is checked downstream rather than trusted.
#
# Tier policy: `opus` is the default and the portable choice (every plan has
# it). `fable` is sanctioned for the hardest delegated reasoning (long-horizon,
# multi-file, adversarial verification); no plan defaults to it and it costs
# about 2.5x Opus 5.5 per token. `sonnet` is the bounded tier and needs an
# explicit `effort:`, so the cost and depth pick is ours rather than the
# model default's. `inherit` is not accepted: it hides the pick and ties the
# agent to whatever session calls it. `effort:` (low|medium|high|xhigh|max,
# default inherits) is validated whenever present.
#
# Usage:
#   bash scripts/check-agent-model.sh [--project-dir <path>] [agent.md ...]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd).
#   agent.md ...    Explicit files to check (pre-commit style); when present,
#                   discovery is skipped and only these files are checked.
#
# Exit codes:
#   0 - every agent declares a tier model in its required shape, and every effort: value (if present) is valid
#   1 - one or more agents declare a disallowed model or an invalid effort: value

set -euo pipefail

# Files exempt from the opus requirement. Empty by design: the only sanctioned
# non-Opus subagent (the cold-read-gate haiku reader) is a skill-inline dispatch,
# not an agent file. Add a path here only for a genuine measurement-instrument
# agent whose entire job is to report what confuses a low-capability reader.
# Test seam: CHECK_AGENT_MODEL_ALLOWLIST (whitespace-separated) extends it so the
# regression test can exercise the honoring path without a real exemption.
AGENT_MODEL_ALLOWLIST=()
# shellcheck disable=SC2206  # intentional word-split of the test-seam env var
AGENT_MODEL_ALLOWLIST+=(${CHECK_AGENT_MODEL_ALLOWLIST:-})

proj_dir=""
explicit_files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$2"; shift 2 ;;
    *) explicit_files+=("$1"); shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Collect agent files. Explicit args win (pre-commit passes changed files);
# otherwise discover every `*-plugin/agents/*.md` under proj_dir (excluding
# .claude-plugin). The second-stage find prunes `.claude/worktrees/*` — agent
# worktree copies are full repo checkouts created by concurrently-running
# isolated agents, so descending into them would re-scan and mis-report sibling
# agents' checkouts (#1492 class).
#
# Discovery runs from INSIDE proj_dir against RELATIVE paths (#2219). With an
# absolute base, the bare `*/.claude/worktrees/*` prune fires on the whole tree
# whenever proj_dir is ITSELF an agent worktree — its own path contains
# `/.claude/worktrees/`, so every descendant matches, the scan root is pruned
# entirely, and the guard reports "No agent files found" + exit 0 having checked
# nothing. Since worktree-isolated subagents are this repo's normal way of doing
# plugin work, that made an agent's own local verification structurally incapable
# of failing. Relative paths make the root `.`, so its absolute prefix cannot
# match while worktree copies nested ANYWHERE below it still prune correctly.
# Same fix, and same reasoning, as scripts/check-subagent-types.sh.
agent_files=()
plugin_dirs=()
if [ ${#explicit_files[@]} -gt 0 ]; then
  agent_files=("${explicit_files[@]}")
else
  cd "$proj_dir" || { echo "check-agent-model.sh: cannot cd to $proj_dir" >&2; exit 2; }

  while IFS= read -r -d '' plugin_dir; do
    plugin_dirs+=("$plugin_dir")
  done < <(find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0)

  if [ ${#plugin_dirs[@]} -gt 0 ]; then
    while IFS= read -r -d '' agent_file; do
      agent_files+=("$agent_file")
    done < <(
      find "${plugin_dirs[@]}" -path '*/.claude/worktrees/*' -prune -o \
        -path '*/agents/*.md' -type f -print0
    )
  fi
fi

if [ ${#agent_files[@]} -eq 0 ]; then
  # Distinguish "nothing to check" from "the scan misfired" (#2219). A guard
  # that did not run and a guard that found nothing look identical otherwise.
  if [ ${#plugin_dirs[@]} -gt 0 ] && [ ${#explicit_files[@]} -eq 0 ]; then
    echo "AGENT_FILES_SCANNED=0" >&2
    echo "⚠️  Found ${#plugin_dirs[@]} plugin director(ies) under $proj_dir but ZERO agent files." >&2
    echo "    This is a discovery misfire, not a clean tree — the guard checked nothing." >&2
    echo "    Likely cause: a find prune matching the scan root itself (#2219)." >&2
    exit 1
  fi
  echo "AGENT_FILES_SCANNED=0"
  echo "SCANNED_EMPTY=true"
  echo "No agent files found (no plugin directories under $proj_dir — nothing to check)"
  exit 0
fi

# is_allowlisted <file> — true if the file matches an AGENT_MODEL_ALLOWLIST entry
# (compared by trailing path so callers can pass relative or absolute forms).
is_allowlisted() {
  local candidate="${1#./}"
  local entry
  for entry in ${AGENT_MODEL_ALLOWLIST[@]+"${AGENT_MODEL_ALLOWLIST[@]}"}; do
    entry="${entry#./}"
    [ -z "$entry" ] && continue
    case "$candidate" in
      "$entry" | */"$entry") return 0 ;;
    esac
  done
  return 1
}

# frontmatter <file> — the YAML between the first two `---` lines.
frontmatter() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside { print }' "$1" | tr -d '\r'
}

# agent_tools <file> — the `tools:` entries, one per line, from either the
# inline comma form (`tools: Read, Grep`) or a YAML list (`tools:` + `- Read`).
agent_tools() {
  frontmatter "$1" | awk '
    /^tools:/ {
      v = $0; sub(/^tools:[[:space:]]*/, "", v)
      if (v != "") { gsub(/[][]/, "", v); n = split(v, a, ","); for (i = 1; i <= n; i++) { gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", a[i]); if (a[i] != "") print a[i] }; exit }
      inlist = 1; next
    }
    inlist && /^[[:space:]]*-/ { v = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", v); gsub(/"/, "", v); print v; next }
    inlist { exit }
  '
}

# lean_haiku_problems <file> — empty when the file meets the lean-reader
# conditions; otherwise one reason per line.
lean_haiku_problems() {
  local f="$1" fm tool tools
  fm="$(frontmatter "$f")"
  grep -qE '^omitClaudeMd:[[:space:]]*true[[:space:]]*$' <<<"$fm" || echo "needs omitClaudeMd: true"
  # Each of these hands the agent tools or context outside Read/Grep/Glob:
  # MCP servers can write and execute, `skills:` preloads skill bodies, and
  # `hooks:` runs commands on the agent's behalf.
  for key in mcpServers skills hooks; do
    grep -qE "^${key}:" <<<"$fm" && echo "declares ${key}:, which a lean read-only reader must not"
  done
  # The tools parser reads the first `tools:` line; a second one would be the
  # value a YAML reader keeps (last wins), so it could widen the list unseen.
  [ "$(grep -cE '^tools:' <<<"$fm")" -gt 1 ] && echo "declares tools: more than once"
  tools="$(agent_tools "$f")"
  if [ -z "$tools" ]; then
    echo "needs an explicit tools: list of Read/Grep/Glob (omitted tools inherit everything)"
  else
    while IFS= read -r tool; do
      case "$tool" in
        Read | Grep | Glob) ;;
        *) echo "tool '$tool' is outside the read-only set Read/Grep/Glob" ;;
      esac
    done <<<"$tools"
  fi
  grep -qE '^effort:[[:space:]]*[a-z]+' <<<"$fm" || echo "needs an explicit effort:"
}

errors=0
checked=0
lean_haiku=0
sonnet=0

for agent_file in "${agent_files[@]}"; do
  [ -f "$agent_file" ] || continue
  checked=$((checked + 1))

  if is_allowlisted "$agent_file"; then
    continue
  fi

  agent_model=$(head -20 "$agent_file" | grep -m1 '^model:' | sed 's/^model:[[:space:]]*//' | tr -d '\r' || true)

  if [ "$agent_model" = "haiku" ]; then
    problems="$(lean_haiku_problems "$agent_file")"
    if [ -n "$problems" ]; then
      while IFS= read -r p; do
        echo "❌ $agent_file: model: haiku — $p (haiku is only for a lean read-only reader — see .claude/rules/agent-development.md § Lean subagents)" >&2
        errors=$((errors + 1))
      done <<<"$problems"
    else
      lean_haiku=$((lean_haiku + 1))
    fi
  elif [ "$agent_model" = "sonnet" ]; then
    sonnet=$((sonnet + 1))
    if ! frontmatter "$agent_file" | grep -qE '^effort:[[:space:]]*[a-z]+'; then
      echo "❌ $agent_file: model: sonnet needs an explicit effort: (the bounded tier — see .claude/rules/agent-development.md § Model Selection for Agents)" >&2
      errors=$((errors + 1))
    fi
  elif [ "$agent_model" != "opus" ] && [ "$agent_model" != "fable" ]; then
    echo "❌ $agent_file: model: ${agent_model:-<missing>} (must be opus, fable, sonnet with an explicit effort:, or haiku on a lean read-only reader — see .claude/rules/agent-development.md)" >&2
    errors=$((errors + 1))
  fi

  # effort: is optional (absent means the agent inherits the session's
  # effort), but when present it must be one of the five valid tiers.
  agent_effort=$(head -20 "$agent_file" | grep -m1 '^effort:' | sed 's/^effort:[[:space:]]*//' | tr -d '\r' || true)
  if [ -n "$agent_effort" ]; then
    case "$agent_effort" in
      low | medium | high | xhigh | max) ;;
      *)
        echo "❌ $agent_file: effort: $agent_effort (must be one of low|medium|high|xhigh|max, or omitted to inherit the session's effort)" >&2
        errors=$((errors + 1))
        ;;
    esac
  fi
done

if [ $errors -gt 0 ]; then
  echo "" >&2
  echo "Found $errors problem(s) across agent file(s) (out of $checked checked)." >&2
  echo "Pick a tier model for every plugin agent: 'opus' (default), 'fable' (hardest" >&2
  echo "delegated reasoning), 'sonnet' with an explicit 'effort:' (bounded, checkable" >&2
  echo "work), or 'haiku' as a lean read-only reader. A subagent's output re-enters" >&2
  echo "the main loop as a tool result, so a weaker model's output needs a check." >&2
  echo "See .claude/rules/agent-development.md § 'Model Selection for Agents'." >&2
  exit 1
fi

echo "AGENT_FILES_SCANNED=$checked"
echo "LEAN_HAIKU_AGENTS=$lean_haiku"
echo "SONNET_AGENTS=$sonnet"
echo "All $checked agent files declare a tier model in its required shape, with valid effort values. ✅"
exit 0
