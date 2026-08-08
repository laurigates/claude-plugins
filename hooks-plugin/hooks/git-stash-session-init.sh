#!/usr/bin/env bash
# SessionStart hook - records git baselines for session-scoped tracking
#
# Two baselines are written:
#   - stash baseline (used by git-stash-reminder.sh), keyed by
#     (session_id, repo root) — see below
#   - HEAD commit baseline (used by test-verification.sh to skip when no
#     commits have landed since the session began), keyed by session_id
#
# The stash baseline is keyed per (session, stash namespace), NOT per session
# alone (issue #2306). A session's cwd can move into a DIFFERENT git repository
# after SessionStart (nested checkout, sibling repo, vendored tree); a
# session-only key meant the Stop hook compared that repo's stashes against a
# baseline that described some other repo, so every pre-existing stash there was
# reported as "created during this session".
#
# The namespace is the git COMMON dir, not `--show-toplevel`: `refs/stash` lives
# in the common dir and is shared by every linked worktree of a repo, so keying
# on the toplevel would give one stash namespace two baselines.
#
# On-disk layout:
#   ${CLAUDE_STASH_BASELINE_DIR:-/tmp/claude-stash-baselines}/
#     <session-id>.d/
#       .session-start          # empty marker; its mtime IS the session start
#       <namespace-key>         # one file per stash namespace seen this session
#
# Both writes are WRITE-ONCE per session. SessionStart fires again on resume,
# clear and compact (matcher "" in plugin.json), and re-writing either file
# would un-report a stash the Stop hook had already flagged: a fresh marker
# moves the session-start bound past the stash's creation time, and a fresh
# baseline absorbs the stash's own hash. The session started when it started.
#
# Each per-namespace baseline starts with a `# <namespace>` header line so that
# a repo which legitimately had NO stashes still produces a non-empty file. The
# Stop hook treats a 0-byte baseline as UNKNOWN (defect 2 of #2306), which would
# otherwise be indistinguishable from "this repo had no stashes".
#
# The script keeps its historical name for plugin.json compatibility even
# though it now records more than stashes.
set -euo pipefail

# Stable per-namespace filename. Prefers a hash (bounded length, no
# path-separator escaping); falls back to a sanitized path when no hashing
# tool is on PATH. MUST stay byte-identical to the copy in git-stash-reminder.sh
# — the two scripts have to agree on where a repo's baseline lives.
repo_key() {
    local root="$1" key=""
    if command -v shasum >/dev/null 2>&1; then
        key=$(printf '%s' "$root" | shasum -a 256 2>/dev/null | cut -d' ' -f1)
    elif command -v sha256sum >/dev/null 2>&1; then
        key=$(printf '%s' "$root" | sha256sum 2>/dev/null | cut -d' ' -f1)
    fi
    if [ -z "$key" ]; then
        key=$(printf '%s' "$root" | tr -c 'a-zA-Z0-9_-' '_')
    fi
    printf '%s' "${key:0:64}"
}

# Absolute, symlink-resolved path of the git COMMON dir — the directory that
# holds refs/stash. Every linked worktree of a repo resolves to the SAME value,
# which is what makes one stash namespace map to one baseline. MUST stay
# byte-identical to the copy in git-stash-reminder.sh.
stash_namespace() { # stash_namespace <cwd>
    local cwd="$1" gcd=""
    gcd=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    if [ -z "$gcd" ]; then
        # git < 2.31 has no --path-format; the bare form is relative to <cwd>.
        gcd=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null || true)
        case "$gcd" in
            ''|/*) ;;
            *) gcd="$cwd/$gcd" ;;
        esac
    fi
    if [ -z "$gcd" ]; then
        return 0
    fi
    (cd "$gcd" 2>/dev/null && pwd -P) || printf '%s' "$gcd"
}

# Read JSON input from stdin and extract fields
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# Sanitize session_id to prevent path traversal (keep only alnum, hyphens, underscores)
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')

# Guard: no working directory or session ID
if [ -z "$CWD" ] || [ -z "$SESSION_ID" ]; then
    exit 0
fi

# Guard: not a git repository
if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

# Record current stash commit hashes as the session baseline for THIS repo.
# Uses %H (full commit hash) because stash indices (%gd) shift when stashes
# are added or removed. Hashes are stable identifiers.
STASH_BASELINE_DIR="${CLAUDE_STASH_BASELINE_DIR:-/tmp/claude-stash-baselines}"
SESSION_BASELINE_DIR="${STASH_BASELINE_DIR}/${SESSION_ID}.d"
mkdir -p "$SESSION_BASELINE_DIR" 2>/dev/null || true

# The marker's mtime is the session start time. git-stash-reminder.sh uses it
# to filter out stashes that were created before this session began, which is
# a defence that holds even when the baseline itself is missing or unusable.
# Write-once: a resume/compact re-fire must not move the bound forward past a
# stash this session already created (and already reported).
if [ ! -e "${SESSION_BASELINE_DIR}/.session-start" ]; then
    : > "${SESSION_BASELINE_DIR}/.session-start" 2>/dev/null || true
fi

STASH_ROOT=$(stash_namespace "$CWD")
if [ -n "$STASH_ROOT" ]; then
    STASH_BASELINE_FILE="${SESSION_BASELINE_DIR}/$(repo_key "$STASH_ROOT")"
    # Write-once for the same reason: re-recording on a resume/compact would
    # absorb a stash the session created after the original SessionStart. A
    # 0-byte file is a failed/legacy capture, so it is (re)written.
    if [ ! -s "$STASH_BASELINE_FILE" ]; then
        {
            printf '# %s\n' "$STASH_ROOT"
            git -C "$CWD" stash list --format='%H' 2>/dev/null || true
        } > "$STASH_BASELINE_FILE" 2>/dev/null || true
    fi
fi

# Record HEAD commit at session start. Used by test-verification.sh to skip
# the test run when HEAD has not advanced (no commits landed → nothing new
# to verify). Empty file if HEAD cannot be resolved (unborn branch, etc.).
# NOTE: not env-overridable — test-verification.sh reads this path literally,
# so a seam here alone would let the two halves disagree.
TEST_BASELINE_DIR="/tmp/claude-test-baselines"
mkdir -p "$TEST_BASELINE_DIR"
TEST_BASELINE_FILE="${TEST_BASELINE_DIR}/${SESSION_ID}"
git -C "$CWD" rev-parse HEAD 2>/dev/null > "$TEST_BASELINE_FILE" || true

exit 0
