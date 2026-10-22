#!/usr/bin/env bash
# Regression tests for migrate-generated-rules-keys.sh — the one-time fix-up for
# pre-contract `generated.rules` keys (issue #2868).
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
#
# Manifests written by blueprint 3.0.0 (format 3.2.0) key `generated.rules`
# WITHOUT `.md` (`architecture-patterns`) and carry no `content_hash`.
# /blueprint:sync resolves "$RULES_DIR/$key", finds nothing, and reports every
# rule missing. SEMANTIC, not syntactic: every case EXECUTES the script against
# a sandbox manifest and asserts on what lands in the JSON.
set -u

# Neutralize inherited git context so a sandbox op can never reach the shared
# checkout (issue #1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/../migrate-generated-rules-keys.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available"
    exit 0
fi

pass=0
fail=0
ok()    { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

assert_eq() { # <label> <expected> <actual>
    if [ "$2" = "$3" ]; then ok "$1"; else notok "$1 (expected '$2', got '$3')"; fi
}
assert_contains() { # <label> <needle> <haystack>
    case "$3" in *"$2"*) ok "$1" ;; *) notok "$1 (missing '$2')" ;; esac
}
assert_not_contains() { # <label> <needle> <haystack>
    case "$3" in *"$2"*) notok "$1 (unexpectedly found '$2')" ;; *) ok "$1" ;; esac
}

