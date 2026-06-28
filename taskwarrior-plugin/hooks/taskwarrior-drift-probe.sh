#!/usr/bin/env bash
# taskwarrior-drift-probe.sh — SessionStart probe for taskwarrior-plugin drift.
#
# Surfaces two kinds of drift at session start (via the shared drift-aggregator
# nudge) so they no longer accumulate silently until a manual sweep:
#
#   1. udas_missing       — the plugin's custom UDAs (bpid, bpdoc, bpms, ghid,
#                           ghpr, agent, pid, host, branch, worktree) are not
#                           declared in ~/.taskrc, so `task add` silently drops
#                           the field. Single-sourced from scripts/ensure-udas.sh
#                           in --check mode (never mutates ~/.taskrc here).
#   2. stale_linked_tasks — pending tasks whose linked GitHub issue/PR has closed
#                           or merged. Classified by the SAME deterministic
#                           reconcile.sh that /taskwarrior:task-reconcile uses, in
#                           DRY-RUN mode, debounced behind a per-project TTL cache
#                           (forge state is a poll, not a local event).
#
# No-ops when ~/.taskrc is absent OR the task binary is missing. The stale check
# additionally requires an authenticated `gh`; it is read-only and mutates no
# tasks. Opt out of the gh poll with CLAUDE_TASKWARRIOR_DRIFT_NO_RECONCILE=1.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROTO_LIB="${SCRIPT_DIR}/../../hooks-plugin/hooks/lib/drift-protocol.sh"
if [ ! -f "$PROTO_LIB" ]; then
    for candidate in \
        "${CLAUDE_PLUGIN_ROOT:-}/../hooks-plugin/hooks/lib/drift-protocol.sh" \
        "$HOME/.claude/plugins/hooks-plugin/hooks/lib/drift-protocol.sh"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            PROTO_LIB="$candidate"
            break
        fi
    done
fi
if [ ! -f "$PROTO_LIB" ]; then
    exit 0
fi
# shellcheck source=../../hooks-plugin/hooks/lib/drift-protocol.sh
# shellcheck disable=SC1091  # PROTO_LIB resolves at runtime via fallback chain
. "$PROTO_LIB"

drift_init "taskwarrior-plugin"

# No-op if user doesn't use taskwarrior.
TASKRC="${HOME}/.taskrc"
if [ ! -f "$TASKRC" ]; then
    drift_emit
    exit 0
fi
if ! command -v task >/dev/null 2>&1; then
    drift_emit
    exit 0
fi

# Single-source the required-UDA list: ask the shared ensure-udas.sh script
# (which task-add / task-claim also use) what is missing, in --check mode so it
# never mutates ~/.taskrc from a SessionStart probe.
ENSURE_UDAS="${TW_DRIFT_ENSURE_UDAS:-${SCRIPT_DIR}/../scripts/ensure-udas.sh}"
if [ -f "$ENSURE_UDAS" ]; then
    uda_report=$(bash "$ENSURE_UDAS" --check 2>/dev/null || true)
    missing_count=$(printf '%s\n' "$uda_report" | grep -m1 '^UDAS_MISSING=' | cut -d= -f2)
    missing_count="${missing_count:-0}"
    if [ "$missing_count" -gt 0 ] 2>/dev/null; then
        list=$(printf '%s\n' "$uda_report" | grep -m1 '^MISSING_NAMES=' | cut -d= -f2)
        drift_add_finding warn \
            udas_missing \
            "${missing_count} UDA(s) missing from ~/.taskrc: ${list}" \
            "/taskwarrior:task-add"
    fi
fi

# --- Drain the on-exit GitHub-sync queue -------------------------------------
# The on-exit-taskwarrior-plugin native hook (issue #1810) queues the UUIDs of
# tasks whose GitHub linkage changed. Drain it BEFORE the stale-check below so a
# busted drift cache forces the affected projects to re-poll in THIS run rather
# than waiting out the TTL. The drain does no network I/O (it only resolves
# UUIDs→projects via one batched `task export` and invalidates the matching
# cache files), so it is cheap to run every session start. Fails open.
DRAIN_SH="${TW_DRIFT_DRAIN_SCRIPT:-${SCRIPT_DIR}/../scripts/drain-ghsync-queue.sh}"
if [ "${CLAUDE_TASKWARRIOR_NO_GHSYNC_QUEUE:-0}" != "1" ] && [ -f "$DRAIN_SH" ]; then
    bash "$DRAIN_SH" >/dev/null 2>&1 || true
fi

