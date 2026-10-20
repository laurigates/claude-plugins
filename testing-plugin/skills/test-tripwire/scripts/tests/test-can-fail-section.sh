#!/usr/bin/env bash
# Regression test for issue #3094: test-tripwire's "Verify It Can Fail" section
# told the agent to snapshot with `cp`, edit the file, run the test and restore
# with `cp`. A hand-written probe that edits with `sed -i` hits the
# `sed-inplace` block (#3043), and a skipped restore leaves the file mutated.
# The section now routes the probe through the mutation-check.sh helper of
# agent-patterns-plugin:parallel-agent-dispatch (#3090), which restores on
# every exit path.
#
# Pins, scoped to the section only (from its heading to the next `## `):
#   - names `agent-patterns-plugin:parallel-agent-dispatch` and `mutation-check.sh`
#   - shows the usage shape (`<path> '<sed-expr>' -- <gate>`) and both verdicts
#   - keeps the on-the-assertion check and the reported control
#   - no `cp` snapshot/restore, no `sed -i`, no `git checkout --` instruction
#   - no filesystem path into another plugin (cross-plugin = name reference)
#
# SKILL_MD overrides the file under test, so a broken copy can prove the pins
# have teeth.
#
# Run: bash testing-plugin/skills/test-tripwire/scripts/tests/test-can-fail-section.sh

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
skill="${SKILL_MD:-$here/../../SKILL.md}"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }

if [ ! -f "$skill" ]; then
  echo "FAIL SKILL.md not found: $skill"
  exit 1
fi

section=$(awk '
  /^## Verify It Can Fail[[:space:]]*$/ { on = 1; next }
  on && /^## / { exit }
  on { print }
' "$skill")

if [ -n "$section" ]; then ok "S1 section present"; else bad "S1 section 'Verify It Can Fail' missing or empty"; fi

has() { grep -F -q -- "$1" <<<"$section"; }
has_re() { grep -E -q -- "$1" <<<"$section"; }

if has 'agent-patterns-plugin:parallel-agent-dispatch'; then ok "S2 names the owning skill"; else bad "S2 does not name agent-patterns-plugin:parallel-agent-dispatch"; fi
if has 'mutation-check.sh'; then ok "S3 names mutation-check.sh"; else bad "S3 does not name mutation-check.sh"; fi
if has_re "mutation-check\.sh <[a-z]+> '<sed-expr>' -- <"; then ok "S4 shows the usage shape"; else bad "S4 usage shape <path> '<sed-expr>' -- <gate> missing"; fi
if has 'MUTANT=killed' && has 'MUTANT=survived'; then ok "S5 maps both verdicts"; else bad "S5 MUTANT=killed and MUTANT=survived not both named"; fi
if has 'on the assertion'; then ok "S6 keeps the on-the-assertion check"; else bad "S6 'on the assertion' check dropped"; fi
if has 'Report the control'; then ok "S7 keeps the reported control"; else bad "S7 'Report the control' dropped"; fi

if has_re '(^|[^[:alnum:]_-])cp[[:space:]]'; then bad "S8 a cp snapshot/restore step remains"; else ok "S8 no cp step"; fi
if has_re 'sed[[:space:]]+-i'; then bad "S9 a sed -i instruction remains"; else ok "S9 no sed -i"; fi
if has 'git checkout --'; then bad "S10 a git checkout -- instruction remains"; else ok "S10 no git checkout --"; fi
if has_re '(\.\./|/)?agent-patterns-plugin/'; then bad "S11 filesystem path into agent-patterns-plugin"; else ok "S11 cross-plugin reference is by name only"; fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
