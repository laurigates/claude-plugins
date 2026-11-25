#!/usr/bin/env bash
# configure-opencode.sh — generate a runnable OpenCode config for a local
# MLX-served model plus an orchestrator primary agent that fans out to the
# exported subagents.
#
# Generates two artifacts into <target>:
#   - opencode.json       (provider + model + default_agent + the skill-discovery
#                          adapter + build-agent bash allowlist so test/status
#                          commands skip the permission prompt during fan-out)
#   - agents/orchestrator.md  (read-only primary agent that delegates via `task`)
#
# The adapter (ADR-0022, #2094) is how this marketplace's ~400 skills reach
# OpenCode: a `search_skills` pull tool plus ranked top-k push injection at
# ~600 standing tokens, instead of a flattened copy costing ~34,000 (measured,
# adapters/CUTOVER.md §8). It is registered as a [path, config] entry in the
# `plugin` array, paired with `"permission": { "skill": "deny" }` — the stable
# config surface that suppresses OpenCode's own uncapped <available_skills>
# listing (adapters/opencode/index.ts documents both halves).
#
# Non-destructive: if <target>/opencode.json already exists it writes
# opencode.json.opencode-sample instead and prints a merge instruction, so an
# existing hand-tuned config is never clobbered. The orchestrator agent is
# always (re)written — it is a generated artifact.
#
# Schema is validated against https://opencode.ai/docs (provider/model/agent),
# NOT the common-but-wrong shape (`providers`/`api_base`/`tools:` list). See
# docs/opencode-export.md "Gotchas".
#
# Usage: ./scripts/configure-opencode.sh <target> [--provider P] [--model M] [--port N] [--plugins "a b c"]
#                                          [--plugin NAME ...] [--no-adapter]
#   --plugins "a b c"  OpenCode ecosystem npm plugins for the `plugin` array.
#   --plugin NAME      (repeatable) a marketplace plugin the adapter indexes;
#                      written as the adapter options' "plugins" list. None
#                      means every plugin. An unknown name exits 2.
set -euo pipefail

config_script_dir="$(cd "$(dirname "$0")" && pwd)"
config_repo_root="$(cd "$config_script_dir/.." && pwd)"
# shellcheck source=/dev/null  # lib/plugin-args.sh, linted on its own
. "$config_script_dir/lib/plugin-args.sh"

config_target="${1:?usage: configure-opencode.sh <target> [--provider P] [--model M] [--port N] [--plugins LIST]}"
shift || true

config_provider="mlx-local"
config_model="mlx-community/Qwen3.6-35B-A3B-4bit"
config_port="8080"
# Default ecosystem plugins (verified npm packages, no API key, self-host-friendly).
# See docs/opencode-export.md "Recommended ecosystem plugins".
config_plugins="@openspoon/subtask2 opencode-pty @tarquinen/opencode-dcp"
config_adapter=1
config_adapter_k=5
config_skill_plugins=()

while [ $# -gt 0 ]; do
    case "$1" in
        --provider) config_provider="$2"; shift 2 ;;
        --model)    config_model="$2";    shift 2 ;;
        --port)     config_port="$2";     shift 2 ;;
        --plugins)  config_plugins="$2";  shift 2 ;;
        --plugin)
            [ "$#" -ge 2 ] || { echo "--plugin needs a plugin name" >&2; exit 2; }
            require_plugin "$config_repo_root" "$2"
            config_skill_plugins+=("$2")
            shift 2
            ;;
        --no-adapter) config_adapter=0;   shift 1 ;;
        --adapter-k)  config_adapter_k="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# Expand a leading ~ to $HOME (justfile variables are not tilde-expanded).
if [ "${config_target#\~}" != "$config_target" ]; then
    config_target="${HOME}${config_target#\~}"
fi

config_baseurl="http://127.0.0.1:${config_port}/v1"

# Build the JSON array fragment from the space-separated plugin list. Manual
# quoting is safe — plugin names are @/scope/-/alnum only, no JSON metacharacters.
config_plugins_json=""
for config_plugin in $config_plugins; do
    if [ -z "$config_plugins_json" ]; then
        config_plugins_json="\"$config_plugin\""
    else
        config_plugins_json="$config_plugins_json, \"$config_plugin\""
    fi
done

echo "=== OPENCODE CONFIGURE ==="
echo "TARGET=$config_target"
echo "PROVIDER=$config_provider"
echo "MODEL=$config_model"
echo "BASEURL=$config_baseurl"
echo "PLUGINS=$config_plugins"

