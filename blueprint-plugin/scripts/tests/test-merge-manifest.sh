#!/usr/bin/env bash
# shellcheck disable=SC2015   # file-level: `cond && ok … || notok …` is the
# deliberate assertion idiom across this repo's test scripts (ok/notok both
# exit 0, so the || branch only runs on a real failure).
#
# Tests for merge-manifest.py (the structural merge driver for
# docs/blueprint/manifest.json) and hooks/register-merge-driver.sh.
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
#
# The SEMANTIC invariants pinned (per .claude/rules/regression-testing.md):
#   - two branches that each ran a task merge cleanly, and the run-state
#     triple (last_completed_at, last_result, stats) comes from ONE side — the
#     later run — never a mix of both
#   - registry entries added on either side are all kept
#   - the same id registered for different documents on both sides is still
#     a CONFLICT, with ordinary conflict markers in the file (a driver that
#     "resolves" everything passes every other case and fails this one)
#   - the driver never exits >128 (git reads that as a crash, not a conflict)
#   - end to end through real git: merge and stash pop resolve with the driver
#     registered, and the same merge still conflicts with it unregistered
#     (the control proves the driver, not the fixture, made the difference)
#   - the hook registers only when .gitattributes declares the driver, and is
#     idempotent
set -u

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER="${SCRIPT_DIR}/../merge-manifest.py"
HOOK="${SCRIPT_DIR}/../../hooks/register-merge-driver.sh"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

