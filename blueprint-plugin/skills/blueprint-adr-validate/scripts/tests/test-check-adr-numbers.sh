#!/usr/bin/env bash
# Regression test for check-adr-numbers.sh (issue #1585).
# Auto-discovered by scripts/run-skill-script-tests.sh via
# */skills/*/scripts/tests/test-*.sh.
set -uo pipefail

# Neutralize any inherited git context so `git -C "$sandbox"` cannot be hijacked
# into the real shared .git (issue #1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/../check-adr-numbers.sh"

pass=0
fail=0
ok()   { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }

# --- fixture: a git repo with a base commit (origin/main-like) ----------------
SANDBOX="$(mktemp -d)"
[ -n "$SANDBOX" ] || { echo "mktemp failed"; exit 1; }
trap 'rm -rf "$SANDBOX"' EXIT

git -C "$SANDBOX" init -q
git -C "$SANDBOX" config user.email t@t.t
git -C "$SANDBOX" config user.name t
mkdir -p "$SANDBOX/docs/adrs"

# Base ref holds ADR 0038 under one filename, indexed in the README.
cat > "$SANDBOX/docs/adrs/0038-declarative-bootstrapping.md" <<'MD'
# ADR-0038: Declarative bootstrapping
status: Accepted
MD
cat > "$SANDBOX/docs/adrs/README.md" <<'MD'
# ADRs
- [ADR-0038](0038-declarative-bootstrapping.md)
MD
git -C "$SANDBOX" add -A
git -C "$SANDBOX" commit -q -m "base"
git -C "$SANDBOX" branch base-main

run() { bash "$CHECK" --project-dir "$SANDBOX" --base-ref "$1"; }

# --- TEST A: clean tree matching base → STATUS=OK -----------------------------
out="$(run base-main)"
if grep -q '^STATUS=OK$' <<<"$out"; then ok "A: clean tree → OK"; else bad "A: clean tree should be OK"; echo "$out"; fi

# --- TEST B: parallel-PR collision — a PR branched before the base's 0038
# merged, so its working tree has 0038-sensor but NOT the 0038-declarative that
# now sits on base-main under a different filename.
rm -f "$SANDBOX/docs/adrs/0038-declarative-bootstrapping.md"
cat > "$SANDBOX/docs/adrs/0038-sensor-pipeline.md" <<'MD'
# ADR-0038: Sensor pipeline
status: Accepted
MD
# index the new one so we isolate the collision (not the missing-index) signal
cat > "$SANDBOX/docs/adrs/README.md" <<'MD'
# ADRs
- [ADR-0038 sensor](0038-sensor-pipeline.md)
MD
out="$(run base-main)"; rc=$?
if grep -q 'TYPE=adr_number_collision' <<<"$out" && grep -q '^STATUS=ERROR$' <<<"$out"; then
  ok "B: base-ref collision detected (ERROR)"
else bad "B: expected adr_number_collision ERROR"; echo "$out"; fi
if [ "$rc" -eq 1 ]; then ok "B: exit 1 on collision"; else bad "B: expected exit 1, got $rc"; fi
rm -f "$SANDBOX/docs/adrs/0038-sensor-pipeline.md"
git -C "$SANDBOX" checkout -q -- docs/adrs/

# --- TEST C: two files in the working tree claim the same number --------------
cat > "$SANDBOX/docs/adrs/0041-alpha.md" <<'MD'
# ADR-0041: Alpha
MD
cat > "$SANDBOX/docs/adrs/0041-beta.md" <<'MD'
# ADR-0041: Beta
MD
printf -- '- [ADR-0041 a](0041-alpha.md)\n- [ADR-0041 b](0041-beta.md)\n' >> "$SANDBOX/docs/adrs/README.md"
out="$(run base-main)"
if grep -q 'TYPE=duplicate_adr_number' <<<"$out" && grep -q '^STATUS=ERROR$' <<<"$out"; then
  ok "C: within-tree duplicate detected (ERROR)"
else bad "C: expected duplicate_adr_number ERROR"; echo "$out"; fi
rm -f "$SANDBOX/docs/adrs/0041-alpha.md" "$SANDBOX/docs/adrs/0041-beta.md"
git -C "$SANDBOX" checkout -q -- docs/adrs/README.md

