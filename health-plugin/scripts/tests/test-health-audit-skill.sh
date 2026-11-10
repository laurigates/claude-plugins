#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # pass/fail never fails; backticks in grep patterns are literal
# Regression test: health-audit reads enabledPlugins as an OBJECT.
#
# enabledPlugins maps "plugin-name@marketplace-name" to a boolean
# (https://code.claude.com/docs/en/settings-reference#enabledplugins). The
# skill used to read it as an array (`jq -r '.enabledPlugins[]? // empty'`),
# which prints the booleans `true`/`false` instead of plugin IDs and treats a
# `false` (explicitly disabled) entry as enabled. It also told the agent that
# `claude plugin list --json` lists marketplace plugins, which on 2.1.322 needs
# `--available`.
#
# What this pins:
#   A. no `.enabledPlugins[]` array read and no "enabledPlugins array" prose
#      survives in any file of the skill
#   B. every `claude plugin list --json` the skill documents carries --available
#   C. every documented enabledPlugins filter (the FILTER_* assignments in
#      scripts/enabled-plugins.sh, and any `jq -r '…'` in the markdown), run
#      against an object-form fixture, prints IDs: the true entry, never the
#      false one, never a bare boolean
#   D-H. enabled-plugins.sh list/apply behaviour on the same fixture
#   I. every stack-detection Context command that uses -quit prints its first
#      match (`-quit -print` printed nothing, at HEAD too)
#
# Proof it fails on the pre-fix text: point HEALTH_AUDIT_SKILL_DIR at a dir
# holding the pre-fix SKILL.md and REFERENCE.md (no scripts/); A, B, C and
# D-H fail there.
#
# Hermetic: every file it reads or writes is under a mktemp sandbox.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SKILL_DIR="${HEALTH_AUDIT_SKILL_DIR:-${REPO_ROOT}/health-plugin/skills/health-audit}"
SCRIPT="${SKILL_DIR}/scripts/enabled-plugins.sh"
VALIDATOR="${REPO_ROOT}/scripts/check-structured-output-contract.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed"
  exit 0
fi

SANDBOX="$(mktemp -d)"
if [ -z "$SANDBOX" ] || [ ! -d "$SANDBOX" ]; then
  echo "FATAL: mktemp -d failed" >&2
  exit 2
fi
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

TRUE_ID="bravo-plugin@fixture-market"
FALSE_ID="charlie-plugin@fixture-market"
USER_ONLY_ID="alpha-plugin@fixture-market"
NEW_ID="delta-plugin@fixture-market"

# Fixture: user enables alpha; project enables bravo and disables charlie;
# local disables alpha again (local > project > user).
make_fixture() {
  local fx="$1"
  mkdir -p "$fx/home/.claude" "$fx/proj/.claude"
  printf '{"enabledPlugins":{"%s":true}}\n' "$USER_ONLY_ID" >"$fx/home/.claude/settings.json"
  printf '{"model":"keep-me","permissions":{"allow":["Read"]},"enabledPlugins":{"%s":true,"%s":false}}\n' \
    "$TRUE_ID" "$FALSE_ID" >"$fx/proj/.claude/settings.json"
  printf '{"enabledPlugins":{"%s":false}}\n' "$USER_ONLY_ID" >"$fx/proj/.claude/settings.local.json"
}

FX="$SANDBOX/fx"
make_fixture "$FX"
PROJECT_JSON="$FX/proj/.claude/settings.json"

# --- A. no array-form read anywhere in the skill -----------------------------
if [ ! -d "$SKILL_DIR" ]; then
  fail "A: skill dir missing: $SKILL_DIR"
else
  array_hits="$(grep -rnE '\.enabledPlugins\[\]' "$SKILL_DIR" || true)"
  if [ -z "$array_hits" ]; then
    pass "A: no .enabledPlugins[] array read in the skill files"
  else
    fail "A: array read survives: ${array_hits//$'\n'/ | }"
  fi
  prose_hits="$(grep -rniE 'enabledPlugins`? array' "$SKILL_DIR" || true)"
  if [ -z "$prose_hits" ]; then
    pass "A: no 'enabledPlugins array' prose"
  else
    fail "A: array prose survives: ${prose_hits//$'\n'/ | }"
  fi
