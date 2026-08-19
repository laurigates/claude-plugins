#!/usr/bin/env bash
# PreToolUse hook for the Bash tool — blocks `rm -rf` on a git repository whose
# history exists nowhere else.
#
# Problem it prevents: `rm -rf` on a checkout with no remote (or with a remote
# that has never been pushed to) destroys committed history, the working tree,
# every stash and every unpushed branch in one stroke. There is no reflog, no
# `git fsck --lost-found`, no PR and no coworker's clone to recover from — this
# is the one failure mode with a strictly empty recovery path, which is why it
# is a hard block rather than a nudge (source: `git-plugin:git-repo-delete-check`,
# "the failure mode of skipping it is silent permanent data loss, with no way
# to recover" — that skill is the deliberate, invoke-before-deleting half of
# this guard; the `~/.claude/rules/repo-deletion-safety.md` user rule it was
# promoted out of is now a pointer stub, dotfiles #353).
#
# Strategy:
#   1. Guard: opt-out env var, jq/git availability, tool_name == Bash.
#   2. Suppress remote-exec commands (ssh/scp/rsync/docker/podman/kubectl/
#      nerdctl) — they target a filesystem this hook cannot inspect (#1900).
#   3. Cheap regex pre-filter for an `rm -<flags>` invocation; bail when absent.
#   4. Authoritative parse: split the command into statements on *unquoted*
#      `&&`, `||`, `;`, `|` and newlines; per statement strip leading
#      `VAR=value` assignments plus sudo/command/env/nice, require the command
#      word to be exactly `rm`, and require at least one recursion flag
#      (-r/-R/-rf/-fr/--recursive). Safety blocks deliberately fire inside
#      compound commands and pipelines — only the context-budget read-blocks
#      were narrowed to whole-command scope (#2148).
#   5. Per operand that resolves to a real directory, decide whether deleting it
#      destroys history: it must be a repo ROOT, i.e.
#      `git rev-parse --absolute-git-dir` equals "<dir>/.git" or "<dir>". That
#      one predicate excludes subdirectories, linked worktrees and submodules
#      (whose `.git` is a gitfile pointing into the parent). An operand that is
#      a *parent* of repos is scanned to depth 3, capped at 20 hits.
#   6. Tier 1 (exit 2): the repo has no remote (1a), or a remote that has never
#      been pushed to (1b). The message carries the source skill's three-option
#      remediation and is SELF-EXTINGUISHING — pushing, or writing the backup
#      tarball, changes the world state this hook reads, so the retried
#      `rm -rf` succeeds on the next attempt with no override. That property is
#      what keeps the same-session repeat-block rate near zero.
#   7. Tier 2 (opt-in, `ask`): a remote-backed repo that still carries
#      uncommitted / unpushed / stashed work. Off by default — agents delete
#      dirty clones and worktrees constantly and no *history* is at risk there,
#      so a default-on prompt would be pure tax.
#
# Fails OPEN by design. Never blocked: unresolvable operands ($VAR, $(...),
# globs, `{}` from `find -exec`), symlinks (rm removes the link, not the
# target), non-directories, and — by default — anything under a temp directory
# (this repo's own fixtures create remote-less repos under mktemp -d and clean
# them up with `rm -rf`). Sibling deletion verbs (`git clean -xdff`, `trash`,
# `mv`, `rmdir`, `shred`, `find … -delete`) are out of scope. See
# hooks/README.md for the full enumerated gap list.
#
# Opt out: CLAUDE_HOOKS_DISABLE_REPO_DELETION_SAFETY=1 — honored only when the
#   human operator has it in the *process* environment. An inline
#   `CLAUDE_HOOKS_DISABLE_REPO_DELETION_SAFETY=1 rm -rf …` prefix sets it for
#   the child command, never for this hook process, and the statement parser
#   strips leading `VAR=value` assignments so the bypass attempt is still
#   classified as an `rm`. Do not self-serve it.
# Tuning:
#   CLAUDE_REPO_BACKUP_DIR                 (default "$HOME/Backups") — where an
#       existing `<basename>-*.tar.*` clears the block, and the directory named
#       in the block message.
#   CLAUDE_HOOKS_REPO_DELETION_TMP_EXEMPT  (default 1) — 0 also guards repos
#       under /tmp, /private/tmp, /var/folders and $TMPDIR.
#   CLAUDE_HOOKS_REPO_DELETION_WARN_DIRTY  (default 0) — 1 enables the tier-2
#       `ask` on a remote-backed repo carrying uncommitted/unpushed/stashed work.
#
# Matches: Bash
# Exit codes: 0 = allow (or tier-2 envelope printed), 2 = block.
# Tier 1 blocks through the standard block() convention. The opt-in tier 2
# instead prints a PreToolUse permissionDecision:"ask" JSON envelope and exits
# 0, so that path deliberately does not use the block() convention.

