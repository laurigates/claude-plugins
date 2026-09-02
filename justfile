# Justfile - Claude Code Plugin Collection
# Run `just` or `just help` to see available recipes

set positional-arguments

# Subdirectory modules — invoke via `just <mod>::recipe`.
mod claude-probe 'experiments/claude-probe'
mod skill-catalog-routing 'experiments/skill-catalog-routing'

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

# Channel M scan for the six context-engineering shifts (C1-C6); --strict gates the always-loaded ratchet
[group: "lint"]
lint-context-engineering *args:
    ./scripts/check-context-engineering.py {{args}}

# Lint all shell scripts for shell-scripting.md compliance (shebang, set flags, block())
[group: "lint"]
lint-shell *args:
    ./scripts/lint-shell-scripts.sh {{args}}

# Deliberately NOT in lint-all: it needs the pack repos checked out locally
# (~/repos/laurigates/comfyui-nodes), so on any other machine — and in CI — it
# would report a clean no-op and make lint-all look greener than it is. The
# scheduled sweep is .github/workflows/fleet-drift-audit.yml.
# Report drift between the ComfyUI pack fleet and the scaffold template
[group: "lint"]
lint-fleet-drift *args:
    ./comfyui-plugin/skills/comfyui-node-scaffold/scripts/check-fleet-drift.py {{args}}

# Run all lint checks
[group: "lint"]
lint-all: lint-context-commands lint-compliance lint-health lint-infra lint-taskwarrior-tags lint-shell lint-context-engineering

####################
# Config drift
####################

# The EXPENSIVE tier of config-drift: semantic overlap + promotion candidates.
#
# Deliberately NOT in lint-all and NOT reachable from the SessionStart probe.
# It runs the analyzer through `uv run --script` because the PEP-723 block at
# the top of config-drift.py declares fastembed + numpy, and neither is
# installed for the bare `python3` the probe hook and the test suite invoke —
# so this is the only supported way to reach the embedding pass. First run
# downloads the BAAI/bge-small-en-v1.5 model; later runs read
# ~/.cache/config-drift/embeddings.json, which is content-keyed and warm.
#
# It existed only as a command line in a PR body before this recipe.
#
# Exits 1 whenever any warn-severity finding exists, which on a real corpus is
# the normal state (review_staleness alone accounts for ~67). That is the
# analyzer's standing contract, not a fault in this recipe — read the report,
# and use `--gate` (exit 2 on error only) for a CI gate.
# Semantic-tier config drift: embedding overlap and promotion candidates
[group: "lint"]
config-drift-semantic *args:
    uv run --script ./health-plugin/scripts/config-drift.py --format=report {{args}}

# Re-derive the T_PROMOTE distribution over a corpus (dev-only; see the
# constant's comment for the numbers this produced on 2026-08-29). Point --root
# at a wider tree to calibrate against it: `just config-drift-calibrate --root ~/repos`
# Measure the promotion-band distribution used to set T_PROMOTE
[group: "lint"]
config-drift-calibrate *args:
    uv run --script ./health-plugin/scripts/config-drift.py --calibrate {{args}}

####################
# Testing
####################

# Run every skill-local regression test (**/skills/**/scripts/tests/test-*.sh)
[group: "test"]
test-skill-scripts:
    ./scripts/run-skill-script-tests.sh

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
# Adapters (skill-discovery core — ADR-0022)
####################

# Run the adapters test suite (bun test; includes the eval meta-tests)
[group: "adapters"]
adapters-test:
    cd adapters && bun test

# Type-check + lint the adapters package (local↔CI parity with test-adapters.yml)
[group: "adapters"]
adapters-check:
    cd adapters && bunx tsc --noEmit && bunx biome ci .

# Run the retrieval eval (BM25-only smoke; structured === SECTION === output)
[group: "adapters"]
eval-adapter *args:
    cd adapters && bun eval/run-eval.ts {{args}}

# Run the retrieval eval with hybrid fusion (needs a reachable ollama /api/embed)
[group: "adapters"]
eval-adapter-hybrid:
    cd adapters && bun eval/run-eval.ts --with-embeddings