# --- TEST D: an ADR absent from the README index → WARN -----------------------
cat > "$SANDBOX/docs/adrs/0042-unindexed.md" <<'MD'
# ADR-0042: Unindexed
MD
out="$(run base-main)"; rc=$?
if grep -q 'TYPE=adr_missing_index_row' <<<"$out" && grep -q '^STATUS=WARN$' <<<"$out"; then
  ok "D: missing index row detected (WARN)"
else bad "D: expected adr_missing_index_row WARN"; echo "$out"; fi
if [ "$rc" -eq 0 ]; then ok "D: WARN exits 0 (parallel-safe)"; else bad "D: WARN should exit 0, got $rc"; fi
rm -f "$SANDBOX/docs/adrs/0042-unindexed.md"

# --- TEST E: no docs/adrs dir → OK, no false positive -------------------------
E_SANDBOX="$(mktemp -d)"
[ -n "$E_SANDBOX" ] || { echo "mktemp failed"; exit 1; }
git -C "$E_SANDBOX" init -q
out="$(bash "$CHECK" --project-dir "$E_SANDBOX" --base-ref HEAD 2>/dev/null)"
if grep -q 'ADR_DIR=none' <<<"$out" && grep -q '^STATUS=OK$' <<<"$out"; then
  ok "E: no ADR dir → OK"
else bad "E: missing ADR dir should be OK"; echo "$out"; fi
rm -rf "$E_SANDBOX"

# --- TEST F: base ref unavailable → still runs (dupes/index only) --------------
out="$(bash "$CHECK" --project-dir "$SANDBOX" --base-ref does-not-exist 2>/dev/null)"
if grep -q '^BASE_REF_AVAILABLE=false$' <<<"$out" && grep -q '^STATUS=OK$' <<<"$out"; then
  ok "F: absent base ref degrades gracefully"
else bad "F: absent base ref should degrade to OK"; echo "$out"; fi

# ==============================================================================
# Issue #2129 — the guard reported STATUS=OK on a real ADR-0016 collision.
# ==============================================================================

# --- fixture: the reported shape — two ADR directories, one claimant numbered
# only in FRONTMATTER (no number in its filename), the other by BASENAME. -------
new_sandbox() { # -> prints a fresh git-repo sandbox path
  local s
  s="$(mktemp -d)" || return 1
  [ -n "$s" ] || return 1
  git -C "$s" init -q
  git -C "$s" config user.email t@t.t
  git -C "$s" config user.name t
  printf '%s\n' "$s"
}

G_SANDBOX="$(new_sandbox)" || { echo "mktemp failed"; exit 1; }
[ -n "$G_SANDBOX" ] || { echo "mktemp failed"; exit 1; }
trap 'rm -rf "$SANDBOX" "$G_SANDBOX"' EXIT
mkdir -p "$G_SANDBOX/docs/blueprint/adrs" "$G_SANDBOX/docs/adrs"

# Registered claimant: number in the filename AND in frontmatter.
cat > "$G_SANDBOX/docs/blueprint/adrs/0016-in-engine-ui-not-win32-dialogs.md" <<'MD'
---
id: ADR-0016
status: Accepted
title: In-engine UI, not Win32 dialogs
---

# ADR-0016: In-engine UI, not Win32 dialogs
MD
# UNREGISTERED claimant: number ONLY in frontmatter — invisible to a
# basename-only guard, which is exactly how this collision hid.
cat > "$G_SANDBOX/docs/adrs/objs-format.md" <<'MD'
---
id: ADR-0016
status: Accepted
title: OBJS format
---

# OBJS format
MD
# Index both dirs so we isolate the collision signal from missing-index WARNs.
printf '# ADRs\n- [ADR-0016](0016-in-engine-ui-not-win32-dialogs.md)\n' \
  > "$G_SANDBOX/docs/blueprint/adrs/README.md"
printf '# ADRs\n- [ADR-0016](objs-format.md)\n' > "$G_SANDBOX/docs/adrs/README.md"

# --- TEST G: the reported bug — cross-directory, frontmatter-only claim --------
out="$(bash "$CHECK" --project-dir "$G_SANDBOX" \
        --adr-dir docs/adrs --adr-dir docs/blueprint/adrs \
        --base-ref does-not-exist 2>/dev/null)"; rc=$?
