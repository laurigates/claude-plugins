#!/bin/bash
# PreToolUse hook for Bash tool - validates kubectl/helm commands include --context
#
# This hook enforces explicit Kubernetes context selection to prevent accidental
# operations on the wrong cluster. It blocks kubectl and helm commands that don't
# specify a --context flag.
#
# Configuration (add to .claude/settings.json or plugin.json):
# {
#   "hooks": {
#     "PreToolUse": [
#       {
#         "matcher": "Bash",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash /path/to/validate-kubectl-context.sh",
#             "timeout": 3000
#           }
#         ]
#       }
#     ]
#   }
# }

# Read the JSON input from stdin
INPUT=$(cat)

# Extract the command from the tool input
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# If no command, allow it
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Function to output a blocking message (exit code 2 = blocking error)
block_with_reminder() {
    local message="$1"
    echo "$message" >&2
    exit 2
}

# Commands that don't require --context (read-only info commands)
# These are safe because they don't modify cluster state
SAFE_KUBECTL_SUBCOMMANDS="config|version|api-resources|api-versions|explain|completion"

# Check if this is a kubectl command
if echo "$COMMAND" | grep -Eq '(^|\s|;|&&|\|)kubectl\s+'; then

    # Allow safe commands that don't need context
    if echo "$COMMAND" | grep -Eq "kubectl\s+($SAFE_KUBECTL_SUBCOMMANDS)"; then
        exit 0
    fi

    # Check if --context is specified (short form -c is not standard for kubectl)
    if ! echo "$COMMAND" | grep -Eq '\s--context[=\s]'; then
        block_with_reminder "KUBECTL SAFETY: Missing --context flag.

Always specify the Kubernetes context explicitly to avoid operating on the wrong cluster:

  kubectl --context=CONTEXT_NAME <command>

Available contexts can be listed with:
  kubectl config get-contexts

Example with context:
  kubectl --context=production get pods
  kubectl --context=staging apply -f deployment.yaml

To set a default context for your session (not recommended for automation):
  kubectl config use-context CONTEXT_NAME

Using explicit --context prevents accidental operations on production or other critical clusters."
    fi
fi

# Check if this is a helm command
if echo "$COMMAND" | grep -Eq '(^|\s|;|&&|\|)helm\s+'; then

    # Helm commands that don't need context
    SAFE_HELM_SUBCOMMANDS="version|completion|env|repo|search|show|plugin|create|package|template"

    # Allow safe commands
    if echo "$COMMAND" | grep -Eq "helm\s+($SAFE_HELM_SUBCOMMANDS)"; then
        exit 0
    fi

    # Check if --kube-context is specified (helm uses --kube-context, not --context)
    if ! echo "$COMMAND" | grep -Eq '\s--kube-context[=\s]'; then
        block_with_reminder "HELM SAFETY: Missing --kube-context flag.

Always specify the Kubernetes context explicitly to avoid operating on the wrong cluster:

  helm --kube-context=CONTEXT_NAME <command>

Example with context:
  helm --kube-context=production list
  helm --kube-context=staging install myapp ./chart

Available contexts can be listed with:
  kubectl config get-contexts

Using explicit --kube-context prevents accidental deployments to production or other critical clusters."
    fi
fi

# If we get here, the command is allowed
exit 0
