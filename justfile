# Justfile - Claude Code Plugin Collection
# Run `just` or `just help` to see available recipes

set positional-arguments

# Subdirectory modules — invoke via `just <mod>::recipe`.
mod claude-probe 'experiments/claude-probe'

# Show available recipes
default:
    @just --list

####################
# Linting
####################

# Lint SKILL.md context commands for patterns that break backtick execution
[group: "lint"]
lint-context-commands *args:
    ./scripts/lint-context-commands.sh {{args}}

# Run plugin compliance checks (validates plugin.json, frontmatter, marketplace, release-please)
[group: "lint"]
lint-compliance *args:
    ./scripts/plugin-compliance-check.sh {{args}}

# Run blueprint health check (skill inventory, staleness, frontmatter completeness)
[group: "lint"]
lint-health:
    ./scripts/blueprint-health-check.sh

# Run infrastructure compliance check (registry sync, workflow health, versions, security)
[group: "lint"]
lint-infra:
    ./scripts/infra-compliance-check.sh

# Lint taskwarrior-plugin docs for hyphenated tag names (taskwarrior parser quirk)
[group: "lint"]
lint-taskwarrior-tags:
    ./scripts/lint-taskwarrior-tags.sh

# Run all lint checks
[group: "lint"]
lint-all: lint-context-commands lint-compliance lint-health lint-infra lint-taskwarrior-tags

####################
# Testing
####################

# Run every skill-local regression test (**/skills/**/scripts/tests/test-*.sh)
[group: "test"]
test-skill-scripts:
    ./scripts/run-skill-script-tests.sh

####################
# Git Repo Agent
####################

# Install git-repo-agent as editable uv tool
[group: "git-repo-agent"]
install-agent:
    uv tool install -e ./git-repo-agent

# Compile plugin skills into subagent prompt files
[group: "git-repo-agent"]
compile-prompts:
    python git-repo-agent/scripts/compile_prompts.py

# Check if compiled prompts are up-to-date
[group: "git-repo-agent"]
check-prompts:
    python git-repo-agent/scripts/compile_prompts.py --check

####################
# GitHub
####################

# Rebase all open PRs onto their base branch
[group: "github"]
[confirm("This will rebase all open PRs. Continue?")]
pr-rebase-all:
    #!/usr/bin/env bash
    set -euo pipefail
    prs=$(gh pr list --json number,title --jq '.[].number')
    if [ -z "$prs" ]; then
        echo "No open PRs found"
        exit 0
    fi
    for pr in $prs; do
        title=$(gh pr view "$pr" --json title --jq '.title')
        printf "PR #%-5s %s ... " "$pr" "$title"
        if gh pr update-branch --rebase "$pr" 2>/dev/null; then
            echo "ok"
        else
            echo "FAILED"
        fi
    done

####################
# OpenCode export
####################

# Project skills + subagents to OpenCode format via rulesync (output: dist/opencode)
[group: "opencode"]
export-opencode *args:
    ./scripts/export-opencode.sh {{args}}
