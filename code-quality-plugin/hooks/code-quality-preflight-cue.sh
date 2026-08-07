#!/usr/bin/env bash
# code-quality-preflight-cue.sh — PostToolUse poka-yoke cue for structural edits.
#
# When an Edit/Write touches a file with structural signals (public-symbol lines,
# key manifests, or large payloads), this emits a once-per-session cue suggesting
# a code-quality pre-flight check. It is a behavioral cue (ADR-0017), not a gate:
# continueOnBlock:true in hooks.json means the turn continues with the reason fed
# back to the model.
#
# Mechanism: PostToolUse {"decision":"block","reason":"<cue>"} with continueOnBlock:true
# so the model sees the cue and can act on it without the turn being terminated.
#
# Two suppression layers (issue #2272):
#   1. Sequence debounce — silent while edits to the SAME file are still in
#      flight (another Edit/Write landed within CODE_QUALITY_PREFLIGHT_CUE_DEBOUNCE_TTL
#      seconds), and crucially it does not consume layer 2's budget.
#   2. Once-per-session dedup — one cue per session, to bound transcript-replay cost.
#
# What each layer actually covers, stated precisely so the next reader does not
# over-credit the debounce: the debounce is BACKWARD-looking (it can only see
# edits that already happened), so it can never suppress edit 1 of a sequence —
# which is exactly the case #2272 filed. What removes the harm there is the
# reworded cue below ("once this edit sequence is complete"), which the issue
# explicitly accepts as sufficient on its own. The debounce's job is narrower:
# make sure the session's single cue lands on a *settled* edit rather than on a
# mid-burst one, by not consuming layer 2's budget while a file is hot.
#
# Accepted true-positive loss (issue #2272 shape (1) takes this trade knowingly):
# in a session that edits ONE file repeatedly at sub-TTL intervals and never
# returns to it after a quiet period, the cue can never fire for that file — the
# recency marker is refreshed by every edit, and PostToolUse only runs when an
# edit happens, so no invocation ever observes the quiet gap.
#
# -e is intentionally omitted: a best-effort cue must never break a tool call.
set -uo pipefail

# Bypass (code-quality-plugin convention).
if [ "${CODE_QUALITY_SKIP_HOOKS:-}" = "1" ]; then
    exit 0
fi

cq_input=$(cat)

cq_tool_name=$(printf '%s' "$cq_input" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
cq_file_path=$(printf '%s' "$cq_input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
cq_new_string=$(printf '%s' "$cq_input" | jq -r '.tool_input.new_string // empty' 2>/dev/null || echo "")
cq_content=$(printf '%s' "$cq_input" | jq -r '.tool_input.content // empty' 2>/dev/null || echo "")
cq_session_id=$(printf '%s' "$cq_input" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-')

# Only Edit/Write carry structural edits.
case "$cq_tool_name" in
    Edit|Write) ;;
    *) exit 0 ;;
esac

[ -z "$cq_file_path" ] && exit 0

# --- Exclusions: silence early, before detection ---
cq_base_name="${cq_file_path##*/}"

# .md/.txt prose and diagram/binary assets — always silent.
# Diagram sources (.d2) and rendered/binary artifacts (.svg/.png/.jpg/.jpeg/.pdf)
# are not lintable by /code-quality:code-lint, so a large diagram edit should not
# trip the structural cue (issue #1730).
case "$cq_file_path" in
    *.md|*.txt|*.d2|*.svg|*.png|*.jpg|*.jpeg|*.pdf) exit 0 ;;
esac

# CHANGELOG.md explicitly (belt-and-suspenders).
[ "$cq_base_name" = "CHANGELOG.md" ] && exit 0

