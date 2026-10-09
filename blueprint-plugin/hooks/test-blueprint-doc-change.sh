#!/usr/bin/env bash
# Regression tests for blueprint-doc-change.sh and the path handling it shares
# with auto-sync-id-registry.sh / sync-feature-tracker.sh (lib/doc-paths.sh).
#
# Pins the contract that was broken in three ways at once:
#   - hooks.json registered the handlers on `Write(docs/adrs/**)`-style
#     matchers, which are tested against the tool NAME and never fired
#   - the handlers compared an absolute `tool_input.file_path` against
#     `docs/adrs/*.md`, so they no-oped even when invoked
#   - edits made through Bash never reached a Write|Edit hook at all
#
# Cases: absolute Write/Edit paths, Bash `bashEditDiff.changedFiles` and
# `files[].filePath`, logical-vs-physical temp paths (/var vs /private/var on
# macOS), and the no-op cases (no diff, skipped diff, outside the project, no
# manifest, BLUEPRINT_SKIP_HOOKS).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/blueprint-doc-change.sh"
REGISTRY_HOOK="${SCRIPT_DIR}/auto-sync-id-registry.sh"
HOOKS_JSON="${SCRIPT_DIR}/../hooks.json"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

make_project() {
    # make_project <autonomy-level> — prints the LOGICAL path mktemp returned
    local proj
    proj=$(mktemp -d)
    if [ -z "$proj" ] || [ ! -d "$proj" ]; then
        echo "FATAL: mktemp failed" >&2
        exit 1
    fi
    mkdir -p "$proj/docs/blueprint" "$proj/docs/adrs" "$proj/docs/prds"
    cat > "$proj/docs/blueprint/manifest.json" <<EOF
{
  "format_version": "3.4.0",
  "automation": { "autonomy_level": $1 },
  "id_registry": { "last_prd": 0, "last_prp": 0, "documents": {}, "github_issues": {} },
  "task_registry": {
    "feature-tracker-sync": { "enabled": true, "auto_run": true, "schedule": "daily" }
  }
}
EOF
    printf '%s' "$proj"
}

write_adr() {
    # write_adr <proj> <number> <status>
    cat > "$1/docs/adrs/ADR-$2-probe.md" <<EOF
---
id: ADR-$2
title: Probe decision $2
status: $3
created: 2026-10-09
---

# ADR-$2: Probe decision $2
EOF
}

registered_path() {
    # registered_path <proj> <id>
    jq -r --arg id "$2" '.id_registry.documents[$id].path // "NONE"' "$1/docs/blueprint/manifest.json"
}

run_hook() {
    # run_hook <hook> <proj> <payload> [env...] — cwd and CLAUDE_PROJECT_DIR = proj
    local hook="$1" proj="$2" payload="$3"
    shift 3
    (cd "$proj" && printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$proj" "$@" bash "$hook" 2>/dev/null)
}

write_payload() { jq -nc --arg t "$1" --arg f "$2" '{tool_name: $t, tool_input: {file_path: $f}}'; }
bash_payload() { jq -nc --argjson d "$1" '{tool_name: "Bash", tool_input: {command: "true"}, tool_response: {stdout: "", bashEditDiff: $d}}'; }

# --- registration contract -------------------------------------------------

if jq -e '[.hooks.PostToolUse[] | select(.matcher == "Write|Edit|Bash")
          | .hooks[].command | select(test("blueprint-doc-change\\.sh"))] | length == 1' \
       "$HOOKS_JSON" >/dev/null 2>&1; then
    ok "hooks.json registers blueprint-doc-change.sh once on the exact matcher Write|Edit|Bash"
else
    notok "hooks.json registers blueprint-doc-change.sh once on the exact matcher Write|Edit|Bash"
fi

if jq -e '[.hooks[][] | .matcher // "" | select(test("^[A-Za-z_|, -]*\\("))] | length == 0' \
       "$HOOKS_JSON" >/dev/null 2>&1; then
    ok "hooks.json has no permission-rule syntax in a matcher (matchers see only the tool name)"
else
    notok "hooks.json has no permission-rule syntax in a matcher (matchers see only the tool name)"
fi

# --- Write / Edit ------------------------------------------------------------

proj=$(make_project 0)
write_adr "$proj" 101 Proposed
run_hook "$HOOK" "$proj" "$(write_payload Write "$proj/docs/adrs/ADR-101-probe.md")"
if [ "$(registered_path "$proj" ADR-101)" = "docs/adrs/ADR-101-probe.md" ]; then
    ok "Write with an absolute file_path registers the ADR with a project-relative path"
else
    notok "Write with an absolute file_path registers the ADR (got $(registered_path "$proj" ADR-101))"
fi

