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
# A second rule covers the other route into the real repo (issues #1745, #3080):
# an inherited GIT_DIR overrides `git -C`. Every `*-plugin/hooks/test-*.sh` suite
# (any plugin, not just hooks-plugin) that runs git must `unset GIT_DIR …` before
# its first git command. See "Rule 2" in the loop below.
# A second rule covers the other route into the real repo (issue #1745): an
# inherited GIT_DIR overrides `git -C`. Every hooks-plugin/hooks/test-*.sh suite
# that runs git must `unset GIT_DIR …` before its first git command. See
# "Rule 2" in the loop below.
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

# Rule 2 patterns. GIT_EXEC_RE matches a line whose COMMAND is git with a
# repo-touching subcommand (optionally behind `X=$(`, `(`, `$(`, `if`, `!`,
# `then`, `&&`, `||`), so a git command quoted inside a test-case string is
# not counted. GIT_UNSET_RE matches an `unset` naming GIT_DIR.
GIT_EXEC_RE='^[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=\$\(|\(|\$\(|if|!|then|&&|\|\|)[[:space:]]*)*git[[:space:]]+(-C|init|commit|config|clone|worktree|checkout|switch|branch|add|remote|update-ref|symbolic-ref)([[:space:]]|$)'
GIT_UNSET_RE='^[[:space:]]*unset[[:space:]].*GIT_DIR([[:space:]]|$)'

# Collect candidate shell scripts (skip vendored / .git / nested agent worktree
# clones / the gitignored dist/ OpenCode export build output — the worktrees + dist
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

    # Rule 2 (issues #1745, #3080): a plugin hook test suite that runs git must
    # Rule 2 (issue #1745): a hooks-plugin hook test suite that runs git must
    # unset the inherited GIT_DIR family BEFORE its first git command. Under
    # pre-commit, GIT_DIR/GIT_INDEX_FILE point at the real repo and override
    # `git -C`, so a sandbox `init`/`config`/`branch -m` acts on the shared
    # clone: on 2026-10-13 it flipped core.bare=true, wrote a test identity and
    # renamed a worktree's branch onto `main` (PR #3077). Scoped to every
    # `*-plugin/hooks/test-*.sh` (#3080 — the hazard is not hooks-plugin's
    # alone). A hook script whose name happens to start with `test-`
    # (hooks-plugin's test-verification.sh) is registered in its plugin's
    # manifest and is not a suite, so it is skipped.
    case "$rel" in
        *-plugin/hooks/test-*.sh)
            plugin_dir="${rel%%/hooks/*}"
            base="$(basename "$script")"
            registered=0
            for manifest in "$ROOT_DIR/$plugin_dir/.claude-plugin/plugin.json" "$ROOT_DIR/$plugin_dir/hooks/hooks.json"; do
                if [ -f "$manifest" ] && grep -qF "hooks/$base" "$manifest"; then
                    registered=1
                fi
            done
            if [ "$registered" -eq 0 ]; then
    # renamed a worktree's branch onto `main` (PR #3077). A hook script whose
    # name happens to start with `test-` (test-verification.sh) is registered in
    # the plugin manifest and is not a suite, so it is skipped.
    case "$rel" in
        hooks-plugin/hooks/test-*.sh)
            manifest="$ROOT_DIR/hooks-plugin/.claude-plugin/plugin.json"
            base="$(basename "$script")"
            if ! { [ -f "$manifest" ] && grep -qF "hooks/$base" "$manifest"; }; then
                first_git=$(grep -nE "$GIT_EXEC_RE" "$script" 2>/dev/null | head -1 | cut -d: -f1)
                if [ -n "$first_git" ]; then
                    first_unset=$(grep -nE "$GIT_UNSET_RE" "$script" 2>/dev/null | head -1 | cut -d: -f1)
                    if [ -z "$first_unset" ] || [ "$first_unset" -gt "$first_git" ]; then
                        issue_count=$((issue_count + 1))
                        issues+=("  - SEVERITY=ERROR FILE=$rel LINE=$first_git MSG=hook test suite runs git without first unsetting GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR (issues #1745, #3080)")
                        issues+=("  - SEVERITY=ERROR FILE=$rel LINE=$first_git MSG=hook test suite runs git without first unsetting GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR (issue #1745)")
                    fi
                fi
            fi
            ;;
    esac

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
        if grep -Eq '\|\|[[:space:]]*(\{|exit|return)' <<<"$content"; then
            continue
        fi
        # Guard on the next two lines?
        nextlines=$(sed -n "$((lineno + 1)),$((lineno + 2))p" "$script")
        if grep -Eq "\[[[:space:]]+-[nd][[:space:]]+\"?\\\$(\{)?$var(\})?\"?[[:space:]]" <<<"$nextlines"; then
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
    echo "For a hook test suite (#1745/#3080), unset inherited git env before the first git command:"
    echo "  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX"
fi
echo "=== END GIT SANDBOX GUARDS ==="

if [ "$STRICT" -eq 1 ] && [ "$issue_count" -gt 0 ]; then
    exit 1
fi
exit 0