# Not `set -e`: git probes exit non-zero routinely (rev-parse on a non-repo,
# remote/for-each-ref on an unrelated dir) and every substitution below is
# individually guarded with `|| true` / `|| return 0`.
set -uo pipefail

# Human-operator escape hatch. Only honored from the exported shell
# environment; see the header for why an inline prefix cannot reach it.
[ "${CLAUDE_HOOKS_DISABLE_REPO_DELETION_SAFETY:-}" = "1" ] && exit 0

# Degrade silently when a dependency is missing — never fail a user's command
# because the hook's toolchain is incomplete.
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[ -n "$COMMAND" ] || exit 0

# The directory the Bash command actually runs in — relative operands resolve
# against it, not against the hook process's own cwd (#1695).
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

# Remote-exec suppression (#1900): the deletion happens on another filesystem,
# where a coincidentally-named local path must not be consulted.
FIRST_TOKEN=$(printf '%s' "$COMMAND" | awk 'NF{print $1; exit}' 2>/dev/null || echo "")
case "$FIRST_TOKEN" in
    ssh|scp|rsync|docker|podman|kubectl|nerdctl) exit 0 ;;
esac

# Cheap pre-filter: an `rm` with at least one flag, optionally behind
# sudo/command or leading VAR=value assignments, at a statement boundary.
PREFILTER_RE='(^|[;&|(]|&&|\|\||[[:space:]])(sudo[[:space:]]+|command[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*rm[[:space:]]+-'
printf '%s' "$COMMAND" | grep -Eq "$PREFILTER_RE" || exit 0

block() {
    echo "$1" >&2
    exit 2
}

ask() {
    local reason="$1" json_reason
    json_reason=$(printf '%s' "$reason" | jq -Rs .)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$json_reason"
    exit 0
}

BACKUP_DIR="${CLAUDE_REPO_BACKUP_DIR:-${HOME:-/tmp}/Backups}"
TMP_EXEMPT="${CLAUDE_HOOKS_REPO_DELETION_TMP_EXEMPT:-1}"
WARN_DIRTY="${CLAUDE_HOOKS_REPO_DELETION_WARN_DIRTY:-0}"
TMPROOT="${TMPDIR:-/tmp}"
TMPROOT="${TMPROOT%/}"

# ── Command parsing ───────────────────────────────────────────────────────────

# Split $1 into statements on unquoted `;`, `&`, `|` runs and newlines.
# Quote- and backslash-aware so that a separator inside a quoted argument
# (`git commit -m "cleanup; rm -rf old"`) never manufactures a statement.
# Result lands in the global array STATEMENTS.
split_statements() {
    local s="$1" cur="" i=0 n c q=""
    n=${#s}
    STATEMENTS=()
    while [ "$i" -lt "$n" ]; do
        c="${s:$i:1}"
        if [ -n "$q" ]; then
            if [ "$c" = '\' ] && [ "$q" = '"' ]; then
                cur+="$c"
                i=$((i + 1))
                [ "$i" -lt "$n" ] && { cur+="${s:$i:1}"; i=$((i + 1)); }
                continue
            fi
            cur+="$c"
            [ "$c" = "$q" ] && q=""
            i=$((i + 1))
            continue
        fi
        case "$c" in
            "'"|'"')
                q="$c"; cur+="$c"; i=$((i + 1)) ;;
            '\')
                cur+="$c"; i=$((i + 1))
                [ "$i" -lt "$n" ] && { cur+="${s:$i:1}"; i=$((i + 1)); } ;;
            ';'|'&'|'|'|$'\n')
                STATEMENTS+=("$cur"); cur=""
                while [ "$i" -lt "$n" ]; do
                    case "${s:$i:1}" in
                        ';'|'&'|'|'|$'\n') i=$((i + 1)) ;;
                        *) break ;;
                    esac
                done ;;
            *)
                cur+="$c"; i=$((i + 1)) ;;
        esac
    done
    STATEMENTS+=("$cur")
}

