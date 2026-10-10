#!/usr/bin/env bash
# Regression test for blueprint-sync-ids.sh (issue #1553).
# Plants a fixture doc tree under a mktemp project dir and asserts the
# semantic invariants: an ADR whose frontmatter id (ADR-0007) disagrees
# with its filename-derived expectation (0009-*.md -> ADR-0009) is flagged
# MISMATCH and drives STATUS=ERROR; an ADR whose id matches its filename
# passes silently; a PRD missing an id is NEEDS_ID; and the github_issues
# reverse index is built from the manifest registry.
# Exit 0 on success, non-zero on failure. SKIP (exit 0) if jq absent.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
audit_script="${script_dir}/../blueprint-sync-ids.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run blueprint-sync-ids tests"
  exit 0
fi

[ -f "$audit_script" ] || fail "blueprint-sync-ids.sh not found at $audit_script"

proj="$(mktemp -d)"
home="$(mktemp -d)"
trap 'rm -rf "$proj" "$home"' EXIT

mkdir -p "${proj}/docs/prds" "${proj}/docs/adrs" "${proj}/docs/prps" \
         "${proj}/docs/blueprint/work-orders"

# ADR with a matching id (0008-*.md -> ADR-0008) — should pass.
cat > "${proj}/docs/adrs/0008-session-storage.md" <<'MD'
---
id: ADR-0008
status: Accepted
---
# ADR-0008: Session Storage
MD

# ADR with a MISMATCHED id (filename says 0009 -> ADR-0009, frontmatter says ADR-0007).
cat > "${proj}/docs/adrs/0009-database-migration.md" <<'MD'
---
id: ADR-0007
status: Accepted
---
# ADR-0009: Database Migration
MD

# PRD missing an id -> NEEDS_ID.
cat > "${proj}/docs/prds/payment-flow.md" <<'MD'
---
status: Active
---
# Payment Flow
MD

# Manifest with a documents registry carrying github_issues for the reverse index.
cat > "${proj}/docs/blueprint/manifest.json" <<'JSON'
{
  "id_registry": {
    "documents": {
      "PRD-001": { "github_issues": [42] },
      "PRP-002": { "github_issues": [42] },
      "WO-003":  { "github_issues": [45] }
    }
  }
}
JSON

out="$(bash "$audit_script" --home-dir "$home" --project-dir "$proj")"

# Invariant 1: the planted MISMATCH is flagged AND drives STATUS=ERROR.
grep -q "^ADR_MISMATCH=1$" <<<"$out" \
  || fail "expected ADR_MISMATCH=1, got:\n$out"
grep -q "TYPE=id_mismatch.*HAS=ADR-0007 EXPECTED=ADR-0009" <<<"$out" \
  || fail "expected an id_mismatch issue (HAS=ADR-0007 EXPECTED=ADR-0009), got:\n$out"
grep -q "^STATUS=ERROR$" <<<"$out" \
  || fail "expected STATUS=ERROR with a mismatch present, got:\n$out"
pass "mismatched ADR id is flagged and drives STATUS=ERROR"

# Invariant 2: the matching ADR id passes (counted, not flagged).
grep -q "^ADR_WITH_ID=1$" <<<"$out" \
  || fail "expected ADR_WITH_ID=1 for the matching ADR, got:\n$out"
# The fixture registry has no ADR-0008 entry, so an `unregistered` row for it
# is expected (issue #2866); it must not appear in any id-shape issue.
id_issues="$(grep -E "TYPE=(id_mismatch|needs_id|duplicate_id)" <<<"$out" || true)"
grep -q "0008-session-storage.md" <<<"$id_issues" \
  && fail "the matching ADR (0008) must not appear in any id issue line:\n$out"
pass "matching ADR id passes without an issue"

# Invariant 3: the id-less PRD is NEEDS_ID.
grep -q "^PRD_NEEDS_ID=1$" <<<"$out" \
  || fail "expected PRD_NEEDS_ID=1 for the id-less PRD, got:\n$out"
pass "PRD missing an id is reported as NEEDS_ID"

