#!/usr/bin/env bash
# check-git-sandbox-guards.sh — guard against the issue #1692 shared-checkout leak.
#
# THE HAZARD
# A test/hook shell script builds a throwaway repo:
#     SANDBOX=$(mktemp -d)
#     git -C "$SANDBOX" init -q -b main
#     git -C "$SANDBOX" config user.email t@e.com
# If `mktemp` fails, `$SANDBOX` is the empty string and `git -C "" init` silently
# falls back to the CURRENT WORKING DIRECTORY. In a shared checkout (multiple
# agents in one clone — the laurigates portfolio layout) that re-inits the REAL
# repo, flips it to bare (`git init --bare ""`), and injects a junk identity into
# its `.git/config`. The failure is invisible: the test passes, the corruption
# surfaces later as "fatal: this operation must be run in a work tree".
#
# THE RULE THIS ENFORCES
# Any `VAR=$(mktemp …)` whose VAR is later used in a *repo-targeting* position —
# `git -C "$VAR"`, `git init … "$VAR"`, `git clone … "$VAR"`, or `cd "$VAR"` — must
# be GUARDED: the assignment line carries `|| { … exit/return … }`, OR one of the
# next two lines tests `[ -n "$VAR" ]` / `[ -d "$VAR" ]`. An empty value must then
# abort before any git op runs.
#
# Python tests are NOT covered: `tempfile.mkdtemp()` / pytest `tmp_path` raise on
# failure and never yield an empty path, so the shell-specific leak cannot occur.
#
# Output: structured KEY=VALUE per .claude/rules/structured-script-output.md.
#   --strict  exit 1 when ISSUE_COUNT > 0 (for pre-commit / CI). Default: report only.

set -uo pipefail

STRICT=0
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for arg in "$@"; do
    case "$arg" in
        --strict) STRICT=1 ;;
        --root) shift ;; # reserved
        *) [ -d "$arg" ] && ROOT_DIR="$arg" ;;
    esac
done

issue_count=0
declare -a issues=()

# Collect candidate shell scripts (skip vendored / .git / nested agent worktree
# clones / the gitignored dist/ rulesync build output — the worktrees + dist
# prune mirrors #1492/#1548 so we scan only the real tree, not N copies of it
# nor generated exports). The worktrees/dist prunes are anchored to "$ROOT_DIR/…"
# rather than a bare `*/.claude/worktrees/*`: when the linter itself runs from
# inside a worktree (ROOT_DIR is under .claude/worktrees/), the bare glob would
# prune the entire scan root and find nothing. Anchoring matches only worktrees
# nested *below* the scanned root.
# This linter's own regression test embeds deliberately-unguarded `mktemp -d`
# fixtures inside `cat <<EOF` heredoc bodies; scanning it would flag its own
# fixtures. Exclude it (a linter does not lint its own fixtures).
SELF_TEST="$ROOT_DIR/scripts/tests/test-check-git-sandbox-guards.sh"
mapfile -d '' scripts < <(
    find "$ROOT_DIR" \
        \( -path '*/.git/*' -o -path '*/node_modules/*' \
           -o -path "$ROOT_DIR/.claude/worktrees/*" -o -path "$ROOT_DIR/dist/*" \
           -o -path "$SELF_TEST" \) -prune \
        -o -type f -name '*.sh' -print0 2>/dev/null
)

for script in "${scripts[@]}"; do
    rel="${script#"$ROOT_DIR"/}"

    # File-level danger gate: does this script perform a repo-CREATING or
    # repo-TARGETING git op? `git init`/`git clone`/`git worktree add` create a
    # repo at a path arg; `git -C "$…"` runs in a directory arg. If the dir arg is
    # an empty sandbox var, all of these silently act on the CWD. We gate at file
    # level (not per-var) so indirection — `for d in "$SBX"; do git -C "$d" init` —
    # is still covered: any unguarded `mktemp -d` in such a file is a hazard.
    if ! grep -Eq 'git[[:space:]]+(-C[[:space:]]+"?\$|init\b|clone\b|worktree[[:space:]]+add\b)' "$script"; then
        continue
    fi

    # Flag every unguarded `VAR=$(mktemp -d)` (directory) assignment. A guard is
    # `|| {`/`|| exit`/`|| return` on the assignment line, or a `[ -n "$VAR" ]` /
    # `[ -d "$VAR" ]` test on either of the next two lines. Temp *files*
    # (`mktemp` without -d) are excluded: they are never a git/cd target.
    while IFS=: read -r lineno content; do
        [ -n "$lineno" ] || continue
        var=$(printf '%s\n' "$content" | sed -E 's/^[[:space:]]*(local[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/')
        [ -n "$var" ] || continue

        # Guard on the assignment line itself?
        if printf '%s\n' "$content" | grep -Eq '\|\|[[:space:]]*(\{|exit|return)'; then
            continue
        fi
        # Guard on the next two lines?
        nextlines=$(sed -n "$((lineno + 1)),$((lineno + 2))p" "$script")
        if printf '%s\n' "$nextlines" | grep -Eq "\[[[:space:]]+-[nd][[:space:]]+\"?\\\$(\{)?$var(\})?\"?[[:space:]]"; then
            continue
        fi

        issue_count=$((issue_count + 1))
        issues+=("  - SEVERITY=ERROR FILE=$rel LINE=$lineno VAR=$var MSG=unguarded mktemp -d in a git-repo script (issue #1692)")
    done < <(grep -nE '^[[:space:]]*(local[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=[[:space:]]*"?\$\(mktemp[[:space:]]+(-d|--directory)' "$script" 2>/dev/null)
done

status="OK"
[ "$issue_count" -gt 0 ] && status="ERROR"

echo "=== GIT SANDBOX GUARDS ==="
echo "SCRIPTS_SCANNED=${#scripts[@]}"
echo "STATUS=$status"
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
    echo "ISSUES:"
    printf '%s\n' "${issues[@]}"
    echo ""
    echo "FIX: guard the sandbox dir before any git op, e.g.:"
    echo "  VAR=\$(mktemp -d) || { echo 'mktemp failed' >&2; exit 1; }"
    echo "  [ -n \"\$VAR\" ] && [ -d \"\$VAR\" ] || { echo 'bad sandbox dir' >&2; exit 1; }"
fi
echo "=== END GIT SANDBOX GUARDS ==="

if [ "$STRICT" -eq 1 ] && [ "$issue_count" -gt 0 ]; then
    exit 1
fi
exit 0