# Test/spec files — path segment or basename pattern.
case "$cq_file_path" in
    */test/*|*/spec/*|*/__tests__/*) exit 0 ;;
esac
case "$cq_base_name" in
    *_test.*|*.test.*|*.spec.*) exit 0 ;;
esac

# Lockfiles — always silent.
case "$cq_base_name" in
    package-lock.json|yarn.lock|pnpm-lock.yaml|bun.lockb|Cargo.lock|uv.lock|poetry.lock) exit 0 ;;
esac

# Docs/ADR/PRD paths — covered by blueprint hooks.
case "$cq_file_path" in
    docs/adrs/*|docs/prds/*|*/docs/adrs/*|*/docs/prds/*) exit 0 ;;
esac

# Session-scratchpad / harness-temp throwaways — always silent (issue #1905).
# The Claude Code harness writes one-off analysis scripts to a per-session
# scratchpad under its temp root (`/tmp/claude-<uid>/…/scratchpad/`, with the
# macOS symlink `/private/tmp/claude-<uid>/…`). These files are never committed
# to any repo, so a lint pre-flight cue on them is pure noise (following
# hook-block-vs-nudge: don't nudge where the redirect is inapplicable). Match a
# `*/scratchpad/*` path segment and the harness session-temp roots (both the
# `/tmp` and `/private/tmp` forms), plus a `$TMPDIR`-prefixed path for robustness.
case "$cq_file_path" in
    */scratchpad/*|/tmp/claude-*|/private/tmp/claude-*) exit 0 ;;
esac
if [ -n "${TMPDIR:-}" ]; then
    case "$cq_file_path" in
        "${TMPDIR%/}"/*) exit 0 ;;
    esac
fi

# --- Sequence debounce: stay silent while edits to this file are in flight ---
# (issue #2272) A PostToolUse cue on edit N of M is inherently early for N < M:
# the pre-flight lint it asks for would run against a knowingly half-applied
# refactor and produce actively-wrong findings — e.g. "`inline` is unused,
# rename to `_inline`" on a symbol whose four uses land three edits later.
# The hook cannot see the future, so it reads the past: when this same file was
# edited moments ago a sequence is in flight — stay silent AND do not consume
# the once-per-session budget below, so the one cue can still land on a later,
# settled edit. Recency is recorded for EVERY non-excluded Edit/Write, not just
# structural ones: "a sequence is in flight" is a property of the file, not of
# whether each individual edit happened to trip a signal.
# CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR is the test seam (shared with the dedup
# block below); CODE_QUALITY_PREFLIGHT_CUE_DEBOUNCE_TTL=0 disables the debounce.
#
# HOME is resolved defensively, NOT as a bare "${HOME}": under `set -u` an unset
# HOME would abort the hook with "HOME: unbound variable" and a non-zero exit —
# and because this block now runs before detection, that abort would hit EVERY
# non-excluded Edit/Write rather than only structural ones. A best-effort cue
# must never break a tool call (see the -e note in the header), so degrade to
# the temp root instead of exploding.
cq_cache_home="${HOME:-}"
if [ -z "$cq_cache_home" ]; then
    cq_cache_home="${TMPDIR:-/tmp}"
    cq_cache_home="${cq_cache_home%/}"
fi
cq_cache_dir="${CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR:-${cq_cache_home}/.cache/code-quality-preflight-cue}"
cq_debounce_ttl="${CODE_QUALITY_PREFLIGHT_CUE_DEBOUNCE_TTL:-120}"
case "$cq_debounce_ttl" in ''|*[!0-9]*) cq_debounce_ttl=120 ;; esac

# Session-scoped so two concurrent sessions editing the same path never debounce
# each other. The `.edits` subdirectory cannot collide with a session-id marker
# file: session ids are sanitised to [a-zA-Z0-9_-] above, so none can begin with
# a dot.
cq_sid_key="${cq_session_id:-nosession}"
cq_path_key=$(printf '%s' "$cq_file_path" | cksum 2>/dev/null | tr -cd '0-9')
cq_path_key="${cq_path_key:-nohash}"
cq_name_key="${cq_base_name//[^a-zA-Z0-9._-]/_}"
cq_name_key="${cq_name_key:0:100}"
cq_edit_dir="${cq_cache_dir}/.edits/${cq_sid_key}"
cq_edit_marker="${cq_edit_dir}/${cq_name_key}-${cq_path_key}"

cq_now=$(date +%s 2>/dev/null || echo 0)
case "$cq_now" in ''|*[!0-9]*) cq_now=0 ;; esac
cq_last=0
if [ -f "$cq_edit_marker" ]; then
    cq_last=$(cat "$cq_edit_marker" 2>/dev/null || echo 0)
    case "$cq_last" in ''|*[!0-9]*) cq_last=0 ;; esac
fi
mkdir -p "$cq_edit_dir" 2>/dev/null || true
# Braces + an OUTER stderr redirect: a *redirection* failure (unwritable or
# non-directory cache path) is reported by the shell itself, not by printf, so
# `printf … > f 2>/dev/null` would still leak "Not a directory" to stderr on
# every invocation. A best-effort cue must stay silent on both channels.
{ printf '%s' "$cq_now" > "$cq_edit_marker"; } 2>/dev/null || true

# --- Cache hygiene: bound the recency-marker population ---
# The pre-#2272 cache held ONE dedup marker per session. The debounce adds one
# marker per (session, file-touched) plus a directory per session, written for
# every non-excluded Edit/Write — so an unswept ~/.cache would grow without
# limit. Prune markers untouched for CODE_QUALITY_PREFLIGHT_CUE_MARKER_TTL
# minutes (default 1440 = 24h; far above any plausible debounce TTL, so a live
# sequence is never disarmed by the sweep), then drop the emptied session dirs.
# The sweep is gated on a sentinel so it costs one stat() on the hot path and
# runs at most hourly. The sentinel is refreshed BEFORE the sweep so a killed
# run degrades to "skip until the next window" rather than sweeping every
# invocation. `.last-sweep` cannot collide with a session marker: session ids
# are sanitised to [a-zA-Z0-9_-], so none can begin with a dot.
# 0 is rejected, NOT honoured: the sibling knob DEBOUNCE_TTL reads 0 as
# "disable", but here 0 means `find -mmin +0` — prune anything a minute old —
# which is the OPPOSITE, silently disarming every live 120s debounce. A reader
# who generalises "0 disables" from the debounce row would get the inverse of
# what they intended, so 0 falls back to the default like any other invalid value.
cq_marker_ttl="${CODE_QUALITY_PREFLIGHT_CUE_MARKER_TTL:-1440}"
case "$cq_marker_ttl" in ''|0|*[!0-9]*) cq_marker_ttl=1440 ;; esac
cq_sweep_sentinel="${cq_cache_dir}/.last-sweep"
if [ -z "$(find "$cq_sweep_sentinel" -mmin -60 2>/dev/null)" ]; then
    { : > "$cq_sweep_sentinel"; } 2>/dev/null || true
    find "${cq_cache_dir}/.edits" -type f -mmin "+${cq_marker_ttl}" -delete 2>/dev/null || true
    find "${cq_cache_dir}/.edits" -mindepth 1 -type d -empty -delete 2>/dev/null || true
fi

# Fail open by construction: a broken clock leaves cq_now=0, the guard is false,
# and the cue fires. A best-effort cue must never suppress on a degraded read.
if [ "$cq_debounce_ttl" -gt 0 ] && [ "$cq_now" -gt 0 ] && [ "$cq_last" -gt 0 ] \
    && [ "$((cq_now - cq_last))" -lt "$cq_debounce_ttl" ]; then
    exit 0
fi

# --- Detection: fire if ANY signal matches ---
cq_payload="${cq_new_string}
${cq_content}"
cq_is_structural=0

# Signal 1: key manifest basenames.
case "$cq_base_name" in
    plugin.json|marketplace.json|package.json|Cargo.toml|pyproject.toml) cq_is_structural=1 ;;
esac

# Signal 2: a public-symbol / export line in the edit payload.
# Shell scripts are special-cased: `export FOO=bar` is a builtin variable
# assignment, not a public-API symbol, so it must NOT count as structural —
# otherwise a small shell wrapper (e.g. a ~25-line LaunchAgent script) trips
# the cue on its env exports (issue #1766). Shell scripts still fire on
# Signal 3 (>= 50 lines), where a shellcheck pre-flight is genuinely warranted.
case "$cq_base_name" in
    *.sh|*.bash|*.zsh) cq_symbol_re='^[+-]?[[:space:]]*(pub |public |def |class |func )' ;;
    *)                 cq_symbol_re='^[+-]?[[:space:]]*(export |export default|module\.exports|pub |public |def |class |func )' ;;
esac
if [ "$cq_is_structural" -eq 0 ] && \
    printf '%s' "$cq_payload" | grep -Eq "$cq_symbol_re"; then
    cq_is_structural=1
fi

# Signal 3: large payload (>= 50 lines) — but ONLY for source types that
# /code-quality:code-lint can actually act on. code-lint auto-detects
# ruff/eslint/biome/clippy/gofmt/shellcheck (see skills/code-lint/SKILL.md); it has
# no linter for config/data/IaC files (.yaml/.yml/.json/.toml/.tf/.tfvars/.hcl, …),
# which routinely exceed 50 lines. Firing the cue there points at a skill that does
# nothing for the file just written — an alarming, non-actionable "blocking error"
# on routine multi-line config writes (issue #1825). So gate the large-payload signal
# on the lintable source extensions; Signals 1 (key manifests) and 2 (code symbols)
# still fire for the structural cases that DO warrant a pre-flight. This generalizes
# the earlier narrow per-type skips for .d2/.svg (#1730) and small shell wrappers
# (#1766) into one rule: large payload only counts when the file has a code-lint linter.
if [ "$cq_is_structural" -eq 0 ]; then
    case "$cq_base_name" in
        *.py|*.pyi|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.rs|*.go|*.sh|*.bash|*.zsh)
            cq_line_count=$(printf '%s' "$cq_payload" | wc -l)
            if [ "$cq_line_count" -ge 50 ]; then
                cq_is_structural=1
            fi
            ;;
    esac
fi

[ "$cq_is_structural" -eq 0 ] && exit 0

# --- Dedup: one cue per session ---
# cq_cache_dir (the CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR test seam) is resolved
# once in the sequence-debounce block above.
if [ -n "$cq_session_id" ]; then
    cq_marker="${cq_cache_dir}/${cq_session_id}"
    [ -f "$cq_marker" ] && exit 0
    mkdir -p "$cq_cache_dir" 2>/dev/null || true
    touch "$cq_marker" 2>/dev/null || true
fi

# The /evaluate:evaluate-skill half is only relevant when a skill file changed;
# mention it exclusively for paths under a skills/ tree so it doesn't read as a
# no-op suggestion on ordinary code edits (issue #1766). SKILL.md itself is .md
# (excluded above), so in practice this fires for non-.md files under skills/.
#
# Phrasing is timing-aware (issue #2272): a PostToolUse hook cannot tell edit 1
# of 4 from a finished edit, so it must never instruct a lint *now* — linting a
# knowingly half-applied refactor yields actively-wrong findings (an unused-symbol
# rename for a symbol whose uses land in a later edit). "once this edit sequence
# is complete" is correct for both the single-edit and mid-sequence cases.
# This rewording — not the debounce — is what covers the case #2272 actually
# filed: edit 1 of a 4-edit sequence still FIRES (a backward-looking debounce
# cannot suppress the first edit of anything); only the instruction changed,
# from "lint before continuing" to "lint once the sequence settles".
case "$cq_file_path" in
    */skills/*|skills/*) cq_cue="[code-quality] Large/structural edit detected. Run /code-quality:code-lint as a pre-flight, and /evaluate:evaluate-skill since a skill changed, once this edit sequence is complete — not mid-sequence, where a partly-applied refactor lints as broken." ;;
    *)                   cq_cue="[code-quality] Large/structural edit detected. Run /code-quality:code-lint as a pre-flight once this edit sequence is complete — not mid-sequence, where a partly-applied refactor lints as broken." ;;
esac

jq -n --arg reason "$cq_cue" '{"decision":"block","reason":$reason}'

exit 0
