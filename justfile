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

# Lint all shell scripts for shell-scripting.md compliance (shebang, set flags, block())
[group: "lint"]
lint-shell *args:
    ./scripts/lint-shell-scripts.sh {{args}}

# Run all lint checks
[group: "lint"]
lint-all: lint-context-commands lint-compliance lint-health lint-infra lint-taskwarrior-tags lint-shell

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

# Defaults are overridable via environment or `just opencode_model=… <recipe>`.
opencode_config := env_var_or_default("OPENCODE_CONFIG", "~/.config/opencode")
opencode_model := env_var_or_default("OPENCODE_MODEL", "mlx-community/Qwen3.6-35B-A3B-4bit")
opencode_port := env_var_or_default("OPENCODE_PORT", "8080")
opencode_provider := "mlx-local"
# Default ecosystem plugins baked into the generated config (verified npm packages,
# no API key, self-host-friendly). Override with OPENCODE_PLUGINS or `just opencode_plugins=…`.
# Full verified menu (incl. opt-in + OCX plugins) in docs/opencode-export.md.
opencode_plugins := env_var_or_default("OPENCODE_PLUGINS", "@openspoon/subtask2 opencode-pty @tarquinen/opencode-dcp")

# Project skills + subagents to OpenCode format via rulesync (output: dist/opencode)
[group: "opencode"]
export-opencode *args:
    ./scripts/export-opencode.sh {{args}}

# Install exported agents + skills additively into an OpenCode config dir
# (default: global ~/.config/opencode; pass `.opencode` for a project install)
[group: "opencode"]
install-opencode target=opencode_config:
    ./scripts/install-opencode.sh "{{target}}"

# Generate opencode.json + agents/orchestrator.md (non-destructive to existing config)
[group: "opencode"]
configure-opencode target=opencode_config:
    ./scripts/configure-opencode.sh "{{target}}" \
        --provider "{{opencode_provider}}" \
        --model "{{opencode_model}}" \
        --port "{{opencode_port}}" \
        --plugins "{{opencode_plugins}}"

# Install + configure, then print the serve + run next steps
[group: "opencode"]
setup-opencode target=opencode_config: (install-opencode target) (configure-opencode target)
    @echo ""
    @echo "Next steps:"
    @echo "  1. Install the server:  uv tool install mlx-lm"
    @echo "  2. Serve the model:     just serve-opencode-model"
    @echo "     (or: mlx_lm.server --model {{opencode_model}} --port {{opencode_port}})"
    @echo "  3. Verify it is up:     curl -s localhost:{{opencode_port}}/v1/models"
    @echo "  4. Run OpenCode:        cd <project> && opencode   (Tab or /agents to reach orchestrator)"

# Serve the local model via mlx-lm (OpenAI-compatible /v1 on the configured port)
[group: "opencode"]
serve-opencode-model:
    mlx_lm.server --model {{opencode_model}} --port {{opencode_port}}

# Opt-in: install OCX orchestration plugins (worktree + background-agents; excludes workspace)
[group: "opencode"]
install-opencode-ocx target=opencode_config:
    ./scripts/install-opencode-ocx.sh "{{target}}"

####################
# pi (pi.dev) export
####################

# Verify pi/tiers.yaml matches the marketplace and its skill refs resolve
# (local↔CI parity: the enforcement path is the script; this is a convenience alias)
[group: "pi"]
check-pi-tiers:
    ./scripts/check-pi-tiers.sh --strict