sha_of() { # <file>
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# A thelma-shaped project: format 3.2.0, four extensionless keys, no hashes,
# plus one key whose file does not exist.
make_project() {
    local p_dir
    p_dir="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 1; }
    [ -n "$p_dir" ] || { echo "FATAL: empty mktemp dir" >&2; exit 1; }
    [ -d "$p_dir" ] || { echo "FATAL: mktemp dir missing" >&2; exit 1; }
    mkdir -p "$p_dir/docs/blueprint" "$p_dir/.claude/rules"
    cat >"$p_dir/docs/blueprint/manifest.json" <<'JSON'
{
  "format_version": "3.2.0",
  "created_by": {"blueprint_plugin": "3.0.0"},
  "structure": {"generated_rules_path": ".claude/rules/"},
  "generated": {
    "rules": {
      "architecture-patterns": {"source": "docs/prds/", "generated_at": "2025-12-01T00:00:00Z", "plugin_version": "3.0.0", "status": "current"},
      "testing-strategies":    {"source": "docs/prds/", "generated_at": "2025-12-01T00:00:00Z", "plugin_version": "3.0.0", "status": "current"},
      "implementation-guides": {"source": "docs/prds/", "generated_at": "2025-12-01T00:00:00Z", "plugin_version": "3.0.0", "status": "current"},
      "quality-standards":     {"source": "docs/prds/", "generated_at": "2025-12-01T00:00:00Z", "plugin_version": "3.0.0", "status": "current"},
      "orphan-rule":           {"source": "docs/prds/", "generated_at": "2025-12-01T00:00:00Z", "status": "current"}
    }
  }
}
JSON
    for r in architecture-patterns testing-strategies implementation-guides quality-standards; do
        printf '# %s\n\nedited many times since generation\n' "$r" >"$p_dir/.claude/rules/$r.md"
    done
    printf '%s' "$p_dir"
}

proj="$(make_project)"
man="$proj/docs/blueprint/manifest.json"
rules="$proj/.claude/rules"

# ── CASE 1: --dry-run reports findings and writes nothing ────────────────────
before="$(cat "$man")"
out="$(bash "$SCRIPT" --project-dir "$proj" --dry-run 2>&1)"
rc=$?
assert_eq "case1: dry-run exits 0 (WARN is not an error)" "0" "$rc"
assert_contains "case1: dry-run mode is named" "MODE=dry-run" "$out"
assert_contains "case1: STATUS=WARN when keys need migrating" "STATUS=WARN" "$out"
assert_contains "case1: counts four extensionless keys" "KEY_MISSING_EXTENSION=4" "$out"
assert_contains "case1: counts four missing hashes" "RECORD_MISSING_HASH=4" "$out"
assert_contains "case1: names key_missing_extension" "TYPE=key_missing_extension KEY=architecture-patterns" "$out"
assert_contains "case1: names record_missing_hash" "TYPE=record_missing_hash KEY=architecture-patterns" "$out"
assert_contains "case1: the orphan key is reported unresolved" "TYPE=key_unresolved KEY=orphan-rule" "$out"
assert_eq "case1: dry-run leaves the manifest byte-identical" "$before" "$(cat "$man")"

# ── CASE 2: apply re-keys, backfills hash, preserves other fields ────────────
out="$(bash "$SCRIPT" --project-dir "$proj" 2>&1)"
rc=$?
assert_eq "case2: apply exits 0" "0" "$rc"
assert_contains "case2: apply mode is named" "MODE=apply" "$out"
assert_contains "case2: four entries migrated" "MIGRATED=4" "$out"
for r in architecture-patterns testing-strategies implementation-guides quality-standards; do
    assert_eq "case2: $r re-keyed with .md" "true" \
        "$(jq --arg k "$r.md" '.generated.rules | has($k)' "$man")"
    assert_eq "case2: old key $r removed" "false" \
        "$(jq --arg k "$r" '.generated.rules | has($k)' "$man")"
    assert_eq "case2: $r content_hash is bare sha256 of the current file" \
        "$(sha_of "$rules/$r.md")" \
        "$(jq -r --arg k "$r.md" '.generated.rules[$k].content_hash' "$man")"
    assert_eq "case2: $r status records the user edits as modified" "modified" \
        "$(jq -r --arg k "$r.md" '.generated.rules[$k].status' "$man")"
done
assert_eq "case2: source preserved" "docs/prds/" \
    "$(jq -r '.generated.rules["testing-strategies.md"].source' "$man")"
assert_eq "case2: generated_at preserved" "2025-12-01T00:00:00Z" \
    "$(jq -r '.generated.rules["testing-strategies.md"].generated_at' "$man")"
assert_eq "case2: plugin_version preserved" "3.0.0" \
    "$(jq -r '.generated.rules["testing-strategies.md"].plugin_version' "$man")"
assert_eq "case2: no source_hash invented" "false" \
    "$(jq '.generated.rules["testing-strategies.md"] | has("source_hash")' "$man")"
assert_eq "case2: the key without a matching file is left untouched" \
    '{"source":"docs/prds/","generated_at":"2025-12-01T00:00:00Z","status":"current"}' \
    "$(jq -c '.generated.rules["orphan-rule"]' "$man")"
assert_eq "case2: no orphan-rule.md key invented" "false" \
    "$(jq '.generated.rules | has("orphan-rule.md")' "$man")"
assert_contains "case2: the orphan key is still reported" "TYPE=key_unresolved KEY=orphan-rule" "$out"
assert_eq "case2: the rule files themselves are untouched" "$(printf '# quality-standards\n\nedited many times since generation')" \
    "$(cat "$rules/quality-standards.md")"
# The consumer contract: "$RULES_DIR/$key" resolves for every migrated key.
missing=0
while IFS= read -r k; do
    [ -f "$rules/$k" ] || missing=$((missing + 1))
done < <(jq -r '.generated.rules | keys[] | select(endswith(".md"))' "$man")
assert_eq "case2: every .md key resolves as \$RULES_DIR/\$key" "0" "$missing"

# ── CASE 3: second run is a no-op ────────────────────────────────────────────
after_first="$(cat "$man")"
out="$(bash "$SCRIPT" --project-dir "$proj" 2>&1)"
assert_contains "case3: second run migrates nothing" "MIGRATED=0" "$out"
assert_contains "case3: second run finds no extensionless key to fix" "KEY_MISSING_EXTENSION=0" "$out"
assert_eq "case3: second run leaves the manifest byte-identical" "$after_first" "$(cat "$man")"
out="$(bash "$SCRIPT" --project-dir "$proj" --dry-run 2>&1)"
assert_not_contains "case3: dry-run after migration has no record_missing_hash" "TYPE=record_missing_hash" "$out"
rm -rf "$proj"

# ── CASE 4: a .md key without content_hash is backfilled; hashed keys are not touched
proj="$(make_project)"
man="$proj/docs/blueprint/manifest.json"
printf 'dev\n' >"$proj/.claude/rules/development.md"
jq '.generated.rules = {
      "development.md": {"source": "blueprint-init", "content_hash": "abc", "status": "current"},
      "quality-standards.md": {"source": "docs/prds/", "status": "current"}
    }' "$man" >"$man.new" && mv "$man.new" "$man"
