#!/usr/bin/env bash
# Pre-compute deterministic data for the monthly Agentic Quality Audit.
#
# Extracted verbatim from the inline `run:` block of the
# `Pre-compute deterministic data` step in `.github/workflows/scheduled-audits.yml`
# (issue #2557). Nothing under `scripts/tests/` could reach the generator while it
# lived as shell embedded in YAML, so its two known defects were untestable; the
# sibling `blueprint-health`, `infra-compliance` and `docs-index` jobs in that same
# workflow already delegate to `scripts/*.sh`.
#
# The markdown on stdout is fed to the audit prompt as DATA (it is scraped from
# third-party-authored skill files). It is deliberately NOT the
# `=== SECTION ===`/`KEY=VALUE` contract of `.claude/rules/structured-script-output.md`
# — that convention exists for skill-orchestrated STATUS rollups, and there is no
# rollup consumer here; the consumer is a prompt.
#
# Flagging predicates are unchanged from the inline original. In particular the
# "Missing Agentic Optimizations" list is NOT gated on `has_bash` — it annotates
# rather than filters, per `.claude/rules/context-engineering.md` ("**Optional**;
# keep it where the commands are the payload"), and the summary row in
# `scheduled-audits.yml` plus the "flagged skills" referent in prompt §2/§3 both
# depend on the full list.
#
# Every `find` prunes `.claude/worktrees` — each agent worktree is a full repo
# clone, so an unpruned walk is the #2214 timeout class (~26,000 files instead of
# ~408). `scripts/tests/test-audit-scripts-exit.sh` asserts this structurally.
#
# Usage: bash scripts/agentic-audit-precompute.sh > precomputed.md
#
# Contract: always exits 0 having emitted a complete report.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 0

TODAY=$(date +%s)

# Collected `reviewed:` dates of the stale skills, one per line, for the
# date-cohort roll-up below (#2557 Rec 3). A file rather than an array so the
# counting is a plain `sort`/`uniq -c`.
DATES_FILE="$(mktemp 2>/dev/null)"
if [ -z "$DATES_FILE" ]; then
  DATES_FILE="${TMPDIR:-/tmp}/agentic-audit-reviewed-dates.$$"
  : > "$DATES_FILE"
fi
trap 'rm -f "$DATES_FILE"' EXIT

# Find skills missing Agentic Optimizations table
MISSING_AGENTIC=""
while IFS= read -r -d '' skill; do
  if ! grep -qi "agentic optimization" "$skill" 2>/dev/null; then
    has_bash=$(head -50 "$skill" | grep -m1 "^allowed-tools:" | grep -c "Bash" || true)
    rel_path="${skill#./}"
    MISSING_AGENTIC+="- $rel_path (Bash in allowed-tools: $([ "$has_bash" -gt 0 ] && echo yes || echo no))\n"
  fi
done < <(find . -path './.claude/worktrees' -prune -o \
  -path '*/skills/*' \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

# Find stale reviews (>90 days)
STALE_REVIEWS=""
while IFS= read -r -d '' skill; do
  reviewed=$(head -50 "$skill" | grep -m1 "^reviewed:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  if [ -n "$reviewed" ]; then
    rev_ts=$(date -d "$reviewed" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$reviewed" +%s 2>/dev/null || echo "")
    if [ -n "$rev_ts" ]; then
      days=$(( (TODAY - rev_ts) / 86400 ))
      if [ "$days" -gt 90 ]; then
        STALE_REVIEWS+="- ${skill#./}: reviewed $reviewed ($days days ago)\n"
        printf '%s\n' "$reviewed" >> "$DATES_FILE"
      fi
    fi
  fi
done < <(find . -path './.claude/worktrees' -prune -o \
  -path '*/skills/*' \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

STALE_TOTAL=$(wc -l < "$DATES_FILE" | tr -d ' ')
STALE_DISTINCT_DATES=$(sort -u "$DATES_FILE" | wc -l | tr -d ' ')
STALE_TOP_COHORTS=$(sort "$DATES_FILE" | uniq -c | sort -rn | head -5)

# Find skills missing required sections
MISSING_SECTIONS=""
while IFS= read -r -d '' skill; do
  missing=""
  grep -qi "when to use" "$skill" 2>/dev/null || missing+="When-to-Use, "
  head -50 "$skill" | grep -qm1 "^name:" 2>/dev/null || missing+="name, "
  head -50 "$skill" | grep -qm1 "^description:" 2>/dev/null || missing+="description, "
  head -50 "$skill" | grep -qm1 "^allowed-tools:" 2>/dev/null || missing+="allowed-tools, "
  if [ -n "$missing" ]; then
    MISSING_SECTIONS+="- ${skill#./}: ${missing%, }\n"
  fi
done < <(find . -path './.claude/worktrees' -prune -o \
  -path '*/skills/*' \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

TOTAL_SKILLS=$(find . -path './.claude/worktrees' -prune -o \
  -path '*/skills/*' \( -iname "SKILL.md" -o -iname "skill.md" \) -print 2>/dev/null | wc -l | tr -d ' ')

# Build summary
{
  echo "Pre-computed data for $TOTAL_SKILLS skills:"
  echo ""
  echo "## Skills missing Agentic Optimizations table:"
  echo -e "$MISSING_AGENTIC"
  echo "## Skills with stale reviews (>90 days):"
  echo -e "$STALE_REVIEWS"
  echo "## Stale-review date distribution"
  echo ""
  echo "Observed distribution of the \`reviewed:\` dates above. Reported as data,"
  echo "not as a diagnosis — a shared date is not by itself evidence of a bulk edit."
  echo ""
  echo "- Stale skills counted: $STALE_TOTAL"
  echo "- Distinct \`reviewed:\` dates among them: $STALE_DISTINCT_DATES"
  echo "- Largest cohorts (count, date):"
  echo ""
  if [ -n "$STALE_TOP_COHORTS" ]; then
    printf '%s\n' "$STALE_TOP_COHORTS" | sed 's/^[[:space:]]*/  - /'
  else
    echo "  - (none)"
  fi
  echo ""
  echo "## Skills with missing required sections/frontmatter:"
  echo -e "$MISSING_SECTIONS"
}

# Explicit terminal exit — the generator is consumed by a workflow step whose
# `run:` block runs under `set -e`, so an inherited last-statement status would
# silently abort the audit.
exit 0
