#!/usr/bin/env bash
# PreToolUse hook for the Bash tool — nudges before cutting a new branch from a
# local default branch that is ahead of its remote.
#
# Problem (git-hazards.md trap #2 — "Unpushed commits on local `main` ride into
# new branches"): branching off a local `main` that still holds unpushed commits
# inherits them. The new branch's PR then bundles those stray commits under an
# unrelated title, and a squash-merge hides them everywhere except the file
# list.
#
# Strategy:
#   1. Guard: fires only on branch-CREATING forms — `git switch -c/-C/--create/
#      --force-create`, `git checkout -b/-B`, `git worktree add ... -b/-B`.
#      Quoted segments are scrubbed before matching so a commit message that
#      merely mentions the command is inert. Bare `git branch <name>` is
#      deliberately out of scope: listing/deleting/-vv dominate its real-world
#      use, so distinguishing creation costs more false positives than the
#      coverage buys.
#   2. Resolve the repo dir in precedence order: an explicit `git -C <path>` in
#      the command (#1389) > the hook input's `.cwd`, i.e. the worktree the Bash
#      command actually runs in (#1695) > the hook process's own cwd.
#   3. Exemption 1 (load-bearing): an explicit start-point was given
#      (`git switch -c feat/x origin/main`). The hook's OWN suggested fix has
#      that shape — get this wrong and the corrected command re-triggers the
#      nudge, producing the infinite ask loop that is exactly the repeat-block
#      pathology which demoted the find/grep/ls guards.
#   4. Exemption 2: nudge only when HEAD *is* the resolved default branch.
#      Stacking a branch off a feature branch is deliberate.
#   5. Dedup: at most one nudge per session+repo+default per TTL. The window is
#      claimed BEFORE the work, so a killed run degrades to "no check" rather
#      than re-polling on every call.
#   6. If local <default> is ahead of origin/<default>, emit
#      permissionDecision:"ask" — a nudge, never a hard deny. Nothing here is
#      irreversible (worst case is a PR whose file list is wider than its title,
#      fixable with a single `git rebase --onto`), and repos that legitimately
#      develop on their default branch must never be dead-ended.
#
# The default branch is RESOLVED (refs/remotes/origin/HEAD, then a probed
# main/master fallback), never hardcoded to `main` — origin/HEAD is unset in
# most agent worktrees, --single-branch clones and CI checkouts, so the fallback
# is the usual path rather than the exception.
#
# No `git fetch` in the default path: a stale origin/<default> can only
# OVERSTATE the ahead-count, the suggested fix contains the fetch anyway, and a
# network round-trip on every branch creation is a poor trade against the 5000ms
# timeout. Opt in with CLAUDE_HOOKS_BRANCH_BASE_FETCH=1.
#
# Unlike branch-protection.sh, this hook does NOT defer under permission_mode
# "auto": auto mode's classifier reasons about protected-branch writes and
# force-pushes and has no notion of which base a branch is cut from, so
# deferring would leave the hazard ungated rather than avoid double-gating.
#
# Known gaps (documented, not oversights): a *stale* origin/<default> that was
# never fetched, cutting from an equally-ahead feature branch, and bare
# `git branch <name>` are all uncovered.
#
# Opt out: CLAUDE_HOOKS_DISABLE_BRANCH_BASE_GUARD=1 — the documented answer for
#   a repo that legitimately develops on its default branch (dotfiles, personal
#   repos). Honored only from the operator's exported shell environment: an
#   inline `VAR=1 git switch -c ...` prefix sets it for the child command, not
#   for this hook process, and the statement parser strips leading VAR=value
#   assignments so a bypass attempt is still classified as a branch creation.
# TTL override (seconds): CLAUDE_HOOKS_BRANCH_BASE_TTL (default 300)
# Fresher ahead-count:    CLAUDE_HOOKS_BRANCH_BASE_FETCH=1
#
# This hook asks via a JSON envelope rather than blocking with exit 2, so it
# deliberately does not use the block() convention.
#
# Matches: Bash

# Not `set -e`: git probes exit non-zero routinely (symbolic-ref on a detached
# HEAD, rev-parse outside a repo), and every such probe here is guarded.
set -uo pipefail

# Human-operator escape hatch — see header comment for why an inline prefix on
# the guarded command cannot reach this check.
[ "${CLAUDE_HOOKS_DISABLE_BRANCH_BASE_GUARD:-}" = "1" ] && exit 0

# Degrade silently when a dependency is missing — never fail the user's command.
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ "$TOOL_NAME" = "Bash" ] || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[ -n "$COMMAND" ] || exit 0
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null || echo "nosession")

