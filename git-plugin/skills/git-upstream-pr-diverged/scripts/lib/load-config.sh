#!/usr/bin/env bash
# shellcheck shell=bash
set -uo pipefail

# Load configuration for the upstream-pr skill.
#
# Configuration is read in this order (later overrides earlier):
#   1. Auto-detected defaults
#        - upstream_remote: "upstream"
#        - upstream_repo:   parsed from `git remote get-url <upstream_remote>`
#        - branch_prefix:   "pr-upstream/"
#   2. Frontmatter in .claude/upstream-pr.local.md (project-local)
#   3. Environment variables: UPSTREAM_REMOTE, UPSTREAM_REPO, BRANCH_PREFIX,
#                             LINTER_CMD, TEST_CMD, PR_BODY_TEMPLATE_PATH
#
# Sources expose these variables to the caller:
#   UPSTREAM_REMOTE, UPSTREAM_REPO, BRANCH_PREFIX,
#   LINTER_CMD (may be empty), TEST_CMD (may be empty),
#   PR_BODY_TEMPLATE_PATH (may be empty)
#
# Intended usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/load-config.sh"
#   load_upstream_pr_config

# shellcheck disable=SC2034  # variables are exported for callers

extract_field() {
    local file="$1" field="$2"
    [[ -f "$file" ]] || return 0
    head -50 "$file" | grep -m1 "^${field}:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r'
}

derive_repo_from_remote_url() {
    local url="$1"
    # github.com:owner/repo[.git] or https://github.com/owner/repo[.git]
    sed -E 's#.*github\.com[:/]##; s#\.git$##' <<<"$url"
}

load_upstream_pr_config() {
    local config_file=".claude/upstream-pr.local.md"

    UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-$(extract_field "$config_file" upstream_remote)}"
    UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"

    UPSTREAM_REPO="${UPSTREAM_REPO:-$(extract_field "$config_file" upstream_repo)}"
    if [[ -z "$UPSTREAM_REPO" ]]; then
        local url
        url=$(git remote get-url "$UPSTREAM_REMOTE" 2>/dev/null || true)
        if [[ -n "$url" ]]; then
            UPSTREAM_REPO=$(derive_repo_from_remote_url "$url")
        fi
    fi

    BRANCH_PREFIX="${BRANCH_PREFIX:-$(extract_field "$config_file" branch_prefix)}"
    BRANCH_PREFIX="${BRANCH_PREFIX:-pr-upstream/}"

    LINTER_CMD="${LINTER_CMD:-$(extract_field "$config_file" linter_cmd)}"
    TEST_CMD="${TEST_CMD:-$(extract_field "$config_file" test_cmd)}"
    PR_BODY_TEMPLATE_PATH="${PR_BODY_TEMPLATE_PATH:-$(extract_field "$config_file" pr_body_template_path)}"

    export UPSTREAM_REMOTE UPSTREAM_REPO BRANCH_PREFIX
    export LINTER_CMD TEST_CMD PR_BODY_TEMPLATE_PATH
}