pass=0
fail=0
ok()    { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

WORK=$(mktemp -d) || { echo "mktemp failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "mktemp returned no dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

# --- fixtures ----------------------------------------------------------------
# A trimmed manifest in the real shape: one task's run state, an id registry.
manifest() { # $1=sync last_completed_at (or null) $2=runs $3=extra-registry-json
    local ts="$1" runs="$2" extra="${3:-}"
    local ts_json result_json
    if [ "$ts" = null ]; then ts_json=null; result_json=null; else ts_json="\"$ts\""; result_json='"ok"'; fi
    cat <<EOF
{
  "format_version": "3.4.0",
  "updated_at": ${ts_json},
  "task_registry": {
    "sync-ids": {
      "enabled": true,
      "last_completed_at": ${ts_json},
      "last_result": ${result_json},
      "schedule": "weekly",
      "stats": {
        "runs": ${runs}
      }
    }
  },
  "id_registry": {
    "last_prd": 1,
    "documents": {
      "PRD-001": {
        "title": "First"
      }${extra}
    }
  }
}
EOF
}

run_driver() { # base ours theirs -> sets RC, leaves result in ours
    python3 "$DRIVER" "$1" "$2" "$3" "manifest.json" 2>"$WORK/stderr"
    RC=$?
}

# --- 1. both sides ran the task + one side registered a doc -> clean ---------
manifest null 0 > "$WORK/o.json"
manifest 2026-10-31T21:12:25Z 1 ',
      "PRD-002": {
        "title": "Second"
      }' > "$WORK/a.json"
manifest 2026-10-29T11:35:43Z 3 > "$WORK/b.json"
run_driver "$WORK/o.json" "$WORK/a.json" "$WORK/b.json"
[ "$RC" -eq 0 ] && ok "concurrent task runs merge cleanly (exit 0)" || notok "concurrent task runs merge cleanly — exit $RC: $(cat "$WORK/stderr")"
got=$(jq -c '.task_registry."sync-ids" | [.last_completed_at, .stats.runs]' "$WORK/a.json")
[ "$got" = '["2026-10-31T21:12:25Z",1]' ] && ok "run-state triple comes from the later run as a unit" || notok "run-state triple mixed sides: $got"
[ "$(jq -r '.updated_at' "$WORK/a.json")" = 2026-10-31T21:12:25Z ] && ok "updated_at takes the later timestamp" || notok "updated_at: $(jq -r .updated_at "$WORK/a.json")"
[ "$(jq -r '.id_registry.documents | keys | join(",")' "$WORK/a.json")" = PRD-001,PRD-002 ] && ok "registry entry added on one side is kept" || notok "registry keys: $(jq -c '.id_registry.documents|keys' "$WORK/a.json")"

# Swapped sides: the later run must still win.
manifest 2026-10-29T11:35:43Z 3 > "$WORK/a.json"
manifest 2026-10-31T21:12:25Z 1 > "$WORK/b.json"
run_driver "$WORK/o.json" "$WORK/a.json" "$WORK/b.json"
got=$(jq -c '.task_registry."sync-ids" | [.last_completed_at, .stats.runs]' "$WORK/a.json")
[ "$RC" -eq 0 ] && [ "$got" = '["2026-10-31T21:12:25Z",1]' ] && ok "later run wins when it is on the other side" || notok "swapped sides: exit $RC, $got"

# --- 2. disjoint registry additions on both sides -> union -------------------
manifest null 0 ',
      "PRD-002": {
        "title": "Ours"
      }' > "$WORK/a.json"
manifest null 0 ',
      "PRD-003": {
        "title": "Theirs"
      }' > "$WORK/b.json"
run_driver "$WORK/o.json" "$WORK/a.json" "$WORK/b.json"
[ "$RC" -eq 0 ] && [ "$(jq -r '.id_registry.documents | keys | join(",")' "$WORK/a.json")" = PRD-001,PRD-002,PRD-003 ] \
    && ok "disjoint registry additions are unioned" || notok "union: exit $RC, $(jq -c '.id_registry.documents|keys' "$WORK/a.json" 2>&1)"

# --- 3. same id, different document on both sides -> real conflict -----------
manifest null 0 ',
      "PRD-002": {
        "title": "Ours"
      }' > "$WORK/a.json"
manifest null 0 ',
      "PRD-002": {
        "title": "Theirs"
      }' > "$WORK/b.json"
run_driver "$WORK/o.json" "$WORK/a.json" "$WORK/b.json"
[ "$RC" -ne 0 ] && ok "same id for different docs is a conflict (exit $RC)" || notok "same-id collision was silently resolved"
[ "$RC" -le 128 ] && ok "conflict exit code stays <=128 (not a driver crash)" || notok "exit $RC reads as a crash to git"
grep -q '^<<<<<<< ' "$WORK/a.json" && grep -q '^>>>>>>> ' "$WORK/a.json" \
    && ok "conflict leaves ordinary conflict markers in %A" || notok "no conflict markers written"
grep -q 'id_registry.documents.PRD-002' "$WORK/stderr" && ok "stderr names the conflicting JSON path" || notok "stderr: $(cat "$WORK/stderr")"

# --- 4. only one side changed -> takes it, byte-identical formatting ---------
manifest null 0 > "$WORK/a.json"
manifest 2026-10-31T21:12:25Z 1 > "$WORK/b.json"
cp "$WORK/b.json" "$WORK/expected.json"
run_driver "$WORK/o.json" "$WORK/a.json" "$WORK/b.json"
[ "$RC" -eq 0 ] && cmp -s "$WORK/a.json" "$WORK/expected.json" && ok "one-sided change is taken byte-for-byte" || notok "one-sided change: exit $RC, diff: $(diff "$WORK/a.json" "$WORK/expected.json" | head -5)"

# --- 5. unparseable input -> line-merge fallback, no crash ---------------------
printf '{ not json\n' > "$WORK/a.json"
manifest 2026-10-31T21:12:25Z 1 > "$WORK/b.json"
run_driver "$WORK/o.json" "$WORK/a.json" "$WORK/b.json"
[ "$RC" -ge 1 ] && [ "$RC" -le 128 ] && ok "invalid JSON falls back to a line-merge conflict" || notok "invalid JSON: exit $RC"

# --- 6. end to end through git ----------------------------------------------
new_repo() { # $1=dir: repo with the attribute declared and a base manifest
    local repo="$1"
    [ -n "$repo" ] || return 1
    git init -q -b main "$repo"
    mkdir -p "$repo/docs/blueprint"
    printf 'docs/blueprint/manifest.json merge=blueprint-manifest\n' > "$repo/.gitattributes"
    manifest null 0 > "$repo/docs/blueprint/manifest.json"
    git -C "$repo" add -A && git -C "$repo" commit -qm base
    git -C "$repo" switch -qc feature
    manifest 2026-10-29T11:35:43Z 3 > "$repo/docs/blueprint/manifest.json"
    git -C "$repo" commit -qam "feature ran sync-ids"
    git -C "$repo" switch -q main
    manifest 2026-10-31T21:12:25Z 1 ',
      "PRD-002": {
        "title": "Second"
      }' > "$repo/docs/blueprint/manifest.json"
    git -C "$repo" commit -qam "main ran sync-ids and registered PRD-002"
}
register() { CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$1" bash "$HOOK" </dev/null; }

# 6a. control: attribute declared, driver NOT registered -> git conflicts.
CTRL="$WORK/control"
new_repo "$CTRL"
if git -C "$CTRL" merge -q --no-ff --no-edit feature >/dev/null 2>&1; then
    notok "control merge resolved without the driver — fixture does not exercise the driver"
else
    ok "control: same merge conflicts with the driver unregistered"
fi

# 6b. registered -> the same merge is clean.
REPO="$WORK/repo"
new_repo "$REPO"
register "$REPO"
[ -n "$(git -C "$REPO" config --local --get merge.blueprint-manifest.driver)" ] && ok "hook registers the driver when .gitattributes declares it" || notok "hook did not register the driver"
if git -C "$REPO" merge -q --no-ff --no-edit feature >/dev/null 2>"$WORK/merge.err"; then
    ok "git merge resolves the manifest through the driver"
else
    notok "git merge conflicted with the driver registered: $(cat "$WORK/merge.err")"
fi
f="$REPO/docs/blueprint/manifest.json"
! grep -q '^<<<<<<<' "$f" && jq -e '.id_registry.documents."PRD-002" and (.task_registry."sync-ids".stats.runs == 1)' "$f" >/dev/null \
    && ok "merged manifest is valid JSON with the expected content" || notok "merged manifest: $(head -c 300 "$f")"

# 6c. stash pop — the case that motivated this driver.
git -C "$REPO" reset -q --hard HEAD~1   # back to main's own commit
git -C "$REPO" switch -q feature
manifest 2026-11-01T08:00:00Z 4 > "$REPO/docs/blueprint/manifest.json"
git -C "$REPO" stash -q
git -C "$REPO" switch -q main
if git -C "$REPO" stash pop -q >/dev/null 2>"$WORK/pop.err"; then
    ok "stash pop resolves the manifest through the driver"
else
    notok "stash pop conflicted: $(cat "$WORK/pop.err")"
fi
[ "$(jq -r '.task_registry."sync-ids".last_completed_at' "$f")" = 2026-11-01T08:00:00Z ] && ok "stash pop keeps the newer stashed run" || notok "after pop: $(jq -c '.task_registry."sync-ids"' "$f")"

# --- 7. hook scoping and idempotency ------------------------------------------
before=$(git -C "$REPO" config --local --get merge.blueprint-manifest.driver)
register "$REPO"
[ "$(git -C "$REPO" config --local --get merge.blueprint-manifest.driver)" = "$before" ] && ok "hook is idempotent" || notok "hook rewrote an identical registration"

PLAIN="$WORK/plain"
git init -q "$PLAIN"
register "$PLAIN"
[ -z "$(git -C "$PLAIN" config --local --get merge.blueprint-manifest.driver)" ] && ok "hook leaves repos without the attribute alone" || notok "hook registered in a repo that did not opt in"

register "$WORK" && ok "hook exits 0 outside a git repo" || notok "hook failed outside a git repo"

# 7b. stale cached path -> driver falls back to git's line merge, never crashes.
git -C "$CTRL" merge --abort 2>/dev/null
git -C "$CTRL" config --local merge.blueprint-manifest.driver \
    "f='/nonexistent/merge-manifest.py'; if [ -f \"\$f\" ]; then python3 \"\$f\" %O %A %B %P; else git merge-file -L ours -L base -L theirs %A %O %B; fi"
git -C "$CTRL" merge -q --no-ff --no-edit feature >/dev/null 2>&1
grep -q '^<<<<<<<' "$CTRL/docs/blueprint/manifest.json" && ok "missing driver script degrades to a normal conflict" || notok "stale-path fallback did not produce conflict markers"

echo
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