# Invariant 4: the reverse github_issues index groups by issue (42, 45 -> 2).
grep -q "^GH_ISSUE_MAPPINGS=2$" <<<"$out" \
  || fail "expected GH_ISSUE_MAPPINGS=2 (issues 42 and 45), got:\n$out"
grep -q "^MANIFEST_PRESENT=true$" <<<"$out" \
  || fail "expected MANIFEST_PRESENT=true, got:\n$out"
pass "reverse github_issues index built from manifest registry"

# Counter-case: a clean tree (no mismatch, no missing ids) exits 0 / STATUS=OK.
proj2="$(mktemp -d)"
mkdir -p "${proj2}/docs/adrs"
cat > "${proj2}/docs/adrs/0001-ok.md" <<'MD'
---
id: ADR-0001
---
# ADR-0001: Ok
MD
out2="$(bash "$audit_script" --home-dir "$home" --project-dir "$proj2")"
rc2=$?
grep -q "^STATUS=OK$" <<<"$out2" \
  || fail "expected STATUS=OK for a clean tree, got:\n$out2"
[ "$rc2" -eq 0 ] || fail "expected exit 0 for a clean tree, got $rc2"
rm -rf "$proj2"
pass "clean tree yields STATUS=OK and exit 0"

# ==============================================================================
# Issue #2866 — a thelma-shaped tree reported STATUS=OK with 0 issues.
# ADR-NNN-title.md naming in docs/adr/, a duplicate PRP-010, a swapped registry
# pair, unregistered documents, a registry path missing on disk, stale counters.
# ==============================================================================

# The structured-output validator lives at the repo root; a plugin installed on
# its own does not ship it, so the contract assertion runs only when present.
contract="${script_dir}/../../../../../scripts/check-structured-output-contract.sh"
validate_contract() { # <label> <output>
  [ -f "$contract" ] || return 0
  printf '%s\n' "$2" | bash "$contract" --validate - >/dev/null 2>&1 \
    || fail "$1: output violates the structured-output contract:\n$2"
  pass "$1: output satisfies the structured-output contract"
}

proj3="$(mktemp -d)"
[ -n "$proj3" ] || fail "mktemp failed"
trap 'rm -rf "$proj" "$home" "$proj3"' EXIT
mkdir -p "${proj3}/docs/adr" "${proj3}/docs/prps" "${proj3}/docs/prds" "${proj3}/docs/blueprint"

write_doc() { # <path> <id-or-empty>
  if [ -n "$2" ]; then
    printf -- '---\nid: %s\nstatus: Accepted\n---\n# Doc\n' "$2" > "${proj3}/$1"
  else
    printf -- '---\nstatus: Accepted\n---\n# Doc\n' > "${proj3}/$1"
  fi
}
write_doc docs/adr/ADR-001-progressive-rendering.md ADR-001
write_doc docs/adr/ADR-002-analysis-workspace.md ""
write_doc docs/adr/ADR-003-tiles.md ADR-003
write_doc docs/adr/decision-without-number.md ADR-004
printf '# ADRs\n' > "${proj3}/docs/adr/README.md"
write_doc docs/prps/gemini-embedding-2-evaluation.md PRP-010
write_doc docs/prps/theme-curation-consolidation.md PRP-010
write_doc docs/prps/openfeature-integration-prp.md PRP-008
write_doc docs/prps/hierarchy-aware-duplicate-detection.md PRP-009
write_doc docs/prds/discovery.md PRD-001

cat > "${proj3}/docs/blueprint/manifest.json" <<'JSON'
{
  "id_registry": {
    "last_prd": 1,
    "last_prp": 9,
    "last_adr": 2,
    "documents": {
      "PRD-001": { "path": "docs/prds/discovery.md" },
      "ADR-001": { "path": "docs/adr/ADR-001-progressive-rendering.md" },
      "PRP-008": { "path": "docs/prps/hierarchy-aware-duplicate-detection.md" },
      "PRP-009": { "path": "docs/prps/openfeature-integration-prp.md" },
      "PRP-011": { "path": "docs/prps/removed-long-ago.md" }
    }
  }
}
JSON

out3="$(bash "$audit_script" --home-dir "$home" --project-dir "$proj3")"
rc3=$?

