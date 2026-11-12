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
# The "Agentic Optimizations" table is OPTIONAL (`.claude/rules/context-engineering.md`
# § Supersedes: keep it "where the commands are the payload"). So this script no
# longer lists every skill without one (#3573): it lists only CLI-wrapper skills
# without one, as an INFO note, using the predicate of
# `health-plugin:health-agentic-audit` Step 3 — at least half of the skill's fenced
# shell commands start with the same tool, and that tool is named in the skill's
# `name` or `description`. "Fenced shell commands" are the non-blank, non-comment,
# non-continuation lines of ```bash/sh/shell/zsh/console fences, with a leading
# `$ ` prompt stripped. The workflow prompt reports this list as INFO only; the
# audit's primary finding is bare CLI commands, which Claude scans for itself.
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

# Print "<total> <count> <tool>" for the most common first word among a skill's
# fenced shell commands; print nothing when it has none. Ties break on the
# lexically smaller tool so the output is deterministic.
fenced_tool_stats() {
  awk '
    /^[[:space:]]*```/ {
      if (in_fence) { in_fence = 0; next }
      lang = $0
      sub(/^[[:space:]]*`+/, "", lang)
      sub(/[[:space:]].*$/, "", lang)
      lang = tolower(lang)
      shell = (lang == "bash" || lang == "sh" || lang == "shell" || lang == "zsh" || lang == "console")
      in_fence = 1; cont = 0
      next
    }
    in_fence && shell {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      was_cont = cont
      cont = (line ~ /[\\]$/)
      if (was_cont || line == "" || line ~ /^#/) next
      sub(/^[$][[:space:]]+/, "", line)
      split(line, w, /[[:space:]]+/)
      if (w[1] == "") next
      total++
      n[w[1]]++
    }
    END {
      best = ""; bc = 0
      for (t in n) if (n[t] > bc || (n[t] == bc && t < best)) { best = t; bc = n[t] }
      if (total > 0) print total, bc, best
    }
  ' "$1" 2>/dev/null
}

# Find CLI-wrapper skills without an Agentic Optimizations table (INFO)
CLI_WRAPPER_NO_TABLE=""
while IFS= read -r -d '' skill; do
  grep -qi "agentic optimization" "$skill" 2>/dev/null && continue
  stats=$(fenced_tool_stats "$skill")
  [ -n "$stats" ] || continue
  read -r fence_total fence_top fence_tool <<<"$stats"
  [ $((fence_top * 2)) -ge "$fence_total" ] || continue
  skill_meta=$(head -50 "$skill" | grep -E '^(name|description):' || true)
  grep -qiwF -- "$fence_tool" <<<"$skill_meta" || continue
  CLI_WRAPPER_NO_TABLE+="- ${skill#./} ($fence_tool)\n"
done < <(find . -path './.claude/worktrees' -prune -o \
  -path '*/skills/*' \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)
[ -n "$CLI_WRAPPER_NO_TABLE" ] || CLI_WRAPPER_NO_TABLE="- (none)\n"

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
  echo "## CLI-wrapper skills without an Agentic Optimizations table (INFO):"
  echo -e "$CLI_WRAPPER_NO_TABLE"
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