out="$(bash "$SCRIPT" --project-dir "$proj" --dry-run 2>&1)"
assert_contains "case4: .md key without hash flagged" "TYPE=record_missing_hash KEY=quality-standards.md" "$out"
assert_not_contains "case4: hashed key not flagged" "KEY=development.md" "$out"
bash "$SCRIPT" --project-dir "$proj" >/dev/null 2>&1
assert_eq "case4: hash backfilled on the .md key" \
    "$(sha_of "$proj/.claude/rules/quality-standards.md")" \
    "$(jq -r '.generated.rules["quality-standards.md"].content_hash' "$man")"
assert_eq "case4: an existing content_hash is never overwritten" '{"source":"blueprint-init","content_hash":"abc","status":"current"}' \
    "$(jq -c '.generated.rules["development.md"]' "$man")"
rm -rf "$proj"

# ── CASE 5: rekey collision with an existing .md record is left alone ─────────
proj="$(make_project)"
man="$proj/docs/blueprint/manifest.json"
jq '.generated.rules = {
      "testing-strategies": {"source": "old"},
      "testing-strategies.md": {"source": "new", "content_hash": "def", "status": "current"}
    }' "$man" >"$man.new" && mv "$man.new" "$man"
out="$(bash "$SCRIPT" --project-dir "$proj" 2>&1)"
assert_contains "case5: collision reported" "TYPE=key_conflict KEY=testing-strategies" "$out"
assert_eq "case5: the existing .md record is not clobbered" "new" \
    "$(jq -r '.generated.rules["testing-strategies.md"].source' "$man")"
assert_eq "case5: the extensionless record is kept for a human" "old" \
    "$(jq -r '.generated.rules["testing-strategies"].source' "$man")"
rm -rf "$proj"

# ── CASE 6: non-default rules dir and manifest without generated.rules ──────
proj="$(make_project)"
man="$proj/docs/blueprint/manifest.json"
mkdir -p "$proj/.claude/rules/blueprint"
printf 'x\n' >"$proj/.claude/rules/blueprint/architecture-patterns.md"
jq '.structure.generated_rules_path = ".claude/rules/blueprint/"
    | .generated.rules = {"architecture-patterns": {"source": "docs/prds/"}}' "$man" >"$man.new" && mv "$man.new" "$man"
bash "$SCRIPT" --project-dir "$proj" >/dev/null 2>&1
assert_eq "case6: resolves against structure.generated_rules_path" \
    "$(sha_of "$proj/.claude/rules/blueprint/architecture-patterns.md")" \
    "$(jq -r '.generated.rules["architecture-patterns.md"].content_hash' "$man")"
jq 'del(.generated)' "$man" >"$man.new" && mv "$man.new" "$man"
out="$(bash "$SCRIPT" --project-dir "$proj" --dry-run 2>&1)"
rc=$?
assert_eq "case6: no generated.rules exits 0" "0" "$rc"
assert_contains "case6: no generated.rules is STATUS=OK" "STATUS=OK" "$out"
rm -rf "$proj"

# ── CASE 7: no manifest is OK; unknown flag exits 2 and writes nothing ───────
proj="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$proj" ] || { echo "FATAL: empty mktemp dir" >&2; exit 1; }
out="$(bash "$SCRIPT" --project-dir "$proj" 2>&1)"
rc=$?
assert_eq "case7: missing manifest exits 0 (nothing to migrate)" "0" "$rc"
assert_contains "case7: missing manifest is SOURCE=none" "SOURCE=none" "$out"
rm -rf "$proj"
proj="$(make_project)"
man="$proj/docs/blueprint/manifest.json"
before="$(cat "$man")"
out="$(bash "$SCRIPT" --project-dir "$proj" --dryrun 2>&1)"
rc=$?
assert_eq "case7: unknown flag exits 2, never swallowed" "2" "$rc"
assert_contains "case7: names the unknown flag" "unknown argument: --dryrun" "$out"
assert_eq "case7: the manifest is untouched" "$before" "$(cat "$man")"
rm -rf "$proj"

