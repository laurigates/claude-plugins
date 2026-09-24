#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail`: pass/fail both exit 0
# Self-test for scripts/check-description-collisions.py (issue #2244).
#
# SEMANTIC, not syntactic: every case EXECUTES the sweep against planted
# fixtures and asserts on its structured output. A grep of the script for a
# token would pass against a sweep whose n-gram filter or weighting broke.
#
# The negative cases carry as much weight as the positives. A sweep that
# flagged every shared word would satisfy the "planted collision is found"
# case while being useless, so framing-only phrases, a gated skill, and a
# description with no `Use when` must all stay OUT of the collision list.
#
# Usage: bash scripts/tests/test-check-description-collisions.sh
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
checker="$repo_root/scripts/check-description-collisions.py"
audit_script="$repo_root/scripts/audit-skill-descriptions.py"

fixture="$(mktemp -d "${TMPDIR:-/tmp}/desc-collisions-XXXXXX")"
[ -n "$fixture" ] && [ -d "$fixture" ] || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$fixture"' EXIT

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); }
fail() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }

# Whole-line match: an unanchored `COLLISION_COUNT=1` is also satisfied by
# `COLLISION_COUNT=12` (the #2219/#2297 anchoring lesson).
has_line() { grep -qxF -- "$2" <<<"$1"; }
has_text() { grep -qF -- "$2" <<<"$1"; }

run_input() {
  # $1 = fixture JSON file; remaining args pass through
  local input="$1"; shift
  OUT="$(python3 "$checker" --input "$input" "$@" 2>&1)"
  RC=$?
}

write_json() { printf '%s\n' "$2" >"$fixture/$1"; }

rec() {
  # rec PLUGIN SKILL DESCRIPTION [auto_invokable]
  local auto="${4:-true}"
  python3 -c 'import json,sys; print(json.dumps({"plugin": sys.argv[1], "skill": sys.argv[2], "description_full": sys.argv[3], "auto_invokable": sys.argv[4] == "true"}))' \
    "$1" "$2" "$3" "$auto"
}

# --- A: a planted shared trigger across two plugins is flagged --------------
write_json a.json "[$(rec alpha-plugin one 'Frob widgets. Use when reticulating splines nightly.'),
$(rec beta-plugin two 'Grob gadgets. Use when reticulating splines on demand.'),
$(rec beta-plugin three 'Zork zaps. Use when polishing brass knobs.')]"
run_input "$fixture/a.json"
[ "$RC" -eq 0 ] && pass || fail "A: advisory sweep must exit 0 on collisions (rc=$RC)"
has_line "$OUT" "STATUS=WARN" && pass || fail "A: collision reports STATUS=WARN"
has_line "$OUT" "COLLISION_COUNT=1" && pass || fail "A: exactly one collision"
has_line "$OUT" "SKILLS_SCANNED=3" && pass || fail "A: all three records scanned"
has_text "$OUT" 'NGRAM="reticulating splines" SKILLS=2 PLUGINS=2 WEIGHT=4 MEMBERS=alpha-plugin/one,beta-plugin/two' \
  && pass || fail "A: planted phrase flagged with members + cross-plugin weight"
has_text "$OUT" "beta-plugin/three" && fail "A: a distinct description must not appear in any collision" || pass

# --- B: distinct descriptions are clean (and the scan was not vacuous) ------
write_json b.json "[$(rec alpha-plugin one 'Frob widgets. Use when reticulating splines.'),
$(rec beta-plugin two 'Zork zaps. Use when polishing brass knobs.')]"
run_input "$fixture/b.json"
[ "$RC" -eq 0 ] && pass || fail "B: clean corpus exits 0"
has_line "$OUT" "STATUS=OK" && pass || fail "B: clean corpus reports STATUS=OK"
has_line "$OUT" "COLLISION_COUNT=0" && pass || fail "B: no collisions"
has_line "$OUT" "SKILLS_SCANNED=2" && pass || fail "B: guard integrity — both records were actually scanned"

# --- C: unparseable / wrong-shape / empty input is ERROR, never a clean pass -
write_json c1.json '[{"plugin": "alpha-plugin", "skill": "one",'
run_input "$fixture/c1.json"
[ "$RC" -eq 1 ] && pass || fail "C1: malformed JSON exits 1 (rc=$RC)"
has_line "$OUT" "STATUS=ERROR" && pass || fail "C1: malformed JSON is STATUS=ERROR"
has_text "$OUT" "TYPE=malformed_input" && pass || fail "C1: malformed JSON names the cause"

