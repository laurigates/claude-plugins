#!/usr/bin/env bash
# Regression tests for blueprint-tracker-check.sh — the deterministic
# feature-tracker integrity check (issue #2128).
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
#
# Pins the SEMANTIC invariants, not the presence of strings:
#
#   A  a self-consistent tracker is silent (OK, exit 0)
#   B  `statistics` is a CACHE: divergence is reported PER FIELD with the
#      recomputed expectation next to the stale value, and it is an ERROR
#   C  enum drift severity is driven by the tolerated union — a value inside the
#      configured status_vocabulary WARNs and names the canonical spelling; a
#      value in neither the schema enum nor the vocabulary is an ERROR
#   D  an FR cited across docs but never minted is surfaced
#   E  a doc still `Draft` while every FR it cites has landed is surfaced
#   F  two timestamp fields for one fact are surfaced; ERROR when they disagree
#   G  `pending` is a dead bucket; `partial` is a SCHEMA bucket and must never
#      be flagged (the issue's prose calls it dead — the schema disagrees)
#   H  THE NEGATIVE CASE — an FR id appearing in BOTH the features collection
#      and tasks.completed[] is the documented drain design, NOT a duplicate.
#      This is the false positive the issue author already made once ("7 false
#      duplicate records"), so it is pinned hardest: zero issues, no output line
#      mentioning a duplicate at all.
#   I  object-keyed `features` (the schema shape) is walked into its nested
#      sub-features; a status-less FR *category* is not a feature record and is
#      not reported as an unminted citation either
#   J  array-shaped `features` (the shape the reporting repo and
#      blueprint-feature-tracker-sync.sh use) is handled
#   K  features status vs task-list membership is checked for AGREEMENT
#   L  a missing tracker is the common case, not a defect (OK, exit 0)
#   M  an unparseable tracker IS a defect (ERROR, exit 1)
#   N  an unknown flag is rejected loudly rather than swallowed (the #2057 lesson)
#   O  the section delimiters and roll-up an orchestrator parses are well formed
set -u

# Neutralize inherited git context so no sandbox git op can be hijacked into the
# real shared .git (issue #1745). No git ops here today; the guard travels with
# the fixture shape.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="${SCRIPT_DIR}/../blueprint-tracker-check.sh"

pass=0
fail=0
ok()    { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

SANDBOX_ROOT="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$SANDBOX_ROOT" ] || { echo "FATAL: empty mktemp dir" >&2; exit 1; }
[ -d "$SANDBOX_ROOT" ] || { echo "FATAL: mktemp dir missing" >&2; exit 1; }
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

proj_n=0
p=""
# Sets the global `p` to a FRESH project dir. Deliberately not a command
# substitution: a subshell would lose the counter and every case would pile its
# fixtures into one directory, cross-contaminating the assertions.
make_project() {
    proj_n=$((proj_n + 1))
    p="${SANDBOX_ROOT}/p${proj_n}"
    mkdir -p "$p/docs/blueprint" "$p/docs/prds"
}

# Sets the globals `out` and `RC`. Same reason: `$(...)` would swallow the exit
# code the caller needs to assert on.
out=""
RC=0
run_check() {
    out="$(bash "$CHECK" --project-dir "$1" 2>&1)"
    RC=$?
}