# Remote-exec suppression (#1900 precedent): the command targets another
# filesystem that `git -C` here cannot inspect.
case "$(printf '%s' "$COMMAND" | awk 'NR==1{print $1}')" in
    ssh|docker|podman|kubectl|nerdctl) exit 0 ;;
esac

# ── ask(): the JSON-envelope nudge. Escape with jq, never by hand. ────────────
ask() {
    local reason="$1" json_reason
    json_reason=$(printf '%s' "$reason" | jq -Rs .)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' \
        "$json_reason"
    exit 0
}

# ── Statement splitting ───────────────────────────────────────────────────────
# Split $COMMAND on UNQUOTED `;`, `&&`, `||`, `|`, `&`, `(`, `)` and newline.
# Quote state is tracked so a delimiter inside a string does not split.
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

# Blank out quoted segments so `git commit -m "git switch -c x"` is inert.
# check-branch-sync-on-push.sh's regex lacks this; do not inherit the weakness.
scrub_quotes() {
    sed -E "s/'[^']*'/''/g; s/\"[^\"]*\"/\"\"/g"
}

# Branch-creating forms only. This is a PRE-FILTER — parse_statement below is
# authoritative about whether a create flag and a start-point are present.
TRIGGER_RE='(^|[;&|(]|&&[[:space:]]*|\|\|[[:space:]]*|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(switch[[:space:]]+(-c|-C|--create|--force-create)|checkout[[:space:]]+(-b|-B)|worktree[[:space:]]+add[[:space:]]+[^[:space:]]*[[:space:]]*(-b|-B))'

# ── Statement parse (authoritative) ──────────────────────────────────────────
# Sets: MODE, NEW_BRANCH, START_POINT, GIT_C_PATH. Returns 1 when the statement
# is not a branch creation.
MODE=""; NEW_BRANCH=""; START_POINT=""; GIT_C_PATH=""

unquote() {
    local s="${1-}"
    s="${s//\'/}"
    s="${s//\"/}"
    printf '%s' "$s"
}

parse_statement() {
    local stmt="$1" t create_re i n
    local -a raw=() pos=()
    read -r -a raw <<<"$stmt"
    n=${#raw[@]}
    [ "$n" -gt 0 ] || return 1

    MODE=""; NEW_BRANCH=""; START_POINT=""; GIT_C_PATH=""

    # Strip leading `VAR=value` assignments and sudo/command/env/nice wrappers,
    # so an inline-bypass attempt is still classified as a branch creation.
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

    # Global git options before the subcommand. -C/-c/--git-dir/... take a value.
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

    case "$(unquote "${raw[$i]:-}")" in
        switch)   MODE="switch";   create_re='^(-c|-C|--create|--force-create)$' ;;
        checkout) MODE="checkout"; create_re='^(-b|-B)$' ;;
        worktree) MODE="worktree"; create_re='^(-b|-B)$' ;;
        *) return 1 ;;
    esac
    i=$((i + 1))

    if [ "$MODE" = "worktree" ]; then
        [ "$(unquote "${raw[$i]:-}")" = "add" ] || return 1
        i=$((i + 1))
    fi

    local created=0
    while [ "$i" -lt "$n" ]; do
        t=$(unquote "${raw[$i]}")
        [ "$t" = "--" ] && break
        if [[ "$t" =~ $create_re ]]; then
            created=1
            NEW_BRANCH=$(unquote "${raw[$((i + 1))]:-}")
            i=$((i + 2)); continue
        fi
        case "$t" in
            --create=*|--force-create=*)
                created=1; NEW_BRANCH="${t#*=}"; i=$((i + 1)); continue ;;
            # Value-taking flags whose argument must NOT be read as a
            # start-point. `-t`/`--track` take no separate value, so their
            # following token IS the start-point and must stay positional.
            --orphan|--reason) i=$((i + 2)); continue ;;
            -*) i=$((i + 1)); continue ;;
        esac
        pos+=("$t")
        i=$((i + 1))
    done

    [ "$created" -eq 1 ] || return 1

    # switch/checkout: the branch name was the create flag's value, so the first
    # positional is the start-point. `worktree add -b <branch> <path> [<ref>]`
    # spends the first positional on the worktree PATH.
    if [ "$MODE" = "worktree" ]; then
        START_POINT="${pos[1]-}"
    else
        START_POINT="${pos[0]-}"
    fi
    return 0
}

# ── Find the branch-creating statement ───────────────────────────────────────
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

