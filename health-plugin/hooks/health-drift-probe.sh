#!/usr/bin/env bash
# health-drift-probe.sh — SessionStart probe for health-plugin drift.
#
# Detects mismatch between the user's enabled plugin set and the project's
# detected stack. Example: kubernetes-plugin enabled in a repo with no YAML
# manifests, python-plugin enabled in a repo with no Python files.
#
# Reads ~/.claude/settings.json (.enabledPlugins is a map of "plugin@source"
# -> bool). No-ops when the file is absent or has no enabled plugins.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROTO_LIB="${SCRIPT_DIR}/../../hooks-plugin/hooks/lib/drift-protocol.sh"
if [ ! -f "$PROTO_LIB" ]; then
    for candidate in \
        "${CLAUDE_PLUGIN_ROOT:-}/../hooks-plugin/hooks/lib/drift-protocol.sh" \
        "$HOME/.claude/plugins/hooks-plugin/hooks/lib/drift-protocol.sh"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            PROTO_LIB="$candidate"
            break
        fi
    done
fi
if [ ! -f "$PROTO_LIB" ]; then
    exit 0
fi
# shellcheck source=../../hooks-plugin/hooks/lib/drift-protocol.sh
# shellcheck disable=SC1091  # PROTO_LIB resolves at runtime via fallback chain
. "$PROTO_LIB"

drift_init "health-plugin"

SETTINGS="${HOME}/.claude/settings.json"
if [ ! -f "$SETTINGS" ]; then
    drift_emit
    exit 0
fi

# Enabled plugin names (strip "@source" suffix). True-only entries.
enabled=$(
    jq -r '
        (.enabledPlugins // {})
        | to_entries[]
        | select(.value == true)
        | .key
        | sub("@.*"; "")
    ' "$SETTINGS" 2>/dev/null || echo ""
)
if [ -z "$enabled" ]; then
    drift_emit
    exit 0
fi

# Stack-detection map: plugin → "true" if the stack is detected in $DRIFT_CWD.
declare -A detected_stack=()

if find "$DRIFT_CWD" -maxdepth 3 \( -name '*.py' -o -name 'pyproject.toml' -o -name 'requirements.txt' \) -print -quit 2>/dev/null | grep -q .; then
    detected_stack[python-plugin]=true
fi
if find "$DRIFT_CWD" -maxdepth 3 \( -name 'package.json' -o -name '*.ts' -o -name '*.tsx' \) -print -quit 2>/dev/null | grep -q .; then
    detected_stack[typescript-plugin]=true
fi
if find "$DRIFT_CWD" -maxdepth 3 \( -name 'Cargo.toml' -o -name '*.rs' \) -print -quit 2>/dev/null | grep -q .; then
    detected_stack[rust-plugin]=true
fi
if find "$DRIFT_CWD" -maxdepth 3 -name 'go.mod' -print -quit 2>/dev/null | grep -q .; then
    detected_stack[go-plugin]=true
fi
if find "$DRIFT_CWD" -maxdepth 4 \( -name 'Chart.yaml' -o -name 'kustomization.yaml' -o -name 'Tiltfile' -o -name 'skaffold.yaml' \) -print -quit 2>/dev/null | grep -q .; then
    detected_stack[kubernetes-plugin]=true
elif find "$DRIFT_CWD" -maxdepth 3 -path '*/k8s/*.yaml' -print -quit 2>/dev/null | grep -q .; then
    detected_stack[kubernetes-plugin]=true
fi
if find "$DRIFT_CWD" -maxdepth 3 \( -name 'Dockerfile' -o -name 'docker-compose.yml' -o -name 'compose.yaml' -o -name 'compose.yml' \) -print -quit 2>/dev/null | grep -q .; then
    detected_stack[container-plugin]=true
fi
if find "$DRIFT_CWD" -maxdepth 3 \( -name '*.tf' -o -name '*.tofu' \) -print -quit 2>/dev/null | grep -q .; then
    detected_stack[terraform-plugin]=true
fi

# Plugins we audit. Anything outside this list is left alone — many plugins
# (git, hooks, prose, ...) have no stack to detect against.
auditable_plugins=(
    python-plugin
    typescript-plugin
    rust-plugin
    go-plugin
    kubernetes-plugin
    container-plugin
    terraform-plugin
)

unused_count=0
unused_list=""
while IFS= read -r plugin; do
    [ -z "$plugin" ] && continue
    # Only flag if this plugin is in the auditable set.
    is_auditable=false
    for ap in "${auditable_plugins[@]}"; do
        if [ "$ap" = "$plugin" ]; then
            is_auditable=true
            break
        fi
    done
    [ "$is_auditable" = "true" ] || continue

    if [ -z "${detected_stack[$plugin]:-}" ]; then
        unused_count=$((unused_count + 1))
        if [ -z "$unused_list" ]; then
            unused_list="$plugin"
        else
            unused_list="${unused_list}, ${plugin}"
        fi
    fi
done <<< "$enabled"

if [ "$unused_count" -gt 0 ]; then
    drift_add_finding info \
        enabled_plugins_unused \
        "${unused_count} enabled plugin(s) with no detected stack: ${unused_list}" \
        "/health:audit"
fi

drift_emit
exit 0
