#!/usr/bin/env bash
# Verify every plugin agent's top-level frontmatter keys are fields Claude Code
# actually reads on a subagent definition.
#
# Background (#2646): ten plugin agents declared `context: fork`, and
# .claude/rules/agent-development.md documented it as an agent field meaning
# "isolated context". It is a SKILL frontmatter field
# (code.claude.com/docs/en/skills.md § Run skills in a subagent). The subagent
# frontmatter table (code.claude.com/docs/en/sub-agents.md § Supported
# frontmatter fields) does not list it, and the same page states that
# "Claude Code ignores a field it doesn't recognize without reporting an
# error". A live probe measured it inert on a named agent: forked and briefed
# probes returned bit-identical 2549 subagent_tokens, both blind to the parent
# turn. So the key did nothing, silently, while a rule told authors what it did.
# Inheriting the parent conversation belongs only to the runtime `fork`
# subagent type chosen at dispatch.
#
# The same silence applies to every unrecognized key — a misspelled
# `disalowedTools`, a skill's `allowed-tools` (which would leave the agent with
# EVERY tool), a field copied from another harness. This guard makes the class
# loud:
#
#   documented agent field              → OK
#   repo lifecycle date (created/…)     → OK  (this repo's convention; harmless)
#   skill-only field (context, …)       → ERROR skill_only_key
#   anything else                       → ERROR undocumented_key
#
# The documented set is EMBEDDED, copied from sub-agents.md on the date below,
# so the gate needs no network. `--docs-file <path>` makes a locally fetched
# copy of that page the authority instead, and reports where the embedded copy
# has drifted from it:
#
#   curl -sSL https://code.claude.com/docs/en/sub-agents.md -o /tmp/sub-agents.md
#   bash scripts/check-agent-frontmatter-keys.sh --docs-file /tmp/sub-agents.md
#
# Declared residuals: the ten `context` keys predate this guard. They are
# declared below, counted (ALLOWLISTED=), and itemised, and a declared entry
# that matches nothing is itself an ERROR (stale_allowlist_entry) — so the list
# can only shrink. Issue #2722 removes them; delete the entries in that change.
#
# Usage:
#   bash scripts/check-agent-frontmatter-keys.sh [--project-dir <path>] [--docs-file <path>]
#
# Exit codes:
#   0 - OK or WARN (drift against --docs-file is a WARN)
#   1 - ERROR: an agent carries a key Claude Code ignores, a stale residual, a
#       file with no frontmatter, a discovery misfire, or an unparseable docs file
#   2 - usage error (an unknown argument is rejected, never swallowed — #2057)

set -uo pipefail

# code.claude.com/docs/en/sub-agents.md § Supported frontmatter fields,
# fetched 2026-09-23 (Claude Code 2.1.280).
DOCUMENTED_FIELDS=(
  name description tools disallowedTools model permissionMode maxTurns skills
  mcpServers hooks memory background omitClaudeMd effort isolation color
  initialPrompt experimental
)

# Lifecycle dates this repo requires on every agent
# (.claude/rules/agent-development.md § Complete Field Reference). Claude Code
# ignores them; they carry review provenance for humans and audits.
REPO_CONVENTION_FIELDS=(created modified reviewed)

# code.claude.com/docs/en/skills.md frontmatter table, minus the fields the
# subagent table shares (name, description, model, effort, background, hooks).
SKILL_ONLY_FIELDS=(
  context agent allowed-tools disallowed-tools argument-hint arguments
  disable-model-invocation user-invocable when_to_use paths shell metadata
  license compatibility
)