write_json c2.json '{"plugin": "alpha-plugin"}'
run_input "$fixture/c2.json"
[ "$RC" -eq 1 ] && has_line "$OUT" "STATUS=ERROR" && pass || fail "C2: a non-array document is ERROR"

write_json c3.json '[]'
run_input "$fixture/c3.json"
[ "$RC" -eq 1 ] && pass || fail "C3: an empty record list exits 1"
has_text "$OUT" "TYPE=nothing_scanned" && pass || fail "C3: zero skills is a misfire, not a clean corpus"

write_json c4.json '[{"skill": "orphan", "description_full": "Use when x y."}]'
run_input "$fixture/c4.json"
[ "$RC" -eq 1 ] && has_text "$OUT" "TYPE=malformed_input" && pass || fail "C4: a record without plugin/skill is ERROR"

# --- D: framing-only phrases are not collisions; framing + content is --------
write_json d.json "[$(rec alpha-plugin one 'A. Use when the user mentions helm charts.'),
$(rec alpha-plugin two 'B. Use when the user mentions helm releases.'),
$(rec beta-plugin three 'C. Use when the user mentions kafka topics.')]"
run_input "$fixture/d.json"
has_text "$OUT" 'NGRAM="user mentions"' && fail "D: 'user mentions' frames a trigger and must not be a collision" || pass
has_text "$OUT" 'NGRAM="user mentions helm" SKILLS=2 PLUGINS=1 WEIGHT=2' \
  && pass || fail "D: the shared content word keeps 'user mentions helm' reportable"
has_line "$OUT" "COLLISION_COUNT=1" && pass || fail "D: only the helm pair collides"

# --- E: a sub-gram carried by the SAME skills is folded into the longer one --
write_json e.json "[$(rec alpha-plugin one 'A. Use when tuning widget harness.'),
$(rec alpha-plugin two 'B. Use when tuning widget harness.'),
$(rec beta-plugin three 'C. Use when the widget harness breaks.')]"
run_input "$fixture/e.json"
has_text "$OUT" 'NGRAM="tuning widget harness" SKILLS=2' && pass || fail "E: the maximal phrase is reported"
has_text "$OUT" 'NGRAM="tuning widget"' && fail "E: a same-set sub-gram must be folded, not reported twice" || pass
# Guard: a sub-gram shared by a DIFFERENT (larger) set is its own collision.
has_text "$OUT" 'NGRAM="widget harness" SKILLS=3 PLUGINS=2 WEIGHT=6' \
  && pass || fail "E: a sub-gram with a wider member set must still be reported"
has_line "$OUT" "COLLISION_COUNT=2" && pass || fail "E: two distinct collisions"

# --- F: cross-plugin collisions outrank same-plugin ones ---------------------
write_json f.json "[$(rec alpha-plugin one 'A. Use when frobbing gizmos.'),
$(rec alpha-plugin two 'B. Use when frobbing gizmos.'),
$(rec alpha-plugin three 'C. Use when zapping doodads.'),
$(rec beta-plugin four 'D. Use when zapping doodads.')]"
run_input "$fixture/f.json"
first_issue="$(grep -m1 'TYPE=trigger_collision' <<<"$OUT")"
has_text "$first_issue" 'NGRAM="zapping doodads" SKILLS=2 PLUGINS=2 WEIGHT=4' \
  && pass || fail "F: the cross-plugin pair (weight 4) sorts first"
has_text "$OUT" 'NGRAM="frobbing gizmos" SKILLS=2 PLUGINS=1 WEIGHT=2' \
  && pass || fail "F: the same-plugin pair keeps weight 2"
has_line "$OUT" "CROSS_PLUGIN_COLLISIONS=1" && pass || fail "F: one cross-plugin collision counted"

