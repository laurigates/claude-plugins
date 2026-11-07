#!/usr/bin/env bash
# shellcheck disable=SC2015   # file-level: `cond && pass || fail` is the deliberate test idiom (pass() returns 0)
# Regression tests for scripts/repair-split-ledger.py (#3490).
#
# Replays the incident: a branch cut before the #3469 split still marks
# docs/regression-ledger.md `merge=union`, so merging the split base keeps the
# whole pre-split table and appends it to the index page. The repair must
# restore the base's index and move only the branch's own rows into entry files.
#
# Run: bash scripts/tests/test-repair-split-ledger.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPAIR="$SCRIPT_DIR/repair-split-ledger.py"
PASS=0
FAIL=0
pass() { printf "  PASS: %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL + 1)); }
field() { grep -E "^$2=" <<<"$1" | cut -d= -f2; }

HEADER=$'# Ledger\n\n| Issue | Root Cause | Check Added | Fixed In |\n|-------|-----------|-------------|----------|\n'
ROW_A='| Alpha bug in thing | cause a | check a | #101 |'
ROW_B='| Beta bug in other thing | cause b | check b | #102 |'
ROW_D='| Delta bug landed after the split | cause d | check d | #104 |'
INDEX=$'# Ledger\n\nOne file per entry under docs/regression-ledger/.\n'

# make_repo <branch-row>: base (old table, union mark) -> main (split) and pr
# (appends <branch-row> to the old table). Leaves pr mid-merge of main.
make_repo() {
    local branch_row="$1" b_entry="${2:-$ROW_B}" repo def
    repo=$(mktemp -d) || return 1
    [ -n "$repo" ] && [ -d "$repo" ] || return 1
    (
        cd "$repo" || exit 1
        git init -q
        git config user.email t@e.com
        git config user.name t
        git config commit.gpgsign false
        git config merge.ff false
        def=$(git symbolic-ref --short HEAD)
        mkdir -p docs
        printf '%s%s\n%s\n' "$HEADER" "$ROW_A" "$ROW_B" >docs/regression-ledger.md
        printf 'docs/regression-ledger.md merge=union\n' >.gitattributes
        git add .
        git commit -qm base
        git switch -qc pr
        printf '%s\n' "$branch_row" >>docs/regression-ledger.md
        git commit -qam pr
        git switch -q "$def"
        mkdir -p docs/regression-ledger
        printf '%s\n' "$ROW_A" >docs/regression-ledger/101-alpha-bug-in-thing.md
        printf '%s\n' "$b_entry" >docs/regression-ledger/102-beta-bug-in-other-thing.md
        printf '%s\n' "$ROW_D" >docs/regression-ledger/104-delta-bug-landed-after-the-split.md
        printf '%s' "$INDEX" >docs/regression-ledger.md
        : >.gitattributes
        git add .
        git commit -qm split
        git branch -q -f main HEAD 2>/dev/null || true
        git switch -q pr
        git merge --no-commit --no-ff "$def" >/dev/null 2>&1 || true
        git branch -q -f base-ref "$def"
    )
    echo "$repo"
}

echo "=== repair-split-ledger regression tests ==="

# --- 1: the incident reproduces, then the repair restores the index ---------
ROW_C='| Gamma bug the PR fixed | cause c | check c | #4001 |'
r1=$(make_repo "$ROW_C") || { echo "setup failed" >&2; exit 1; }
rows_before=$(grep -c '^|' "$r1/docs/regression-ledger.md" || true)
[ "$rows_before" -gt 0 ] && pass "control: union merge re-appends the old table ($rows_before rows in index)" \
    || fail "control: expected the union merge to leave rows in the index"
out1=$(cd "$r1" && python3 "$REPAIR" base-ref 2>&1)
[ "$(field "$out1" ACTION)" = "repaired" ] && pass "incident: ACTION=repaired" || fail "incident: ACTION=$(field "$out1" ACTION)"
[ "$(cat "$r1/docs/regression-ledger.md")" = "$(git -C "$r1" show base-ref:docs/regression-ledger.md)" ] \
    && pass "incident: index equals the base's index" || fail "incident: index differs from base"
entry=$(cat "$r1"/docs/regression-ledger/4001-*.md 2>/dev/null)
[ "$entry" = "$ROW_C" ] && pass "incident: branch row moved to 4001-<slug>.md" || fail "incident: entry file missing or wrong: '$entry'"
[ "$(field "$out1" ENTRIES_WRITTEN)" = "1" ] && pass "incident: only the branch's own row written (A, B not duplicated)" \
    || fail "incident: ENTRIES_WRITTEN=$(field "$out1" ENTRIES_WRITTEN)"
[ "$(find "$r1/docs/regression-ledger" -name '*.md' | wc -l)" -eq 4 ] && pass "incident: 4 entry files (A, B, D, C)" \
    || fail "incident: expected 4 entry files"
git -C "$r1" diff --cached --quiet -- docs/regression-ledger.md docs/regression-ledger \
    && fail "incident: repair left nothing staged" || pass "incident: repair staged its files"
[ -z "$(git -C "$r1" diff --name-only)" ] && pass "incident: nothing left unstaged" || fail "incident: unstaged changes remain"
[ "$(field "$out1" STATUS)" = "OK" ] && pass "incident: STATUS=OK" || fail "incident: STATUS=$(field "$out1" STATUS)"

# --- 2: a branch row with no #N blocks the repair and changes nothing ---------
r2=$(make_repo '| Unnumbered bug | cause | check | none |') || exit 1
before2=$(cat "$r2/docs/regression-ledger.md")
out2=$(cd "$r2" && python3 "$REPAIR" base-ref 2>&1)
[ "$(field "$out2" ACTION)" = "blocked-unnumbered-row" ] && pass "unnumbered: ACTION=blocked-unnumbered-row" \
    || fail "unnumbered: ACTION=$(field "$out2" ACTION)"
[ "$(cat "$r2/docs/regression-ledger.md")" = "$before2" ] && pass "unnumbered: index untouched (row_in_index keeps blocking)" \
    || fail "unnumbered: index was rewritten"
[ "$(field "$out2" STATUS)" = "WARN" ] && [ "$(field "$out2" ISSUE_COUNT)" = "1" ] \
    && pass "unnumbered: STATUS=WARN ISSUE_COUNT=1" || fail "unnumbered: STATUS/ISSUE_COUNT wrong"

# --- 3: base not split -> skip ---------------------------------------------
r3=$(make_repo "$ROW_C") || exit 1
out3=$(cd "$r3" && python3 "$REPAIR" HEAD~0 2>&1)
[ "$(field "$out3" ACTION)" = "skip-base-not-split" ] && pass "unsplit base: skipped" || fail "unsplit base: ACTION=$(field "$out3" ACTION)"

# --- 4: index already clean -> skip, nothing staged by the script -----------
r4=$(make_repo "$ROW_C") || exit 1
( cd "$r4" && python3 "$REPAIR" base-ref >/dev/null 2>&1 )
out4=$(cd "$r4" && python3 "$REPAIR" base-ref 2>&1)
[ "$(field "$out4" ACTION)" = "skip-index-clean" ] && pass "rerun: idempotent (skip-index-clean)" || fail "rerun: ACTION=$(field "$out4" ACTION)"

# --- 5: a row the base reworded after the split is not resurrected ----------
# Only the merge-base filter stops this: the old wording of row B is in the
# merged table but matches no entry file on the base any more.
r5=$(make_repo "$ROW_C" '| Beta bug, reworded on main | cause b | check b | #102 |') || exit 1
out5=$(cd "$r5" && python3 "$REPAIR" base-ref 2>&1)
[ "$(field "$out5" ENTRIES_WRITTEN)" = "1" ] && ! grep -rqF "$ROW_B" "$r5/docs/regression-ledger" \
    && pass "reworded: old wording of a pre-split row not resurrected" \
    || fail "reworded: ENTRIES_WRITTEN=$(field "$out5" ENTRIES_WRITTEN), old row resurrected?"

rm -rf "$r1" "$r2" "$r3" "$r4" "$r5"

echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
echo "PASS: test-repair-split-ledger ($PASS assertions)"