# ── A / H / J: a self-consistent tracker with an FR in BOTH the features
# collection and tasks.completed[] — the drain design. Must be totally silent.
make_project
cat > "$p/docs/blueprint/feature-tracker.json" <<'JSON'
{
  "version": "1.1.0",
  "last_updated": "2026-07-01",
  "project": "clean",
  "source_document": "REQUIREMENTS.md",
  "current_phase": "phase-1",
  "tasks": {
    "in_progress": [],
    "pending":   [{"id": "FR-003", "description": "Gamma"}],
    "completed": [{"id": "FR-001", "description": "Alpha", "completed": "2026-07-01"}]
  },
  "phases": [{"id": "phase-1", "name": "Core", "status": "in_progress"}],
  "features": [
    {"id": "FR-001", "name": "Alpha", "status": "complete",    "phase": "phase-1"},
    {"id": "FR-002", "name": "Beta",  "status": "in_progress", "phase": "phase-1"},
    {"id": "FR-003", "name": "Gamma", "status": "not_started", "phase": "phase-1"}
  ],
  "statistics": {
    "total_features": 3, "complete": 1, "partial": 0, "in_progress": 1,
    "not_started": 1, "blocked": 0, "completion_percentage": 33.3
  }
}
JSON
run_check "$p"
if grep -q '^STATUS=OK$' <<<"$out" && grep -q '^ISSUE_COUNT=0$' <<<"$out" && [ "$RC" -eq 0 ]; then
    ok "A: self-consistent tracker -> OK, exit 0"
else
    notok "A: expected OK/0 issues/exit 0 (rc=$RC)"; printf '%s\n' "$out"
fi
if grep -q '^FEATURES_SHAPE=array$' <<<"$out"; then
    ok "J: array-shaped features handled"
else
    notok "J: expected FEATURES_SHAPE=array"; printf '%s\n' "$out"
fi
# H: the false positive the issue author already made once.
if grep -qi 'duplicate' <<<"$out"; then
    notok "H: FR-001 in features AND tasks.completed[] was reported as a duplicate"
    printf '%s\n' "$out"
else
    ok "H: FR id in features + tasks.completed[] is NOT a duplicate (drain design)"
fi
# H (second half): the drain-design repeat must not even count as an issue.
if [ "$(grep -c '^  - SEVERITY=' <<<"$out")" -eq 0 ]; then
    ok "H: no issue rows at all for the features/tasks id overlap"
else
    notok "H: expected zero issue rows"; printf '%s\n' "$out"
fi

# ── B: statistics divergence, per field, ERROR ───────────────────────────────
make_project
cat > "$p/docs/blueprint/feature-tracker.json" <<'JSON'
{
  "last_updated": "2026-07-01",
  "features": [
    {"id": "FR-001", "name": "Alpha", "status": "complete",    "phase": "phase-1"},
    {"id": "FR-002", "name": "Beta",  "status": "complete",    "phase": "phase-1"},
    {"id": "FR-003", "name": "Gamma", "status": "in_progress", "phase": "phase-1"}
  ],
  "statistics": {
    "total_features": 5, "complete": 1, "partial": 0, "in_progress": 3,
    "not_started": 0, "blocked": 0, "completion_percentage": 68.0
  }
}
JSON
run_check "$p"
if [ "$RC" -eq 1 ] && grep -q '^STATUS=ERROR$' <<<"$out"; then
    ok "B: statistics divergence -> ERROR, exit 1"
else
    notok "B: expected ERROR + exit 1 (rc=$RC)"; printf '%s\n' "$out"
fi
b_ok=true
grep -q 'TYPE=statistics_divergence FIELD=total_features EXPECTED=3 ACTUAL=5' <<<"$out" || b_ok=false
grep -q 'TYPE=statistics_divergence FIELD=complete EXPECTED=2 ACTUAL=1'       <<<"$out" || b_ok=false
grep -q 'TYPE=statistics_divergence FIELD=in_progress EXPECTED=1 ACTUAL=3'    <<<"$out" || b_ok=false
grep -q 'TYPE=statistics_divergence FIELD=completion_percentage EXPECTED=66.7 ACTUAL=68' <<<"$out" || b_ok=false
if [ "$b_ok" = true ]; then
    ok "B: per-field expected-vs-actual reported (incl. recomputed 66.7 vs cached 68.0)"
else
    notok "B: missing per-field expected/actual rows"; printf '%s\n' "$out"
fi
# The unchanged fields must NOT be reported.
if grep -q 'FIELD=partial ' <<<"$out" || grep -q 'FIELD=blocked ' <<<"$out"; then
    notok "B: an agreeing statistics field was reported as divergent"; printf '%s\n' "$out"
else
    ok "B: agreeing fields (partial, blocked) are silent"