# node_modules populated + ollama reachable with nomic-embed-text = hybrid ranker;
# a missing embed model still works but degrades to BM25-only (worse ranking).
# Verify the pi adapter's prerequisites (deterministic, no model call, no cost)
[group: "adapters"]
pi-adapter-check:
    #!/usr/bin/env bash
    set -euo pipefail
    ext="{{justfile_directory()}}/adapters/pi/index.ts"
    echo "=== PI ADAPTER PREREQS ==="
    command -v pi >/dev/null && echo "PI=$(pi --version 2>&1 | head -1)" || echo "PI=MISSING (bun install -g @earendil-works/pi)"
    [ -f "$ext" ] && echo "EXTENSION=$ext" || echo "EXTENSION=MISSING"
    [ -d "{{justfile_directory()}}/adapters/node_modules" ] && echo "NODE_MODULES=present" || echo "NODE_MODULES=MISSING (cd adapters && bun install)"
    endpoint="${OLLAMA_ENDPOINT:-http://localhost:11434}"
    if models="$(curl -s --max-time 3 "$endpoint/api/tags" 2>/dev/null)"; then
        if grep -q '"name":"nomic-embed-text' <<<"$models"; then
            echo "EMBED_MODEL=nomic-embed-text (hybrid ranker available)"
        else
            echo "EMBED_MODEL=MISSING — ranker degrades to BM25-only (ollama pull nomic-embed-text)"
        fi
    else
        echo "OLLAMA=unreachable at $endpoint — ranker degrades to BM25-only"
    fi

# Launches pi with the ADR-0022 skill-discovery extension via --extension,
# replacing the uncapped native <available_skills> listing with pins + ranked
# top-k. Pass args through, e.g. `just pi-adapter -p "find a git-commit skill"`.
# Make it permanent with `just pi-adapter-register`.
# Trial the pi adapter with ZERO config changes (interactive unless -p is passed)
[group: "adapters"]
pi-adapter *args:
    pi -e "{{justfile_directory()}}/adapters/pi/index.ts" {{args}}

# Persist the adapter into pi's `extensions` array (global ~/.pi/agent/settings.json
# by default; override target with PI_SETTINGS=<path>, e.g. a project .pi/settings.json).
# Idempotent and non-clobbering: appends only the one path, preserves every other
# key, creates the file if absent, writes mode 600. NB pi loads local extensions
# from `extensions`, NOT the `packages` array `pi install`/`pi list` manage — so
# `pi list` will not show it; that is expected, not a failure.
# Register the pi adapter permanently (edits pi's settings.json, reversible)
[group: "adapters"]
pi-adapter-register:
    #!/usr/bin/env bash
    set -euo pipefail
    ext="{{justfile_directory()}}/adapters/pi/index.ts"
    settings="${PI_SETTINGS:-$HOME/.pi/agent/settings.json}"
    mkdir -p "$(dirname "$settings")"
    [ -f "$settings" ] || echo '{}' > "$settings"
    if jq -e --arg ext "$ext" '(.extensions // []) | index($ext) != null' "$settings" >/dev/null; then
        echo "already registered in $settings:"
        echo "  $ext"
        exit 0
    fi
    tmp="$(mktemp "$(dirname "$settings")/settings.XXXXXX")"
    jq --arg ext "$ext" '.extensions = ((.extensions // []) + [$ext])' "$settings" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$settings"
    echo "registered in $settings:"
    echo "  $ext"
    echo "Run any pi session (no -e needed) to use it; undo with \`just pi-adapter-unregister\`."