phys=$(cd "$proj" && pwd -P)
write_adr "$proj" 102 Proposed
run_hook "$HOOK" "$proj" "$(write_payload Write "$phys/docs/adrs/ADR-102-probe.md")"
if [ "$(registered_path "$proj" ADR-102)" = "docs/adrs/ADR-102-probe.md" ]; then
    ok "a physical payload path (/private/var/…) matches a logical CLAUDE_PROJECT_DIR"
else
    notok "a physical payload path matches a logical CLAUDE_PROJECT_DIR (got $(registered_path "$proj" ADR-102))"
fi

write_adr "$proj" 101 Accepted
run_hook "$HOOK" "$proj" "$(write_payload Edit "$proj/docs/adrs/ADR-101-probe.md")"
status=$(jq -r '.id_registry.documents["ADR-101"].status' "$proj/docs/blueprint/manifest.json")
if [ "$status" = "Accepted" ]; then
    ok "Edit with an absolute file_path refreshes the registered status"
else
    notok "Edit with an absolute file_path refreshes the registered status (got $status)"
fi

write_adr "$proj" 103 Proposed
run_hook "$HOOK" "$proj" "$(write_payload Write "docs/adrs/ADR-103-probe.md")"
if [ "$(registered_path "$proj" ADR-103)" = "docs/adrs/ADR-103-probe.md" ]; then
    ok "a relative file_path still registers (pre-2.1.89 payloads, direct invocation)"
else
    notok "a relative file_path still registers (got $(registered_path "$proj" ADR-103))"
fi

write_adr "$proj" 104 Proposed
run_hook "$REGISTRY_HOOK" "$proj" "$(write_payload Write "$proj/docs/adrs/ADR-104-probe.md")"
if [ "$(registered_path "$proj" ADR-104)" = "docs/adrs/ADR-104-probe.md" ]; then
    ok "auto-sync-id-registry.sh invoked directly accepts an absolute file_path"
else
    notok "auto-sync-id-registry.sh invoked directly accepts an absolute file_path (got $(registered_path "$proj" ADR-104))"
fi

# A body-only edit to a registered document must not rewrite the manifest:
# jq re-serialises the whole file, which reformats a hand-edited manifest.
python3 -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p))
open(p, "w").write(json.dumps(d, indent=4) + "\n")
' "$proj/docs/blueprint/manifest.json"
printf '\nA body paragraph.\n' >> "$proj/docs/adrs/ADR-104-probe.md"
before=$(cat "$proj/docs/blueprint/manifest.json")
run_hook "$HOOK" "$proj" "$(write_payload Edit "$proj/docs/adrs/ADR-104-probe.md")"
if [ "$(cat "$proj/docs/blueprint/manifest.json")" = "$before" ]; then
    ok "a body-only edit to a registered ADR leaves the manifest byte-identical"
else
    notok "a body-only edit to a registered ADR rewrote the manifest"
fi
rm -rf "$proj"

# --- Bash ----------------------------------------------------------------------

proj=$(make_project 0)
write_adr "$proj" 201 Proposed
run_hook "$HOOK" "$proj" "$(bash_payload "$(jq -nc --arg f "$proj/docs/adrs/ADR-201-probe.md" '{changedFiles: [$f]}')")"
if [ "$(registered_path "$proj" ADR-201)" = "docs/adrs/ADR-201-probe.md" ]; then
    ok "Bash bashEditDiff.changedFiles registers the ADR"
else
    notok "Bash bashEditDiff.changedFiles registers the ADR (got $(registered_path "$proj" ADR-201))"
fi

write_adr "$proj" 202 Proposed
run_hook "$HOOK" "$proj" "$(bash_payload "$(jq -nc --arg f "$proj/docs/adrs/ADR-202-probe.md" '{files: [{filePath: $f, hunks: []}]}')")"
if [ "$(registered_path "$proj" ADR-202)" = "docs/adrs/ADR-202-probe.md" ]; then
    ok "Bash bashEditDiff.files[].filePath registers the ADR when changedFiles is absent"
else
    notok "Bash bashEditDiff.files[].filePath registers the ADR (got $(registered_path "$proj" ADR-202))"
fi

write_adr "$proj" 203 Proposed
before=$(cat "$proj/docs/blueprint/manifest.json")
run_hook "$HOOK" "$proj" "$(jq -nc --arg f "$proj/docs/adrs/ADR-203-probe.md" '{tool_name: "Bash", tool_input: {command: ("cat " + $f)}, tool_response: {stdout: ""}}')"
run_hook "$HOOK" "$proj" "$(bash_payload "$(jq -nc --arg f "$proj/docs/adrs/ADR-203-probe.md" '{skipped: true, changedFiles: [$f]}')")"
if [ "$(cat "$proj/docs/blueprint/manifest.json")" = "$before" ]; then
    ok "Bash without a bashEditDiff, or with skipped:true, leaves the manifest untouched"
