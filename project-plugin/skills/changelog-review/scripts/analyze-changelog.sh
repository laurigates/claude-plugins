#!/usr/bin/env bash
# Analyze a Claude Code changelog excerpt for plugin impact.
#
# Emits structured KEY=VALUE output (see .claude/rules/structured-script-output.md)
# that the changelog-review workflow parses to build a triage issue. Extracted
# from the inline workflow bash so it is unit-testable (issue #1638).
#
# What it does beyond raw keyword counting:
#   - Adds a DEPRECATION dimension (deprecat|removed|renamed|unshipped|no longer)
#     — the class that silently slipped through before (TaskOutput, 2.1.83).
#   - For each deprecated/removed *identifier* named in the excerpt, greps the
#     repo's plugin content (skills/hooks/agents/rules) and surfaces the files
#     that reference it as triage candidates — the missing "changelog → plugin
#     code" bridge. A rule-doc-only candidate map would never have routed the
#     TaskOutput deprecation to hooks-plugin/hooks/bash-antipatterns.sh.
#   - Flags an oversized excerpt (a review stall) as STATUS=WARN so a 60-version
#     mega-batch is visible rather than silently lossy.
#
# Usage:
#   analyze-changelog.sh --excerpt <file> [--repo-dir <dir>] \
#       [--tracked <ver>] [--latest <ver>] [--max-versions <n>]
#
# Output: one `=== CHANGELOG ANALYSIS ===` section on stdout. Candidate files
# are listed one-per-line between `CANDIDATES:` and the section footer.
set -uo pipefail

excerpt=""
repo_dir="."
tracked="unknown"
latest="unknown"
max_versions=25

while [ $# -gt 0 ]; do
  case "$1" in
    --excerpt)      excerpt="$2"; shift 2 ;;
    --repo-dir)     repo_dir="$2"; shift 2 ;;
    --tracked)      tracked="$2"; shift 2 ;;
    --latest)       latest="$2"; shift 2 ;;
    --max-versions) max_versions="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$excerpt" ] || [ ! -f "$excerpt" ]; then
  echo "ERROR: --excerpt <file> is required and must exist" >&2
  exit 2
fi

# grep -c exits 1 on zero matches but still prints "0"; `|| true` keeps the
# count while normalising the exit code (see .claude/rules/parallel-safe-queries.md).
count() { grep -ciE "$1" "$excerpt" 2>/dev/null || true; }

HOOK=$(count 'hook')
SKILL=$(count 'skill')
AGENT=$(count 'agent|subagent')
PERM=$(count 'permission')
PLUGIN=$(count 'plugin')
MCP=$(count 'mcp')
SANDBOX=$(count 'sandbox')
BREAKING=$(count 'breaking')
# New dimension (#1638): deprecations/removals/renames that previously scored
# zero on every tracked keyword and sorted as Low / no-candidates.
DEPRECATION=$(count 'deprecat|removed|renamed|unshipped|no longer')

# Number of version headings in the excerpt = how many new versions this batch
# covers. A large batch signals a review stall and a higher drop risk.
VERSION_COUNT=$(grep -cE '^## \[?[0-9]+\.[0-9]+\.[0-9]+' "$excerpt" 2>/dev/null || true)

# --- Candidate rule-doc files from keyword hits (the original mapping) ---------
candidates=()
add() { candidates+=("$@"); }
[ "$HOOK"     -gt 0 ] && add ".claude/rules/hooks-reference.md" ".claude/rules/prompt-agent-hooks.md"
[ "$SKILL"    -gt 0 ] && add ".claude/rules/skill-development.md"
[ "$AGENT"    -gt 0 ] && add ".claude/rules/agent-development.md"
[ "$PERM"     -gt 0 ] && add ".claude/rules/agentic-permissions.md"
[ "$PLUGIN"   -gt 0 ] && add ".claude/rules/plugin-structure.md"
[ "$MCP"      -gt 0 ] && add ".claude/rules/hooks-reference.md" ".claude/rules/prompt-agent-hooks.md"
[ "$SANDBOX"  -gt 0 ] && add ".claude/rules/sandbox-guidance.md"
[ "$BREAKING" -gt 0 ] && add "CLAUDE.md" ".claude/rules/plugin-structure.md"