fi
# 68 vs 68.0 must NOT be a divergence (integer/decimal spelling of one number).
make_project
cat > "$p/docs/blueprint/feature-tracker.json" <<'JSON'
{
  "features": [
    {"id": "FR-001", "status": "complete"},
    {"id": "FR-002", "status": "not_started"}
  ],
  "statistics": {
    "total_features": 2, "complete": 1, "partial": 0, "in_progress": 0,
    "not_started": 1, "blocked": 0, "completion_percentage": 50
  }
}
JSON
run_check "$p"
if grep -q '^STATUS=OK$' <<<"$out"; then
    ok "B: 50 and 50.0 are the same percentage (no false divergence)"
else
    notok "B: integer percentage spelling reported as divergence"; printf '%s\n' "$out"
fi

# ── C: enum drift severity driven by the tolerated union ─────────────────────
# `completed` IS in the configured status_vocabulary -> WARN naming `complete`.
make_project
cat > "$p/docs/blueprint/manifest.json" <<'JSON'
{
  "format_version": "3.4.0",
  "validation": {
    "status_vocabulary": {
      "done": ["complete", "completed"],
      "unfinished": ["draft", "proposed", "ready", "in_progress"]
    }
  }
}
JSON
cat > "$p/docs/blueprint/feature-tracker.json" <<'JSON'
{
  "features": [
    {"id": "FR-001", "status": "complete"},
    {"id": "FR-002", "status": "completed"}
  ],
  "statistics": {
    "total_features": 2, "complete": 2, "partial": 0, "in_progress": 0,
    "not_started": 0, "blocked": 0, "completion_percentage": 100
  }
}
JSON
run_check "$p"
if grep -q 'SEVERITY=WARN TYPE=feature_status_near_miss' <<<"$out" \
    && grep -q 'FOUND=completed CANONICAL=complete' <<<"$out" \
    && grep -q '^STATUS=WARN$' <<<"$out" && [ "$RC" -eq 0 ]; then
    ok "C: vocabulary-tolerated 'completed' -> WARN naming the canonical spelling, exit 0"
else
    notok "C: expected a WARN near-miss naming 'complete' (rc=$RC)"; printf '%s\n' "$out"
fi
# The near-miss still counts toward `complete`, so the cache is NOT also
# reported as divergent for the same drift.
if grep -q 'TYPE=statistics_divergence' <<<"$out"; then
    notok "C: a resolved near-miss double-reported as statistics divergence"; printf '%s\n' "$out"
else
    ok "C: a resolved near-miss counts toward its canonical bucket"
fi
# `frobnicated` is in NEITHER the schema enum nor the vocabulary -> ERROR.
make_project
cat > "$p/docs/blueprint/manifest.json" <<'JSON'
{
  "validation": {
    "status_vocabulary": {"done": ["complete", "completed"], "unfinished": ["draft"]}
  }
}
JSON
cat > "$p/docs/blueprint/feature-tracker.json" <<'JSON'
{
  "features": [
    {"id": "FR-001", "status": "complete"},
    {"id": "FR-003", "status": "frobnicated"}
  ],
  "statistics": {
    "total_features": 2, "complete": 1, "partial": 0, "in_progress": 0,
    "not_started": 0, "blocked": 0, "completion_percentage": 50
  }
}
JSON
run_check "$p"
if grep -q 'SEVERITY=ERROR TYPE=feature_status_unknown FR=FR-003 FOUND=frobnicated' <<<"$out" \
    && [ "$RC" -eq 1 ]; then
    ok "C: status in neither enum nor vocabulary -> ERROR, exit 1"
else
    notok "C: expected feature_status_unknown ERROR + exit 1 (rc=$RC)"; printf '%s\n' "$out"
fi

