#!/usr/bin/env bash
# PermissionRequest hook — auto-approve safe operations, auto-deny dangerous ones
#
# Toggle: set CLAUDE_HOOKS_DISABLE_PERMISSION_AUTO=1 to skip this hook
#
# Matches: Bash (and optionally all tools)
# Approves: read-only git, test runners, linters — only when EVERY command in
#           the command line is one of them (see below)
# Denies: destructive filesystem ops, force push to protected branches
# Passes through: everything else (user decides)
#
# Customize the APPROVE and DENY patterns below for your project.
#
# ── Why approval is decided per parsed command node (#2733) ──────────────────
#
# The approve rules used to be `grep -Eq '^\s*git\s+(status|…)'` over the raw
# command string. grep anchors `^` at every LINE, and nothing looked past the
# first statement, so `git status && touch x`, `npm test; chmod -R 777 .` and
# `git log -1<newline>touch x` were all approved as a whole — and because the
# deny rules ran after the approve rules, `git status && rm -rf /` was approved
# without the deny rule ever being reached.
#
# Now:
#   1. The deny rules run FIRST, on the raw text (over-denying is the safe
#      polarity for a deny rule, so they stay regexes).
#   2. The command is parsed with `ast-grep --lang bash` (tree-sitter-bash), as
#      terraform-plugin/hooks/validate-terraform-apply.sh (#2506) and
#      auto-checkpoint.sh (#2652) do, and approval requires that:
#        - the parse has no ERROR node and no empty (MISSING) command node;
#        - every byte outside the command nodes is a list/pipeline separator
#          (`&&` `||` `;` `|` `&` newline) or whitespace — so a subshell, group,
#          loop, conditional, function, redirection, heredoc or comment, all of
#          which leave their own syntax outside the command node, yields no
#          decision;
#        - every command node's own bytes contain no expansion, substitution,
#          redirection, escape or separator character ($ ` ( ) < > ; & | \ #
#          or a newline) — so `$(…)`, `<(…)`, `$VAR` and a quoted multi-line
#          argument yield no decision even where they sit inside the node;
#        - every command node matches one of the approve rules below, which
#          keep their pre-#2733 meaning but are now matched against the node's
#          own text instead of the raw string.
#      The node bytes are sliced from the raw command by the parser's byte
#      offsets, so a parser that misreports node boundaries cannot smuggle a
#      separator past the per-node character check.
#   3. With no ast-grep, a failing / garbled / timed-out parse (5 s), or any
#      condition above unmet, the hook emits NO decision. For an allow hook the
#      safe fallback is "ask the user", never the old regex.

set -euo pipefail

# Toggle off
[ "${CLAUDE_HOOKS_DISABLE_PERMISSION_AUTO:-}" = "1" ] && exit 0

# Byte semantics for ${COMMAND:offset:length}: ast-grep reports byte offsets.
LC_ALL=C

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only handle Bash commands
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

[ -z "$COMMAND" ] && exit 0

# --- AUTO-DENY: Dangerous operations (before approve, on the raw text) ---

# Destructive filesystem operations on root or home
# shellcheck disable=SC2016  # $HOME is a grep pattern, not shell expansion
if echo "$COMMAND" | grep -Eq 'rm\s+(-rf|-fr)\s+(/|~/|\$HOME)'; then
  echo '{"decision": "deny", "reason": "Destructive operation on root or home directory"}'
  exit 0
fi

# Force push to protected branches
if echo "$COMMAND" | grep -Eq 'git\s+push\s+.*--force.*\s(main|master)\b'; then
  echo '{"decision": "deny", "reason": "Force push to protected branch"}'
  exit 0
fi

# --- AUTO-APPROVE: Safe, read-only operations ---

# Prints the approve reason for ONE command node's text, or returns 1.
approve_reason() {
  local node=$1
  # Read-only git operations
  if printf '%s\n' "$node" | grep -Eq '^\s*git\s+(status|log|diff|branch|remote|show|blame|shortlog|describe|ls-files|rev-parse|rev-list)'; then
    echo "Read-only git operation"
  # Test runners (read-only, fail-fast)
  elif printf '%s\n' "$node" | grep -Eq '^\s*(npm\s+test|npx\s+(vitest|jest)|bun\s+test|pytest|cargo\s+test|go\s+test|make\s+test)'; then
    echo "Test execution"
  # Linters and formatters (read-only check mode)
  elif printf '%s\n' "$node" | grep -Eq '^\s*(npx\s+(biome|eslint|prettier)|bun\s+run\s+(lint|check|format)|ruff\s+check|mypy|tsc\s+--noEmit)'; then
    echo "Linter/formatter check"
  # gh CLI read operations
  elif printf '%s\n' "$node" | grep -Eq '^\s*gh\s+(pr\s+(view|checks|list|diff)|issue\s+(view|list)|run\s+(view|list))'; then
    echo "GitHub CLI read operation"
  else
    return 1
  fi
}

# `sg` collides with shadow-utils' sg(1); adopt it only if it IS ast-grep (#2451).
ASTGREP=""
if command -v ast-grep >/dev/null 2>&1; then
  ASTGREP="ast-grep"
elif command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'; then
  ASTGREP="sg"
fi
[ -n "$ASTGREP" ] || exit 0

# Empty when coreutils `timeout` is absent (stock macOS); the `+` expansion
# below keeps an empty array legal under `set -u` on bash < 4.4.
TIMEOUT=()
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT=(timeout 5)
fi

AST_RULES='id: command
language: bash
rule:
  kind: command
---
id: error
language: bash
rule:
  kind: ERROR
'

# Any parser failure (missing, non-zero exit, timeout) => no decision.
PARSE=$(printf '%s' "$COMMAND" \
  | ${TIMEOUT[@]+"${TIMEOUT[@]}"} "$ASTGREP" scan --inline-rules "$AST_RULES" --stdin --json=compact 2>/dev/null) || exit 0

# One "<start> <end>" line per command node in source order, or "ERROR".
# Garbage output fails jq => no decision.
NODES=$(printf '%s' "$PARSE" | jq -r '
  if any(.[]; .ruleId != "command") then "ERROR"
  else sort_by(.range.byteOffset.start)[] | "\(.range.byteOffset.start) \(.range.byteOffset.end)"
  end' 2>/dev/null) || exit 0
[ -n "$NODES" ] || exit 0

# Separators a plain list/pipeline may leave between command nodes.
SEPARATORS='^[[:space:];&|]*$'
# Characters a plain command node may not contain.
UNSAFE_NODE_CHARS=$'[$`()<>;&|\\#\n\r]'

LEN=${#COMMAND}
pos=0
reason=""
while read -r start end; do
  [ "$start" = "ERROR" ] && exit 0
  [[ $start =~ ^[0-9]+$ && $end =~ ^[0-9]+$ ]] || exit 0
  # Overlapping, empty, or out-of-range node => no decision.
  if [ "$start" -lt "$pos" ] || [ "$end" -le "$start" ] || [ "$end" -gt "$LEN" ]; then
    exit 0
  fi
  [[ ${COMMAND:pos:start-pos} =~ $SEPARATORS ]] || exit 0
  node=${COMMAND:start:end-start}
  [[ $node =~ $UNSAFE_NODE_CHARS ]] && exit 0
  node_reason=$(approve_reason "$node") || exit 0
  [ -n "$reason" ] || reason=$node_reason
  pos=$end
done <<<"$NODES"
[[ ${COMMAND:pos} =~ $SEPARATORS ]] || exit 0
[ -n "$reason" ] || exit 0

printf '{"decision": "approve", "reason": "%s"}\n' "$reason"
exit 0