# Split one statement into shell words, honoring quotes and backslashes and
# stripping the quote characters. Result lands in the global array TOKENS.
tokenize() {
    local s="$1" cur="" i=0 n c q="" started=0
    n=${#s}
    TOKENS=()
    while [ "$i" -lt "$n" ]; do
        c="${s:$i:1}"
        if [ -n "$q" ]; then
            if [ "$c" = '\' ] && [ "$q" = '"' ]; then
                i=$((i + 1))
                [ "$i" -lt "$n" ] && { cur+="${s:$i:1}"; i=$((i + 1)); }
                continue
            fi
            if [ "$c" = "$q" ]; then q=""; else cur+="$c"; fi
            i=$((i + 1))
            continue
        fi
        case "$c" in
            "'"|'"')
                q="$c"; started=1; i=$((i + 1)) ;;
            '\')
                i=$((i + 1))
                [ "$i" -lt "$n" ] && { cur+="${s:$i:1}"; started=1; i=$((i + 1)); } ;;
            ' '|$'\t')
                [ "$started" -eq 1 ] && { TOKENS+=("$cur"); cur=""; started=0; }
                i=$((i + 1)) ;;
            *)
                cur+="$c"; started=1; i=$((i + 1)) ;;
        esac
    done
    [ "$started" -eq 1 ] && TOKENS+=("$cur")
    return 0
}

# ── Repo classification ───────────────────────────────────────────────────────

# True only when deleting $1 destroys git history. `--absolute-git-dir` equals
# "$dir/.git" for a normal repo root and "$dir" for a bare repo (or for the
# .git directory itself); it is something else entirely — …/.git/worktrees/N,
# …/.git/modules/N, or the PARENT repo's .git — in every case where deleting
# $dir destroys nothing. Preferred over `[ -d "$1/.git" ]` for exactly that
# reason.
is_repo_root() {
    local d="$1" gd
    gd=$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null) || return 1
    [ -n "$gd" ] || return 1
    [ "$gd" = "$d/.git" ] || [ "$gd" = "$d" ]
}

# Echo a verdict token for repo root $1, or nothing when deletion is safe:
#   (empty)              — history lives elsewhere, or a backup tarball exists
#   no_remote            — tier 1a: no remote at all; this is the only copy
#   remote_never_pushed  — tier 1b: a remote is configured but nothing reached it
#   dirty|U|P|S|B        — tier 2 (opt-in): remote-backed but work is unsaved
classify() {
    local d="$1" base u p s b
    base=$(basename "$d")

    # ESCAPE — a dated backup tarball for this repo already exists. This is what
    # makes option 2 of the block message self-extinguishing.
    ls "$BACKUP_DIR/$base"-*.tar.* >/dev/null 2>&1 && return 0

    # TIER 1a — no remote at all.
    [ -z "$(git -C "$d" remote 2>/dev/null || true)" ] && { echo "no_remote"; return 0; }

    # TIER 1b — a remote is configured but nothing was ever pushed to it.
    [ -z "$(git -C "$d" for-each-ref --count=1 refs/remotes 2>/dev/null || true)" ] &&
        { echo "remote_never_pushed"; return 0; }

    # TIER 2 — opt-in. History is on the remote; only local-only work is at risk.
    [ "$WARN_DIRTY" = "1" ] || return 0
    u=$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d '[:space:]')
    p=$(git -C "$d" log --oneline '@{u}..HEAD' 2>/dev/null | wc -l | tr -d '[:space:]')
    s=$(git -C "$d" stash list 2>/dev/null | wc -l | tr -d '[:space:]')
    b=$(git -C "$d" branch -vv 2>/dev/null | grep -vc '\[' || true)
    case "$u" in ''|*[!0-9]*) u=0 ;; esac
    case "$p" in ''|*[!0-9]*) p=0 ;; esac
    case "$s" in ''|*[!0-9]*) s=0 ;; esac
    case "$b" in ''|*[!0-9]*) b=0 ;; esac
    if [ "$u" -gt 0 ] || [ "$p" -gt 0 ] || [ "$s" -gt 0 ] || [ "$b" -gt 0 ]; then
        echo "dirty|$u|$p|$s|$b"
    fi
    return 0
}