# ── D: an FR cited by docs but never minted ──────────────────────────────────
make_project
cat > "$p/docs/blueprint/feature-tracker.json" <<'JSON'
{
  "features": [
    {"id": "FR-001", "status": "complete", "implementation": {"notes": "supersedes FR-025 partially"}},
    {"id": "FR-002", "status": "not_started"}
  ],
  "statistics": {
    "total_features": 2, "complete": 1, "partial": 0, "in_progress": 0,
    "not_started": 1, "blocked": 0, "completion_percentage": 50
  }
}
JSON
cat > "$p/docs/prds/PRD-007.md" <<'MD'
---
status: Accepted
---
Depends on FR-025 landing first. See also FR-001.
MD
run_check "$p"
if grep -q 'TYPE=fr_cited_not_minted FR=FR25' <<<"$out" && [ "$RC" -eq 0 ]; then
    ok "D: FR cited by docs (and an evidence string) but absent from features -> flagged"
else
    notok "D: expected fr_cited_not_minted for FR-025 (rc=$RC)"; printf '%s\n' "$out"
fi
# FR-025 is cited by the PRD *and* by the tracker's own notes string.
if grep -q 'TYPE=fr_cited_not_minted FR=FR25 CITATIONS=2' <<<"$out"; then
    ok "D: citation count spans docs/** and the tracker's own evidence text"
else
    notok "D: expected CITATIONS=2 for FR-025"; printf '%s\n' "$out"
fi
# A minted FR must never be reported as unminted, whatever spelling cites it.
if grep -q 'TYPE=fr_cited_not_minted FR=FR1' <<<"$out"; then
    notok "D: minted FR-001 reported as unminted"; printf '%s\n' "$out"
else
    ok "D: minted FR-001 cited as 'FR-001' is not reported"
fi

# ── E: doc still Draft while every FR it cites has landed ────────────────────
make_project
cat > "$p/docs/blueprint/feature-tracker.json" <<'JSON'
{
  "features": [
    {"id": "FR-001", "status": "complete"},
    {"id": "FR-002", "status": "complete"},
    {"id": "FR-009", "status": "not_started"}
  ],
  "statistics": {
    "total_features": 3, "complete": 2, "partial": 0, "in_progress": 0,
    "not_started": 1, "blocked": 0, "completion_percentage": 66.7
  }
}
JSON
cat > "$p/docs/prds/PRD-001.md" <<'MD'
---
status: Draft
---
# Landed PRD
Implements FR-001 and FR-002.
MD
cat > "$p/docs/prds/PRD-002.md" <<'MD'
---
status: Draft
---
# Genuinely unfinished PRD
Implements FR-009.
MD
run_check "$p"
if grep -q 'TYPE=doc_status_stale DOC=docs/prds/PRD-001.md DOC_STATUS=Draft' <<<"$out" && [ "$RC" -eq 0 ]; then
    ok "E: Draft doc whose FRs all landed -> flagged, exit 0"
else
    notok "E: expected doc_status_stale for PRD-001 (rc=$RC)"; printf '%s\n' "$out"
fi
if grep -q 'DOC=docs/prds/PRD-002.md' <<<"$out"; then
    notok "E: Draft doc with an unfinished FR was flagged"; printf '%s\n' "$out"
else
    ok "E: Draft doc whose FR has NOT landed is correctly silent"
fi

# ── F: two timestamp fields for one fact ─────────────────────────────────────
make_project
cat > "$p/docs/blueprint/feature-tracker.json" <<'JSON'
{
  "last_updated": "2026-05-19",
  "updated_at": "2026-05-20",
  "features": [{"id": "FR-001", "status": "complete"}],
  "statistics": {
    "total_features": 1, "complete": 1, "partial": 0, "in_progress": 0,
    "not_started": 0, "blocked": 0, "completion_percentage": 100
  }
}
JSON
run_check "$p"
if grep -q 'SEVERITY=ERROR TYPE=duplicate_timestamp_field' <<<"$out" \
    && grep -q 'CANONICAL=last_updated' <<<"$out" && [ "$RC" -eq 1 ]; then
    ok "F: disagreeing last_updated/updated_at -> ERROR naming the schema field"
else
    notok "F: expected duplicate_timestamp_field ERROR (rc=$RC)"; printf '%s\n' "$out"