# --- G: gated skills and trigger-less descriptions do not collide ------------
write_json g.json "[$(rec alpha-plugin one 'A. Use when reticulating splines.'),
$(rec alpha-plugin gated 'B. Use when reticulating splines.' false),
$(rec beta-plugin notrigger 'Handles reticulating splines for you.')]"
run_input "$fixture/g.json"
has_line "$OUT" "COLLISION_COUNT=0" && pass || fail "G: a gated skill and a trigger-less one must not create a collision"
has_line "$OUT" "SKILLS_SCANNED=2" && pass || fail "G: the disable-model-invocation skill is excluded from the scan"
has_line "$OUT" "NO_USE_WHEN_SKIPPED=1" && pass || fail "G: the trigger-less description is counted, not tokenized"

# --- H: preview-only input is flagged, never read as a clean corpus ----------
write_json h.json '[{"plugin": "alpha-plugin", "skill": "one", "description": "Frob widgets across the whole fleet of rotating machinery while the operator waits. Use when reticulating spli..."},
{"plugin": "beta-plugin", "skill": "two", "description": "Grob gadgets across the whole fleet of rotating machinery while the operator waits. Use when reticulating spli..."}]'
run_input "$fixture/h.json"
has_line "$OUT" "PREVIEW_ONLY=2" && pass || fail "H: truncated previews are counted"
has_text "$OUT" "TYPE=truncated_input" && pass || fail "H: truncated input is a named WARN"
has_line "$OUT" "STATUS=WARN" && pass || fail "H: preview-only input cannot report STATUS=OK"

# --- I: an unknown argument exits 2, never a silent default run (#2057) ------
python3 "$checker" --max-dff 3 >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "I: an unknown flag exits 2"

# --- J/K need the audit script, which imports PyYAML -------------------------
if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "  (J/K skipped: PyYAML unavailable — the fixture cases above still ran)"
else
  # --- J: end to end through the audit — the collision lives past char 120 ---
  # The audit's `description` is a 120-char preview; this phrase sits beyond
  # it in both skills, so only a sweep reading `description_full` can see it.
  fx="$fixture/e2e"
  mkdir -p "$fx/scripts" "$fx/alpha-plugin/skills/one" "$fx/beta-plugin/skills/two"
  cp "$audit_script" "$fx/scripts/audit-skill-descriptions.py"
  long_head="Coordinates a long fleet of rotating machinery for the night operator and records every reading in the shared ledger."
  printf -- '---\nname: one\ndescription: %s Use when reticulating quantum splines nightly.\n---\n# one\n' "$long_head" \
    >"$fx/alpha-plugin/skills/one/SKILL.md"
  printf -- '---\nname: two\ndescription: %s Use when reticulating quantum splines on demand.\n---\n# two\n' "$long_head" \
    >"$fx/beta-plugin/skills/two/SKILL.md"
  preview="$(python3 "$fx/scripts/audit-skill-descriptions.py" --auto-invokable --json --all --list \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["description"])')"
  has_text "$preview" "splines" && fail "J: fixture validity — the phrase must lie past the 120-char preview" || pass
  OUT="$(python3 "$checker" --project-dir "$fx" 2>&1)"; RC=$?
  [ "$RC" -eq 0 ] && pass || fail "J: end-to-end sweep exits 0 (rc=$RC)"
  has_line "$OUT" "PREVIEW_ONLY=0" && pass || fail "J: the audit supplies description_full"
  has_text "$OUT" 'NGRAM="reticulating quantum splines" SKILLS=2 PLUGINS=2' \
    && pass || fail "J: a collision past the preview cut-off is found"

  # --- K: the real corpus — non-vacuous, advisory, full text available -----
  OUT="$(python3 "$checker" 2>&1)"; RC=$?
  [ "$RC" -eq 0 ] && pass || fail "K: the real corpus sweep is advisory (exit 0, rc=$RC)"
  has_line "$OUT" "SOURCE=audit-skill-descriptions.py" && pass || fail "K: default source is the audit"
  has_line "$OUT" "PREVIEW_ONLY=0" && pass || fail "K: every real record carries description_full"
  scanned="$(sed -n 's/^SKILLS_SCANNED=//p' <<<"$OUT")"
  [ "${scanned:-0}" -ge 100 ] && pass || fail "K: guard integrity — the real scan covered >=100 skills (got '${scanned:-}')"
  grep -qxE 'STATUS=(OK|WARN)' <<<"$OUT" && pass || fail "K: the real corpus is OK or WARN, never ERROR"
fi

echo "PASSED=$PASSED FAILED=$FAILED"
[ "$FAILED" -eq 0 ]
