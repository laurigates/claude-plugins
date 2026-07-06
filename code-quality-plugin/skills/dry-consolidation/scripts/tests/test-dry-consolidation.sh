#!/usr/bin/env bash
# Regression test for dry-consolidation Step 1 clone-detection offload (issue #2012).
#
# Semantic invariants (not just a parse check): a future bulk edit that
# "tightens" the skill could silently revert Step 1 from the deterministic
# jscpd + ast-grep clone detector back to the old agent-driven Grep-only scan,
# or drop the quantified Extraction Plan fields. This guards all three:
#   1. Step 1 invokes jscpd (the token-based clone detector).
#   2. Step 1 uses ast-grep for structural shape confirmation.
#   3. Step 1 retains the graceful Grep fallback for when npx/jscpd is absent.
#   4. The Extraction Plan format gained the quantified fields (tokens/lines
#      duplicated + similarity) sourced from jscpd's report.
#
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_md="${script_dir}/../../SKILL.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

[ -f "$skill_md" ] || fail "SKILL.md not found at $skill_md"

body="$(cat "$skill_md")"

# 1. jscpd is the clone-detection engine of Step 1.
grep -q 'npx jscpd' <<<"$body" \
  || fail "Step 1 no longer invokes 'npx jscpd' (clone detection reverted?)"
grep -q -- '--reporters json' <<<"$body" \
  || fail "jscpd invocation dropped '--reporters json' (JSON report is what the agent parses)"
pass "Step 1 invokes jscpd with a JSON report"

# 2. ast-grep confirms structural shape (rename-tolerant, modulo captured vars).
grep -q 'ast-grep -p' <<<"$body" \
  || fail "Step 1 lost the 'ast-grep -p' structural-confirmation step"
pass "Step 1 uses ast-grep for structural shape confirmation"

# 3. The graceful Grep fallback survives (non-JS / no-npx ecosystems).
grep -qi 'fallback' <<<"$body" \
  || fail "Step 1 lost its graceful fallback path"
grep -q 'Use Grep to find repeated function names' <<<"$body" \
  || fail "Step 1 lost the Grep fallback search strategy"
pass "Step 1 retains the graceful Grep fallback"

# 4. Extraction Plan gained the quantified fields from jscpd's report.
grep -q '^- Duplicated:.*tokens.*lines' <<<"$body" \
  || fail "Extraction Plan lost the 'Duplicated: N tokens / N lines' quantified field"
grep -q '^- Similarity:' <<<"$body" \
  || fail "Extraction Plan lost the 'Similarity' quantified field"
pass "Extraction Plan carries the quantified tokens/lines/similarity fields"

echo "ALL PASS: dry-consolidation jscpd offload invariants intact"
