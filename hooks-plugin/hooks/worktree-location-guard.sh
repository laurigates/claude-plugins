#!/usr/bin/env bash
# PreToolUse hook for the Bash tool — denies a hand-rolled `git worktree add`
# whose path lands outside the target repo's `.claude/worktrees/`.
#
# Problem: Claude Code creates its own worktrees under
# `<repo>/.claude/worktrees/<name>`, where `worktree-audit`-style sweeps and the
# EnterWorktree/ExitWorktree lifecycle find them. A worktree made by hand in Bash
# has no lifecycle, and the older convention `git worktree add ../<repo>-<task>`
# (still printed by several git-plugin skills until this hook landed) scatters
# them as siblings of the repo. Observed 2026-10-29 across ~/repos: 12 sibling
# worktrees (`infrastructure-wt-*`, `claude-plugins-wt-*`, …), all but one with
# a merged PR, none ever removed. Five of the seven infrastructure ones were
# created by sessions whose cwd was ANOTHER repo — EnterWorktree only serves the
# session's own repo, so cross-repo work is exactly where hand-rolling happens.
#
# Strategy:
#   1. Fire on `git [-C <dir>] worktree add … <path>`. Quoted segments are
#      scrubbed before the pre-filter so a commit message mentioning the command
#      is inert.
#   2. Resolve the base dir the path is relative to: `git -C <dir>` (resolved
#      against the hook input's `.cwd`) > `.cwd` > the hook process's cwd. git
#      chdirs into `-C` before reading the path, so a relative path resolves
#      against it.
#   3. Resolve the MAIN worktree root from `--git-common-dir`, so a session
#      sitting inside a linked worktree still targets `<main>/.claude/worktrees/`
#      rather than nesting under its own worktree.
#   4. Canonicalise both sides (deepest existing ancestor via `pwd -P`, plus the
#      not-yet-existing tail) so `..`, `~` and macOS's /tmp → /private/tmp
#      symlink compare correctly.
#   5. Allow paths under `<main>/.claude/worktrees/` and throwaway temp dirs
#      ($TMPDIR, /tmp, /private/tmp, /var/folders) — the verification recipes in
#      git-plugin:git-merge-hazards use detached scratch worktrees there.
#   6. Otherwise deny with the corrected command. A deny, not an `ask`: the
#      corrected form is the same `git worktree add` with a different path, so
#      the agent can always retry and is never dead-ended
#      (.claude/rules/hook-block-vs-nudge.md, test 3), while an `ask` would put
#      a permission prompt in front of the user for a mechanical fix the agent
#      can make itself.
#
# Unresolvable paths (`$VAR`, `$(…)`, backticks, globs) are let through — the
# hook cannot know what the shell will expand them to.
#
# Opt out: CLAUDE_HOOKS_DISABLE_WORKTREE_LOCATION_GUARD=1, honored only from the
#   operator's exported shell environment (an inline prefix sets it for the
#   child command, not for this hook process).
#
# This hook denies via a JSON envelope rather than exit 2, so it deliberately
# does not use the block() convention.
#
# Matches: Bash

# Not `set -e`: git probes exit non-zero routinely outside a repo, and every
# such probe here is guarded.
set -uo pipefail

[ "${CLAUDE_HOOKS_DISABLE_WORKTREE_LOCATION_GUARD:-}" = "1" ] && exit 0

# Degrade silently when a dependency is missing — never fail the user's command.
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

INPUT=$(cat)
printf '%s' "$INPUT" | jq -e 'type == "object" and (.tool_input | type == "object")' >/dev/null 2>&1 || exit 0
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ "$TOOL_NAME" = "Bash" ] || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[ -n "$COMMAND" ] || exit 0
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

# Cheap pre-filter before any parsing.
case "$COMMAND" in *worktree*add*) ;; *) exit 0 ;; esac

# Remote-exec suppression: the command targets another filesystem.
case "$(printf '%s' "$COMMAND" | awk 'NR==1{print $1}')" in
    ssh|docker|podman|kubectl|nerdctl) exit 0 ;;
esac

deny() {
    local json_reason
    json_reason=$(printf '%s' "$1" | jq -Rs .)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
        "$json_reason"
    exit 0
}