fi
# A single canonical timestamp is silent.
make_project
cat > "$p/docs/blueprint/feature-tracker.json" <<'JSON'
{
  "last_updated": "2026-05-20",
  "features": [{"id": "FR-001", "status": "complete"}],
  "statistics": {
    "total_features": 1, "complete": 1, "partial": 0, "in_progress": 0,
    "not_started": 0, "blocked": 0, "completion_percentage": 100
  }
}
JSON
run_check "$p"
if grep -q '^STATUS=OK$' <<<"$out" && grep -q '^TIMESTAMP_FIELD_COUNT=1$' <<<"$out"; then
    ok "F: a single last_updated is silent"
else
    notok "F: one timestamp field should be silent"; printf '%s\n' "$out"
fi

# ── G: `pending` is dead; `partial` is a SCHEMA bucket and never flagged ─────
make_project
cat > "$p/docs/blueprint/feature-tracker.json" <<'JSON'
{
  "features": [
    {"id": "FR-001", "status": "complete"},
    {"id": "FR-002", "status": "partial"}
  ],
  "statistics": {
    "total_features": 2, "complete": 1, "partial": 1, "in_progress": 0,
    "not_started": 0, "blocked": 0, "completion_percentage": 50, "pending": 2
  }
}
JSON
run_check "$p"
if grep -q 'TYPE=dead_statistics_bucket BUCKET=pending' <<<"$out"; then
    ok "G: 'pending' dead bucket flagged"
else
    notok "G: expected dead_statistics_bucket BUCKET=pending"; printf '%s\n' "$out"
fi
if grep -q 'BUCKET=partial' <<<"$out"; then
    notok "G: 'partial' flagged — it IS a schema statistics bucket"; printf '%s\n' "$out"
else
    ok "G: 'partial' never flagged (schema bucket, despite the issue's prose)"
fi
if grep -q 'TYPE=feature_status_near_miss' <<<"$out" || grep -q 'TYPE=feature_status_unknown' <<<"$out"; then
    notok "G: 'partial' feature status flagged as enum drift"; printf '%s\n' "$out"
else
    ok "G: 'partial' is a valid feature status too"
fi

# ── I: object-keyed features (the schema shape) ──────────────────────────────
make_project
cat > "$p/docs/blueprint/feature-tracker.json" <<'JSON'
{
  "last_updated": "2026-07-01",
  "features": {
    "FR1": {
      "name": "Category one",
      "features": {
        "FR1.1": {"name": "a", "status": "complete",    "phase": "phase-1"},
        "FR1.2": {"name": "b", "status": "not_started", "phase": "phase-1"}
      }
    },
    "FR2": {
      "name": "Category two",
      "features": {
        "FR2.1": {"name": "c", "status": "blocked", "phase": "phase-2"}
      }
    }
  },
  "statistics": {
    "total_features": 3, "complete": 1, "partial": 0, "in_progress": 0,
    "not_started": 1, "blocked": 1, "completion_percentage": 33.3
  }
}
JSON
run_check "$p"
if grep -q '^FEATURES_SHAPE=object$' <<<"$out" \
    && grep -q '^FEATURE_RECORD_COUNT=3$' <<<"$out" \
    && grep -q '^STATUS=OK$' <<<"$out" && [ "$RC" -eq 0 ]; then
    ok "I: object-keyed features walked into sub-features (3 records, not 2 or 5)"
else
    notok "I: expected FEATURES_SHAPE=object, 3 records, OK (rc=$RC)"; printf '%s\n' "$out"
fi
# The status-less FR category is minted, so a doc citing it is not "unminted".
if grep -q 'TYPE=fr_cited_not_minted' <<<"$out"; then
    notok "I: a status-less FR category was reported as an unminted citation"; printf '%s\n' "$out"
else
    ok "I: status-less FR category is minted-but-not-a-record"
fi

