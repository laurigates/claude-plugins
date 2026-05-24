#!/usr/bin/env bash
# Scrub fork-local context from the most recent commit message before
# pushing to upstream.
#
# Usage: scrub-commit.sh [--check]
#
# Without --check: opens the commit message in $EDITOR for an interactive
# amend. Pre-fills the message with a scrub checklist appended as
# stripped-comments so the human can edit while seeing the rules.
#
# With --check: reports which scrub rules the current HEAD commit message
# violates without rewriting anything. Exit 1 if any violations found.
#
# The scrub rules:
#   - Strip local issue references: "Closes #N", "Fixes #N", "Refs #N",
#     "Addresses #N" (these point at the fork's tracker, not upstream's)
#   - Strip Claude trailers: "Co-authored-by: Claude...",
#     "Generated with Claude Code", "Co-Authored-By: Claude..."
#   - Flag (but don't auto-strip) fork-specific tooling references:
#     bandit, ty, vulture, mypy custom config — these may not apply
#     upstream
#   - Keep the conventional-commit prefix (fix:, feat:, etc.)
#
# Pre-commit hooks: upstream may have no .pre-commit-config.yaml. The
# amend uses PRE_COMMIT_ALLOW_NO_CONFIG=1 to avoid the locally-installed
# pre-commit hook refusing the commit.

set -euo pipefail

mode="amend"
if [[ "${1:-}" == "--check" ]]; then
    mode="check"
fi

# --- Detect violations -----------------------------------------------------

msg=$(git log -1 --format='%B')

issue_refs=$(grep -nE '^[[:space:]]*(Closes|Fixes|Refs|Addresses)[[:space:]]*:?[[:space:]]*#[0-9]+' <<<"$msg" || true)
claude_trailers=$(grep -niE 'Claude (Code|Opus|Sonnet|Haiku)|Co-[Aa]uthored-[Bb]y:[[:space:]]*Claude|Generated with \[?Claude' <<<"$msg" || true)
fork_tooling=$(grep -niE '\b(bandit|vulture|ty)\b' <<<"$msg" || true)

indent_lines() {
    awk '{print "    "$0}' <<<"$1"
}

violations=0
[[ -n "$issue_refs" ]] && violations=$((violations + 1))
[[ -n "$claude_trailers" ]] && violations=$((violations + 1))

if [[ "$mode" == "check" ]]; then
    if [[ "$violations" -eq 0 && -z "$fork_tooling" ]]; then
        echo "OK — no scrub violations found."
        exit 0
    fi

    echo "Scrub violations found in HEAD commit message:"
    echo
    if [[ -n "$issue_refs" ]]; then
        echo "  Local issue references (point at fork tracker, strip before upstream PR):"
        indent_lines "$issue_refs"
        echo
    fi
    if [[ -n "$claude_trailers" ]]; then
        echo "  Claude trailers (upstream doesn't follow this convention):"
        indent_lines "$claude_trailers"
        echo
    fi
    if [[ -n "$fork_tooling" ]]; then
        echo "  Fork-specific tooling references (verify upstream runs these):"
        indent_lines "$fork_tooling"
        echo "    (advisory — describe the underlying problem if upstream doesn't run the tool)"
        echo
    fi
    echo "Run 'bash $(basename "$0")' (without --check) to amend interactively."
    exit 1
fi

# --- Interactive amend -----------------------------------------------------

cat <<'EOF'
==> Scrub checklist for upstream PR commit message:
    1. Strip local issue refs (Closes #N, Fixes #N, Refs #N) — they point
       at the fork's tracker, not upstream's.
    2. Strip Claude trailers (Co-authored-by: Claude..., Generated with
       Claude Code) — upstream doesn't follow that convention.
    3. Soften fork-specific tooling — if the body cites a tool upstream
       doesn't run (bandit, ty, vulture), describe the underlying
       problem instead.
    4. Keep the conventional-commit prefix (fix:, feat:, etc.).
EOF
echo

if [[ -n "$issue_refs$claude_trailers$fork_tooling" ]]; then
    echo "Detected items to consider:"
    [[ -n "$issue_refs" ]]      && { echo "  Issue refs:";        indent_lines "$issue_refs"; }
    [[ -n "$claude_trailers" ]] && { echo "  Claude trailers:";   indent_lines "$claude_trailers"; }
    [[ -n "$fork_tooling" ]]    && { echo "  Fork tooling (advisory):"; indent_lines "$fork_tooling"; }
    echo
fi

echo "Opening editor for amend..."
PRE_COMMIT_ALLOW_NO_CONFIG=1 git -c core.commentChar='|' commit --amend
