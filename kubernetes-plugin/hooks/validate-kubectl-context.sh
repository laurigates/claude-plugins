#!/usr/bin/env bash
# PreToolUse hook for Bash tool - validates kubectl/helm/skaffold commands include a context
#
# This hook enforces explicit Kubernetes context selection to prevent accidental
# operations on the wrong cluster. It blocks kubectl, helm, and skaffold commands
# that perform cluster writes without specifying a context flag
# (kubectl --context, helm/skaffold --kube-context).
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

set -euo pipefail

# Read the JSON input from stdin
INPUT=$(cat)

# Extract the command from the tool input
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# If no command, allow it
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Function to output a blocking message (exit code 2 = blocking error)
block() {
    echo "$1" >&2
    exit 2
}

# Strip heredoc bodies from a command string so that kubectl/helm mentioned
# in heredoc text (e.g. PR descriptions, commit messages) does not trigger
# validation. Only shell commands outside heredoc bodies are checked.
#
# Regression: heredoc bodies containing the word "kubectl" falsely triggered
# this hook even when kubectl was not being invoked as a shell command.
strip_heredocs() {
    local in_heredoc=0
    local marker=""
    while IFS= read -r line; do
        if [ "$in_heredoc" -eq 0 ]; then
            printf '%s\n' "$line"
            # Detect heredoc start: <<, <<-, with optional quoting around marker
            if printf '%s' "$line" | grep -qF '<<'; then
                marker=$(printf '%s' "$line" | sed 's/.*<<[^A-Za-z_]*//' | grep -oE '^[A-Za-z_][A-Za-z_0-9]*')
                [ -n "$marker" ] && in_heredoc=1
            fi
        else
            # Strip leading whitespace (handles <<- indented heredocs) then check for end marker
            stripped=$(printf '%s' "$line" | sed 's/^[[:space:]]*//')
            if [ "$stripped" = "$marker" ]; then
                in_heredoc=0
            fi
            # Do not output heredoc body lines
        fi
    done
}

# Strip single- and double-quoted string contents so that kubectl/helm
# mentioned inside a grep pattern, echo argument, awk regex, etc. does
# not trigger validation. Only shell tokens outside quoted strings are
# checked.
#
# Regression: `grep -n "kubectl exec|pod-db" justfile` falsely triggered
# this hook because the substring "kubectl" inside the quoted grep
# pattern matched the kubectl-detection regex. Legitimate kubectl
# invocations like `kubectl --context="prod" get pods` are preserved
# because the `kubectl` token sits outside the quoted string.
#
# Heuristic — escaped quotes (`"\""`) inside strings are not perfectly
# handled, but the common case (grep patterns, echo/printf arguments,
# awk regexes, find -name patterns) is covered.
strip_quoted_strings() {
    sed -E -e "s/'[^']*'//g" -e 's/"[^"]*"//g'
}

# Strip heredoc bodies, then quoted string contents, before checking
# for kubectl/helm invocations.
COMMAND_CLEAN=$(printf '%s\n' "$COMMAND" | strip_heredocs | strip_quoted_strings)

# Detect whether a tool name appears as an actual command invocation in
# COMMAND_CLEAN, rather than as a bare substring inside prose. A command
# position is:
#   - the start of the command (or any line of it), or
#   - immediately after a shell command separator: ; & | (  — which also
#     covers &&, ||, and $( ), or
#   - after a run of leading command-prefix tokens: env assignments
#     (NAME=value) or sudo/time/env/command/exec/nice/nohup.
#
# Regression (issue #1544): the previous anchor allowed ANY whitespace
# (`\s`) before the tool name, so a bare mention in prose that leaked past
# heredoc/quote stripping — e.g. "a helm hook" in a `git commit -m "..."`
# message containing an escaped quote — was treated as a `helm` invocation
# and blocked. Anchoring on command position eliminates that false-positive
# while still catching env-prefixed and sudo-prefixed invocations.
is_invocation() {
    printf '%s\n' "$COMMAND_CLEAN" | grep -Eq \
        "(^|[;&|(])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|(sudo|time|env|command|exec|nice|nohup)[[:space:]]+)*$1[[:space:]]"
}

# Commands that don't require --context (read-only info commands)
# These are safe because they don't modify cluster state
SAFE_KUBECTL_SUBCOMMANDS="config|version|api-resources|api-versions|explain|completion"

# Check if this is a kubectl command
if is_invocation kubectl; then

    # Allow safe commands that don't need context
    if echo "$COMMAND_CLEAN" | grep -Eq "kubectl\s+($SAFE_KUBECTL_SUBCOMMANDS)"; then
        exit 0
    fi

    # Check if --context is specified (short form -c is not standard for kubectl)
    if ! echo "$COMMAND_CLEAN" | grep -Eq '\s--context[= ]'; then
        block "KUBECTL SAFETY: Missing --context flag.

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
if is_invocation helm; then

    # Helm commands that don't need context
    # These operate on charts, repos, or registries — never on a cluster.
    # Regression: `helm pull` (and its alias `helm fetch`) was missing, blocking
    # chart downloads from a repo.
    SAFE_HELM_SUBCOMMANDS="version|completion|env|repo|search|show|inspect|plugin|create|package|template|pull|fetch|lint|verify|dependency|registry|push"

    # Allow safe commands
    if echo "$COMMAND_CLEAN" | grep -Eq "helm\s+($SAFE_HELM_SUBCOMMANDS)"; then
        exit 0
    fi

    # Check if --kube-context is specified (helm uses --kube-context, not --context)
    if ! echo "$COMMAND_CLEAN" | grep -Eq '\s--kube-context[= ]'; then
        block "HELM SAFETY: Missing --kube-context flag.

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

# Check if this is a skaffold command
#
# skaffold performs cluster writes (deploy/delete/run/dev/debug/apply) using the
# *current* kubectl context, so it can silently mutate the wrong cluster exactly
# like kubectl/helm. Issue #1870: `skaffold deploy` deployed a dev stack into a
# production GKE cluster because the current context was prod and skaffold was
# unguarded. skaffold accepts the same `--kube-context` flag as helm.
if is_invocation skaffold; then

    # skaffold subcommands that never touch a cluster — safe without a context.
    # Everything not listed here (deploy, delete, run, dev, debug, apply, verify)
    # falls through to the --kube-context requirement, failing safe on unknown
    # subcommands.
    SAFE_SKAFFOLD_SUBCOMMANDS="build|render|diagnose|init|fix|schema|config|completion|version|filter|inspect|credits|survey|test|options|help|lsp|apiserver"

    # Allow safe commands
    if echo "$COMMAND_CLEAN" | grep -Eq "skaffold\s+($SAFE_SKAFFOLD_SUBCOMMANDS)"; then
        exit 0
    fi

    # Check if --kube-context is specified (skaffold uses --kube-context, like helm)
    if ! echo "$COMMAND_CLEAN" | grep -Eq '\s--kube-context[= ]'; then
        block "SKAFFOLD SAFETY: Missing --kube-context flag.

skaffold deploys to the CURRENT kubectl context by default, which can silently
push a dev stack into production. Always pin the context explicitly:

  skaffold --kube-context=CONTEXT_NAME deploy
  skaffold --kube-context=staging run

Alternatively, pin the context in skaffold.yaml so every run is safe:

  deploy:
    kubeContext: staging

Available contexts can be listed with:
  kubectl config get-contexts

Using an explicit --kube-context (or a pinned deploy.kubeContext) prevents
accidental deploys to production or other critical clusters."
    fi
fi

# If we get here, the command is allowed
exit 0
