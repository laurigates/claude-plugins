#!/usr/bin/env bash
# Stop hook - reminds about git stashes created DURING the current session
#
# Baselines are written by git-stash-session-init.sh at SessionStart, keyed by
# (session_id, stash namespace). Three independent, layered defences keep a
# pre-existing stash from being reported as a session stash (issue #2306):
#
#   1. Per-(session, stash-namespace) baseline lookup. The baseline was
#      previously keyed by session alone but compared against whatever repo the
#      cwd pointed at when the Stop hook ran. A session that started in one
#      repo and later moved into another (nested checkout, sibling repo,
#      vendored tree) therefore judged repo B's stashes against repo A's
#      baseline, and every pre-existing stash in B counted as new.
#
#      The key is the git COMMON dir, not `--show-toplevel`: `refs/stash` lives
#      in the common dir and is shared by every linked worktree of a repo, so
#      keying on the toplevel would hand ONE stash namespace TWO baselines and
#      reintroduce the same first-observation miss through a worktree.
#
#      A repo with no baseline is one this session has not observed before.
#      Capture what was already there — bounded by the session start, so a
#      stash the session itself created is NOT absorbed — and then judge the
#      remainder normally. Capturing everything and exiting would swallow a
#      genuine session stash made in a repo the session had not yet Stopped in.
#
#   2. An empty baseline file is treated as UNKNOWN, not as "no stashes were
#      here". A 0-byte file used to satisfy the `-f` guard and then match no
#      hash, so every stash counted as new (defect 1 reliably produced 0-byte
#      baselines, which is how the two defects compounded). Every baseline
#      written by this hook family carries a `# <stash-namespace>` header line,
#      so a repo that legitimately had no stashes still yields a NON-empty file
#      and stays distinguishable from a capture that failed. An empty one is
#      re-captured and this Stop stays silent.
#
#   3. Age filter. A stash whose creation timestamp predates the session start
#      cannot have been created during the session, whatever the baseline
#      says. Session start is the mtime of the `.session-start` marker written
#      by git-stash-session-init.sh. When that marker is absent — the plugin
#      was installed mid-session — it falls back to the mtime of the per-repo
#      baseline file, i.e. the moment this session first observed the repo.
#      That is the best bound available and is never earlier than the true
#      session start, so the filter can only ever be conservative (it never
#      lets an older stash through). The baseline is therefore captured even
#      for a repo holding NO stashes, so entering a repo establishes that bound
#      before any stash exists there.
#
# An unusable baseline and the pre-#2306 legacy flat baseline (a plain file at
# <dir>/<session-id>) both degrade to SILENCE — never to a false alarm. A stash
# genuinely created during the session is still reported, in the SessionStart
# repo, in a repo entered later, and through a linked worktree.
set -euo pipefail

# Stable per-namespace filename. MUST stay byte-identical to the copy in
# git-stash-session-init.sh — the two scripts have to agree on where a repo's
# baseline lives.
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
# byte-identical to the copy in git-stash-session-init.sh.
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

# Portable mtime in epoch seconds (GNU stat, then BSD stat, then 0).
file_mtime() {
    local mt
    mt=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)
    case "$mt" in
        ''|*[!0-9]*) printf '0' ;;
        *) printf '%s' "$mt" ;;
    esac
}

# Read JSON input from stdin and extract fields
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

# Guard: stop_hook_active - prevent infinite loops
# When Claude is already acting on a previous stop hook's feedback,
# do not block again
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Guard: no working directory provided
if [ -z "$CWD" ]; then
    exit 0
fi

# Guard: not a git repository
if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

# Sanitize session_id (keep only alnum, hyphens, underscores)
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')
if [ -z "$SESSION_ID" ]; then
    exit 0
fi

# Resolve the stash namespace the stashes actually belong to. This is the key
# the baseline must be looked up by — NOT the session alone, not the
# SessionStart cwd, and not the worktree toplevel (defence 1).
STASH_ROOT=$(stash_namespace "$CWD")
if [ -z "$STASH_ROOT" ]; then
    exit 0
fi
# Only used to name the location in the message the user reads.
REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")

BASELINE_ROOT="${CLAUDE_STASH_BASELINE_DIR:-/tmp/claude-stash-baselines}"
SESSION_BASELINE_DIR="${BASELINE_ROOT}/${SESSION_ID}.d"
BASELINE_FILE="${SESSION_BASELINE_DIR}/$(repo_key "$STASH_ROOT")"

CURRENT_STASHES=$(git -C "$CWD" stash list --format='%H|%gd|%ct|%gs' 2>/dev/null || true)

# Defence 3's bound, read BEFORE the capture below so the capture itself can
# use it (see the header for the fallback rationale).
SESSION_START=$(file_mtime "${SESSION_BASELINE_DIR}/.session-start")