# Declared residuals, `<repo-relative path>|<key>`. Owner: #2722.
AGENT_KEY_RESIDUALS=(
  "agents-plugin/agents/attribute-router.md|context"
  "agents-plugin/agents/dependency-audit.md|context"
  "agents-plugin/agents/performance.md|context"
  "agents-plugin/agents/research.md|context"
  "agents-plugin/agents/review.md|context"
  "agents-plugin/agents/security-audit.md|context"
  "evaluate-plugin/agents/eval-analyzer.md|context"
  "evaluate-plugin/agents/eval-comparator.md|context"
  "evaluate-plugin/agents/eval-grader.md|context"
  "feedback-plugin/agents/friction-learner.md|context"
)
RESIDUAL_OWNER="#2722"

# Test seam: when CHECK_AGENT_FRONTMATTER_KEYS_ALLOWLIST is SET — including set
# to the empty string — it REPLACES the declared list, so fixture runs are
# hermetic. `${VAR+set}`, not `-n`: an explicitly empty list is the state the
# no-residual path exists to exercise (the #2521 lesson).
if [ -n "${CHECK_AGENT_FRONTMATTER_KEYS_ALLOWLIST+set}" ]; then
  # shellcheck disable=SC2206  # intentional word-split of the seam value
  AGENT_KEY_RESIDUALS=(${CHECK_AGENT_FRONTMATTER_KEYS_ALLOWLIST})
fi

usage() {
  echo "usage: check-agent-frontmatter-keys.sh [--project-dir <path>] [--docs-file <path>]" >&2
}

proj_dir=""
docs_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      [ $# -ge 2 ] || { usage; exit 2; }
      proj_dir="$2"; shift 2 ;;
    --docs-file)
      [ $# -ge 2 ] || { usage; exit 2; }
      docs_file="$2"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "check-agent-frontmatter-keys.sh: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

issues=()
has_error=false
has_warn=false

add_issue() {
  # add_issue <SEVERITY> <rest-of-row>
  issues+=("  - SEVERITY=$1 $2")
  case "$1" in
    ERROR) has_error=true ;;
    WARN) has_warn=true ;;
  esac
}