# Remove the adapter from pi's `extensions` array (mirror of pi-adapter-register;
# same PI_SETTINGS override). No-op if it was never registered.
# Unregister the pi adapter (reverses pi-adapter-register)
[group: "adapters"]
pi-adapter-unregister:
    #!/usr/bin/env bash
    set -euo pipefail
    ext="{{justfile_directory()}}/adapters/pi/index.ts"
    settings="${PI_SETTINGS:-$HOME/.pi/agent/settings.json}"
    if [ ! -f "$settings" ] || ! jq -e --arg ext "$ext" '(.extensions // []) | index($ext) != null' "$settings" >/dev/null; then
        echo "not registered in ${settings} — nothing to do"
        exit 0
    fi
    tmp="$(mktemp "$(dirname "$settings")/settings.XXXXXX")"
    jq --arg ext "$ext" '.extensions = ((.extensions // []) | map(select(. != $ext)))' "$settings" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$settings"
    echo "unregistered from $settings:"
    echo "  $ext"

####################
# OpenCode (adapter + agents/hooks export)
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

# Skills are NOT exported — they reach OpenCode via the adapter (ADR-0022, #2094).
# Project subagents + hooks to OpenCode format (output: dist/opencode)
[group: "opencode"]
export-opencode *args:
    ./scripts/export-opencode.sh {{args}}

# Additive: the user's own agents/plugins under <target> are preserved.
# Install exported agents + hook plugins into an OpenCode config dir (default: global)
[group: "opencode"]
install-opencode target=opencode_config:
    ./scripts/install-opencode.sh "{{target}}"

# Non-destructive: an existing opencode.json is kept and a .opencode-sample written.
# Generate opencode.json (provider + skill adapter) + agents/orchestrator.md
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

# Verify the OpenCode adapter's prerequisites (deterministic, no model call, no cost)
[group: "adapters"]
oc-adapter-check target=opencode_config:
    #!/usr/bin/env bash
    set -euo pipefail
    ext="{{justfile_directory()}}/adapters/opencode/index.ts"
    target="{{target}}"
    target="${target/#\~/$HOME}"
    echo "=== OPENCODE ADAPTER PREREQS ==="
    command -v opencode >/dev/null && echo "OPENCODE=$(opencode --version 2>&1 | head -1)" || echo "OPENCODE=MISSING (mise use -g npm:opencode-ai)"
    [ -f "$ext" ] && echo "PLUGIN=$ext" || echo "PLUGIN=MISSING"
    [ -d "{{justfile_directory()}}/adapters/node_modules" ] && echo "NODE_MODULES=present" || echo "NODE_MODULES=MISSING (cd adapters && bun install)"
    cfg="$target/opencode.json"
    if [ -f "$cfg" ]; then
        jq -e --arg ext "$ext" '[.plugin // [] | .[] | select(type == "array") | .[0]] | index($ext) != null' "$cfg" >/dev/null \
            && echo "REGISTERED=true" || echo "REGISTERED=false (just oc-adapter-register)"
        # Without this the native uncapped <available_skills> block is still
        # injected and the model sees two competing skill surfaces.
        [ "$(jq -r '.permission.skill // "unset"' "$cfg")" = "deny" ] \
            && echo "NATIVE_LISTING=suppressed" || echo "NATIVE_LISTING=ACTIVE (needs permission.skill=deny)"
    else
        echo "CONFIG=MISSING ($cfg — just configure-opencode)"
    fi
    endpoint="${OLLAMA_ENDPOINT:-http://localhost:11434}"
    if models="$(curl -s --max-time 3 "$endpoint/api/tags" 2>/dev/null)"; then
        if grep -q '"name":"nomic-embed-text' <<<"$models"; then
            echo "EMBED_MODEL=nomic-embed-text (hybrid ranker available)"
        else
            echo "EMBED_MODEL=MISSING — ranker degrades to BM25-only (ollama pull nomic-embed-text)"
        fi
    else
        echo "OLLAMA=unreachable at $endpoint — ranker degrades to BM25-only"
    fi

