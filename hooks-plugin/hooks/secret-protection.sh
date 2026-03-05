#!/usr/bin/env bash
# PreToolUse hook — blocks access to sensitive files and credential exposure
#
# Toggle: set CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 to skip this hook
#
# Matches: Read, Edit, Write, Bash
# Detects: .env files, SSH keys, cloud credentials, private keys, token files

# Toggle off
[ "${CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION:-}" = "1" ] && exit 0

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

block() {
  echo "$1" >&2
  exit 2
}

# Sensitive file patterns (applied to Read, Edit, Write file_path and Bash arguments)
check_sensitive_path() {
  local target="$1"
  [ -z "$target" ] && return 1

  # .env files (but allow .env.example, .env.sample, .env.template)
  if echo "$target" | grep -Eq '(^|/)\.env($|\.[^(example|sample|template)])' && \
     ! echo "$target" | grep -Eq '\.(example|sample|template)$'; then
    block "BLOCKED: Access to .env file '$target' denied. These files contain secrets.
Use .env.example for templates. Set CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 to override."
  fi

  # SSH private keys
  if echo "$target" | grep -Eq '(^|/)(\.ssh/(id_|config|known_hosts|authorized_keys)|.*\.pem$|.*_rsa$|.*_ed25519$|.*_ecdsa$)'; then
    block "BLOCKED: Access to SSH key/config '$target' denied. These are sensitive credentials.
Set CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 to override."
  fi

  # Cloud credential files
  if echo "$target" | grep -Eq '(^|/)(\.aws/credentials|\.config/gcloud/|\.kube/config|\.docker/config\.json)'; then
    block "BLOCKED: Access to cloud credentials '$target' denied.
Set CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 to override."
  fi

  # Generic credential/secret files
  if echo "$target" | grep -Eq '(^|/)(credentials\.json|secrets\.json|service[_-]account.*\.json|.*\.keystore|.*\.jks|.*\.p12|.*\.pfx)$'; then
    block "BLOCKED: Access to credential file '$target' denied.
Set CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 to override."
  fi

  # Private key files
  if echo "$target" | grep -Eq '\.(key|privkey)$'; then
    block "BLOCKED: Access to private key file '$target' denied.
Set CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 to override."
  fi

  return 1
}

# Check file_path for Read, Edit, Write tools
if [ "$TOOL_NAME" = "Read" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
  check_sensitive_path "$FILE_PATH"
fi

# Check Bash commands for sensitive file access and credential exposure
if [ "$TOOL_NAME" = "Bash" ] && [ -n "$COMMAND" ]; then
  # Block printing environment variables that likely contain secrets
  if echo "$COMMAND" | grep -Eq '(echo|printf|cat|env|printenv|export).*\$(.*_(KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL|AUTH)s?)'; then
    block "BLOCKED: Command may expose secret environment variables.
Use the application's configuration system instead of echoing secrets.
Set CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 to override."
  fi

  # Block printenv/env for full environment dump
  if echo "$COMMAND" | grep -Eq '^\s*(printenv|env)\s*$'; then
    block "BLOCKED: Dumping the full environment may expose secrets.
Use 'printenv VAR_NAME' for specific non-sensitive variables instead.
Set CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 to override."
  fi

  # Check for cat/read/access of sensitive files in bash commands
  for pattern in '\.env\b' '\.ssh/' '\.aws/credentials' '\.kube/config' '\.docker/config\.json' 'credentials\.json' 'secrets\.json'; do
    if echo "$COMMAND" | grep -Eq "(cat|head|tail|less|more|nano|vim|vi|code|read)\s+[^|]*${pattern}"; then
      block "BLOCKED: Command accesses a sensitive file matching '${pattern}'.
Set CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 to override."
    fi
  done
fi

exit 0