# ── Clean / no-op paths: assert the FULL structured block ────────────────────
# Regression (PR #3052 review): the clean paths expanded empty arrays bare under
# `set -u` (`issues=("${findings[@]}")`). macOS /bin/bash 3.2 (and bash < 4.4)
# aborts there with `unbound variable` — exit 1, no STATUS line. These cases
# assert the whole block (header, STATUS, ISSUE_COUNT, footer, exit 0), so a
# crash under any interpreter fails them. The static check in CASE 11 catches
# the construct on a modern bash, where the crash itself cannot reproduce.
#
# OLD_BASH: an interpreter that exhibits the <4.4 empty-array behaviour, when
# one is available (macOS /bin/bash, or MIGRATE_TEST_OLD_BASH=/path/to/bash).
old_bash="${MIGRATE_TEST_OLD_BASH:-}"
if [ -z "$old_bash" ] && [ -x /bin/bash ]; then
    # shellcheck disable=SC2016  # the $BASH_VERSINFO expansions are for the child
    if /bin/bash -c '[ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }' 2>/dev/null; then
        old_bash=/bin/bash
    fi
fi
interpreters=(bash)
[ -n "$old_bash" ] && interpreters+=("$old_bash")

assert_clean_block() { # <label> <expected-mode> <expected-migrated> <rc> <out>
    assert_eq "$1: exits 0" "0" "$4"
    assert_contains "$1: section header" "=== GENERATED RULES KEY MIGRATION ===" "$5"
    assert_contains "$1: mode" "MODE=$2" "$5"
    assert_contains "$1: STATUS=OK" "STATUS=OK" "$5"
    assert_contains "$1: ISSUE_COUNT=0" "ISSUE_COUNT=0" "$5"
    assert_contains "$1: MIGRATED=$3" "MIGRATED=$3" "$5"
    assert_contains "$1: section footer" "=== END GENERATED RULES KEY MIGRATION ===" "$5"
    assert_not_contains "$1: no REASON on OK" "REASON=" "$5"
    assert_not_contains "$1: no unbound-variable crash" "unbound variable" "$5"
}

for interp in "${interpreters[@]}"; do
    tag="[$(basename "$interp")]"

    # ── CASE 8: clean, compliant manifest under --dry-run ────────────────────
    proj="$(make_project)"
    man="$proj/docs/blueprint/manifest.json"
    h="$(sha_of "$proj/.claude/rules/architecture-patterns.md")"
    jq --arg h "$h" '.generated.rules = {
          "architecture-patterns.md": {"source": "docs/prds/", "content_hash": $h, "status": "current"}
        }' "$man" >"$man.new" && mv "$man.new" "$man"
    before="$(cat "$man")"
    out="$("$interp" "$SCRIPT" --project-dir "$proj" --dry-run 2>&1)"
    rc=$?
    assert_clean_block "case8 $tag: compliant dry-run" "dry-run" "0" "$rc" "$out"
    assert_contains "case8 $tag: ENTRIES=1" "ENTRIES=1" "$out"
    assert_contains "case8 $tag: KEY_MISSING_EXTENSION=0" "KEY_MISSING_EXTENSION=0" "$out"
    assert_contains "case8 $tag: RECORD_MISSING_HASH=0" "RECORD_MISSING_HASH=0" "$out"
    assert_eq "case8 $tag: manifest untouched" "$before" "$(cat "$man")"
    # Same compliant manifest in apply mode: nothing to do, still a full block.
    out="$("$interp" "$SCRIPT" --project-dir "$proj" 2>&1)"
    rc=$?
    assert_clean_block "case8 $tag: compliant apply" "apply" "0" "$rc" "$out"
    assert_eq "case8 $tag: compliant apply writes nothing" "$before" "$(cat "$man")"
    rm -rf "$proj"

    # ── CASE 9: apply with an EMPTY residual set, then the idempotent rerun ──
    proj="$(make_project)"
    man="$proj/docs/blueprint/manifest.json"
    jq 'del(.generated.rules["orphan-rule"])' "$man" >"$man.new" && mv "$man.new" "$man"
    out="$("$interp" "$SCRIPT" --project-dir "$proj" 2>&1)"
    rc=$?
    assert_clean_block "case9 $tag: apply, empty residual" "apply" "4" "$rc" "$out"
    assert_contains "case9 $tag: UNRESOLVED=0" "UNRESOLVED=0" "$out"
    assert_contains "case9 $tag: CONFLICTS=0" "CONFLICTS=0" "$out"
    after_first="$(cat "$man")"
    out="$("$interp" "$SCRIPT" --project-dir "$proj" 2>&1)"
    rc=$?
    assert_clean_block "case9 $tag: second (idempotent) run" "apply" "0" "$rc" "$out"
    assert_eq "case9 $tag: second run leaves manifest byte-identical" "$after_first" "$(cat "$man")"
    out="$("$interp" "$SCRIPT" --project-dir "$proj" --dry-run 2>&1)"
    rc=$?
    assert_clean_block "case9 $tag: dry-run after migration" "dry-run" "0" "$rc" "$out"
    rm -rf "$proj"