if [ -f "$BASELINE_FILE" ] && [ ! -s "$BASELINE_FILE" ]; then
    # Defence 2: present but 0 bytes. Every baseline this hook family writes
    # carries a `# <namespace>` header, so a repo that legitimately had no
    # stashes still yields a non-empty file. An empty one therefore means the
    # capture failed or predates #2306 — the state is UNKNOWN, so treat
    # everything present as pre-existing and say nothing this Stop.
    {
        printf '# %s\n' "$STASH_ROOT"
        printf '%s\n' "$CURRENT_STASHES" | cut -d'|' -f1 | grep -v '^$' || true
    } > "$BASELINE_FILE" 2>/dev/null || true
    exit 0
fi

if [ ! -f "$BASELINE_FILE" ]; then
    # Defence 1: first time this session has observed this stash namespace.
    # Record what was already here — bounded by the session start, so a stash
    # the session itself created is NOT absorbed into the baseline — then fall
    # through and judge the remainder normally. Without a session-start bound
    # the only safe reading is that everything present is pre-existing, which
    # degrades this namespace to silence.
    mkdir -p "$SESSION_BASELINE_DIR" 2>/dev/null || true
    {
        printf '# %s\n' "$STASH_ROOT"
        printf '%s\n' "$CURRENT_STASHES" | awk -F'|' -v s="$SESSION_START" '
            $1 == "" { next }
            s > 0 && $3 ~ /^[0-9]+$/ && $3 + 0 >= s + 0 { next }
            { print $1 }
        '
    } > "$BASELINE_FILE" 2>/dev/null || true
    if [ ! -s "$BASELINE_FILE" ]; then
        # The capture could not be written (read-only baseline dir, full disk).
        # A successful one always contains at least the header, so an unwritten
        # or empty file here means this session has NO record of the namespace
        # and no bound derived from it — there is no basis for any claim.
        exit 0
    fi
    if [ "$SESSION_START" -eq 0 ]; then
        # No marker and no prior observation: the capture we just made is the
        # earliest bound available. It suppresses every stash present right now.
        SESSION_START=$(file_mtime "$BASELINE_FILE")
    fi
fi

# Fast path: nothing to report. Runs AFTER the capture so that entering a
# stash-free repo still establishes its baseline (and, with no `.session-start`
# marker, the session-start bound) before any stash exists there.
if [ -z "$CURRENT_STASHES" ]; then
    exit 0
fi

BASELINE_HASHES=$(cat "$BASELINE_FILE" 2>/dev/null || true)
if [ "$SESSION_START" -eq 0 ]; then
    SESSION_START=$(file_mtime "$BASELINE_FILE")
fi

# Compare: find stashes whose hashes are NOT in the baseline
NOW=$(date +%s)
NEW_STASHES=""
NEW_COUNT=0

while IFS='|' read -r hash ref ts subject; do
    [ -z "$hash" ] && continue
    [ -z "$ts" ] && continue
    # A non-numeric timestamp cannot be reasoned about; skip rather than guess.
    case "$ts" in
        *[!0-9]*) continue ;;
    esac

    # Skip stashes that existed at session start (in the baseline)
    if [ -n "$BASELINE_HASHES" ] && echo "$BASELINE_HASHES" | grep -qF "$hash" 2>/dev/null; then
        continue
    fi

    # Defence 3: a stash created before this session began cannot be a session
    # stash, regardless of what the baseline does or does not contain.
    if [ "$SESSION_START" -gt 0 ] && [ "$ts" -lt "$SESSION_START" ]; then
        continue
    fi

    # This is a new stash created during the session
    NEW_COUNT=$((NEW_COUNT + 1))
    AGE=$((NOW - ts))
    HOURS=$((AGE / 3600))
    MINS=$(( (AGE % 3600) / 60 ))
    if [ "$HOURS" -gt 0 ]; then
        AGE_STR="${HOURS}h ${MINS}m ago"
    else
        AGE_STR="${MINS}m ago"
    fi
    NEW_STASHES="${NEW_STASHES}  ${ref} (${AGE_STR}): ${subject} → git stash pop\n"
done <<< "$CURRENT_STASHES"

# No new stashes → exit silently
if [ "$NEW_COUNT" -eq 0 ]; then
    exit 0
fi

# Build the reason message for new session stashes only
REASON="Found ${NEW_COUNT} git stash(es) created during this session in ${REPO_ROOT}. Review before exiting:\n"
REASON="${REASON}\nSession stashes — pop or apply them:\n${NEW_STASHES}"
REASON="${REASON}\nRun 'git stash list' to inspect, or 'git stash show -p stash@{N}' to review contents."

# Output block decision with proper JSON escaping via jq
FORMATTED_REASON=$(printf '%b' "$REASON")
# shellcheck disable=SC2016  # jq expression, not shell expansion
jq -n --arg reason "$FORMATTED_REASON" '{"decision": "block", "reason": $reason}'
