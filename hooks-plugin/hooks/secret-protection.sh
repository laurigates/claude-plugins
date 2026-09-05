#!/usr/bin/env bash
# PreToolUse hook — blocks access to sensitive files and credential exposure
#
# Toggle: a human operator can export CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1
# in their shell environment to skip this hook. The toggle is only honored
# when set in the process environment — an inline prefix on the command line
# is intentionally NOT honored so that an agent cannot self-serve the bypass
# (see .claude/rules/handling-blocked-hooks.md).
#
# Matches: Read, Edit, Write, Bash
# Detects: .env files, SSH keys, cloud credentials, private keys, token files

set -euo pipefail

# Toggle off
[ "${CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION:-}" = "1" ] && exit 0

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Every block message ends with this note. It deliberately does NOT read
# "set CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 to override" — that phrasing
# reads to an agent as a bypass it can perform, but the toggle is only read
# from the hook's own process environment, so an inline prefix on the
# retried command does nothing (see .claude/rules/handling-blocked-hooks.md).
OVERRIDE_NOTE="If this is a false positive, delegate to the user per .claude/rules/handling-blocked-hooks.md — ask them to export CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 in their own shell (only honored there, not inline on a command). Do not attempt to self-serve this bypass."

block() {
  echo "$1" >&2
  exit 2
}

# Sensitive file patterns (applied to Read, Edit, Write file_path and Bash arguments)
check_sensitive_path() {
  local target="$1"
  [ -z "$target" ] && return 0

  # .env files (but allow .env.example, .env.sample, .env.template)
  if echo "$target" | grep -Eq '(^|/)\.env($|\.[^(example|sample|template)])' && \
     ! echo "$target" | grep -Eq '\.(example|sample|template)$'; then
    block "BLOCKED: Access to .env file '$target' denied. These files contain secrets.
Use .env.example for templates. ${OVERRIDE_NOTE}"
  fi

  # SSH private keys
  if echo "$target" | grep -Eq '(^|/)(\.ssh/(id_|config|known_hosts|authorized_keys)|.*\.pem$|.*_rsa$|.*_ed25519$|.*_ecdsa$)'; then
    block "BLOCKED: Access to SSH key/config '$target' denied. These are sensitive credentials.
${OVERRIDE_NOTE}"
  fi

  # Cloud credential files
  if echo "$target" | grep -Eq '(^|/)(\.aws/credentials|\.config/gcloud/|\.kube/config|\.docker/config\.json)'; then
    block "BLOCKED: Access to cloud credentials '$target' denied.
${OVERRIDE_NOTE}"
  fi

  # Generic credential/secret files
  if echo "$target" | grep -Eq '(^|/)(credentials\.json|secrets\.json|service[_-]account.*\.json|.*\.keystore|.*\.jks|.*\.p12|.*\.pfx)$'; then
    block "BLOCKED: Access to credential file '$target' denied.
${OVERRIDE_NOTE}"
  fi

  # Private key files
  if echo "$target" | grep -Eq '\.(key|privkey)$'; then
    block "BLOCKED: Access to private key file '$target' denied.
${OVERRIDE_NOTE}"
  fi

  return 0
}