# ── EXEMPTION 1 (load-bearing): an explicit start-point was given ────────────
# `git switch -c feat/x origin/main` is the hook's own suggested fix. It must
# never re-trigger the nudge.
[ -n "$START_POINT" ] && exit 0

# ── Repo dir: `git -C <path>` (#1389) > input .cwd (#1695) > process cwd ─────
REPO_DIR="${GIT_C_PATH:-${HOOK_CWD:-}}"
if [ -n "$REPO_DIR" ]; then
    git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 || exit 0
else
    git rev-parse --git-dir >/dev/null 2>&1 || exit 0
    REPO_DIR="$PWD"
fi

# ── EXEMPTION 2: only nudge when HEAD *is* the resolved default branch ──────
BRANCH=$(git -C "$REPO_DIR" symbolic-ref --short HEAD 2>/dev/null || echo "")
[ -n "$BRANCH" ] || exit 0   # detached HEAD

DEFAULT=$(git -C "$REPO_DIR" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || echo "")
if [ -z "$DEFAULT" ]; then
    for candidate in main master; do
        if git -C "$REPO_DIR" rev-parse --verify --quiet "refs/remotes/origin/$candidate" >/dev/null 2>&1; then
            DEFAULT="$candidate"
            break
        fi
    done
fi
[ -n "$DEFAULT" ] || exit 0                 # no origin / no resolvable default
[ "$BRANCH" = "$DEFAULT" ] || exit 0        # stacking off a feature branch is deliberate
git -C "$REPO_DIR" rev-parse --verify --quiet "refs/remotes/origin/$DEFAULT" >/dev/null 2>&1 || exit 0

# ── Dedup: one nudge per session+repo+default per TTL ────────────────────────
TTL="${CLAUDE_HOOKS_BRANCH_BASE_TTL:-300}"
case "$TTL" in ''|*[!0-9]*) TTL=300 ;; esac
SID=$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-'); SID="${SID:-nosession}"
ROOT=$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$REPO_DIR")
KEY=$(printf '%s@%s' "$ROOT" "$DEFAULT" | tr -cd 'a-zA-Z0-9_.@-' | tail -c 100)
KEY="${KEY:-repo}"
CACHE="${TMPDIR:-/tmp}/claude-branch-base/$SID/$KEY"
now=$(date +%s 2>/dev/null || echo 0)
case "$now" in ''|*[!0-9]*) now=0 ;; esac
if [ -f "$CACHE" ]; then
    last=$(cat "$CACHE" 2>/dev/null || echo 0)
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    if [ "$last" -gt 0 ] && [ "$now" -gt 0 ] && [ $((now - last)) -lt "$TTL" ]; then
        exit 0
    fi
fi
# Claim the window BEFORE the work: a killed run degrades to "no check" rather
# than re-polling on every subsequent call.
mkdir -p "$(dirname "$CACHE")" 2>/dev/null || true
printf '%s' "$now" > "$CACHE" 2>/dev/null || true

# ── Measure (no network in the default path) ─────────────────────────────────
if [ "${CLAUDE_HOOKS_BRANCH_BASE_FETCH:-0}" = "1" ]; then
    git -C "$REPO_DIR" fetch --quiet origin "$DEFAULT" >/dev/null 2>&1 || true
fi
AHEAD=$(git -C "$REPO_DIR" rev-list --count "refs/remotes/origin/$DEFAULT..HEAD" 2>/dev/null || echo 0)
case "$AHEAD" in ''|*[!0-9]*) AHEAD=0 ;; esac
[ "$AHEAD" -gt 0 ] || exit 0

SUBJECTS=$(git -C "$REPO_DIR" log --oneline -3 "refs/remotes/origin/$DEFAULT..HEAD" 2>/dev/null || echo "")
BRANCH_LABEL="${NEW_BRANCH:-<branch>}"

REASON="Local '$DEFAULT' is $AHEAD commit(s) ahead of origin/$DEFAULT, and you are about to cut '$BRANCH_LABEL' from it. Those commits ride into the new branch and get bundled into its PR under an unrelated title — a squash-merge hides them everywhere except the file list (git-hazards.md trap #2).

Commits that would ride along:
$SUBJECTS

Cut from the remote instead:
  git fetch origin && git switch -c $BRANCH_LABEL origin/$DEFAULT
Verify at any time with:
  git log --oneline origin/$DEFAULT..$DEFAULT

Approve if carrying those commits is intentional (stacked branch, or this repo develops on $DEFAULT). Silence this guard permanently by exporting CLAUDE_HOOKS_DISABLE_BRANCH_BASE_GUARD=1 from your shell."

ask "$REASON"