# --- skill-discovery adapter -------------------------------------------------
config_adapter_entry="$config_repo_root/adapters/opencode/index.ts"
config_skill_permission=""
if [ "$config_adapter" -eq 1 ]; then
    # Marketplace plugin names are validated directory names (no JSON
    # metacharacters), so manual quoting is safe here too.
    config_adapter_opts="\"k\": $config_adapter_k, \"pins\": []"
    if [ "${#config_skill_plugins[@]}" -gt 0 ]; then
        config_skill_plugins_json=""
        for config_skill_plugin in "${config_skill_plugins[@]}"; do
            config_skill_plugins_json="${config_skill_plugins_json:+$config_skill_plugins_json, }\"$config_skill_plugin\""
        done
        config_adapter_opts="$config_adapter_opts, \"plugins\": [$config_skill_plugins_json]"
    fi
    config_adapter_tuple="[\"$config_adapter_entry\", { $config_adapter_opts }]"
    if [ -z "$config_plugins_json" ]; then
        config_plugins_json="$config_adapter_tuple"
    else
        config_plugins_json="$config_plugins_json, $config_adapter_tuple"
    fi
    # Suppresses OpenCode's own uncapped <available_skills> block AND the native
    # `skill` tool, so the adapter is the single skill surface. Note this also
    # hides any personal ~/.claude/skills — pass --no-adapter to keep them.
    config_skill_permission='
  "permission": { "skill": "deny" },'
    echo "ADAPTER=$config_adapter_entry"
    echo "ADAPTER_K=$config_adapter_k"
    echo "ADAPTER_PLUGINS=${config_skill_plugins[*]:-all}"
    if [ -d "$config_repo_root/adapters/node_modules" ]; then
        echo "ADAPTER_NODE_MODULES=present"
    else
        echo "ADAPTER_NODE_MODULES=MISSING (cd adapters && bun install)"
    fi
else
    echo "ADAPTER=disabled (--no-adapter)"
fi

mkdir -p "$config_target/agents"

# --- opencode.json (non-destructive) -----------------------------------------
config_json="$config_target/opencode.json"
if [ -e "$config_json" ]; then
    config_json="$config_target/opencode.json.opencode-sample"
    echo "CONFIG_EXISTS=true"
else
    echo "CONFIG_EXISTS=false"
fi

# Unquoted heredoc so $config_* expand; \$schema stays a literal JSON key.
cat > "$config_json" <<JSON
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "$config_provider": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local MLX",
      "options": { "baseURL": "$config_baseurl" },
      "models": { "$config_model": { "name": "$config_model" } }
    }
  },
  "plugin": [$config_plugins_json],$config_skill_permission
  "model": "$config_provider/$config_model",
  "default_agent": "orchestrator",
  "lsp": true,
  "agent": {
    "build": {
      "permission": {
        "bash": {
          "go test *": "allow",
          "npm test": "allow",
          "npm run test*": "allow",
          "bun test*": "allow",
          "pytest*": "allow",
          "cargo test*": "allow",
          "just test*": "allow",
          "git status*": "allow",
          "git diff*": "allow",
          "git log*": "allow",
          "*": "ask"
        }
      }
    }
  }
}
JSON
echo "CONFIG_WRITTEN=$config_json"
if [ "$config_json" != "$config_target/opencode.json" ]; then
    echo "MERGE_HINT=existing opencode.json kept; merge provider/model/default_agent and APPEND the plugin entries to your existing plugin array (do not replace it) from the .opencode-sample"
fi

# --- agents/orchestrator.md (generated artifact, always rewritten) -----------
config_agent="$config_target/agents/orchestrator.md"
cat > "$config_agent" <<MD
---
description: Central router that decomposes a request and delegates to specialized subagents concurrently.
mode: primary
model: $config_provider/$config_model
temperature: 0.1
permission:
  edit: deny
  bash: deny
  webfetch: deny
  write: deny
---

# The Orchestrator

You analyze the request, inspect project topology read-only (read/glob/grep/list),
and dispatch specialized subagents via the \`task\` tool — issuing multiple \`task\`
calls in one turn for independent work. You never edit files or run bash directly.

Workflow:

1. Decompose the request into independent units of work.
2. For each unit, pick the most specialized exported subagent (see \`agents/\`).
3. Issue the \`task\` calls — parallel ones in a single turn when the work is independent.
4. Gather the subagents' results and synthesize a single answer.
MD
echo "AGENT_WRITTEN=$config_agent"

echo "STATUS=OK"
echo "ISSUE_COUNT=0"
echo "=== END OPENCODE CONFIGURE ==="