else
    notok "Bash without a bashEditDiff, or with skipped:true, leaves the manifest untouched"
fi

other=$(mktemp -d)
mkdir -p "$other/docs/adrs"
write_adr "$other" 204 Proposed
run_hook "$HOOK" "$proj" "$(bash_payload "$(jq -nc --arg f "$other/docs/adrs/ADR-204-probe.md" '{changedFiles: [$f]}')")"
if [ "$(registered_path "$proj" ADR-204)" = "NONE" ]; then
    ok "a changed file outside the project is ignored"
else
    notok "a changed file outside the project is ignored"
fi
rm -rf "$other" "$proj"

# --- gates ---------------------------------------------------------------------

proj=$(make_project 0)
write_adr "$proj" 301 Proposed
run_hook "$HOOK" "$proj" "$(write_payload Write "$proj/docs/adrs/ADR-301-probe.md")" BLUEPRINT_SKIP_HOOKS=1
if [ "$(registered_path "$proj" ADR-301)" = "NONE" ]; then
    ok "BLUEPRINT_SKIP_HOOKS=1 is a no-op"
else
    notok "BLUEPRINT_SKIP_HOOKS=1 is a no-op"
fi
rm -f "$proj/docs/blueprint/manifest.json"
run_hook "$HOOK" "$proj" "$(write_payload Write "$proj/docs/adrs/ADR-301-probe.md")"
if [ ! -e "$proj/docs/blueprint/manifest.json" ]; then
    ok "no manifest (blueprint not initialised) is a no-op and creates nothing"
else
    notok "no manifest (blueprint not initialised) is a no-op and creates nothing"
fi
rm -rf "$proj"

# --- schema nudge ----------------------------------------------------------------

if command -v uv >/dev/null 2>&1; then
    proj=$(make_project 0)
    cat > "$proj/docs/adrs/ADR-0099-valid.md" <<'EOF'
---
id: ADR-0099
created: 2026-01-01
modified: 2026-02-02
status: Accepted
deciders: team
domain: architecture
---

# ADR-0099: Title

## Context
c
## Decision
d
## Consequences
q
## Options Considered
o
## Related ADRs
r
EOF
    out=$(run_hook "$HOOK" "$proj" "$(write_payload Write "$proj/docs/adrs/ADR-0099-valid.md")")
    if [ -z "$out" ]; then
        ok "a schema-valid ADR produces no PostToolUse output"
    else
        notok "a schema-valid ADR produces no PostToolUse output (got $out)"
    fi

    write_adr "$proj" 401 Bogus
    out=$(run_hook "$HOOK" "$proj" "$(bash_payload "$(jq -nc --arg f "$proj/docs/adrs/ADR-401-probe.md" '{changedFiles: [$f]}')")")
    ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput | select(.hookEventName == "PostToolUse") | .additionalContext' 2>/dev/null)
    case "$ctx" in
        *"docs/adrs/ADR-401-probe.md"*SEVERITY=ERROR*)
            ok "a schema-invalid ADR edited through Bash returns the ERRORs as PostToolUse additionalContext" ;;
        *)
            notok "a schema-invalid ADR edited through Bash returns additionalContext (got $out)" ;;
    esac
    if [ "$(registered_path "$proj" ADR-401)" = "docs/adrs/ADR-401-probe.md" ]; then
        ok "a schema-invalid ADR is still registered (the nudge does not gate bookkeeping)"
    else
        notok "a schema-invalid ADR is still registered"
    fi
    rm -rf "$proj"
else
    printf 'SKIP - uv unavailable; schema nudge cases need check-schema.py dependencies\n'
fi

# --- feature tracker via the dispatcher ------------------------------------------

proj=$(make_project 1)
cat > "$proj/docs/blueprint/feature-tracker.json" <<'EOF'
{
  "last_updated": "2000-01-01",
  "features": { "FR1": { "name": "Probe", "status": "complete", "phase": "phase-1" } },
  "statistics": {}
}
EOF
printf '# Probe\n\nImplements FR1.\n' > "$proj/docs/prds/probe.md"
run_hook "$HOOK" "$proj" "$(bash_payload "$(jq -nc --arg f "$proj/docs/prds/probe.md" '{changedFiles: [$f]}')")" >/dev/null
updated=$(jq -r '.last_updated' "$proj/docs/blueprint/feature-tracker.json")
if [ "$updated" != "2000-01-01" ]; then
    ok "a Bash edit to a doc citing a tracked FR refreshes the feature tracker (autonomy 1)"
else
    notok "a Bash edit to a doc citing a tracked FR refreshes the feature tracker (autonomy 1)"
fi
rm -rf "$proj"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
