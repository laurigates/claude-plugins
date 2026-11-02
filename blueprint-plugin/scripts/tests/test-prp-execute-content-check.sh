#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016   # file-level: `cond && ok … || notok …`
# is the deliberate assertion idiom across this repo's test scripts (ok/notok
# both exit 0, so the || branch only runs on a real failure); SC2016 because
# the grep patterns match literal backticks in markdown. Must sit before the
# first command — see .claude/rules/shell-scripting.md.
#
# Regression test for issue #3002: the PRP content-quality evaluation runs as a
# fresh-reader dispatch inside /blueprint:prp-execute, before execution starts.
#
# The evaluation used to be an agent hook on `"matcher": "Skill(prp-execute)"`,
# which is tested against the tool name `Skill` and never matched, so it never
# ran (#2999 removed it). Its replacement lives in the skill body, so what can
# rot is prose: the dispatch drifting after the Step 2 baseline, the reader
# losing its independence (loop-integrity.md Pillar 1), or a criterion
# dropping out of the reader prompt. Each is asserted here.
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
set -u

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/../../skills/blueprint-prp-execute" && pwd)"
SKILL="${SKILL_DIR}/SKILL.md"
REF="${SKILL_DIR}/REFERENCE.md"

pass=0
fail=0
ok()    { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

line_of() { # <ERE> <file> -> first matching line number, or empty
    grep -nE -m1 "$1" "$2" | cut -d: -f1
}

# ---- A: the dispatch sits after the PRP load and before the Step 2 baseline -
load_ln="$(line_of 'Read PRP file' "$SKILL")"
step2_ln="$(line_of '^### Step 2' "$SKILL")"
dispatch_ln="$(line_of 'fresh[- ]reader' "$SKILL")"

[ -n "$dispatch_ln" ] && ok "A: SKILL.md has a fresh-reader content-quality step" || notok "A: no fresh-reader step in SKILL.md"
if [ -n "$dispatch_ln" ] && [ -n "$step2_ln" ] && [ "$dispatch_ln" -lt "$step2_ln" ]; then
    ok "A: the content-quality dispatch precedes the Step 2 baseline"
else
    notok "A: dispatch line '${dispatch_ln}' is not before Step 2 (line '${step2_ln}')"
fi
if [ -n "$dispatch_ln" ] && [ -n "$load_ln" ] && [ "$dispatch_ln" -gt "$load_ln" ]; then
    ok "A: the dispatch follows the PRP load"
else
    notok "A: dispatch line '${dispatch_ln}' does not follow the PRP load (line '${load_ln}')"
fi

# ---- B: the step dispatches an independent agent and stops on a fail -------
# Window: from the dispatch line to the Step 2 heading.
if [ -n "$dispatch_ln" ] && [ -n "$step2_ln" ]; then
    step_text="$(sed -n "${dispatch_ln},${step2_ln}p" "$SKILL")"
else
    step_text=""
fi
grep -qE '`(Task|Agent)`' <<<"$step_text" && ok "B: the step dispatches through the Task/Agent tool" || notok "B: the step names no Task/Agent dispatch"
grep -qiE 'only the PRP' <<<"$step_text" && ok "B: the reader is given only the PRP" || notok "B: the step does not limit the reader to the PRP"
grep -qF 'REFERENCE.md#prp-content-quality-check' <<<"$step_text" && ok "B: the step links the reader prompt in REFERENCE.md" || notok "B: no link to REFERENCE.md#prp-content-quality-check"
grep -qF '/blueprint:prp-create' <<<"$step_text" && ok "B: a failed check points at /blueprint:prp-create" || notok "B: a failed check does not suggest /blueprint:prp-create"
grep -qiE '\bstop\b' <<<"$step_text" && ok "B: a failed check stops execution" || notok "B: the step does not stop on a fail"
grep -qF 'Task' <<<"$(sed -n '/^allowed-tools:/p' "$SKILL")" && ok "B: Task is in allowed-tools" || notok "B: Task missing from allowed-tools"

# ---- C: the reader prompt names the four criteria and a determinate verdict -
ref_section="$(awk '/^## PRP Content-Quality Check/{f=1; print; next} f && /^## /{exit} f' "$REF")"
[ -n "$ref_section" ] && ok "C: REFERENCE.md has the PRP Content-Quality Check section" || notok "C: REFERENCE.md lacks ## PRP Content-Quality Check"
for crit in 'specific' 'acceptance criteria' 'edge cases' 'scope'; do
    grep -qiF "$crit" <<<"$ref_section" && ok "C: reader prompt covers '$crit'" || notok "C: reader prompt omits '$crit'"
done
grep -qF '{"ok": true}' <<<"$ref_section" && ok "C: verdict format has the pass shape" || notok "C: no {\"ok\": true} verdict"
grep -qF '"ok": false' <<<"$ref_section" && grep -qF '"reason"' <<<"$ref_section" \
    && ok "C: verdict format has the fail shape with a reason" || notok "C: no {\"ok\": false, \"reason\"} verdict"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
