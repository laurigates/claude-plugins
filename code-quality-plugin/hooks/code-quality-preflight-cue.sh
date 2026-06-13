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
# Dedup is per session (one cue per session) to bound transcript-replay cost.
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

# .md and .txt files — always silent.
case "$cq_file_path" in
    *.md|*.txt) exit 0 ;;
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

# --- Detection: fire if ANY signal matches ---
cq_payload="${cq_new_string}
${cq_content}"
cq_is_structural=0

# Signal 1: key manifest basenames.
case "$cq_base_name" in
    plugin.json|marketplace.json|package.json|Cargo.toml|pyproject.toml) cq_is_structural=1 ;;
esac

# Signal 2: a public-symbol / export line in the edit payload.
if [ "$cq_is_structural" -eq 0 ] && \
    printf '%s' "$cq_payload" | grep -Eq '^[+-]?[[:space:]]*(export |export default|module\.exports|pub |public |def |class |func )'; then
    cq_is_structural=1
fi

# Signal 3: large payload (>= 50 lines).
if [ "$cq_is_structural" -eq 0 ]; then
    cq_line_count=$(printf '%s' "$cq_payload" | wc -l)
    if [ "$cq_line_count" -ge 50 ]; then
        cq_is_structural=1
    fi
fi

[ "$cq_is_structural" -eq 0 ] && exit 0

# --- Dedup: one cue per session ---
# CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR is the test seam.
cq_cache_dir="${CODE_QUALITY_PREFLIGHT_CUE_CACHE_DIR:-${HOME}/.cache/code-quality-preflight-cue}"
if [ -n "$cq_session_id" ]; then
    cq_marker="${cq_cache_dir}/${cq_session_id}"
    [ -f "$cq_marker" ] && exit 0
    mkdir -p "$cq_cache_dir" 2>/dev/null || true
    touch "$cq_marker" 2>/dev/null || true
fi

cq_cue="[code-quality] Large/structural edit detected. Run /code-quality:code-lint (and /evaluate:evaluate-skill if a skill changed) as a pre-flight before continuing."

jq -n --arg reason "$cq_cue" '{"decision":"block","reason":$reason}'

exit 0