if grep -q 'TYPE=duplicate_adr_number' <<<"$out" \
   && grep -q 'docs/adrs/objs-format.md' <<<"$out" \
   && grep -q 'docs/blueprint/adrs/0016-in-engine-ui-not-win32-dialogs.md' <<<"$out" \
   && grep -q '^STATUS=ERROR$' <<<"$out"; then
  ok "G: frontmatter-only claim colliding across directories → ERROR"
else bad "G: expected duplicate_adr_number naming BOTH claimants"; echo "$out"; fi
if [ "$rc" -eq 1 ]; then ok "G: exit 1 on the cross-directory collision"; else bad "G: expected exit 1, got $rc"; fi
# The message must say WHERE the number came from — "claimed by objs-format.md"
# is baffling to a reader whose file has no number in its name.
if grep -qE 'objs-format\.md \((frontmatter|basename\+frontmatter)\)' <<<"$out"; then
  ok "G: claim source (frontmatter) named in the message"
else bad "G: expected the claim source in the duplicate message"; echo "$out"; fi
# The frontmatter-only claimant is counted, proving the collection step widened.
if grep -q '^FRONTMATTER_ONLY_CLAIMS=1$' <<<"$out"; then
  ok "G: frontmatter-only claim counted"
else bad "G: expected FRONTMATTER_ONLY_CLAIMS=1"; echo "$out"; fi

# --- TEST H: --adr-dir is repeatable AND actually scopes the scan --------------
out="$(bash "$CHECK" --project-dir "$G_SANDBOX" \
        --adr-dir docs/adrs --adr-dir docs/blueprint/adrs \
        --base-ref does-not-exist 2>/dev/null)"
if grep -q '^ADR_DIR_COUNT=2$' <<<"$out" \
   && grep -q '^ADR_DIR_1=docs/adrs$' <<<"$out" \
   && grep -q '^ADR_DIR_2=docs/blueprint/adrs$' <<<"$out" \
   && grep -q '^ADR_DIR_SOURCE=cli$' <<<"$out"; then
  ok "H: repeatable --adr-dir scans both directories"
else bad "H: expected two CLI-supplied directories in scope"; echo "$out"; fi
# Only one of the two claimants in scope → no duplicate (proves the flag scopes,
# so TEST G's ERROR comes from the widened scan and not from a blanket sweep).
out="$(bash "$CHECK" --project-dir "$G_SANDBOX" --adr-dir docs/adrs \
        --base-ref does-not-exist 2>/dev/null)"; rc=$?
if grep -q '^ADR_DIR_COUNT=1$' <<<"$out" && ! grep -q 'TYPE=duplicate_adr_number' <<<"$out" && [ "$rc" -eq 0 ]; then
  ok "H: a single --adr-dir sees only its own claimant"
else bad "H: single --adr-dir should not report a duplicate"; echo "$out"; fi
# An unrecognised flag must NOT be swallowed (a typo'd --adr-dir would silently
# narrow the guard back to the default directory set — a false OK).
bash "$CHECK" --project-dir "$G_SANDBOX" --adr-dirs=docs/adrs >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok "H: unknown argument rejected (exit 2)"; else bad "H: expected exit 2 for unknown argument, got $rc"; fi

# --- TEST I: ADR_DIRS honoured from the shared validation config --------------
# `docs/decisions` is NOT in the default resolution order, so it is only ever
# scanned when the manifest's `validation.adr_dirs` says so.
mkdir -p "$G_SANDBOX/docs/decisions" "$G_SANDBOX/docs/blueprint"
cat > "$G_SANDBOX/docs/decisions/legacy-storage.md" <<'MD'
---
id: ADR-0016
status: Accepted
---

# Legacy storage
MD
printf '# Decisions\n- [ADR-0016](legacy-storage.md)\n' > "$G_SANDBOX/docs/decisions/README.md"
# No config yet: docs/decisions is invisible, so its claim cannot collide.
out="$(bash "$CHECK" --project-dir "$G_SANDBOX" --base-ref does-not-exist 2>/dev/null)"
if ! grep -q 'docs/decisions/legacy-storage.md' <<<"$out"; then
  ok "I: unconfigured non-default directory is not scanned"