fi

# --- B. plugin list --json in SKILL.md carries --available ------------------
# SKILL.md is what the agent executes; REFERENCE.md may name the bare form to
# contrast its shape.
list_lines="$(grep -oE '`claude plugin list[^`]*--json[^`]*`' "$SKILL_DIR/SKILL.md" 2>/dev/null || true)"
if [ -z "$list_lines" ]; then
  fail "B: SKILL.md documents no 'claude plugin list ... --json' invocation"
else
  missing_avail="$(grep -vE -- '--available' <<<"$list_lines" || true)"
  if [ -z "$missing_avail" ]; then
    pass "B: every 'claude plugin list --json' in SKILL.md carries --available"
  else
    fail "B: missing --available: ${missing_avail//$'\n'/ | }"
  fi
fi

# --- C. documented filters print IDs, not booleans ---------------------------
# Filters are extracted from the shipped text, never retyped here.
declare -a filter_names=()
declare -a filter_bodies=()
if [ -f "$SCRIPT" ]; then
  while IFS= read -r line; do
    name="${line%%=*}"
    body="${line#*=\'}"
    body="${body%\'}"
    filter_names+=("$name")
    filter_bodies+=("$body")
  done < <(grep -E "^FILTER_[A-Z_]+='[^']*'$" "$SCRIPT" || true)