emit_block() {
    local abs="$1" verdict="$2" base cause
    base=$(basename "$abs")
    case "$verdict" in
        no_remote) cause="no remote configured" ;;
        remote_never_pushed) cause="a remote that has never been pushed to" ;;
        *) cause="no off-machine copy of its history" ;;
    esac
    block "BLOCKED: '$abs' is a git repository with $cause.
This checkout is the ONLY copy of its history — \`rm -rf\` here is permanent and unrecoverable.

Preserve the work first, then re-run the delete (this block clears itself once either succeeds):
  1. Push to a remote:  git -C '$abs' remote add origin <url> && git -C '$abs' push -u origin --all
  2. Tar to a labelled backup (the default when the user just says \"go\"):
     mkdir -p '$BACKUP_DIR' && tar -czf '$BACKUP_DIR/$base-\$(date -I).tar.gz' '$abs'
  3. Delete with no backup — confirm with the user that the work, including any
     uncommitted files, branches and stashes, is genuinely disposable, then ask them
     to run the command themselves per .claude/rules/handling-blocked-hooks.md.
Invoke \`git-plugin:git-repo-delete-check\` to walk the full preflight (unpushed
commits, stashes, upstream-less branches) before choosing between them.
Do not self-serve CLAUDE_HOOKS_DISABLE_REPO_DELETION_SAFETY — it is honored only from the operator's shell environment."
}

emit_ask() {
    local abs="$1" verdict="$2" rest u p s b
    rest="${verdict#dirty|}"
    u="${rest%%|*}"; rest="${rest#*|}"
    p="${rest%%|*}"; rest="${rest#*|}"
    s="${rest%%|*}"; b="${rest##*|}"
    ask "'$abs' is a git repository backed by a remote, so its pushed history survives this deletion — but local-only work would not:
  uncommitted changes (git status --porcelain): $u
  unpushed commits (git log @{u}..HEAD):        $p
  stashes (git stash list):                     $s
  branches with no upstream (git branch -vv):   $b

Approve if that work is genuinely disposable. To preserve it first:
  git -C '$abs' status --porcelain && git -C '$abs' push --all origin
Silence this class of prompt with CLAUDE_HOOKS_REPO_DELETION_WARN_DIRTY=0 (it is already off by default)."
}

decide() {
    local d="$1" verdict
    verdict=$(classify "$d")
    case "$verdict" in
        "") return 0 ;;
        dirty\|*) emit_ask "$d" "$verdict" ;;
        *) emit_block "$d" "$verdict" ;;
    esac
}

# ── Operand inspection ────────────────────────────────────────────────────────

check_path() {
    local p="$1" target abs gd root

    # Flags and the `--` separator are not paths.
    case "$p" in --|-*) return 0 ;; esac

    # Unresolvable operands — $VAR, $(…), `…`, and `{}` from find -exec. The
    # hook cannot know the target, so it fails open rather than guessing.
    case "$p" in *'$'*|*'`'*) return 0 ;; esac

    # Globs. Without dotglob, `*` does not match `.git`, so `rm -rf repo/*`
    # leaves history intact; and expanding an arbitrary glob inside a 5s hook is
    # unbounded. `{}` from `find -exec` lands here too.
    case "$p" in *'*'*|*'?'*|*'['*|*'{'*) return 0 ;; esac

    # Leading ~ only — a mid-path tilde is literal.
    case "$p" in
        '~') p="${HOME:-}" ;;
        '~/'*) p="${HOME:-}${p#\~}" ;;
    esac
    [ -n "$p" ] || return 0

    # Relative operands resolve against the cwd the Bash command runs in.
    target="$p"
    case "$target" in
        /*) ;;
        *) [ -n "$HOOK_CWD" ] && target="${HOOK_CWD%/}/$target" ;;
    esac

    # A symlink: `rm -rf link` removes the link, not the repo it points at.
    [ -L "${target%/}" ] && return 0

    # Not a directory (or missing) → nothing to destroy.
    abs=$(cd "$target" 2>/dev/null && pwd -P) || return 0
    [ -n "$abs" ] || return 0

    if [ "$TMP_EXEMPT" = "1" ]; then
        case "$abs" in
            /tmp/*|/private/tmp/*|/var/folders/*|"$TMPROOT"/*) return 0 ;;
        esac
    fi

    # (a) the operand is itself a repo root (or a bare repo / a .git dir).
    if is_repo_root "$abs"; then
        decide "$abs"
        return 0
    fi

    # (b) the operand is a PARENT holding repos — bounded scan so a
    # `rm -rf ~/repos` over a large tree cannot blow the hook timeout. If it
    # does time out, the non-2 exit is non-blocking: fail open, correctly.
    while IFS= read -r gd; do
        [ -n "$gd" ] || continue
        root=$(dirname "$gd")
        is_repo_root "$root" || continue
        decide "$root"
    done < <(find "$abs" -maxdepth 3 -type d -name .git 2>/dev/null | head -20)

    return 0
}

# ── Main ──────────────────────────────────────────────────────────────────────

STATEMENTS=()
TOKENS=()
split_statements "$COMMAND"

for stmt in ${STATEMENTS[@]+"${STATEMENTS[@]}"}; do
    # Trim leading whitespace and subshell parens.
    while :; do
        case "$stmt" in
            [[:space:]]*|'('*) stmt="${stmt#?}" ;;
            *) break ;;
        esac
    done
    case "$stmt" in *')') stmt="${stmt%)}" ;; esac
    [ -n "$stmt" ] || continue

    tokenize "$stmt"
    [ "${#TOKENS[@]}" -gt 0 ] || continue

    # Strip leading `VAR=value` assignments and command wrappers so an inline
    # bypass attempt is still classified as the `rm` it is.
    idx=0
    while [ "$idx" -lt "${#TOKENS[@]}" ]; do
        case "${TOKENS[$idx]}" in
            [A-Za-z_]*=*|sudo|command|env|nice) idx=$((idx + 1)) ;;
            *) break ;;
        esac
    done
    [ "$idx" -lt "${#TOKENS[@]}" ] || continue

    # The statement's command word must be exactly `rm` — this is what makes a
    # quoted occurrence (`git commit -m "rm -rf old"`) inert.
    [ "${TOKENS[$idx]}" = "rm" ] || continue

    # At least one recursion flag. `rm -f file` can never destroy a directory.
    has_recursive=0
    j=$((idx + 1))
    while [ "$j" -lt "${#TOKENS[@]}" ]; do
        case "${TOKENS[$j]}" in
            --recursive) has_recursive=1 ;;
            --*) ;;
            -*[rR]*)
                rest="${TOKENS[$j]#-}"
                case "$rest" in
                    *[!a-zA-Z]*) ;;
                    *) has_recursive=1 ;;
                esac ;;
        esac
        j=$((j + 1))
    done
    [ "$has_recursive" -eq 1 ] || continue

    j=$((idx + 1))
    while [ "$j" -lt "${#TOKENS[@]}" ]; do
        check_path "${TOKENS[$j]}"
        j=$((j + 1))
    done
done

exit 0
