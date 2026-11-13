#!/usr/bin/env bash
# Regression test for tools-plugin/skills/shell-expert: `producer | grep -q`
# under pipefail, and the capture form the skill prescribes instead (#3590).
#
# The defect: a membership test written as `cmd | grep -Fxq "$x"` under
# `set -o pipefail` returns false for a value that is present. grep exits on
# its first match, cmd takes SIGPIPE (141), and pipefail reports cmd's status.
# The skill's earlier "Right" form, `grep -q PAT <<<"$(cmd)"`, removes the
# SIGPIPE but drops cmd's exit status, so a failed cmd also reads as a miss.
# The form that keeps both is `out=$(cmd)` then `grep -q PAT <<<"$out"`.
#
# Guards:
#   A. the mechanism the skill documents still holds in this bash: the pipe
#      form reads a present value as absent, the capture form reads it present
#   B. `<<<"$(cmd)"` loses cmd's status; `out=$(cmd)` keeps it; set -e does
#      not act on it inside a function called from `if`, an explicit check does
#   C. REFERENCE.md's pipefail section prescribes the assignment capture form,
#      says the inline substitution loses the producer's status, no longer
#      offers `<<<"$(...)"` as a right form, states the errexit-suspension
#      limit, and shows a capture with an explicit status check
#   D. SKILL.md's pipefail guideline names the assignment capture form
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$script_dir/../../skills/shell-expert"
reference="$skill_dir/REFERENCE.md"
skill="$skill_dir/SKILL.md"

pass_count=0
fail_count=0

assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

# --- A. the mechanism ------------------------------------------------------
# The producer writes ~1.2 MB, far past the 64 KiB pipe buffer, and the needle
# is on line 1, so grep -q exits while seq still has output to write.
producer() { seq 1 200000; }

if producer | grep -Fxq 1; then pipe_result=present; else pipe_result=absent; fi
assert "A1: pipe form reads a present value as absent under pipefail (got $pipe_result)" \
  "$([ "$pipe_result" = absent ] && echo true || echo false)"

producer | grep -Fxq 1
pipe_status=("${PIPESTATUS[@]}")
assert "A2: the producer took SIGPIPE (got ${pipe_status[0]})" \
  "$([ "${pipe_status[0]}" -eq 141 ] && echo true || echo false)"
assert "A3: grep itself matched (got ${pipe_status[1]})" \
  "$([ "${pipe_status[1]}" -eq 0 ] && echo true || echo false)"

listing=$(producer)
if grep -Fxq 1 <<<"$listing"; then capture_result=present; else capture_result=absent; fi
assert "A4: capture form reads the value as present (got $capture_result)" \
  "$([ "$capture_result" = present ] && echo true || echo false)"

# --- B. producer status ----------------------------------------------------
failing_producer() { echo partial; return 3; }

grep -Fxq 1 <<<"$(failing_producer)"
inline_status=$?
assert "B1: <<<\"\$(cmd)\" reports only grep's miss, not cmd's failure (got $inline_status)" \
  "$([ "$inline_status" -eq 1 ] && echo true || echo false)"

captured=$(failing_producer)
assign_status=$?
assert "B2: out=\$(cmd) keeps cmd's status (got $assign_status, output '$captured')" \
  "$([ "$assign_status" -eq 3 ] && echo true || echo false)"

# A function called from `if` runs with set -e suspended, so a failed capture
# inside it does not stop the script; an explicit check on the assignment does.
# shellcheck disable=SC2016  # the scripts are run by the child bash, not expanded here
suspended=$(bash -c 'set -euo pipefail
  f() { local out; out=$(echo partial; exit 3); echo continued; grep -q x <<<"$out"; }
  if f; then echo present; else echo absent; fi' 2>/dev/null)
assert "B3: set -e is suspended in a function called from if (got '$(tr '\n' ' ' <<<"$suspended")')" \
  "$([ "$suspended" = "$(printf 'continued\nabsent')" ] && echo true || echo false)"
# shellcheck disable=SC2016
checked=$(bash -c 'set -euo pipefail
  f() { local out; out=$(echo partial; exit 3) || exit 1; grep -q x <<<"$out"; }
  if f; then echo present; else echo absent; fi' 2>/dev/null)
checked_status=$?
assert "B4: an explicit check on the capture stops the script (got status $checked_status, output '$checked')" \
  "$([ "$checked_status" -eq 1 ] && [ -z "$checked" ] && echo true || echo false)"

# --- C. REFERENCE.md -------------------------------------------------------
section=$(awk '
  /^### `pipefail` and readers that exit early/ { in_section = 1; print; next }
  in_section && /^##/ { exit }
  in_section { print }
' "$reference")

assert "C1: REFERENCE.md has the pipefail section" \
  "$([ -n "$section" ] && echo true || echo false)"

# An assignment capture, e.g. `names=$(gh label list ...)`, then a here-string
# read of that variable.
assert "C2: section prescribes an assignment capture (VAR=\$(cmd))" \
  "$(grep -Eq '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\(' <<<"$section" && echo true || echo false)"
assert "C3: section reads the captured variable with a here-string" \
  "$(grep -Eq 'grep -[A-Za-z]*q[A-Za-z]* .*<<<"\$[A-Za-z_]' <<<"$section" && echo true || echo false)"
assert "C4: section says <<<\"\$(cmd)\" loses the producer's exit status" \
  "$(grep -qi "loses the producer's exit status" <<<"$section" && echo true || echo false)"
# No code line inside a fence may read from an inline substitution; prose that
# names the form to warn against it is outside the fences and not scanned.
section_code=$(awk '/^```/ { in_fence = !in_fence; next } in_fence { print }' <<<"$section")
inline_right=$(grep -E '^[^#]*grep -[A-Za-z]*q[A-Za-z]* [^#]*<<<"\$\(' <<<"$section_code" || true)
assert "C5: section offers no grep -q <<<\"\$(cmd)\" form as code (found: ${inline_right:-none})" \
  "$([ -z "$inline_right" ] && echo true || echo false)"
# shellcheck disable=SC2016  # the backticks are literal markdown, not a substitution
assert "C6: section says set -e is suspended in a function called from if/||" \
  "$(grep -qi 'suspends `set -e` inside a function' <<<"$(tr '\n' ' ' <<<"$section")" && echo true || echo false)"
assert "C7: a code example checks the capture's status on the assignment (VAR=\$(cmd) || ...)" \
  "$(grep -Eq '^[^#]*[A-Za-z_][A-Za-z0-9_]*=\$\(.*\)[[:space:]]*\|\|' <<<"$section_code" && echo true || echo false)"

# --- D. SKILL.md -----------------------------------------------------------
# shellcheck disable=SC2016  # the backticks are literal markdown, not a substitution
guideline=$(grep -E 'Under `pipefail`' "$skill" || true)
assert "D1: SKILL.md keeps the pipefail guideline" \
  "$([ -n "$guideline" ] && echo true || echo false)"
assert "D2: the guideline names the assignment capture form" \
  "$(grep -Eq '[A-Za-z_]+=\$\(' <<<"$guideline" && echo true || echo false)"

echo "PASSED=$pass_count FAILED=$fail_count"
[ "$fail_count" -eq 0 ]
