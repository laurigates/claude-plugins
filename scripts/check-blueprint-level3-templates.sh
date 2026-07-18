#!/usr/bin/env bash
# check-blueprint-level3-templates.sh — semantic guard for the ADR-0020 level-3
# workflow templates (issue #2005).
#
# The two templates live in blueprint-plugin/templates/*.workflow.yml, OUTSIDE
# .github/workflows/, so neither `check-workflow-model.sh` (globs
# .github/workflows/*.yml) nor the `actionlint` pre-commit hook (same scope)
# lints them. This guard pins the invariants a bulk edit could silently break:
#
#   - least-privilege: a top-level `permissions:` block
#   - model/effort: every claude-code-action invocation pins `--model opus` + an
#     explicit `--effort` (.claude/rules/workflow-model-effort.md)
#   - gating: the autorun template calls the guard `--mode autorun`; the executor
#     calls it `--mode wo-execute` and triggers on the `work-order-approved` label
#   - script-injection safety: the executor binds the UNTRUSTED issue body to an
#     `env:` var (WO_ISSUE_BODY) and references it ONLY there — never interpolated
#     into a run: line (.claude/rules/github-actions-security.md)
#   - loop-integrity: an independent `verify:` job + state-packet fields
#     (.claude/rules/loop-integrity.md)
#   - actionlint validity (run if available)
#
# Output follows .claude/rules/structured-script-output.md. Exit 1 on any issue.
#
# Usage: check-blueprint-level3-templates.sh [--strict] [--project-dir DIR]

set -uo pipefail

project_dir=""
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) project_dir="${2:-}"; shift 2 ;;
        --strict)      shift ;;          # accepted for convention; always strict
        *)             shift ;;
    esac
done
if [ -z "$project_dir" ]; then
    project_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

tdir="${project_dir}/blueprint-plugin/templates"
autorun="${tdir}/blueprint-autorun.workflow.yml"
wo="${tdir}/blueprint-wo-execute.workflow.yml"

issues=()
add() { issues+=("$1"); }

require() { # require <file> <label> <fixed-string>
    grep -qF -- "$3" "$1" || add "$2: missing required token '$3'"
}

# A top-level (column-0) `permissions:` block — the least-privilege default-deny
# baseline. Anchored so an indented job-level `permissions:` does not satisfy it.
require_toplevel_permissions() { # <file> <label>
    grep -qE '^permissions:' "$1" || add "$2: missing a top-level 'permissions:' block (least-privilege baseline)"
}

# claude_args value lines must each carry --model opus AND --effort.
check_model_effort() { # check_model_effort <file> <label>
    local f="$1" label="$2" line
    local invocations=0
    while IFS= read -r line; do
        invocations=$((invocations + 1))
        printf '%s' "$line" | grep -qF -- "--model opus" || add "$label: a claude_args line lacks '--model opus'"
        printf '%s' "$line" | grep -qE -- "--effort[= ]+[a-z]+" || add "$label: a claude_args line lacks an explicit '--effort'"
    done < <(grep -E '^\s*claude_args:' "$f")
    [ "$invocations" -gt 0 ] || add "$label: no claude_args invocation found (expected claude-code-action steps)"
}

echo "=== BLUEPRINT LEVEL3 TEMPLATES ==="

for f in "$autorun" "$wo"; do
    if [ ! -f "$f" ]; then
        add "$(basename "$f"): template file is missing"
    fi
done

if [ -f "$autorun" ]; then
    require_toplevel_permissions "$autorun" "autorun"
    require "$autorun" "autorun" "schedule:"
    require "$autorun" "autorun" "workflow_dispatch"
    require "$autorun" "autorun" "blueprint-wo-guard.sh --mode autorun"
    require "$autorun" "autorun" "anthropics/claude-code-action"
    require "$autorun" "autorun" "work-order-draft"
    check_model_effort "$autorun" "autorun"
    echo "AUTORUN_TEMPLATE=present"
fi

if [ -f "$wo" ]; then
    require_toplevel_permissions "$wo" "wo-execute"
    require "$wo" "wo-execute" "work-order-approved"
    require "$wo" "wo-execute" "blueprint-wo-guard.sh --mode wo-execute"
    require "$wo" "wo-execute" "blueprint-wo-packet.sh"
    require "$wo" "wo-execute" "anthropics/claude-code-action"
    # Script-injection safety: the untrusted issue body is bound to an env var,
    # and github.event.issue.body appears ONLY on that binding line (never inlined
    # into a run: script). The ${{ }} is a deliberate LITERAL to match, not shell.
    # shellcheck disable=SC2016
    require "$wo" "wo-execute" 'WO_ISSUE_BODY: ${{ github.event.issue.body }}'
    body_refs=$(grep -cF 'github.event.issue.body' "$wo" || true)
    if [ "${body_refs:-0}" -ne 1 ]; then
        add "wo-execute: github.event.issue.body must be referenced exactly once (the env binding) — found ${body_refs} (script-injection risk if inlined into run:)"
    fi
    # Loop integrity: independent verifier job + state-packet fields.
    require "$wo" "wo-execute" "verify:"
    require "$wo" "wo-execute" "state-packet"
    grep -qiE 'independent' "$wo" || add "wo-execute: missing the 'independent' verifier language (loop-integrity Pillar 1)"
    check_model_effort "$wo" "wo-execute"
    echo "WO_EXECUTE_TEMPLATE=present"
fi

# actionlint the templates as if they were live workflows (needs a git repo).
actionlint_status="skipped"
if command -v actionlint >/dev/null 2>&1 && [ -f "$autorun" ] && [ -f "$wo" ]; then
    sandbox="$(mktemp -d)"
    if [ -n "$sandbox" ]; then
        mkdir -p "$sandbox/.github/workflows"
        cp "$autorun" "$sandbox/.github/workflows/blueprint-autorun.yml"
        cp "$wo" "$sandbox/.github/workflows/blueprint-wo-execute.yml"
        # Neutralize inherited git env so the sandbox init can't touch a real repo (#1745).
        alrc=0
        ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX
          git -C "$sandbox" init -q 2>/dev/null
          cd "$sandbox" && actionlint ) || alrc=$?
        if [ "$alrc" -eq 0 ]; then actionlint_status="pass"; else actionlint_status="fail"; add "actionlint reported errors in the templates"; fi
        rm -rf "$sandbox"
    fi
fi
echo "ACTIONLINT=$actionlint_status"

status="OK"
[ "${#issues[@]}" -gt 0 ] && status="ERROR"
echo "STATUS=$status"
echo "ISSUE_COUNT=${#issues[@]}"
if [ "${#issues[@]}" -gt 0 ]; then
    echo "ISSUES:"
    printf '  - %s\n' "${issues[@]}"
fi
echo "=== END BLUEPRINT LEVEL3 TEMPLATES ==="

[ "${#issues[@]}" -eq 0 ] || exit 1
exit 0