fi
for md in "$SKILL_DIR"/*.md; do
  [ -f "$md" ] || continue
  while IFS= read -r body; do
    filter_names+=("doc:$(basename "$md")")
    filter_bodies+=("$body")
  done < <(grep -oE "jq -r '[^']*enabledPlugins[^']*'" "$md" | sed -E "s/^jq -r '//; s/'$//" || true)
done

id_filters=0
for i in "${!filter_names[@]}"; do
  name="${filter_names[$i]}"
  body="${filter_bodies[$i]}"
  [ "$name" = "FILTER_TYPE" ] && continue
  id_filters=$((id_filters + 1))
  out="$(jq -r "$body" "$PROJECT_JSON" 2>&1)"
  want="$TRUE_ID"
  [ "$name" = "FILTER_DISABLED" ] && want="$FALSE_ID"
  if grep -qxE 'true|false' <<<"$out"; then
    fail "C: $name prints bare booleans: ${out//$'\n'/,}"
  elif [ "$out" = "$want" ]; then
    pass "C: $name prints exactly $want"
  else
    fail "C: $name printed '${out//$'\n'/,}', want '$want'"
  fi
done
if [ "$id_filters" -eq 0 ]; then
  fail "C: no documented enabledPlugins filter found to execute"
fi
if [ -f "$SCRIPT" ]; then
  type_body=""
  for i in "${!filter_names[@]}"; do
    [ "${filter_names[$i]}" = "FILTER_TYPE" ] && type_body="${filter_bodies[$i]}"
  done
  if [ "$(jq -r "$type_body" "$PROJECT_JSON" 2>&1)" = "object" ]; then
    pass "C: FILTER_TYPE reports object for the fixture"
  else
    fail "C: FILTER_TYPE did not report object"
  fi
fi

# --- I. stack-detection Context commands print their first match --------------
# `find … -quit -print` evaluates -quit first, so it never prints and the stack
# detection always saw no workflows, Terraform or Kubernetes manifests. Each
# Context command that uses -quit is extracted from SKILL.md and run in a
# fixture that holds one of each; it must print a path.
FXI="$SANDBOX/fxi"
mkdir -p "$FXI/.github/workflows" "$FXI/k8s"
: >"$FXI/.github/workflows/ci.yml"
: >"$FXI/main.tf"
: >"$FXI/k8s/deploy.yaml"
quit_cmds=()
while IFS= read -r ctx_cmd; do
  quit_cmds+=("$ctx_cmd")
done < <(grep -oE '!`find [^`]*-quit[^`]*`' "$SKILL_DIR/SKILL.md" 2>/dev/null | sed -E 's/^!`//; s/`$//' || true)
if [ "${#quit_cmds[@]}" -eq 0 ]; then
  fail "I: no find … -quit Context command found in SKILL.md"
fi
for ctx_cmd in "${quit_cmds[@]}"; do
  if [[ "$ctx_cmd" == *'-quit -print'* ]]; then
    fail "I: -quit before -print never prints: $ctx_cmd"
    continue
  fi
  printed="$(cd "$FXI" && bash -c "$ctx_cmd" 2>&1)"
  if [ -n "$printed" ]; then
    pass "I: prints its first match: ${ctx_cmd}"
  else
    fail "I: printed nothing in a fixture that has a match: ${ctx_cmd}"
  fi
done

# Remaining cases need the script.
if [ ! -f "$SCRIPT" ]; then
  fail "D-H: $SCRIPT does not exist"
  echo "RESULT: ${PASS} passed, ${FAIL} failed"
  exit 1
fi

validate() {
  # $1 label, $2 captured output
  [ -f "$VALIDATOR" ] || return 0
  if bash "$VALIDATOR" --validate - <<<"$2" >"$SANDBOX/validate.out" 2>&1; then
    pass "$1: output passes the structured-output contract"
  else
    fail "$1: structured-output contract: $(tr '\n' ' ' <"$SANDBOX/validate.out")"
  fi
}

# --- D. list: per-scope IDs and effective precedence -------------------------
out="$(bash "$SCRIPT" list --home-dir "$FX/home" --project-dir "$FX/proj")"
rc=$?
[ "$rc" -eq 0 ] && pass "D: list exits 0" || fail "D: list exited $rc"
grep -qx "STATUS=OK" <<<"$out" && pass "D: STATUS=OK" || fail "D: STATUS not OK"
grep -qx "PROJECT_ENABLED=${TRUE_ID}" <<<"$out" && pass "D: PROJECT_ENABLED has the true entry" || fail "D: PROJECT_ENABLED missing ${TRUE_ID}"
grep -qx "PROJECT_DISABLED=${FALSE_ID}" <<<"$out" && pass "D: PROJECT_DISABLED has the false entry" || fail "D: PROJECT_DISABLED missing ${FALSE_ID}"
if grep -q "_ENABLED=${FALSE_ID}" <<<"$out"; then
  fail "D: false entry reported as enabled"
else
  pass "D: false entry never reported as enabled"
fi
effective="$(grep '^EFFECTIVE_ENABLED=' <<<"$out" | sort | tr '\n' ' ')"
if [ "$effective" = "EFFECTIVE_ENABLED=${TRUE_ID} " ]; then
  pass "D: EFFECTIVE_ENABLED applies local > project > user"
else
  fail "D: EFFECTIVE_ENABLED='${effective}', want only ${TRUE_ID} (local false overrides user true)"
fi
if grep -qE '=(true|false)$' <<<"$(grep -E '_(ENABLED|DISABLED)=' <<<"$out")"; then
  fail "D: an ID line carries a bare boolean"
else
  pass "D: no ID line carries a bare boolean"
fi
validate "D" "$out"

# --- E. list: legacy array value is flagged, not read ------------------------
FXE="$SANDBOX/fxe"
mkdir -p "$FXE/home/.claude" "$FXE/proj/.claude"
printf '{"enabledPlugins":["%s"]}\n' "$TRUE_ID" >"$FXE/proj/.claude/settings.json"
out="$(bash "$SCRIPT" list --home-dir "$FXE/home" --project-dir "$FXE/proj")"
rc=$?
if [ "$rc" -eq 0 ] && grep -qx "STATUS=WARN" <<<"$out" && grep -q "TYPE=not_object" <<<"$out"; then
  pass "E: array-valued enabledPlugins reported as WARN not_object"
else
  fail "E: array-valued enabledPlugins not flagged (rc=$rc)"
fi
if grep -q "ENABLED=" <<<"$out"; then
  fail "E: IDs emitted from an array-valued enabledPlugins"
else
  pass "E: nothing read from an array-valued enabledPlugins"
fi
validate "E" "$out"

# --- F. apply: set true / remove key, keep the rest --------------------------
FXF="$SANDBOX/fxf"
make_fixture "$FXF"
target="$FXF/proj/.claude/settings.json"
cp "$target" "$SANDBOX/original.json"
out="$(bash "$SCRIPT" apply --settings "$target" --enable "$NEW_ID" --remove "$TRUE_ID")"
rc=$?
[ "$rc" -eq 0 ] && pass "F: apply exits 0" || fail "F: apply exited $rc: ${out//$'\n'/ | }"
if [ "$(jq -c '.enabledPlugins' "$target")" = "{\"${FALSE_ID}\":false,\"${NEW_ID}\":true}" ]; then
  pass "F: added key set true, removed key gone, false entry kept"
else
  fail "F: enabledPlugins after apply = $(jq -c '.enabledPlugins' "$target")"
fi
if [ "$(jq -r '.model' "$target")" = "keep-me" ] && [ "$(jq -c '.permissions' "$target")" = '{"allow":["Read"]}' ]; then
  pass "F: other settings preserved"
else
  fail "F: other settings changed"
fi
if cmp -s "$SANDBOX/original.json" "${target}.backup"; then
  pass "F: backup equals the original file"
else
  fail "F: backup missing or different"
fi
enabled_body=""
for i in "${!filter_names[@]}"; do
  [ "${filter_names[$i]}" = "FILTER_ENABLED" ] && enabled_body="${filter_bodies[$i]}"
done
if [ -n "$enabled_body" ] && [ "$(jq -r "$enabled_body" "$target")" = "$NEW_ID" ]; then
  pass "F: FILTER_ENABLED reads the edited file as ${NEW_ID} only"
else
  fail "F: FILTER_ENABLED on the edited file is wrong or missing"
fi
validate "F" "$out"

# --- G. apply: missing file is created; emptied object is dropped ------------
created="$SANDBOX/fxg/.claude/settings.json"
out="$(bash "$SCRIPT" apply --settings "$created" --enable "$NEW_ID")"
rc=$?
if [ "$rc" -eq 0 ] && grep -qx "CREATED=true" <<<"$out" \
  && [ "$(jq -c '.' "$created")" = "{\"enabledPlugins\":{\"${NEW_ID}\":true}}" ]; then
  pass "G: missing settings file created with the object form"
else
  fail "G: create path wrong (rc=$rc): $(jq -c '.' "$created" 2>&1)"
fi
out="$(bash "$SCRIPT" apply --settings "$created" --remove "$NEW_ID")"
if [ "$(jq -c '.' "$created")" = "{}" ]; then
  pass "G: removing the last key drops enabledPlugins"
else
  fail "G: after removing the last key: $(jq -c '.' "$created")"
fi

# --- H. apply: invalid ID and absent key -------------------------------------
FXH="$SANDBOX/fxh"
make_fixture "$FXH"
target="$FXH/proj/.claude/settings.json"
cp "$target" "$SANDBOX/before-h.json"
out="$(bash "$SCRIPT" apply --settings "$target" --enable "no-marketplace")"
rc=$?
if [ "$rc" -eq 1 ] && grep -q "TYPE=invalid_id" <<<"$out" && cmp -s "$SANDBOX/before-h.json" "$target"; then
  pass "H: invalid ID rejected, file unchanged"
else
  fail "H: invalid ID not rejected cleanly (rc=$rc)"
fi
validate "H-invalid" "$out"
out="$(bash "$SCRIPT" apply --settings "$target" --remove "echo-plugin@fixture-market")"
rc=$?
if [ "$rc" -eq 0 ] && grep -qx "STATUS=WARN" <<<"$out" && grep -q "TYPE=not_present" <<<"$out"; then
  pass "H: removing an absent key is a WARN"
else
  fail "H: absent-key removal not reported (rc=$rc)"
fi
validate "H-absent" "$out"

echo "RESULT: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
