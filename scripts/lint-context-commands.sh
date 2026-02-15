#!/usr/bin/env bash
# Lint SKILL.md context backtick commands for patterns that break
# Claude Code's backtick execution engine.
#
# Regression tests for known context command issues:
# 1. git log -N shorthand misinterpreted as pattern flag (use --max-count=N)
# 2. Pipe operator blocked by shell protections
# 3. ls commands that fail when files are missing (use find instead)
# 4. Shell operators (&&, ||, ;) blocked by security protections
#
# Exit codes:
#   0 - no issues
#   1 - errors found (patterns known to break)
#   2 - warnings found (use --strict to fail on warnings)
set -euo pipefail

strict=false
[[ "${1:-}" == "--strict" ]] && strict=true

errors=0
warnings=0

report() {
  local level="$1" rule="$2" file="$3" line="$4" content="$5" fix="$6"
  printf "%s [%s]: %s:%s\n" "$level" "$rule" "$file" "$line"
  printf "  Found: %s\n" "$content"
  printf "  Fix: %s\n\n" "$fix"
  if [[ "$level" == "ERROR" ]]; then
    errors=$((errors + 1))
  else
    warnings=$((warnings + 1))
  fi
}

check_pattern() {
  local level="$1" rule="$2" pattern="$3" fix="$4"
  while IFS= read -r match; do
    local file line content
    file="${match%%:*}"; match="${match#*:}"
    line="${match%%:*}"; content="${match#*:}"
    report "$level" "$rule" "$file" "$line" "$content" "$fix"
  done < <(grep -rn "$pattern" --include='SKILL.md' --include='skill.md' . 2>/dev/null || true)
}

##############################
# ERRORS - known to break
##############################

# git log numeric shorthand (-N) breaks backtick execution
check_pattern ERROR \
  "git-log-shorthand" \
  '!`[^`]*git log[^`]* -[0-9]\+[^0-9]' \
  "replace -N with --max-count=N"

# Pipe chains in context commands (blocked by shell protections)
check_pattern ERROR \
  "pipe-operator" \
  '!`[^`]* | [^`]*`' \
  "remove pipe; use tool's native file arg or find instead"

# ls commands that fail when files don't exist
check_pattern ERROR \
  "ls-in-context" \
  '!`ls [^`]*`' \
  "replace ls with find; ls returns non-zero when files are missing"

##############################
# WARNINGS - likely to break
##############################

# && operator in context commands (includes test -f && echo patterns)
check_pattern WARN \
  "shell-operator-and" \
  '!`[^`]* && [^`]*`' \
  "remove && operator; for file checks use: find . -maxdepth 1 -name 'file' 2>/dev/null"

# || operator in context commands
check_pattern WARN \
  "shell-operator-or" \
  '!`[^`]* || [^`]*`' \
  "remove || fallback; use 2>/dev/null and handle empty output in execution logic"

# Semicolons in context commands
check_pattern WARN \
  "shell-operator-semicolon" \
  '!`[^`]*; [^`]*`' \
  "remove ; operator; split into separate context commands"

##############################
# Summary
##############################

if [ "$errors" -gt 0 ]; then
  printf "Found %d error(s), %d warning(s)\n" "$errors" "$warnings"
  exit 1
elif [ "$warnings" -gt 0 ]; then
  printf "Found %d warning(s) (use --strict to fail on warnings)\n" "$warnings"
  $strict && exit 2
  exit 0
else
  printf "All context commands OK\n"
  exit 0
fi
