#!/usr/bin/env bash
# blueprint-structural-cue.sh — PostToolUse cue for architecture-affecting edits.
#
# When an Edit/Write touches a plugin/marketplace manifest or adds a public-API
# (export) line, this emits a one-line, once-per-session cue suggesting a
# blueprint check. It is a behavioral cue (ADR-0017), not a gate: the edit has
# already happened, and it degrades to silence on any error.
#
# Mechanism: PostToolUse {"decision":"block","reason":"<cue>"} with
# continueOnBlock:true in hooks.json, so the model sees the cue and the turn
# continues - the same channel code-quality-preflight-cue.sh uses for this event.
#
# Why not hookSpecificOutput.updatedToolOutput (the pre-#2275 mechanism): that
# field is validated against the TOOL'S OWN output shape. Write/Edit's shape is
# {content, filePath, originalFile, structuredPatch, type, userModified} - it has
# no free-text field, and `content` is the file's actual content, so appending a
# cue banner there would make the model believe the banner was written to disk.
# Emitting a string instead was rejected outright ("expected object, received
# string") and silently discarded, making this hook a no-op. The block channel
# is the only correct carrier for a cue on this event.
#
# Dedup is per session (one cue per session) to bound transcript-replay cost.
#
# -e is intentionally omitted: a best-effort cue must never break a tool call.
set -uo pipefail

# Bypass (shared blueprint-plugin convention).
if [ "${BLUEPRINT_SKIP_HOOKS:-}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)

tool_name=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
file_path=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
new_string=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null || echo "")
content=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || echo "")
session_id=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-')

# Only Edit/Write carry structural edits.
case "$tool_name" in
    Edit|Write) ;;
    *) exit 0 ;;
esac

[ -z "$file_path" ] && exit 0

# Session scratchpad (#2336): the harness's per-session scratch tree lives under
# a temp-rooted claude-<uid>/… directory and belongs to no repo, so
# /blueprint:derive-plans can never be actionable for a file written there. Same
# carve-out family as bash-antipatterns' scratch-path exemptions (#1592, #2052).
# Deliberately narrow: plain /tmp/foo.ts still gets the cue — only the harness's
# own scratchpad tree is inert.
case "$file_path" in
    /tmp/claude-*/*|/private/tmp/claude-*/*|/var/folders/*/claude-*/*) exit 0 ;;
esac

# --- Detection (ADR-0017: start narrow, widen on evidence) ---
base_name="${file_path##*/}"
file_ext="${file_path##*.}"
payload="${new_string}
${content}"
is_structural=0

# File-type guard for the CODE-shaped signals (2-6) — issue #2336.
#
# Signals 2-6 grep source-code patterns out of the edit payload. Applied to any
# file they fire on prose: an English sentence containing "export " (observed in
# a Markdown table cell: "…before the export can be called correct") tripped the
# public-API cue, and `^[+[:space:]]*pub ` matches a list item starting with the
# word "pub". file_ext was computed here and never referenced — the guard this
# restores is the one that went missing when detection widened in #1616.
#
# Signals 1 and 7 (manifests, .proto/.graphql/.prisma, openapi.*) stay
# extension-free: they identify themselves by path or basename already.
is_code_file=0
case "$file_ext" in
    js|jsx|mjs|cjs|ts|tsx|mts|cts|rs|py|pyi|go) is_code_file=1 ;;
esac

# Signal 1: plugin/marketplace manifest.
case "$file_path" in
    *.claude-plugin/marketplace.json) is_structural=1 ;;
esac
if [ "$base_name" = "plugin.json" ]; then
    is_structural=1
fi

# Signal 2: a public-API / export line in the edit payload (JS/TS/Rust/Python).
if [ "$is_code_file" -eq 1 ] && [ "$is_structural" -eq 0 ] && \
    printf '%s' "$payload" | grep -Eq '(export |export default|module\.exports|^[+[:space:]]*pub |def __all__)'; then
    is_structural=1
fi

# Signal 3: TypeScript exported interface or type declaration.
if [ "$is_code_file" -eq 1 ] && [ "$is_structural" -eq 0 ] && \
    printf '%s' "$payload" | grep -Eq 'export (interface|type) [A-Z]'; then
    is_structural=1
fi

# Signal 4: Go exported struct / interface declaration.
if [ "$is_code_file" -eq 1 ] && [ "$is_structural" -eq 0 ] && \
    printf '%s' "$payload" | grep -Eq 'type [A-Z][A-Za-z0-9_]* (struct|interface) \{'; then
    is_structural=1
fi

# Signal 5: Rust public struct / enum / trait declaration.
if [ "$is_code_file" -eq 1 ] && [ "$is_structural" -eq 0 ] && \
    printf '%s' "$payload" | grep -Eq '^[+[:space:]]*(pub|pub\(crate\)) (struct|enum|trait) [A-Z]'; then
    is_structural=1
fi

# Signal 6: route / handler registration (web framework public API).
if [ "$is_code_file" -eq 1 ] && [ "$is_structural" -eq 0 ] && \
    printf '%s' "$payload" | grep -Eq '(app\.(get|post|put|patch|delete|use)\(|router\.(get|post|put|patch|delete|use)\(|@app\.route\(|addRoute\()'; then
    is_structural=1
fi

# Signal 7: schema / IDL file by extension or well-known basename.
case "$file_path" in
    *.proto|*.graphql|*.gql|schema.prisma|*/schema.prisma) is_structural=1 ;;
esac
case "$base_name" in
    openapi.yaml|openapi.yml|openapi.json|swagger.yaml|swagger.yml|swagger.json) is_structural=1 ;;
esac
# openapi-*.yaml / openapi-*.yml patterns
case "$base_name" in
    openapi-*.yaml|openapi-*.yml) is_structural=1 ;;
esac

# Deliberately exclude docs/adrs|prds — validate-*-frontmatter.sh +
# auto-sync-id-registry.sh already cover those; a cue there is redundant.
case "$file_path" in
    docs/adrs/*|docs/prds/*|*/docs/adrs/*|*/docs/prds/*) is_structural=0 ;;
esac

[ "$is_structural" -eq 0 ] && exit 0

# --- Dedup: one cue per session ---
# BLUEPRINT_STRUCTURAL_CUE_CACHE_DIR is the test seam.
cache_dir="${BLUEPRINT_STRUCTURAL_CUE_CACHE_DIR:-${HOME}/.cache/blueprint-structural-cue}"
if [ -n "$session_id" ]; then
    marker="${cache_dir}/${session_id}"
    [ -f "$marker" ] && exit 0
    mkdir -p "$cache_dir" 2>/dev/null || true
    touch "$marker" 2>/dev/null || true
fi

cue="Structural change detected (manifest / public API). Consider /blueprint:derive-plans or /blueprint:adr-validate to keep PRDs/ADRs current."

# Block-with-reason channel (see the header): hooks.json sets continueOnBlock so
# the turn continues with the reason fed back to the model. Deliberately does NOT
# echo tool_response back - the Write/Edit response carries the file's content,
# and re-emitting it here would both bloat the transcript and risk the model
# reading hook text as file text.
jq -n --arg reason "[blueprint] ${cue}" '{"decision":"block","reason":$reason}'

exit 0