# --- Stale linked-task drift -------------------------------------------------
# Surface tasks whose linked GitHub issue/PR has closed or merged, so the queue
# does not silently accumulate stale trackers between manual reconcile sweeps.
#
# The classification is the SAME deterministic computation /taskwarrior:task-reconcile
# uses — we call its bundled reconcile.sh in DRY-RUN mode (mutates nothing) and
# read STALE_COUNT. Forge state is not observable as a local event, so this is a
# poll; to keep SessionStart fast we debounce it behind a per-project TTL cache so
# the `gh` round-trips run at most once per interval per project.
#
# Opt out entirely with CLAUDE_TASKWARRIOR_DRIFT_NO_RECONCILE=1 (the UDA check
# above still runs). Tune the poll interval with CLAUDE_TASKWARRIOR_DRIFT_STALE_TTL
# (seconds, default 14400 = 4h) and the inspected-task cap with
# CLAUDE_TASKWARRIOR_DRIFT_STALE_LIMIT (default 50; the count is a floor when the
# queue carries more linked tasks than the cap).
stale_ttl="${CLAUDE_TASKWARRIOR_DRIFT_STALE_TTL:-14400}"
stale_limit="${CLAUDE_TASKWARRIOR_DRIFT_STALE_LIMIT:-50}"
RECONCILE_SH="${TW_DRIFT_RECONCILE_SCRIPT:-${SCRIPT_DIR}/../skills/task-reconcile/scripts/reconcile.sh}"
RESOLVE_SH="${TW_DRIFT_RESOLVE_SCRIPT:-${SCRIPT_DIR}/../scripts/resolve-project.sh}"
cache_dir="${CLAUDE_TASKWARRIOR_DRIFT_CACHE_DIR:-${TMPDIR:-/tmp}/claude-taskwarrior-drift}"

probe_dir="${DRIFT_CWD:-$PWD}"

cache_get() { # cache_get <file> <KEY>
    [ -f "$1" ] || return 0
    grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2-
}

if [ "${CLAUDE_TASKWARRIOR_DRIFT_NO_RECONCILE:-0}" != "1" ] \
    && [ "$stale_ttl" != "0" ] \
    && [ -f "$RECONCILE_SH" ] \
    && command -v gh >/dev/null 2>&1 \
    && gh auth status >/dev/null 2>&1; then

    # Resolve the current repo's project so the poll is scoped (cost + parity
    # with the rest of the plugin), matching what `/taskwarrior:task-reconcile`
    # does by default.
    proj=""
    if [ -f "$RESOLVE_SH" ]; then
        proj=$(bash "$RESOLVE_SH" --project-dir "$probe_dir" 2>/dev/null \
            | grep -m1 '^PROJECT=' | cut -d= -f2- || true)
    fi

    proj_key=$(printf '%s' "${proj:-_all}" | tr -cd 'a-zA-Z0-9_-')
    [ -n "$proj_key" ] || proj_key="_all"
    cache_file="${cache_dir}/${proj_key}.stale"

    now=$(date +%s 2>/dev/null || echo 0)
    cached_epoch=$(cache_get "$cache_file" EPOCH)
    cached_epoch="${cached_epoch:-0}"
    case "$cached_epoch" in ''|*[!0-9]*) cached_epoch=0 ;; esac

    stale=""
    if [ "$now" -gt 0 ] && [ "$cached_epoch" -gt 0 ] \
        && [ "$((now - cached_epoch))" -lt "$stale_ttl" ] 2>/dev/null; then
        # Fresh cache → reuse the cached count, no network.
        stale=$(cache_get "$cache_file" STALE)
    else
        # Stale/missing cache → claim the debounce window first (with the
        # previously-known count, so a killed poll degrades to "no change" rather
        # than re-polling every session), then run the dry-run classification.
        prev_stale=$(cache_get "$cache_file" STALE)
        prev_stale="${prev_stale:-0}"
        mkdir -p "$cache_dir" 2>/dev/null || true
        printf 'EPOCH=%s\nSTALE=%s\n' "$now" "$prev_stale" > "$cache_file" 2>/dev/null || true

        rc_out=$(bash "$RECONCILE_SH" ${proj:+--project="$proj"} \
            --project-dir "$probe_dir" --limit "$stale_limit" 2>/dev/null || true)
        gh_avail=$(printf '%s\n' "$rc_out" | grep -m1 '^GH_AVAILABLE=' | cut -d= -f2-)
        if [ "$gh_avail" = "true" ]; then
            stale=$(printf '%s\n' "$rc_out" | grep -m1 '^STALE_COUNT=' | cut -d= -f2-)
            stale="${stale:-0}"
            printf 'EPOCH=%s\nSTALE=%s\n' "$now" "$stale" > "$cache_file" 2>/dev/null || true
        else
            # Could not determine upstream state; leave the claim so we don't
            # re-poll this session, and surface nothing (never warn on uncertainty).
            stale=""
        fi
    fi

    case "$stale" in ''|*[!0-9]*) stale="" ;; esac
    if [ -n "$stale" ] && [ "$stale" -gt 0 ] 2>/dev/null; then
        scope_label="${proj:+ in project ${proj}}"
        drift_add_finding warn \
            stale_linked_tasks \
            "${stale} linked task(s)${scope_label} mirror a closed/merged GitHub issue or PR — reconcile to retire them" \
            "/taskwarrior:task-reconcile"
    fi
fi

drift_emit
exit 0