else bad "I: docs/decisions should be invisible without config"; echo "$out"; fi
cat > "$G_SANDBOX/docs/blueprint/manifest.json" <<'JSON'
{
  "validation": {
    "adr_dirs": ["docs/adrs", "docs/decisions"]
  }
}
JSON
out="$(bash "$CHECK" --project-dir "$G_SANDBOX" --base-ref does-not-exist 2>/dev/null)"; rc=$?
if grep -q '^ADR_DIR_COUNT=2$' <<<"$out" \
   && grep -q '^ADR_DIRS=docs/adrs'$'\t''docs/decisions$' <<<"$out" \
   && grep -q '^ADR_DIR_SOURCE=config:' <<<"$out" \
   && grep -q 'TYPE=duplicate_adr_number' <<<"$out" \
   && grep -q 'docs/decisions/legacy-storage.md' <<<"$out" \
   && [ "$rc" -eq 1 ]; then
  ok "I: ADR_DIRS read from the validation config widens the scan"
else bad "I: expected the configured docs/decisions dir to be scanned"; echo "$out"; fi
rm -f "$G_SANDBOX/docs/decisions/legacy-storage.md" "$G_SANDBOX/docs/decisions/README.md"
rmdir "$G_SANDBOX/docs/decisions"

# --- TEST J: the manifest id_registry is the arbiter --------------------------
cat > "$G_SANDBOX/docs/blueprint/manifest.json" <<'JSON'
{
  "validation": {
    "adr_dirs": ["docs/adrs", "docs/blueprint/adrs"]
  },
  "id_registry": {
    "documents": {
      "ADR-0016": {
        "path": "docs/blueprint/adrs/0016-in-engine-ui-not-win32-dialogs.md",
        "title": "In-engine UI, not Win32 dialogs"
      }
    }
  }
}
JSON
out="$(bash "$CHECK" --project-dir "$G_SANDBOX" --base-ref does-not-exist 2>/dev/null)"; rc=$?
if grep -q '^REGISTRY=present$' <<<"$out" \
   && grep -q 'TYPE=adr_registry_mismatch' <<<"$out" \
   && grep -q "docs/adrs/objs-format.md' claims ADR-0016" <<<"$out" \
   && grep -q "maps 0016 to 'docs/blueprint/adrs/0016-in-engine-ui-not-win32-dialogs.md'" <<<"$out" \
   && [ "$rc" -eq 1 ]; then
  ok "J: registry mismatch names the unregistered claimant and the registered path"
else bad "J: expected adr_registry_mismatch against the registry"; echo "$out"; fi
# The REGISTERED file must not be flagged against its own registry entry.
if ! grep -q "TYPE=adr_registry_mismatch.*'docs/blueprint/adrs/0016-in-engine-ui-not-win32-dialogs.md' claims" <<<"$out"; then
  ok "J: the registered claimant is not flagged against itself"
else bad "J: registered file must not be a registry mismatch"; echo "$out"; fi

# --- TEST K: no manifest / no id_registry → silent OK, exit 0 -----------------
K_SANDBOX="$(new_sandbox)" || { echo "mktemp failed"; exit 1; }
[ -n "$K_SANDBOX" ] || { echo "mktemp failed"; exit 1; }
mkdir -p "$K_SANDBOX/docs/adrs"
cat > "$K_SANDBOX/docs/adrs/0007-only-one.md" <<'MD'
---
id: ADR-0007
---

# ADR-0007: Only one
MD
printf '# ADRs\n- [ADR-0007](0007-only-one.md)\n' > "$K_SANDBOX/docs/adrs/README.md"
out="$(bash "$CHECK" --project-dir "$K_SANDBOX" --base-ref does-not-exist 2>/dev/null)"; rc=$?
if grep -q '^REGISTRY=absent$' <<<"$out" && grep -q '^ISSUE_COUNT=0$' <<<"$out" \
   && grep -q '^STATUS=OK$' <<<"$out" && [ "$rc" -eq 0 ] \
   && ! grep -q 'adr_registry_mismatch' <<<"$out"; then
  ok "K: no manifest → REGISTRY=absent, silent OK"