in_list() {
  # in_list <needle> <item>... — exact membership
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

# --- Authority: embedded list, or a fetched docs page ---------------------------
authority="embedded"
authority_fields=("${DOCUMENTED_FIELDS[@]}")
docs_lines=()
if [ -n "$docs_file" ]; then
  authority="docs-file"
  if [ ! -f "$docs_file" ]; then
    echo "check-agent-frontmatter-keys.sh: --docs-file not found: $docs_file" >&2
    exit 2
  fi
  # The supported-fields table is the one whose header reads
  # `| Field | Required | …`. Other tables on the page (permission modes,
  # memory scopes, hook events) also have backticked first cells, so the
  # header — not the cell shape — is what identifies it.
  docs_parsed=()
  while IFS= read -r field; do
    [ -n "$field" ] && docs_parsed+=("$field")
  done < <(
    awk '
      { sub(/\r$/, "") }
      !in_t && /^\|[[:space:]]*Field[[:space:]]*\|[[:space:]]*Required[[:space:]]*\|/ { in_t = 1; next }
      in_t && /^\|[[:space:]]*:?-/ { next }
      in_t && /^\|/ {
        if (match($0, /^\|[[:space:]]*`[^`]+`/)) {
          f = substr($0, RSTART, RLENGTH)
          sub(/^\|[[:space:]]*`/, "", f)
          sub(/`$/, "", f)
          print f
        }
        next
      }
      in_t { exit }
    ' "$docs_file"
  )
  if [ ${#docs_parsed[@]} -eq 0 ]; then
    add_issue ERROR "TYPE=docs_table_not_found FILE=$docs_file MSG=no '| Field | Required |' table found; the page layout changed or the fetch returned something else — refusing to treat an empty table as the authority"
  else
    authority_fields=("${docs_parsed[@]}")
    docs_only=()
    embedded_only=()
    for f in "${docs_parsed[@]}"; do
      in_list "$f" "${DOCUMENTED_FIELDS[@]}" || docs_only+=("$f")
    done
    for f in "${DOCUMENTED_FIELDS[@]}"; do
      in_list "$f" "${docs_parsed[@]}" || embedded_only+=("$f")
    done
    for f in ${docs_only[@]+"${docs_only[@]}"}; do
      add_issue WARN "TYPE=docs_drift FIELD=$f MSG=documented upstream but missing from DOCUMENTED_FIELDS; add it so the default run accepts it"
    done
    for f in ${embedded_only[@]+"${embedded_only[@]}"}; do
      add_issue WARN "TYPE=docs_drift FIELD=$f MSG=in DOCUMENTED_FIELDS but no longer in the fetched table; confirm and remove it"
    done
    docs_lines+=("DOCS_FILE=$docs_file")
    docs_lines+=("DOCS_FIELDS=${#docs_parsed[@]}")
    docs_lines+=("DOCS_ONLY_FIELDS=$(IFS=,; echo "${docs_only[*]+"${docs_only[*]}"}")")
    docs_lines+=("EMBEDDED_ONLY_FIELDS=$(IFS=,; echo "${embedded_only[*]+"${embedded_only[*]}"}")")
  fi
fi

# --- Discovery -------------------------------------------------------------------
# Runs from INSIDE proj_dir against RELATIVE paths (#2219): with an absolute
# base, a `*/.claude/worktrees/*` prune matches the scan root itself whenever
# proj_dir is an agent worktree, and the guard would report a clean tree having
# read nothing. Relative paths make the root `.`, so only worktree clones nested
# BELOW it are pruned.
cd "$proj_dir" || { echo "check-agent-frontmatter-keys.sh: cannot cd to $proj_dir" >&2; exit 2; }

plugin_dirs=()
while IFS= read -r -d '' d; do
  plugin_dirs+=("$d")
done < <(find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0)

agent_dirs=0
agent_files=()
if [ ${#plugin_dirs[@]} -gt 0 ]; then
  agent_dirs="$(find "${plugin_dirs[@]}" -mindepth 1 -maxdepth 1 -type d -name agents | wc -l | tr -d ' ')"
  while IFS= read -r -d '' f; do
    agent_files+=("${f#./}")
  done < <(
    find "${plugin_dirs[@]}" -path '*/.claude/worktrees/*' -prune -o \
      -mindepth 2 -maxdepth 2 -path '*/agents/*.md' -type f -print0 | sort -z
  )
fi

# extract_keys <file> — top-level frontmatter keys, one per line, or the marker
# __NO_FRONTMATTER__. Only column-0 `key:` lines between the opening `---` and
# the closing `---` count: nested mappings and block-scalar bodies are indented,
# and the markdown body is never read.
extract_keys() {
  awk '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") { bad = 1; exit } ; next }
    /^---[[:space:]]*$/ { closed = 1; exit }
    /^[A-Za-z_][A-Za-z0-9_.-]*[[:space:]]*:/ {
      k = $0
      sub(/[[:space:]]*:.*$/, "", k)
      print k
    }
    END { if (bad || !closed) print "__NO_FRONTMATTER__" }
  ' "$1"
}

skill_only_msg() {
  case "$1" in
    context)
      echo "\`context\` is a skill frontmatter field (skills.md § Run skills in a subagent); Claude Code ignores it on an agent without an error. A named agent always starts without the parent's conversation — to hand a subagent the conversation, dispatch the runtime subagent_type: \"fork\" instead" ;;
    allowed-tools)
      echo "\`allowed-tools\` is a skill frontmatter field; on an agent it is ignored, so the agent inherits EVERY tool — the agent field is \`tools:\`" ;;
    disallowed-tools)
      echo "\`disallowed-tools\` is the skill spelling; on an agent it is ignored — the agent field is \`disallowedTools:\`" ;;
    *)
      echo "\`$1\` is a skill frontmatter field; Claude Code ignores it on an agent without an error (sub-agents.md § Supported frontmatter fields)" ;;
  esac
}

scanned=0
keys_checked=0
allowlisted=0
allowlisted_rows=()
declare -A file_keys=()

for f in ${agent_files[@]+"${agent_files[@]}"}; do
  scanned=$((scanned + 1))
  keys="$(extract_keys "$f")"
  if grep -qxF '__NO_FRONTMATTER__' <<<"$keys"; then
    add_issue ERROR "TYPE=no_frontmatter FILE=$f MSG=no closed '---' frontmatter block at line 1; Claude Code cannot read name/description from it"
    continue
  fi
  file_keys["$f"]="$keys"
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    keys_checked=$((keys_checked + 1))
    if in_list "$key" "${authority_fields[@]}" || in_list "$key" "${REPO_CONVENTION_FIELDS[@]}"; then
      continue
    fi
    if in_list "$f|$key" ${AGENT_KEY_RESIDUALS[@]+"${AGENT_KEY_RESIDUALS[@]}"}; then
      allowlisted=$((allowlisted + 1))
      allowlisted_rows+=("  - FILE=$f KEY=$key OWNER=$RESIDUAL_OWNER")
      continue
    fi
    if in_list "$key" "${SKILL_ONLY_FIELDS[@]}"; then
      add_issue ERROR "TYPE=skill_only_key FILE=$f KEY=$key MSG=$(skill_only_msg "$key")"
    else
      add_issue ERROR "TYPE=undocumented_key FILE=$f KEY=$key MSG=\`$key\` is not a documented subagent frontmatter field; Claude Code ignores a field it does not recognize without an error (sub-agents.md § Supported frontmatter fields)"
    fi
  done <<<"$keys"
done

# A declared residual that matches nothing is stale: the list must shrink with
# the defect, or it quietly becomes a permanent exemption.
for entry in ${AGENT_KEY_RESIDUALS[@]+"${AGENT_KEY_RESIDUALS[@]}"}; do
  [ -n "$entry" ] || continue
  e_file="${entry%%|*}"
  e_key="${entry#*|}"
  if [ -z "${file_keys[$e_file]+set}" ] || ! grep -qxF -- "$e_key" <<<"${file_keys[$e_file]}"; then
    add_issue ERROR "TYPE=stale_allowlist_entry ENTRY=$entry MSG=declared residual matches no key in the scanned agents; delete it from AGENT_KEY_RESIDUALS"
  fi
done

# Distinguish "nothing to check" from "the scan misfired" (#2219).
scanned_empty=false
if [ "$scanned" -eq 0 ]; then
  if [ "${agent_dirs:-0}" -gt 0 ]; then
    add_issue ERROR "TYPE=nothing_scanned MSG=found ${agent_dirs} plugin agents director(ies) under $proj_dir but ZERO agent files; this is a discovery misfire, not a clean tree"
  else
    scanned_empty=true
  fi
fi

item_status="OK"
if $has_error; then
  item_status="ERROR"
elif $has_warn; then
  item_status="WARN"
fi

echo "=== AGENT FRONTMATTER KEYS ==="
echo "AUTHORITY=$authority"
for line in ${docs_lines[@]+"${docs_lines[@]}"}; do
  echo "$line"
done
echo "AGENT_FILES_SCANNED=$scanned"
echo "KEYS_CHECKED=$keys_checked"
echo "SCANNED_EMPTY=$scanned_empty"
echo "ALLOWLISTED=$allowlisted"
echo "STATUS=$item_status"
echo "ISSUE_COUNT=${#issues[@]}"
if [ ${#issues[@]} -gt 0 ]; then
  echo "ISSUES:"
  printf '%s\n' "${issues[@]}"
fi
if [ ${#allowlisted_rows[@]} -gt 0 ]; then
  echo "ALLOWLISTED_ENTRIES:"
  printf '%s\n' "${allowlisted_rows[@]}"
fi
echo "=== END AGENT FRONTMATTER KEYS ==="

$has_error && exit 1
exit 0