# ADR-NNN-title.md files are examined, from docs/adr/, with a frontmatter fallback.
grep -q "^ADR_DIR=docs/adr$" <<<"$out3" \
  || fail "expected ADR_DIR=docs/adr (docs/adrs absent), got:\n$out3"
grep -q "^ADR_WITH_ID=3$" <<<"$out3" \
  || fail "expected ADR_WITH_ID=3 (ADR-001, ADR-003, frontmatter-only ADR-004), got:\n$out3"
grep -q "^ADR_NEEDS_ID=1$" <<<"$out3" \
  || fail "expected ADR_NEEDS_ID=1 for the id-less ADR-002, got:\n$out3"
grep -q "TYPE=needs_id .*ADR-002-analysis-workspace.md KIND=ADR EXPECTED=ADR-002" <<<"$out3" \
  || fail "expected needs_id EXPECTED=ADR-002 derived from the ADR-NNN- filename, got:\n$out3"
grep -q "^ADR_FRONTMATTER_ONLY=1$" <<<"$out3" \
  || fail "expected ADR_FRONTMATTER_ONLY=1, got:\n$out3"
pass "ADR-NNN-title.md basenames are examined, with a frontmatter-id fallback"

# Duplicate PRP-010.
grep -q "^DUPLICATE_IDS=1$" <<<"$out3" \
  || fail "expected DUPLICATE_IDS=1, got:\n$out3"
echo "$out3" | grep "TYPE=duplicate_id KIND=PRP ID=PRP-010" | grep "gemini-embedding-2-evaluation.md" \
  | grep -q "theme-curation-consolidation.md" \
  || fail "expected duplicate_id naming both PRP-010 docs, got:\n$out3"
pass "duplicate frontmatter id within a kind is an ERROR naming both docs"

# Swapped registry pair: both docs flagged.
grep -q "^REGISTRY_PRESENT=true$" <<<"$out3" \
  || fail "expected REGISTRY_PRESENT=true, got:\n$out3"
grep -q "^REGISTRY_ID_PATH_MISMATCH=2$" <<<"$out3" \
  || fail "expected REGISTRY_ID_PATH_MISMATCH=2 for the swapped pair, got:\n$out3"
grep -q "SEVERITY=ERROR TYPE=id_path_mismatch DOC=docs/prps/openfeature-integration-prp.md HAS=PRP-008 REGISTRY=PRP-009" <<<"$out3" \
  || fail "expected id_path_mismatch for openfeature (HAS=PRP-008 REGISTRY=PRP-009), got:\n$out3"
grep -q "SEVERITY=ERROR TYPE=id_path_mismatch DOC=docs/prps/hierarchy-aware-duplicate-detection.md HAS=PRP-009 REGISTRY=PRP-008" <<<"$out3" \
  || fail "expected id_path_mismatch for hierarchy (HAS=PRP-009 REGISTRY=PRP-008), got:\n$out3"
pass "a swapped registry id<->path pair is an ERROR on both docs"

# Unregistered documents: ADR-003, ADR-004 and both PRP-010 docs.
grep -q "^REGISTRY_UNREGISTERED=4$" <<<"$out3" \
  || fail "expected REGISTRY_UNREGISTERED=4, got:\n$out3"
grep -q "SEVERITY=WARN TYPE=unregistered DOC=docs/adr/ADR-003-tiles.md KIND=ADR ID=ADR-003" <<<"$out3" \
  || fail "expected ADR-003 reported unregistered, got:\n$out3"
echo "$out3" | grep "TYPE=unregistered" | grep -qE "ADR-001-progressive-rendering|discovery.md" \
  && fail "registered documents must not be reported unregistered:\n$out3"
pass "documents on disk but absent from id_registry are WARN unregistered"

# Registry path missing on disk.
grep -q "SEVERITY=ERROR TYPE=registry_path_missing ID=PRP-011 PATH=docs/prps/removed-long-ago.md" <<<"$out3" \
  || fail "expected registry_path_missing for PRP-011, got:\n$out3"
pass "a registry path missing on disk is an ERROR"

