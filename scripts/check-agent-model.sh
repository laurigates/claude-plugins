#!/usr/bin/env bash
# Verify every plugin agent .md file declares `model: opus` (or `model: fable`
# for the hardest delegated reasoning — see the policy note below).
#
# Background: a subagent's output feeds back into the main loop as a tool
# result, so a weaker delegate quietly degrades everything downstream. `effort` —
# settable per agent via the `effort:` frontmatter field, or per session — not
# `model`, is the cost lever for delegated work; the measured basis (re-checked
# per model generation) lives in `.claude/rules/agent-development.md`
# (§ "Model Selection for Agents"). This matches the user-global standard in
# `~/.claude/rules/agent-and-tool-selection.md` ("Always Use Opus for
# Subagents").
#
# The sole sanctioned non-Opus subagent is the `agent-patterns-plugin`
# cold-read-gate haiku reader — the measurement instrument, not a delegate
# (`~/.claude/rules/agent-and-tool-selection.md` § "Sanctioned exception").
# It is a **skill-inline** `Agent(model: haiku)` dispatch, not an agent `.md`
# file, so **no agent file is exempt today** and AGENT_MODEL_ALLOWLIST is empty.
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
# Model floor policy: `opus` is the committed floor for every plugin agent —
# it is the portable choice (every plan carries Opus; `fable` is no plan's
# default and costs roughly 2x per token, and has no documented fallback for a
# consumer without Fable access). `fable` is additionally sanctioned for
# agents whose job is the hardest delegated reasoning (long-horizon,
# multi-file, adversarial verification) — this guard accepts it alongside
# `opus`. `inherit` is not accepted for plugin agents: it would also inherit
# whatever session model is active, including Sonnet/Haiku sessions below the
# floor. `effort:` frontmatter (low|medium|high|xhigh|max, default inherits)
# is the per-agent cost lever — dial it down for mechanical/high-volume agents
# instead of reaching for a weaker model.
#
# Usage:
#   bash scripts/check-agent-model.sh [--project-dir <path>] [agent.md ...]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd).
#   agent.md ...    Explicit files to check (pre-commit style); when present,
#                   discovery is skipped and only these files are checked.
#
# Exit codes:
#   0 - all agents run on opus or fable, and every effort: value (if present) is valid
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

errors=0
checked=0

for agent_file in "${agent_files[@]}"; do
  [ -f "$agent_file" ] || continue
  checked=$((checked + 1))

  if is_allowlisted "$agent_file"; then
    continue
  fi

  agent_model=$(head -20 "$agent_file" | grep -m1 '^model:' | sed 's/^model:[[:space:]]*//' | tr -d '\r' || true)

  if [ "$agent_model" != "opus" ] && [ "$agent_model" != "fable" ]; then
    echo "❌ $agent_file: model: ${agent_model:-<missing>} (must be opus, or fable for the hardest delegated reasoning; effort is the cost lever — see .claude/rules/agent-development.md)" >&2
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
  echo "Set 'model: opus' (or 'model: fable' for the hardest delegated reasoning)" >&2
  echo "on every plugin agent. A subagent's output re-enters the main loop as a" >&2
  echo "tool result, so a weaker delegate degrades everything downstream. Dial" >&2
  echo "'effort:' down for mechanical agents instead of reaching for a weaker model." >&2
  echo "See .claude/rules/agent-development.md § 'Model Selection for Agents'." >&2
  exit 1
fi

echo "AGENT_FILES_SCANNED=$checked"
echo "All $checked agent files run on opus or fable, with valid effort values. ✅"
exit 0
