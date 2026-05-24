#!/usr/bin/env bash
# drift-aggregator.sh — SessionStart hook that consolidates per-plugin drift
# findings into a single additionalContext nudge.
#
# Per-plugin probes (blueprint-drift-probe.sh, configure-drift-probe.sh, ...)
# write to ${CLAUDE_DRIFT_SIGNALS_DIR:-/tmp/claude-drift-signals}/<sid>/<plugin>.json
# during the same SessionStart event. This aggregator reads every file in that
# directory, sorts findings by severity (error > warn > info) then plugin name,
# caps at 5 lines, and emits a single hookSpecificOutput.additionalContext block
# back to Claude.
#
# Opt-out: CLAUDE_HOOKS_DISABLE_DRIFT_NUDGE=1 → silent exit.
#
# Loop prevention: SessionStart fires once per session, not per turn — no
# stop_hook_active guard needed.

set -uo pipefail

# Opt-out
if [ "${CLAUDE_HOOKS_DISABLE_DRIFT_NUDGE:-0}" = "1" ]; then
    exit 0
fi

# Require jq — without it we cannot parse signals or emit valid JSON.
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
if [ -z "$SESSION_ID" ]; then
    exit 0
fi

# Sanitize (same rules as drift-protocol.sh).
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')
if [ -z "$SESSION_ID" ]; then
    exit 0
fi

SIGNAL_BASE="${CLAUDE_DRIFT_SIGNALS_DIR:-/tmp/claude-drift-signals}"
SIGNAL_DIR="${SIGNAL_BASE}/${SESSION_ID}"

# No signals at all = nothing to report. This is the no-drift path.
if [ ! -d "$SIGNAL_DIR" ]; then
    exit 0
fi

# Concatenate all valid signal files into a single findings stream.
# Each signal contributes its `findings[]` plus its `plugin` field so we can
# render the plugin name on the nudge line.
#
# Defensive jq: `.findings // [] | .[]` skips malformed files (missing key,
# wrong type) instead of erroring out. The `try ... catch empty` in the outer
# stream filter skips files whose top-level JSON is unparseable.
VALID_SIGNALS=()
for sig in "$SIGNAL_DIR"/*.json; do
    [ -f "$sig" ] || continue
    if jq empty "$sig" >/dev/null 2>&1; then
        VALID_SIGNALS+=("$sig")
    fi
done

if [ "${#VALID_SIGNALS[@]}" -eq 0 ]; then
    exit 0
fi

ALL_FINDINGS=$(
    jq -s '
        [
          .[] as $sig
          | ($sig.findings // [])[]
          | . + {plugin: ($sig.plugin // "unknown")}
        ]
    ' "${VALID_SIGNALS[@]}" 2>/dev/null || echo "[]"
)

if [ -z "$ALL_FINDINGS" ] || [ "$ALL_FINDINGS" = "[]" ] || [ "$ALL_FINDINGS" = "null" ]; then
    exit 0
fi

# Sort findings: error > warn > info, then plugin name asc, then kind asc.
# jq lacks descending sort by string, so map severity to numeric rank.
SORTED_FINDINGS=$(
    printf '%s' "$ALL_FINDINGS" | jq -c '
        map(
          . + {
            _rank: (
              if .severity == "error" then 0
              elif .severity == "warn" then 1
              elif .severity == "info" then 2
              else 3
              end
            )
          }
        )
        | sort_by([._rank, .plugin, .kind])
        | map(del(._rank))
    ' 2>/dev/null || echo "$ALL_FINDINGS"
)

TOTAL=$(printf '%s' "$SORTED_FINDINGS" | jq 'length' 2>/dev/null || echo 0)
if [ "$TOTAL" -eq 0 ] 2>/dev/null; then
    exit 0
fi

MAX_LINES=5
if [ "$TOTAL" -le "$MAX_LINES" ]; then
    DISPLAY_COUNT="$TOTAL"
    OVERFLOW=0
else
    DISPLAY_COUNT="$MAX_LINES"
    OVERFLOW=$((TOTAL - MAX_LINES))
fi

# Render each displayed finding as one line:
#   [SEVERITY] plugin-name: summary → /skill
LINES=$(
    printf '%s' "$SORTED_FINDINGS" | jq -r \
        --argjson n "$DISPLAY_COUNT" '
        .[:$n] | .[] |
        "  [\(.severity | ascii_upcase)] \(.plugin): \(.summary) → \(.remediation_skill // "(no remediation skill)")"
    ' 2>/dev/null || echo ""
)

if [ -z "$LINES" ]; then
    exit 0
fi

FOOTER=""
if [ "$OVERFLOW" -gt 0 ]; then
    FOOTER=$(printf '\n  +%d more — run /health:check for the full list' "$OVERFLOW")
fi

CONTEXT=$(printf 'Drift detected since last session:\n%s%s\n\nOffer these to the user as appropriate.' "$LINES" "$FOOTER")

# Emit the SessionStart additionalContext envelope.
jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

exit 0