# Stale counters: last_adr=2 < ADR-004, last_prp=9 < PRP-010; last_prd=1 is current.
grep -q "^COUNTER_STALE=2$" <<<"$out3" \
  || fail "expected COUNTER_STALE=2, got:\n$out3"
grep -q "TYPE=counter_stale COUNTER=last_adr VALUE=2 MAX_ON_DISK=ADR-4" <<<"$out3" \
  || fail "expected counter_stale for last_adr, got:\n$out3"
grep -q "TYPE=counter_stale COUNTER=last_prp VALUE=9 MAX_ON_DISK=PRP-10" <<<"$out3" \
  || fail "expected counter_stale for last_prp, got:\n$out3"
grep -q "COUNTER=last_prd" <<<"$out3" \
  && fail "last_prd=1 equals the highest PRD on disk and must not be stale:\n$out3"
pass "last_* counters below the highest id on disk are WARN counter_stale"

# Roll-up: ERROR, exit 1, REASON= naming the first ERROR finding.
grep -q "^STATUS=ERROR$" <<<"$out3" || fail "expected STATUS=ERROR, got:\n$out3"
[ "$rc3" -eq 1 ] || fail "expected exit 1 on ERROR, got $rc3"
grep -q "^REASON=duplicate_id: KIND=PRP ID=PRP-010" <<<"$out3" \
  || fail "expected REASON=duplicate_id: ..., got:\n$out3"
pass "thelma-shaped tree rolls up to STATUS=ERROR with a REASON="
validate_contract "thelma-shaped tree" "$out3"

# --- Absent registry: this repo's own manifest shape (no id_registry) ---------
proj4="$(mktemp -d)"
[ -n "$proj4" ] || fail "mktemp failed"
trap 'rm -rf "$proj" "$home" "$proj3" "$proj4"' EXIT
mkdir -p "${proj4}/docs/adrs" "${proj4}/docs/prps" "${proj4}/docs/blueprint"
printf -- '---\nid: ADR-001\n---\n# ADR-001\n' > "${proj4}/docs/adrs/ADR-001-first.md"
printf -- '---\nid: ADR-0002\n---\n# ADR-0002\n' > "${proj4}/docs/adrs/0002-second.md"
printf -- '---\nid: PRP-001\n---\n# PRP\n' > "${proj4}/docs/prps/one.md"
for manifest_body in \
  '{ "format_version": "3.3.0", "task_registry": {} }' \
  '{ "format_version": "3.3.0", "id_registry": null }' \
  '{ "format_version": "3.3.0", "id_registry": { "last_adr": 0, "last_prp": 0 } }' \
  '{ "format_version": "3.3.0", "id_registry": { "last_adr": 0, "documents": null } }'; do
  printf '%s\n' "$manifest_body" > "${proj4}/docs/blueprint/manifest.json"
  out4="$(bash "$audit_script" --home-dir "$home" --project-dir "$proj4" 2>&1)"
  rc4=$?
  [ "$rc4" -eq 0 ] || fail "absent registry must exit 0 (manifest: $manifest_body), got $rc4:\n$out4"
  grep -q "^REGISTRY_PRESENT=false$" <<<"$out4" \
    || fail "expected REGISTRY_PRESENT=false (manifest: $manifest_body), got:\n$out4"
  grep -qE "TYPE=(unregistered|counter_stale|id_path_mismatch|registry_path_missing)" <<<"$out4" \
    && fail "absent registry must emit no registry rows (manifest: $manifest_body):\n$out4"
  grep -q "^STATUS=OK$" <<<"$out4" \
    || fail "expected STATUS=OK with no registry (manifest: $manifest_body), got:\n$out4"
  grep -q "^ADR_WITH_ID=2$" <<<"$out4" \
    || fail "expected both ADR namings counted (manifest: $manifest_body), got:\n$out4"
  grep -qiE "jq: error|null \(null\)" <<<"$out4" \
    && fail "a null registry must not surface a jq error (manifest: $manifest_body):\n$out4"
done
pass "absent or null id_registry/documents: REGISTRY_PRESENT=false, no registry rows, exit 0"
validate_contract "absent registry" "$out4"

echo "ALL TESTS PASSED"