# --- Deprecation → plugin-code bridge (#1638) ---------------------------------
# Extract identifiers named in deprecation/removal lines, then grep the repo's
# plugin content for any skill/hook/agent/rule that still references them.
DEPRECATED_TOKENS=""
ACTIONABLE_DEPRECATION=0
if [ "$DEPRECATION" -gt 0 ]; then
  # Search roots that actually exist (keeps the script runnable in test fixtures
  # that only stand up a subset of the tree).
  roots=()
  for r in "$repo_dir"/*-plugin "$repo_dir/.claude/rules" "$repo_dir/CLAUDE.md"; do
    [ -e "$r" ] && roots+=("$r")
  done

  # Tokens: backtick-delimited names on deprecation-context lines that look like
  # tool/setting identifiers (contain an uppercase letter — TaskOutput,
  # AgentOutputTool). This deliberately skips lowercase prose words and
  # command-style `/output-style` tokens; the DEPRECATION count still surfaces
  # those for human review in the issue body.
  # Tokens: identifiers that are the *subject* of a deprecation, not merely
  # co-located with a deprecation keyword. Anchoring to the verb is what keeps
  # the bridge precise — the looser "any backtick token on a line containing
  # 'removed'/'no longer'" form produced false positives like `SendMessage`
  # ("messages relayed via `SendMessage` … no longer carry authority" — a
  # hardening, not a deprecation), `enabledPlugins` ("stale `enabledPlugins`
  # entries referencing removed marketplaces"), and `mcpServers` ("no longer
  # strips inline `mcpServers`"). Two grammatical shapes are matched:
  #   verb-first  — "Deprecated/Removed/Renamed/Unshipped … `Token`"
  #   token-first — "`Token` … is/are/now/been deprecated/removed/renamed"
  # `[^`]{0,40}` can't cross a backtick, so verb-first always grabs the first
  # backticked identifier after the verb (the subject), never a replacement
  # named later in an "in favor of `Other`" clause.
  mapfile -t tokens < <(
    {
      grep -oE '(Deprecated|Removed|Renamed|Unshipped|Un-shipped)[^`]{0,40}`[^`]+`' "$excerpt" 2>/dev/null \
        | grep -oE '`[^`]+`$'
      grep -oE '`[^`]+`[^`]{0,40}(is|are|now|been)[[:space:]]+(deprecated|removed|renamed)' "$excerpt" 2>/dev/null \
        | grep -oE '^`[^`]+`'
    } 2>/dev/null \
      | tr -d '`' \
      | grep -E '[A-Z]' 2>/dev/null \
      | grep -E '^[A-Za-z][A-Za-z0-9_]{2,}$' 2>/dev/null \
      | sort -u || true
  )

  found_tokens=()
  if [ "${#roots[@]}" -gt 0 ]; then
    for tok in "${tokens[@]}"; do
      [ -z "$tok" ] && continue
      # -F literal, -w whole-word, -l files-with-matches. Skip the changelog
      # tracking JSON so a prior recording of the token doesn't self-match.
      mapfile -t hits < <(grep -rlwF "$tok" "${roots[@]}" 2>/dev/null \
        | grep -v '.claude-code-version-check.json' || true)
      if [ "${#hits[@]}" -gt 0 ]; then
        found_tokens+=("$tok")
        for h in "${hits[@]}"; do
          # Normalise to a repo-relative path for the issue body.
          add "${h#"$repo_dir"/}"
        done
      fi
    done
  fi
  if [ "${#found_tokens[@]}" -gt 0 ]; then
    ACTIONABLE_DEPRECATION=1
    DEPRECATED_TOKENS=$(printf '%s ' "${found_tokens[@]}")
    DEPRECATED_TOKENS=${DEPRECATED_TOKENS% }
  fi
fi

# Dedupe candidates, preserving first-seen order.
mapfile -t uniq_candidates < <(printf '%s\n' "${candidates[@]:-}" | awk 'NF && !seen[$0]++')

# --- Status roll-up ------------------------------------------------------------
# WARN when the batch is oversized (stall) or when a deprecation references live
# plugin code that needs follow-up. Neither is an error — the workflow still
# triages — but both deserve a visible flag.
issue_count=0
issues=()
if [ "${VERSION_COUNT:-0}" -gt "$max_versions" ]; then
  issues+=("SEVERITY=WARN TYPE=oversized_batch MSG=excerpt spans ${VERSION_COUNT} versions (>${max_versions}); review-stall, higher drop risk")
  issue_count=$((issue_count + 1))
fi
if [ "$ACTIONABLE_DEPRECATION" -eq 1 ]; then
  issues+=("SEVERITY=WARN TYPE=actionable_deprecation MSG=deprecated identifiers referenced in plugin code: ${DEPRECATED_TOKENS}")
  issue_count=$((issue_count + 1))
fi
STATUS=OK
[ "$issue_count" -gt 0 ] && STATUS=WARN

SUMMARY="Hook:$HOOK Skill:$SKILL Agent:$AGENT Permission:$PERM Plugin:$PLUGIN MCP:$MCP Sandbox:$SANDBOX Breaking:$BREAKING Deprecation:$DEPRECATION"

# --- Emit ----------------------------------------------------------------------
echo "=== CHANGELOG ANALYSIS ==="
echo "TRACKED=$tracked"
echo "LATEST=$latest"
echo "VERSION_COUNT=${VERSION_COUNT:-0}"
echo "HOOK=$HOOK"
echo "SKILL=$SKILL"
echo "AGENT=$AGENT"
echo "PERMISSION=$PERM"
echo "PLUGIN=$PLUGIN"
echo "MCP=$MCP"
echo "SANDBOX=$SANDBOX"
echo "BREAKING=$BREAKING"
echo "DEPRECATION=$DEPRECATION"
echo "ACTIONABLE_DEPRECATION=$ACTIONABLE_DEPRECATION"
echo "DEPRECATED_TOKENS=$DEPRECATED_TOKENS"
echo "SUMMARY=$SUMMARY"
echo "STATUS=$STATUS"
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "ISSUES:"
  for i in "${issues[@]}"; do
    echo "  - $i"
  done
fi
echo "CANDIDATES:"
for c in "${uniq_candidates[@]:-}"; do
  [ -n "$c" ] && echo "  $c"
done
echo "=== END CHANGELOG ANALYSIS ==="

exit 0