else bad "K: missing manifest must degrade silently"; echo "$out"; fi
# A manifest WITHOUT id_registry (this repo's own shape) must stay just as quiet.
mkdir -p "$K_SANDBOX/docs/blueprint"
printf '{\n  "format_version": "3.3.0",\n  "task_registry": {}\n}\n' > "$K_SANDBOX/docs/blueprint/manifest.json"
out="$(bash "$CHECK" --project-dir "$K_SANDBOX" --base-ref does-not-exist 2>/dev/null)"; rc=$?
if grep -q '^REGISTRY=absent$' <<<"$out" && grep -q '^ISSUE_COUNT=0$' <<<"$out" \
   && grep -q '^STATUS=OK$' <<<"$out" && [ "$rc" -eq 0 ]; then
  ok "K: manifest without id_registry → REGISTRY=absent, silent OK"
else bad "K: manifest without id_registry must degrade silently"; echo "$out"; fi
rm -rf "$K_SANDBOX"

# --- TEST L: frontmatter claim colliding with a DIFFERENT file on the base ref -
L_SANDBOX="$(new_sandbox)" || { echo "mktemp failed"; exit 1; }
[ -n "$L_SANDBOX" ] || { echo "mktemp failed"; exit 1; }
mkdir -p "$L_SANDBOX/docs/adrs"
cat > "$L_SANDBOX/docs/adrs/objs-format.md" <<'MD'
---
id: ADR-0016
---

# OBJS format
MD
printf '# ADRs\n- [ADR-0016](objs-format.md)\n' > "$L_SANDBOX/docs/adrs/README.md"
git -C "$L_SANDBOX" add -A
git -C "$L_SANDBOX" commit -q -m base
git -C "$L_SANDBOX" branch base-main
# A parallel PR renames the file; the base ref still holds the number under the
# old name, so the frontmatter claim must be compared across the boundary.
git -C "$L_SANDBOX" mv docs/adrs/objs-format.md docs/adrs/obj-serialisation.md
out="$(bash "$CHECK" --project-dir "$L_SANDBOX" --base-ref base-main 2>/dev/null)"
if grep -q 'TYPE=adr_number_collision' <<<"$out" && grep -q 'objs-format.md' <<<"$out"; then
  ok "L: base-ref frontmatter claim compared across the boundary"
else bad "L: expected adr_number_collision against the base-ref frontmatter claim"; echo "$out"; fi
rm -rf "$L_SANDBOX"

# --- TEST M: project dir is a SUBDIRECTORY of the repo ------------------------
# The #1585 base-ref comparison only worked when project dir == repo root. With
# N directories in scope the path frames have to be right, so pin the case: a
# base-ref collision must still be found when the project dir sits below the
# repo root (git_prefix non-empty).
M_SANDBOX="$(new_sandbox)" || { echo "mktemp failed"; exit 1; }
[ -n "$M_SANDBOX" ] || { echo "mktemp failed"; exit 1; }
mkdir -p "$M_SANDBOX/sub/docs/adrs"
cat > "$M_SANDBOX/sub/docs/adrs/0038-declarative.md" <<'MD'
---
id: ADR-0038
---

# ADR-0038: Declarative
MD
printf '# ADRs\n- [ADR-0038](0038-declarative.md)\n' > "$M_SANDBOX/sub/docs/adrs/README.md"
git -C "$M_SANDBOX" add -A
git -C "$M_SANDBOX" commit -q -m base
git -C "$M_SANDBOX" branch base-main
# The parallel PR replaces it with a DIFFERENT file claiming the same number.
rm -f "$M_SANDBOX/sub/docs/adrs/0038-declarative.md"
cat > "$M_SANDBOX/sub/docs/adrs/0038-sensor.md" <<'MD'
---
id: ADR-0038
---

# ADR-0038: Sensor
MD
printf '# ADRs\n- [ADR-0038](0038-sensor.md)\n' > "$M_SANDBOX/sub/docs/adrs/README.md"
out="$(bash "$CHECK" --project-dir "$M_SANDBOX/sub" --base-ref base-main 2>/dev/null)"; rc=$?
if grep -q 'TYPE=adr_number_collision' <<<"$out" \
   && grep -q "in 'docs/adrs/0038-sensor.md'" <<<"$out" \
   && grep -q "by 'docs/adrs/0038-declarative.md'" <<<"$out" \
   && [ "$rc" -eq 1 ]; then
  ok "M: base-ref collision found with the project dir below the repo root"
else bad "M: expected a base-ref collision in project-dir-relative paths"; echo "$out"; fi
rm -rf "$M_SANDBOX"

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