# `just configure-opencode` already wires the adapter into a config it generates;
# this is the path for a hand-tuned config the generator refuses to clobber.
# Register the OpenCode adapter into an existing opencode.json (idempotent, reversible)
[group: "adapters"]
oc-adapter-register target=opencode_config:
    #!/usr/bin/env bash
    set -euo pipefail
    ext="{{justfile_directory()}}/adapters/opencode/index.ts"
    target="{{target}}"
    target="${target/#\~/$HOME}"
    cfg="$target/opencode.json"
    mkdir -p "$target"
    [ -f "$cfg" ] || echo '{}' > "$cfg"
    if jq -e --arg ext "$ext" '[.plugin // [] | .[] | select(type == "array") | .[0]] | index($ext) != null' "$cfg" >/dev/null; then
        echo "already registered in $cfg:"
        echo "  $ext"
        exit 0
    fi
    tmp="$(mktemp "$target/opencode.XXXXXX")"
    # Both halves land together: the plugin entry serves skills, the deny stops
    # OpenCode also injecting its own uncapped listing beside it.
    jq --arg ext "$ext" \
        '.plugin = ((.plugin // []) + [[$ext, {k: 5, pins: []}]]) | .permission = ((.permission // {}) + {skill: "deny"})' \
        "$cfg" > "$tmp"
    mv "$tmp" "$cfg"
    echo "registered in $cfg:"
    echo "  $ext"
    echo "Undo with \`just oc-adapter-unregister\`."

# No-op if it was never registered.
# Unregister the OpenCode adapter (reverses oc-adapter-register)
[group: "adapters"]
oc-adapter-unregister target=opencode_config:
    #!/usr/bin/env bash
    set -euo pipefail
    ext="{{justfile_directory()}}/adapters/opencode/index.ts"
    target="{{target}}"
    target="${target/#\~/$HOME}"
    cfg="$target/opencode.json"
    if [ ! -f "$cfg" ] || ! jq -e --arg ext "$ext" '[.plugin // [] | .[] | select(type == "array") | .[0]] | index($ext) != null' "$cfg" >/dev/null; then
        echo "not registered in ${cfg} — nothing to do"
        exit 0
    fi
    tmp="$(mktemp "$target/opencode.XXXXXX")"
    # Drop the deny too, or the model is left with no skill surface at all.
    jq --arg ext "$ext" \
        '.plugin = ((.plugin // []) | map(select((type == "array" and .[0] == $ext) | not))) | del(.permission.skill)' \
        "$cfg" > "$tmp"
    mv "$tmp" "$cfg"
    echo "unregistered from $cfg:"
    echo "  $ext"

####################
# pi (pi.dev) export
####################

# Local-model defaults (overridable via environment or `just pi_model=… <recipe>`).
pi_model := env_var_or_default("PI_MODEL", "mlx-community/Qwen3.6-35B-A3B-4bit")
pi_port := env_var_or_default("PI_PORT", "8080")

# Serve the local model via mlx-lm (OpenAI-compatible /v1 on the configured port)
[group: "pi"]
serve-pi-model:
    mlx_lm.server --model {{pi_model}} --port {{pi_port}}

# Registers the ADR-0022 skill-discovery adapter (prereq-checked first), then
# prints the local-provider models.json block + run next steps. Skill discovery
# is the adapter's job — the tier installer it replaced was removed in #2093.
# Wire pi up end to end: register the adapter, then print the model next steps
[group: "pi"]
setup-pi: pi-adapter-check pi-adapter-register
    @echo ""
    @echo "Next steps:"
    @echo "  1. Install the server:  uv tool install mlx-lm"
    @echo "  2. Serve the model:     just serve-pi-model"
    @echo "     (or: mlx_lm.server --model {{pi_model}} --port {{pi_port}})"
    @echo "  3. Add a local provider to ~/.pi/agent/models.json:"
    @echo '     {"providers":{"mlx-local":{"baseUrl":"http://localhost:{{pi_port}}/v1","api":"openai-completions","apiKey":"mlx","compat":{"supportsDeveloperRole":false,"supportsReasoningEffort":false},"models":[{"id":"{{pi_model}}","name":"{{pi_model}} (local)","contextWindow":128000,"maxTokens":32000,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0}}]}}}'
    @echo "     (full block + rationale: docs/pi-export.md)"
    @echo "  4. Run pi:              cd <project> && pi --model mlx-local/{{pi_model}}"
    @echo "     (the adapter is registered, so no -e flag is needed)"
    @echo "  5. Undo the wiring:     just pi-adapter-unregister"