# ── Statement splitting (same program as branch-base-guard.sh) ───────────────
# Split on UNQUOTED `;`, `&&`, `||`, `|`, `&`, `(`, `)` and newline.
split_statements() {
    awk '
    BEGIN { SQ = sprintf("%c", 39) }
    {
        s = ""; q = ""; n = length($0)
        for (i = 1; i <= n; i++) {
            c = substr($0, i, 1)
            if (q != "") { s = s c; if (c == q) q = ""; continue }
            if (c == "\"" || c == SQ) { q = c; s = s c; continue }
            if (c == "\\") { s = s c; i++; if (i <= n) s = s substr($0, i, 1); continue }
            if (c == ";" || c == "(" || c == ")") { print s; s = ""; continue }
            if (c == "|") { if (substr($0, i + 1, 1) == "|") i++; print s; s = ""; continue }
            if (c == "&") { if (substr($0, i + 1, 1) == "&") i++; print s; s = ""; continue }
            s = s c
        }
        print s
    }'
}

scrub_quotes() {
    sed -E "s/'[^']*'/''/g; s/\"[^\"]*\"/\"\"/g"
}

TRIGGER_RE='(^|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+worktree[[:space:]]+add([[:space:]]|$)'

unquote() {
    local s="${1-}"
    s="${s//\'/}"
    s="${s//\"/}"
    printf '%s' "$s"
}

# Sets WT_PATH and GIT_C_PATH. Returns 1 when the statement is not a
# `git worktree add` with a path.
WT_PATH=""; GIT_C_PATH=""
parse_statement() {
    local stmt="$1" t i n
    local -a raw=()
    read -r -a raw <<<"$stmt"
    n=${#raw[@]}
    [ "$n" -gt 0 ] || return 1
    WT_PATH=""; GIT_C_PATH=""

    i=0
    while [ "$i" -lt "$n" ]; do
        t=$(unquote "${raw[$i]}")
        case "$t" in
            [A-Za-z_]*=*) i=$((i + 1)); continue ;;
            sudo|command|env|nice) i=$((i + 1)); continue ;;
        esac
        break
    done
    [ "$(unquote "${raw[$i]:-}")" = "git" ] || return 1
    i=$((i + 1))

    while [ "$i" -lt "$n" ]; do
        t=$(unquote "${raw[$i]}")
        case "$t" in
            -C) GIT_C_PATH=$(unquote "${raw[$((i + 1))]:-}"); i=$((i + 2)); continue ;;
            -c|--git-dir|--work-tree|--namespace|--exec-path|--config-env)
                i=$((i + 2)); continue ;;
            -*) i=$((i + 1)); continue ;;
            *) break ;;
        esac
    done
    [ "$(unquote "${raw[$i]:-}")" = "worktree" ] || return 1
    [ "$(unquote "${raw[$((i + 1))]:-}")" = "add" ] || return 1
    i=$((i + 2))

    # `git worktree add [-f] [--detach] [--checkout] [--lock [--reason <s>]]
    #   [--orphan] [(-b | -B) <new-branch>] <path> [<commit-ish>]`
    while [ "$i" -lt "$n" ]; do
        t=$(unquote "${raw[$i]}")
        case "$t" in
            --) WT_PATH=$(unquote "${raw[$((i + 1))]:-}"); break ;;
            -b|-B|--reason) i=$((i + 2)); continue ;;
            -*) i=$((i + 1)); continue ;;
        esac
        WT_PATH="$t"
        break
    done
    [ -n "$WT_PATH" ]
}

# Lexical normalisation of an absolute path: collapse `.`, `..` and `//`.
normalize() {
    local IFS=/ part out=""
    local -a parts=()
    read -r -a parts <<<"$1"
    for part in "${parts[@]}"; do
        case "$part" in
            ''|.) ;;
            ..) out="${out%/*}" ;;
            *) out="$out/$part" ;;
        esac
    done
    printf '%s' "${out:-/}"
}

# Canonicalise: resolve symlinks on the deepest existing ancestor, keep the tail.
canonical() {
    local p tail="" head
    p=$(normalize "$1")
    head="$p"
    while [ -n "$head" ] && [ ! -d "$head" ]; do
        tail="/${head##*/}$tail"
        head="${head%/*}"
    done
    [ -n "$head" ] || head=/
    head=$(cd -P -- "$head" 2>/dev/null && pwd -P) || return 1
    [ "$head" = "/" ] && head=""
    printf '%s%s' "$head" "$tail"
}