# ── K: features status vs task-list membership (AGREEMENT) ───────────────────
make_project
cat > "$p/docs/blueprint/feature-tracker.json" <<'JSON'
{
  "tasks": {
    "pending":   [{"id": "FR-001", "description": "already done in features"}],
    "completed": [{"id": "FR-002", "description": "not done in features"},
                  {"id": "WO-031", "description": "a work order, not an FR"}]
  },
  "features": [
    {"id": "FR-001", "status": "complete"},
    {"id": "FR-002", "status": "in_progress"}
  ],
  "statistics": {
    "total_features": 2, "complete": 1, "partial": 0, "in_progress": 1,
    "not_started": 0, "blocked": 0, "completion_percentage": 50
  }
}
JSON
run_check "$p"
k_ok=true
grep -q 'TYPE=task_feature_disagreement FR=FR-001 TASK_LIST=pending FEATURE_STATUS=complete' <<<"$out" || k_ok=false
grep -q 'TYPE=task_feature_disagreement FR=FR-002 TASK_LIST=completed FEATURE_STATUS=in_progress' <<<"$out" || k_ok=false
if [ "$k_ok" = true ] && [ "$RC" -eq 0 ]; then
    ok "K: undrained pending FR and completed-but-unfinished FR both surfaced"
else
    notok "K: expected two task_feature_disagreement rows (rc=$RC)"; printf '%s\n' "$out"
fi
if grep -q 'FR=WO-031' <<<"$out"; then
    notok "K: a WO task id with no matching feature was reported"; printf '%s\n' "$out"
else
    ok "K: a non-FR task id has no feature status to contradict"
fi

# ── L: no tracker at all — the common case, not a defect ─────────────────────
make_project
rm -rf "$p/docs"
run_check "$p"
if grep -q '^TRACKER_PRESENT=false$' <<<"$out" && grep -q '^STATUS=OK$' <<<"$out" \
    && grep -q '^ISSUE_COUNT=0$' <<<"$out" && [ "$RC" -eq 0 ]; then
    ok "L: no feature tracker -> OK, exit 0 (not an error)"
else
    notok "L: a missing tracker must degrade to OK/exit 0 (rc=$RC)"; printf '%s\n' "$out"
fi

# ── M: invalid JSON is a real defect ────────────────────────────────────────
make_project
printf '{ "features": [ ' > "$p/docs/blueprint/feature-tracker.json"
run_check "$p"
if grep -q 'TYPE=invalid_json' <<<"$out" && [ "$RC" -eq 1 ]; then
    ok "M: invalid tracker JSON -> ERROR, exit 1"
else
    notok "M: expected invalid_json ERROR + exit 1 (rc=$RC)"; printf '%s\n' "$out"
fi

# ── N: an unknown flag is rejected loudly (the #2057 lesson) ────────────────
make_project
if bash "$CHECK" --project-dir "$p" --only-verdictz=x >/dev/null 2>&1; then
    notok "N: an unknown argument was silently swallowed"
else
    rc=$?
    if [ "$rc" -eq 2 ]; then
        ok "N: unknown argument -> exit 2, not a silent no-op"
    else
        notok "N: expected exit 2 for an unknown argument, got $rc"
    fi
fi

# ── O: the section wrapper is well formed (orchestrators parse it) ───────────
make_project
cat > "$p/docs/blueprint/feature-tracker.json" <<'JSON'
{"features": [], "statistics": {"total_features": 0, "complete": 0, "partial": 0,
 "in_progress": 0, "not_started": 0, "blocked": 0, "completion_percentage": 0}}
JSON
run_check "$p"
if grep -q '^=== BLUEPRINT TRACKER INTEGRITY ===$' <<<"$out" \
    && grep -q '^=== END BLUEPRINT TRACKER INTEGRITY ===$' <<<"$out" \
    && grep -q '^STATUS=OK$' <<<"$out" && grep -q '^ISSUE_COUNT=0$' <<<"$out"; then
    ok "O: empty tracker -> matched section delimiters, OK"
else
    notok "O: section delimiters / roll-up malformed"; printf '%s\n' "$out"
fi

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
