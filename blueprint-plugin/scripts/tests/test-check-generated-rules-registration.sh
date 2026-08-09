#!/usr/bin/env bash
# Regression tests for check-generated-rules-registration.sh (#2331).
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
#
# The defect the guard exists for is a MISSING WRITE. A syntactic pin would
# cement whatever spelling happened to ship (the #1417 -> #1819 lesson), so the
# guard encodes CONCEPTS with several accepted spellings — and this suite pins
# both halves of that:
#
#   REMOVAL fails   the registration substep deleted -> ERROR, exit 1
#   REWORD passes   the same behaviour written differently -> OK, exit 0
#
# Without the reword half, a guard that simply always fired would pass; without
# the removal half, a guard that never fired would pass.
set -u

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${SCRIPT_DIR}/../check-generated-rules-registration.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

pass=0
fail=0
ok()    { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

assert_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else notok "$1 (expected '$2', got '$3')"; fi; }
assert_contains() { case "$3" in *"$2"*) ok "$1" ;; *) notok "$1 (missing '$2')" ;; esac; }
assert_absent()   { case "$3" in *"$2"*) notok "$1 (unexpectedly found '$2')" ;; *) ok "$1" ;; esac; }

# A minimal but COMPLIANT fixture tree. Each case then breaks exactly one thing,
# so a finding is attributable.
make_fixture() {
    local f
    f="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 1; }
    [ -n "$f" ] || { echo "FATAL: empty mktemp dir" >&2; exit 1; }
    [ -d "$f" ] || { echo "FATAL: mktemp dir missing" >&2; exit 1; }
    mkdir -p "$f/blueprint-plugin/skills/blueprint-init" \
             "$f/blueprint-plugin/skills/blueprint-sync" \
             "$f/blueprint-plugin/skills/blueprint-promote" \
             "$f/blueprint-plugin/hooks" \
             "$f/blueprint-plugin/scripts"

    cat >"$f/blueprint-plugin/skills/blueprint-init/SKILL.md" <<'EOF'
# blueprint-init

8. Create initial rules under $RULES_DIR.

8a. Register them so /blueprint:sync can see them:

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/register-generated-rules.sh" \
  --source blueprint-init development.md testing.md
```

The keys are bare filenames including `.md`; each record carries a content_hash.
EOF

    cat >"$f/blueprint-plugin/skills/blueprint-sync/SKILL.md" <<'EOF'
# blueprint-sync

RULES_DIR=$(jq -r '.structure.generated_rules_path // ".claude/rules/"' docs/blueprint/manifest.json)

For each entry of `generated.rules | to_entries[]`, check `test -f "$RULES_DIR/{key}"`.
EOF

    cat >"$f/blueprint-plugin/skills/blueprint-promote/SKILL.md" <<'EOF'
# blueprint-promote

RULES_DIR=$(jq -r '.structure.generated_rules_path // ".claude/rules/"' docs/blueprint/manifest.json)
test -f "$RULES_DIR/$KEY"
EOF

    cat >"$f/blueprint-plugin/hooks/blueprint-drift-probe.sh" <<'EOF'
#!/usr/bin/env bash
jq -r --arg dir "$rules_dir" '
  (.generated.rules // {}) | to_entries[]
  | [(.value.path // ($dir + "/" + .key)), .value.content_hash] | @tsv
' "$MANIFEST"
EOF

    printf 'content_hash\n' >"$f/blueprint-plugin/scripts/register-generated-rules.sh"
    printf '%s' "$f"
}

run_guard() { bash "$GUARD" --project-dir "$1" 2>&1; }

# ── CASE A: the real repo is clean, and the scan is non-vacuous ──────────────
# Guard integrity: without the FILES_SCANNED assertion, every "clean" result
# below would also pass against a guard that read nothing (#2290's class).
out="$(bash "$GUARD" --project-dir "$REPO_ROOT" 2>&1)"
rc=$?
assert_eq "A: the repo's own tree passes" "0" "$rc"
assert_contains "A: STATUS=OK on the repo" "STATUS=OK" "$out"
scanned="$(printf '%s\n' "$out" | grep -m1 '^FILES_SCANNED=' | cut -d= -f2)"
if [ "${scanned:-0}" -gt 0 ]; then
    ok "A: the scan is non-vacuous (FILES_SCANNED=$scanned)"
else
    notok "A: scanned zero files — every clean assertion would be vacuous"
fi
assert_absent "A: the repo run is not flagged as an empty corpus" "SCANNED_EMPTY=true" "$out"

# ── CASE B: guard integrity — the compliant fixture must pass ────────────────
fix="$(make_fixture)"
out="$(run_guard "$fix")"
rc=$?
assert_eq "B: compliant fixture exits 0" "0" "$rc"
assert_contains "B: compliant fixture is STATUS=OK" "STATUS=OK" "$out"
rm -rf "$fix"

# ── CASE C: registration substep REMOVED -> ERROR ───────────────────────────
fix="$(make_fixture)"
cat >"$fix/blueprint-plugin/skills/blueprint-init/SKILL.md" <<'EOF'
# blueprint-init

8. Create initial rules under $RULES_DIR.

9. Handle .gitignore.
EOF
out="$(run_guard "$fix")"
rc=$?
assert_eq "C: removal of the registration substep exits 1" "1" "$rc"
assert_contains "C: names init_missing_registration" "TYPE=init_missing_registration" "$out"
assert_contains "C: names registration_omits_hash" "TYPE=registration_omits_hash" "$out"
rm -rf "$fix"

# ── CASE D: behaviour-preserving REWORD -> still OK ──────────────────────────
# Different words, different ordering, no `content_hash` in the prose at all —
# the behaviour is carried entirely by the script invocation.
fix="$(make_fixture)"
cat >"$fix/blueprint-plugin/skills/blueprint-init/SKILL.md" <<'EOF'
# blueprint-init

8. Write the starter rules.

8a. Record what you just wrote — sync cannot see an unrecorded rule:

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/register-generated-rules.sh" development.md
```
EOF
out="$(run_guard "$fix")"
rc=$?
assert_eq "D: a behaviour-preserving reword still exits 0" "0" "$rc"
assert_contains "D: reword is STATUS=OK" "STATUS=OK" "$out"

# The same reword, but the script it delegates to no longer emits content_hash:
# the concept check must follow the behaviour, not the prose.
printf 'no hashing here\n' >"$fix/blueprint-plugin/scripts/register-generated-rules.sh"
out="$(run_guard "$fix")"
assert_contains "D: delegation to a hash-less writer is caught" "TYPE=registration_omits_hash" "$out"
rm -rf "$fix"

# ── CASE E: an alternative registration spelling (raw jq) is accepted ────────
fix="$(make_fixture)"
cat >"$fix/blueprint-plugin/skills/blueprint-init/SKILL.md" <<'EOF'
# blueprint-init

8. Write the starter rules.

8a. Add a `generated.rules` entry per rule, each carrying a `content_hash`.
EOF
out="$(run_guard "$fix")"
rc=$?
assert_eq "E: a hand-rolled registration spelling still passes" "0" "$rc"
rm -rf "$fix"

# ── CASE F: double-suffix in sync -> ERROR ──────────────────────────────────
fix="$(make_fixture)"
cat >"$fix/blueprint-plugin/skills/blueprint-sync/SKILL.md" <<'EOF'
# blueprint-sync

RULES_DIR=$(jq -r '.structure.generated_rules_path // ".claude/rules/"' docs/blueprint/manifest.json)
test -f "$RULES_DIR/{key}.md"
EOF
out="$(run_guard "$fix")"
rc=$?
assert_eq "F: appending .md to a manifest key exits 1" "1" "$rc"
assert_contains "F: names key_form_double_suffix" "TYPE=key_form_double_suffix" "$out"
assert_absent "F: does not also mis-report the rules-dir rule" "TYPE=sync_hardcodes_rules_dir" "$out"
rm -rf "$fix"

# ── CASE G: the historical hardcoded form -> ERROR ──────────────────────────
fix="$(make_fixture)"
cat >"$fix/blueprint-plugin/skills/blueprint-sync/SKILL.md" <<'EOF'
# blueprint-sync

For each rule in manifest.generated.rules:
test -f .claude/rules/{name}.md
EOF
out="$(run_guard "$fix")"
rc=$?
assert_eq "G: the verbatim pre-fix sync step exits 1" "1" "$rc"
assert_contains "G: names key_form_double_suffix" "TYPE=key_form_double_suffix" "$out"
assert_contains "G: names sync_hardcodes_rules_dir" "TYPE=sync_hardcodes_rules_dir" "$out"
rm -rf "$fix"

# ── CASE H: the array-form drift probe -> ERROR ─────────────────────────────
fix="$(make_fixture)"
cat >"$fix/blueprint-plugin/hooks/blueprint-drift-probe.sh" <<'EOF'
#!/usr/bin/env bash
jq -r '(.generated.rules // [])[] | [.path, .content_hash] | @tsv' "$MANIFEST"
EOF
out="$(run_guard "$fix")"
rc=$?
assert_eq "H: array-form iteration exits 1" "1" "$rc"
assert_contains "H: names drift_probe_array_form" "TYPE=drift_probe_array_form" "$out"
rm -rf "$fix"

# ── CASE I: teaching the broken form is not using it ────────────────────────
# A blockquote in markdown and a comment in shell may cite the hazard.
fix="$(make_fixture)"
cat >>"$fix/blueprint-plugin/skills/blueprint-sync/SKILL.md" <<'EOF'

> Do NOT write `test -f "$RULES_DIR/{key}.md"` — the key already carries `.md`.
EOF
cat >>"$fix/blueprint-plugin/hooks/blueprint-drift-probe.sh" <<'EOF'
# Never iterate as (.generated.rules // [])[] — the schema defines an object.
EOF
out="$(run_guard "$fix")"
rc=$?
assert_eq "I: citing the broken forms in a callout/comment stays green" "0" "$rc"
assert_absent "I: no double-suffix finding from a blockquote" "TYPE=key_form_double_suffix" "$out"
assert_absent "I: no array-form finding from a shell comment" "TYPE=drift_probe_array_form" "$out"
rm -rf "$fix"

# ── CASE J: a tree with no blueprint-plugin is green and says so ────────────
empty="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$empty" ] || { echo "FATAL: empty mktemp dir" >&2; exit 1; }
out="$(run_guard "$empty")"
rc=$?
assert_eq "J: a non-blueprint tree exits 0" "0" "$rc"
assert_contains "J: reports SCANNED_EMPTY rather than a false clean" "SCANNED_EMPTY=true" "$out"
rm -rf "$empty"

# ── CASE K: unknown argument exits 2 (issue #2057) ──────────────────────────
out="$(bash "$GUARD" --only-init 2>&1)"
rc=$?
assert_eq "K: unknown flag exits 2, never swallowed" "2" "$rc"
assert_contains "K: names the unknown flag" "unknown argument: --only-init" "$out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
