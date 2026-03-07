#!/usr/bin/env bash
# ShellSpec spec_helper for blueprint-plugin hooks

# Set project root for fixture paths
export SHELLSPEC_PROJECT_ROOT="${SHELLSPEC_PROJECT_ROOT:-$(dirname "$(dirname "$(realpath "$0")")")}"

# Default timeout for hook tests (5 seconds)
# shellcheck disable=SC2034  # Used by ShellSpec framework
export SHELLSPEC_DEFAULT_TIMEOUT=5

# Ensure jq is available
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required for hook tests" >&2
  exit 1
fi