done

# ── CASE 10: empty or missing flag values are unknown-argument errors ────────
# `--project-dir=` would root-anchor the rules dir (`/.claude/rules`), and a
# trailing `--manifest` with no value silently fell back to the default — a
# swallowed argument retargeting which file is written (#2057 class).
proj="$(make_project)"
man="$proj/docs/blueprint/manifest.json"
before="$(cat "$man")"
# A missing value used to `shift 2` past the end of "$@", which fails without
# shifting and loops forever — bound every call so a regression reads as a
# failure, not a hang (exit 124 != 2).
tmo=""
command -v timeout >/dev/null 2>&1 && tmo="timeout 20"
for args in "--project-dir=" "--manifest=" "--project-dir" "--manifest" "--manifest= --project-dir=$proj"; do
    # shellcheck disable=SC2086  # word-splitting the arg list is the point
    out="$(cd "$proj" && $tmo bash "$SCRIPT" $args 2>&1)"
    rc=$?
    assert_eq "case10: '$args' exits 2" "2" "$rc"
    assert_contains "case10: '$args' names an unknown argument" "unknown argument" "$out"
done
out="$($tmo bash "$SCRIPT" --manifest "" --project-dir "$proj" 2>&1)"
rc=$?
assert_eq "case10: '--manifest \"\"' exits 2" "2" "$rc"
out="$(cd "$proj" && $tmo bash "$SCRIPT" --project-dir "" 2>&1)"
rc=$?
assert_eq "case10: '--project-dir \"\"' exits 2" "2" "$rc"
assert_eq "case10: the manifest is untouched by every rejected invocation" "$before" "$(cat "$man")"
rm -rf "$proj"

# ── CASE 11: no bare empty-array expansion under set -u (bash 3.2) ───────────
# Static backstop for CASE 8/9 on a modern bash, where the crash cannot be
# reproduced: every `"${arr[@]}"` must be guarded as `${arr[@]+"${arr[@]}"}`.
# The strip deliberately has no `\1` backreference (#3147): macOS
# /usr/bin/sed -E does not apply a backreference inside the pattern, so the
# guarded form was never stripped there and every guarded line false-positived.
# Matching the two names independently costs only the same-name check.
bare="$(grep -vE '^[[:space:]]*#' "$SCRIPT" \
    | sed -E 's/\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\+"\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\}"\}//g' \
    | grep -nE '"\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\}"' || true)"
assert_eq "case11: no bare \"\${arr[@]}\" expansion (crashes bash 3.2 under set -u)" "" "$bare"
bash4="$(grep -vE '^[[:space:]]*#' "$SCRIPT" \
    | grep -nE 'declare -A|mapfile|readarray|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^|@Q)\}|declare -n' || true)"
assert_eq "case11: no bash-4+ constructs (macOS /bin/bash is 3.2)" "" "$bash4"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
