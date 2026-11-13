#!/usr/bin/env bash
# shellcheck disable=SC2015   # file-level: `cond && ok … || notok …` is the
# deliberate assertion idiom across this repo's test scripts (ok/notok both
# exit 0, so the || branch only runs on a real failure). Must sit before the
# first command — see .claude/rules/shell-scripting.md.
#
# Regression test for issue #2950: `created_by.blueprint_plugin` (and the
# `--plugin-version` blueprint-init passes to register-generated-rules.sh) is
# the PLUGIN version, read from blueprint-plugin/.claude-plugin/plugin.json at
# run time. blueprint-init wrote "3.3.0" / "3.4.0" and blueprint-upgrade wrote
# "3.0.0": the blueprint FORMAT version in a field named for the plugin.
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
#
# Semantic invariant (per .claude/rules/regression-testing.md): a literal semver
# at any of these sites is the bug, whatever its value, so the test rejects the
# shape rather than one number. It then EXTRACTS the plugin.json read each skill
# documents, runs it with CLAUDE_SKILL_DIR substituted, and requires the result
# to equal plugin.json's version, so a read pointing at the wrong path fails too.
set -u

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PLUGIN_JSON="${PLUGIN_DIR}/.claude-plugin/plugin.json"

pass=0
fail=0
ok()    { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP - jq unavailable\n'
    exit 0
fi

want="$(jq -r '.version' "$PLUGIN_JSON")"
case "$want" in
  [0-9]*.[0-9]*.[0-9]*) ok "plugin.json carries a semver ($want)" ;;
  *) notok "plugin.json version is not a semver: '$want'"; want="" ;;
esac

SEMVER='[0-9]+\.[0-9]+\.[0-9]+'
INIT_SKILL="${PLUGIN_DIR}/skills/blueprint-init/SKILL.md"
INIT_TEMPLATE="${PLUGIN_DIR}/skills/blueprint-init/references/manifest-template.md"
UPGRADE_SKILL="${PLUGIN_DIR}/skills/blueprint-upgrade/SKILL.md"
UPGRADE_REF="${PLUGIN_DIR}/skills/blueprint-upgrade/REFERENCE.md"

# ---- A: no literal semver where the plugin version belongs ------------------
for f in "$INIT_TEMPLATE" "$UPGRADE_REF"; do
    rel="${f#"$PLUGIN_DIR"/}"
    if grep -qE "\"blueprint_plugin\"[[:space:]]*:[[:space:]]*\"${SEMVER}\"" "$f"; then
        notok "A: $rel hard-codes created_by.blueprint_plugin"
    else
        ok "A: $rel does not hard-code created_by.blueprint_plugin"
    fi
done

if grep -qE "\-\-plugin-version[[:space:]=]+\"?${SEMVER}" "$INIT_SKILL"; then
    notok "A: blueprint-init SKILL.md passes a literal --plugin-version"
else
    ok "A: blueprint-init SKILL.md does not pass a literal --plugin-version"
fi

if grep -qE "blueprint_plugin\`?[^.]{0,20}\"${SEMVER}\"" "$UPGRADE_SKILL"; then
    notok "A: blueprint-upgrade SKILL.md sets blueprint_plugin to a literal"
else
    ok "A: blueprint-upgrade SKILL.md does not set blueprint_plugin to a literal"
fi

# ---- B: each skill documents a plugin.json read that resolves to the version -
# Extract the first `jq -r .version "${CLAUDE_SKILL_DIR}/…plugin.json"` from the
# SKILL.md (never retype it here) and run it from that skill's directory.
check_read() { # <label> <SKILL.md>
    local c_label="$1" c_skill="$2" c_dir c_cmd c_got
    c_dir="$(cd "$(dirname "$c_skill")" && pwd)"
    c_cmd="$(grep -oE 'jq -r \.version "\$\{CLAUDE_SKILL_DIR\}/[^"]*plugin\.json"' "$c_skill" | head -n1)"
    if [ -z "$c_cmd" ]; then
        notok "B: $c_label SKILL.md documents no plugin.json version read"
        return
    fi
    ok "B: $c_label SKILL.md documents a plugin.json version read"
    c_got="$(CLAUDE_SKILL_DIR="$c_dir" bash -c "$c_cmd" 2>/dev/null)"
    [ -n "$want" ] && [ "$c_got" = "$want" ] \
        && ok "B: $c_label read resolves to plugin.json's version ($c_got)" \
        || notok "B: $c_label read returned '$c_got', want '$want'"
}
check_read blueprint-init "$INIT_SKILL"
check_read blueprint-upgrade "$UPGRADE_SKILL"

# blueprint-init used to pass --plugin-version "$(jq -r .version …)". A $(…) on
# a bundled-script line voids the skill's pre-approved grant (#3640), so init
# passes no --plugin-version and register-generated-rules.sh reads plugin.json
# itself (pinned by case 8 of test-register-generated-rules.sh).
grep -qE -- '(^[[:space:]]*|register-generated-rules\.sh.*[[:space:]])--plugin-version' "$INIT_SKILL" \
    && notok "B: blueprint-init passes --plugin-version (the script reads plugin.json itself)" \
    || ok "B: blueprint-init leaves --plugin-version to register-generated-rules.sh"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
