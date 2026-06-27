#!/usr/bin/env bash
# configure-opencode.sh — generate a runnable OpenCode config for a local
# MLX-served model plus an orchestrator primary agent that fans out to the
# exported subagents.
#
# Generates two artifacts into <target>:
#   - opencode.json       (provider + model + default_agent + build-agent
#                          bash allowlist so test/status commands skip the
#                          permission prompt during fan-out)
#   - agents/orchestrator.md  (read-only primary agent that delegates via `task`)
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
set -euo pipefail

config_target="${1:?usage: configure-opencode.sh <target> [--provider P] [--model M] [--port N] [--plugins LIST]}"
shift || true

config_provider="mlx-local"
config_model="mlx-community/Qwen3.6-35B-A3B-4bit"
config_port="8080"
# Default ecosystem plugins (verified npm packages, no API key, self-host-friendly).
# See docs/opencode-export.md "Recommended ecosystem plugins".
config_plugins="@openspoon/subtask2 opencode-pty @tarquinen/opencode-dcp"

while [ $# -gt 0 ]; do
    case "$1" in
        --provider) config_provider="$2"; shift 2 ;;
        --model)    config_model="$2";    shift 2 ;;
        --port)     config_port="$2";     shift 2 ;;
        --plugins)  config_plugins="$2";  shift 2 ;;
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
  "plugin": [$config_plugins_json],
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
