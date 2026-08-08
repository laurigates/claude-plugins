#!/usr/bin/env bash
# config-drift-probe.sh — SessionStart probe for Claude rules/skills hygiene.
#
# Surfaces drift in the configuration corpus itself: a pointer stub naming a
# skill that no longer exists, byte-identical duplicate rules across scopes, a
# rule whose topic an existing skill already covers, and an always-loaded
# budget that has crept past its ceiling.
#
# Mounts the EXISTING sweep (../scripts/config-drift.py) on the existing
# drift-protocol trigger. Per .claude/rules/drift-detection-triggering.md the
# missing piece for this class was never the logic, only the trigger, so this
# file deliberately contains no analysis of its own -- it shells out and
# forwards findings.
#
# Cost: runs `--fast --no-embed`, which is pure stdlib, spawns no git, and
# measured 0.05s over 342 rules + 549 skills. That needs no TTL debounce -- the
# debounce guidance in drift-detection-triggering.md is about NETWORK
# round-trips, and this probe makes none. The expensive semantic pass (an
# embedding model) is scheduled-only and never runs here.
#
# Opt-out: CLAUDE_HOOKS_DISABLE_DRIFT_NUDGE=1 (honoured by the aggregator too),
# or CLAUDE_HOOKS_DISABLE_CONFIG_DRIFT=1 for this probe alone.

set -uo pipefail

if [ "${CLAUDE_HOOKS_DISABLE_CONFIG_DRIFT:-0}" = "1" ]; then
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Same fallback chain as health-drift-probe.sh: the monorepo-relative path only
# resolves in a checkout of claude-plugins, not in an installed plugin.
PROTO_LIB="${SCRIPT_DIR}/../../hooks-plugin/hooks/lib/drift-protocol.sh"
if [ ! -f "$PROTO_LIB" ]; then
    for candidate in \
        "${CLAUDE_PLUGIN_ROOT:-}/../hooks-plugin/hooks/lib/drift-protocol.sh" \
        "$HOME/.claude/plugins/hooks-plugin/hooks/lib/drift-protocol.sh"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            PROTO_LIB="$candidate"
            break
        fi
    done
fi
if [ ! -f "$PROTO_LIB" ]; then
    exit 0
fi
# shellcheck source=../../hooks-plugin/hooks/lib/drift-protocol.sh
# shellcheck disable=SC1091  # PROTO_LIB resolves at runtime via fallback chain
. "$PROTO_LIB"

drift_init "config-drift"

ANALYZER="${SCRIPT_DIR}/../scripts/config-drift.py"
if [ ! -f "$ANALYZER" ] || ! command -v python3 >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    drift_emit
    exit 0
fi

# --fast: read cached git dates only, never spawn git. --no-embed: no model, no
# download. Both keep this inside a SessionStart budget.
OUT=$(python3 "$ANALYZER" --root "${DRIFT_CWD:-.}" --fast --no-embed --format=json 2>/dev/null)
if [ -z "$OUT" ] || ! printf '%s' "$OUT" | jq empty >/dev/null 2>&1; then
    # Emit nothing rather than a false all-clear (drift-detection-triggering.md:
    # never act on uncertainty).
    drift_emit
    exit 0
fi

# Forward at most 4 findings. The aggregator caps at 5 lines across ALL plugins,
# so a greedy probe crowds out its siblings. Findings are collapsed by kind:
# 74 stale-review entries must read as one actionable nudge, not 74 identical
# ones.
while IFS=$'\t' read -r severity kind summary remediation; do
    [ -n "$kind" ] || continue
    drift_add_finding "$severity" "$kind" "$summary" "$remediation"
done < <(printf '%s' "$OUT" | jq -r '
  def rank: {"error":0,"warn":1,"info":2}[.severity] // 3;
  def fix:
    {"broken_pointer_stub":          "/agent-patterns:meta-promote",
     "coverage_metric_broken":       "/health:check",
     "duplicate_rule_lexical":       "/agent-patterns:meta-promote",
     "semantic_overlap_rule_rule":   "/agent-patterns:meta-promote",
     "semantic_overlap_rule_skill":  "/health:skill-audit",
     "semantic_overlap_skill_skill": "/health:skill-audit",
     "rule_covered_by_skill":        "/agent-patterns:meta-context-diet",
     "always_loaded_budget":         "/agent-patterns:meta-context-diet",
     "review_staleness":             "/health:skill-audit",
     "frontmatter_coverage":         "/agent-patterns:meta-context-diet"}[.kind] // "/health:check";
  [.findings[]]
  | group_by(.kind)
  | map( (.[0] | . + {rank: rank, fix: fix}) as $head
       | $head + {summary: (if length > 1
                            then ($head.summary + " (+\(length - 1) more of this kind)")
                            else $head.summary end)} )
  | sort_by(.rank, .kind)
  | .[:4][]
  | [.severity, .kind, .summary, .fix] | @tsv
')

drift_emit