absolutize() {   # $1 path, $2 base dir
    local p="$1"
    case "$p" in
        \~) p="$HOME" ;;
        \~/*) p="$HOME/${p#\~/}" ;;
    esac
    case "$p" in
        /*) printf '%s' "$p" ;;
        *) printf '%s/%s' "$2" "$p" ;;
    esac
}

under() {        # $1 path, $2 dir — true when $1 is $2 or inside it
    case "$1/" in "$2"/*) return 0 ;; esac
    return 1
}

# ── Find the `git worktree add` statement ────────────────────────────────────
MATCHED=""
while IFS= read -r stmt; do
    [ -n "$stmt" ] || continue
    printf '%s' "$stmt" | scrub_quotes | grep -Eq "$TRIGGER_RE" || continue
    if parse_statement "$stmt"; then
        MATCHED="$stmt"
        break
    fi
done < <(printf '%s' "$COMMAND" | split_statements)
[ -n "$MATCHED" ] || exit 0

# Unresolvable without running the shell.
case "$WT_PATH$GIT_C_PATH" in *'$'*|*'`'*|*'*'*|*'?'*|*'['*) exit 0 ;; esac

BASE="${HOOK_CWD:-$PWD}"
[ -d "$BASE" ] || exit 0
if [ -n "$GIT_C_PATH" ]; then
    BASE=$(absolutize "$GIT_C_PATH" "$BASE")
fi
git -C "$BASE" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Main worktree root: parent of the common `.git` dir. Fall back to the current
# toplevel for layouts where the common dir is not `<root>/.git` (bare repos,
# submodules under `.git/modules/`).
COMMON=$(git -C "$BASE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "")
case "$COMMON" in
    */.git) ROOT="${COMMON%/.git}" ;;
    *) ROOT=$(git -C "$BASE" rev-parse --show-toplevel 2>/dev/null || echo "") ;;
esac
[ -n "$ROOT" ] || exit 0
ROOT=$(canonical "$ROOT") || exit 0

TARGET=$(canonical "$(absolutize "$WT_PATH" "$BASE")") || exit 0
ALLOWED="$ROOT/.claude/worktrees"

# Inside another linked worktree (a session sitting in one that ran
# `git worktree add .claude/worktrees/y`) is still under $ALLOWED by prefix, but
# nests one checkout inside another; `git worktree remove` of the outer then
# trips over the inner.
nested_in_linked() {
    local wt
    while IFS= read -r wt; do
        [ -n "$wt" ] || continue
        wt=$(canonical "$wt") || continue
        [ "$wt" = "$ROOT" ] && continue
        under "$TARGET" "$wt" && return 0
    done < <(git -C "$BASE" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
    return 1
}

if under "$TARGET" "$ALLOWED" && [ "$TARGET" != "$ALLOWED" ] && ! nested_in_linked; then
    exit 0
fi

for tmp in "${TMPDIR:-}" /tmp /private/tmp /var/folders /private/var/folders; do
    [ -n "$tmp" ] || continue
    tmp_c=$(canonical "$tmp") || continue
    under "$TARGET" "$tmp_c" && exit 0
done

NAME="${TARGET##*/}"
case "$NAME" in
    "${ROOT##*/}"-wt-*) NAME="${NAME#"${ROOT##*/}"-wt-}" ;;
    "${ROOT##*/}"-*) NAME="${NAME#"${ROOT##*/}"-}" ;;
esac
FIXED="$ALLOWED/$NAME"
REST=$(printf '%s' "$MATCHED" | sed -E 's/^[[:space:]]+//')
SUGGEST="git -C $ROOT worktree add"
# Rebuild the argument list with the path swapped, keeping every other token.
SUGGEST_ARGS=""
seen_add=0; swapped=0
read -r -a toks <<<"$REST"
for tok in "${toks[@]}"; do
    if [ "$seen_add" -eq 0 ]; then
        [ "$(unquote "$tok")" = "add" ] && seen_add=1
        continue
    fi
    if [ "$swapped" -eq 0 ] && [ "$(unquote "$tok")" = "$WT_PATH" ]; then
        SUGGEST_ARGS="$SUGGEST_ARGS $FIXED"; swapped=1
    else
        SUGGEST_ARGS="$SUGGEST_ARGS $tok"
    fi
done

deny "WORKTREE LOCATION: '$WT_PATH' resolves to $TARGET, outside $ALLOWED.

Worktrees for $ROOT belong under its .claude/worktrees/, where Claude Code's own worktrees live and where 'just -g worktree-audit' finds them; a sibling directory has no cleanup and accumulates after its PR merges. This applies when working on a repo other than the session's own: create the worktree in the TARGET repo's .claude/worktrees/.

Retry with:
  $SUGGEST$SUGGEST_ARGS

Scratch worktrees under \$TMPDIR or /tmp are allowed. Silence this guard by exporting CLAUDE_HOOKS_DISABLE_WORKTREE_LOCATION_GUARD=1 from your shell."
