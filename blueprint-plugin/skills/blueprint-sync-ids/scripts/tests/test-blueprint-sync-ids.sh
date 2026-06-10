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
echo "$out" | grep -q "^ADR_MISMATCH=1$" \
  || fail "expected ADR_MISMATCH=1, got:\n$out"
echo "$out" | grep -q "TYPE=id_mismatch.*HAS=ADR-0007 EXPECTED=ADR-0009" \
  || fail "expected an id_mismatch issue (HAS=ADR-0007 EXPECTED=ADR-0009), got:\n$out"
echo "$out" | grep -q "^STATUS=ERROR$" \
  || fail "expected STATUS=ERROR with a mismatch present, got:\n$out"
pass "mismatched ADR id is flagged and drives STATUS=ERROR"

# Invariant 2: the matching ADR id passes (counted, not flagged).
echo "$out" | grep -q "^ADR_WITH_ID=1$" \
  || fail "expected ADR_WITH_ID=1 for the matching ADR, got:\n$out"
echo "$out" | grep -q "0008-session-storage.md" \
  && fail "the matching ADR (0008) must not appear in any issue line:\n$out"
pass "matching ADR id passes without an issue"

# Invariant 3: the id-less PRD is NEEDS_ID.
echo "$out" | grep -q "^PRD_NEEDS_ID=1$" \
  || fail "expected PRD_NEEDS_ID=1 for the id-less PRD, got:\n$out"
pass "PRD missing an id is reported as NEEDS_ID"

# Invariant 4: the reverse github_issues index groups by issue (42, 45 -> 2).
echo "$out" | grep -q "^GH_ISSUE_MAPPINGS=2$" \
  || fail "expected GH_ISSUE_MAPPINGS=2 (issues 42 and 45), got:\n$out"
echo "$out" | grep -q "^MANIFEST_PRESENT=true$" \
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
echo "$out2" | grep -q "^STATUS=OK$" \
  || fail "expected STATUS=OK for a clean tree, got:\n$out2"
[ "$rc2" -eq 0 ] || fail "expected exit 0 for a clean tree, got $rc2"
rm -rf "$proj2"
pass "clean tree yields STATUS=OK and exit 0"

echo "ALL TESTS PASSED"