# Check file_path for Read, Edit, Write tools
if [ "$TOOL_NAME" = "Read" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
  check_sensitive_path "$FILE_PATH"
fi

# Check Bash commands for sensitive file access and credential exposure
if [ "$TOOL_NAME" = "Bash" ] && [ -n "$COMMAND" ]; then
  # Block printing environment variables that likely contain secrets.
  # Match an actual variable *reference* whose name ends in a secret-ish suffix:
  # `$VAR_KEY`, `${VAR_TOKEN}`, etc. The name is a contiguous identifier
  # ([A-Za-z0-9_]*) — NOT `.*` — so the match cannot bridge a `$(date …)` command
  # substitution to a distant unrelated `_KEY` elsewhere on the line. That `.*`
  # greediness false-blocked routine config echoes like
  # `echo "$(date) KC_HOSTNAME=$kch FE_KEYCLOAK_URL=$feu"`, where `FE_KEYCLOAK`
  # contains `_KEY` but is an assignment LHS, not a secret variable reference
  # (issue #1580). Public config names ($..._HOST, $..._URL, $..._ENDPOINT) are
  # no longer caught; genuine $..._KEY/_SECRET/_TOKEN/_PASSWORD references are.
  # shellcheck disable=SC2016  # $... is a grep pattern, not shell expansion
  if echo "$COMMAND" | grep -Eq '(echo|printf|cat|env|printenv|export)[^|]*\$\{?[A-Za-z0-9_]*_(KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL|AUTH)[Ss]?\b'; then
    block "BLOCKED: Command may expose secret environment variables.
Use the application's configuration system instead of echoing secrets.
${OVERRIDE_NOTE}"
  fi

  # Block printenv/env for full environment dump
  if echo "$COMMAND" | grep -Eq '^\s*(printenv|env)\s*$'; then
    block "BLOCKED: Dumping the full environment may expose secrets.
Use 'printenv VAR_NAME' for specific non-sensitive variables instead.
${OVERRIDE_NOTE}"
  fi

  # Check for cat/read/access of sensitive files in bash commands.
  #
  # The gap between the reader verb and the file pattern is `[^|;&]*` — NOT
  # `[^|]*` — so a match cannot bridge a command separator (`;`, `&&`, `||`) or
  # a pipe. The wider form let a verb in one statement bind to an unrelated
  # `.env` mention in a *later* statement, false-blocking commands that read no
  # secret at all, e.g. `... | head -1); grep -nE '\.env|PATTERN' "$f"`, where
  # the only `.env` is inside a grep pattern (issue #2444). Same greediness
  # class as the `.*` → `[A-Za-z0-9_]*` narrowing documented above (#1580).
  #
  # The verb group is anchored at a word start with `(^|[^A-Za-z])`, so a verb
  # cannot match inside an ordinary English word. Without it `regardless`,
  # `unless`, `thread`, `encode` and `furthermore` each supplied a verb, and
  # prose that went on to mention `.env.integration` — a commit-message heredoc
  # describing config precedence — was blocked as a sensitive-file read (issue
  # #2597). `\b` / `\<` would be shorter but are GNU extensions; this hook may
  # run under BSD grep (macOS), GNU grep (CI) or ugrep, and `(^|[^A-Za-z])` is
  # POSIX ERE that all three accept. The alternative captures one leading
  # non-letter character, which is trimmed from `$match` below before the block
  # message; the template exemption re-greps from `${pattern}` and never sees it.
  reader_verbs='(cat|head|tail|less|more|nano|vim|vi|code|read)'
  for pattern in '\.env\b' '\.ssh/' '\.aws/credentials' '\.kube/config' '\.docker/config\.json' 'credentials\.json' 'secrets\.json'; do
    # Capture the matched substring (verb + path) rather than a bare boolean, so
    # the block message can name what tripped it and the exemption below can
    # inspect the actual path argument.
    match=$(echo "$COMMAND" | grep -oE "(^|[^A-Za-z])${reader_verbs}[[:space:]]+[^|;&]*${pattern}[^[:space:]|;&'\"]*" | head -1 || true)
    [ -z "$match" ] && continue
    # Drop the single boundary character the `(^|[^A-Za-z])` alternative
    # captured (a space, `;`, `(`, quote, …); at start-of-line it captured
    # nothing and the match already begins with the verb.
    match="${match#[!A-Za-z]}"

    # .env.example / .env.sample / .env.template are templates committed by
    # convention, not secrets. check_sensitive_path() already exempts them on
    # the Read/Edit/Write path; without the same exemption here, `cat
    # .env.example` was blocked while `Read`ing the identical file was allowed
    # (issue #2444). Scoped to the .env pattern to mirror check_sensitive_path()
    # exactly — the other patterns keep no exemption.
    #
    # The exemption requires *every* .env token in the matched region to be a
    # template. Inspecting only the last one would let a real secret hide behind
    # a template in the same statement (`cat .env .env.example`).
    if [ "$pattern" = '\.env\b' ]; then
      env_tokens=$(echo "$match" | grep -oE "${pattern}[^[:space:]|;&'\"]*" || true)
      non_template=$(echo "$env_tokens" | grep -vE '\.(example|sample|template)$' || true)
      [ -n "$env_tokens" ] && [ -z "$non_template" ] && continue
    fi

    block "BLOCKED: Command accesses a sensitive file matching '${pattern}' (matched: '${match}').
${OVERRIDE_NOTE}"
  done
fi

exit 0
