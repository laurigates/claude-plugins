#!/usr/bin/env bash
# PreToolUse hook for Bash tool - gates terraform apply behind terraform plan
#
# Blocks 'terraform apply' to enforce a plan-first workflow: review planned
# infrastructure changes before committing them. This prevents unintended
# resource creation, modification, or destruction.
#
# Plan-first workflow:
#   terraform plan -out=tfplan     # generate and save plan
#   terraform show tfplan          # inspect planned changes
#   terraform apply tfplan         # apply the reviewed plan
#
# The -auto-approve variant is blocked more strictly as it bypasses the
# interactive confirmation prompt entirely.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then exit 0; fi

block() {
    echo "$1" >&2
    exit 2
}

# Only intercept terraform apply
if ! echo "$COMMAND" | grep -qE '(^|\s)terraform\s+apply(\s|$)'; then
    exit 0
fi

# -auto-approve skips interactive confirmation — highest risk variant
if echo "$COMMAND" | grep -q '\-auto-approve'; then
    block "TERRAFORM SAFETY: 'terraform apply -auto-approve' is blocked.

-auto-approve bypasses the interactive change confirmation. Always review planned
changes before applying them:

  terraform plan -out=tfplan     # generate and save the execution plan
  terraform show tfplan          # inspect every planned change
  terraform apply tfplan         # apply after reviewing — still prompts for confirmation

To skip the confirmation prompt after reviewing: terraform apply -auto-approve tfplan"
fi

# Standard terraform apply — gate behind plan review
block "TERRAFORM SAFETY: Run 'terraform plan' before 'terraform apply'.

Review planned infrastructure changes first to prevent unintended modifications:

  terraform plan -out=tfplan     # generate and save the execution plan
  terraform show tfplan          # inspect every planned change
  terraform apply tfplan         # apply the reviewed plan

Once you have reviewed the plan output and are ready to apply, rerun the apply
command referencing the saved plan file."
