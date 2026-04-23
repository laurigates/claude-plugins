#!/usr/bin/env bash
# shellcheck disable=SC2016  # Grep patterns use backticks and $ literally, not as shell expansion
# Lint SKILL.md context backtick commands for patterns that break
# Claude Code's backtick execution engine.
#
# Regression tests for known context command issues:
# 1. git log -N shorthand misinterpreted as pattern flag (use --max-count=N)
# 2. Pipe operator blocked by shell protections
# 3. ls commands that fail when files are missing (use find instead)
# 4. Shell operators (&&, ||, ;) blocked by security protections
# 5. Redirection operators (>, >>) blocked by security protections (includes 2>/dev/null)
# 6. Commands that write to stderr with empty $1 (wc, file, stat)
# 7. cat/head/tail with hardcoded paths that write to stderr when missing (use find)
# 8. git log -n N shorthand (use --max-count=N)
# 9. gh repo view uses GitHub GraphQL API (TLS-sensitive, fails in proxy/offline envs)
# 10. test -f / test -d require Bash permission not granted to context commands (use find)
# 11. grep with multiple hardcoded filenames fails when files don't exist (use find -exec grep)
# 12. find/jq on home-directory paths (~/, $HOME) blocked by sandbox security restrictions
# 13. gh issue/pr list without -R fails in repos without remotes ("no git remotes found")
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

# All patterns anchor to "- " prefix to match context command lines only
# (avoids false positives from markdown tables and code blocks)

# git log numeric shorthand (-N or -n N) breaks backtick execution
check_pattern ERROR \
  "git-log-shorthand" \
  '^- .*!`[^`]*git log[^`]* -[0-9]\+[^0-9]' \
  "replace -N with --max-count=N"

# git log -n N shorthand (use --max-count=N)
check_pattern ERROR \
  "git-log-n-shorthand" \
  '^- .*!`[^`]*git log[^`]* -n [0-9]' \
  "replace -n N with --max-count=N"

# Pipe chains in context commands (blocked by shell protections)
# Regression: ci-autofix-reusable used `gh secret list 2>/dev/null | head -5` (issue #899)
check_pattern ERROR \
  "pipe-operator" \
  '^- .*!`[^`]* | [^`]*`' \
  "remove pipe; use tool's native file arg or find instead"

# ls commands that fail when files don't exist
check_pattern ERROR \
  "ls-in-context" \
  '^- .*!`ls [^`]*`' \
  "replace ls with find; ls returns non-zero when files are missing"

# Redirection operators (>, >>) including 2>/dev/null
# Regression: ci-autofix-reusable used `find .github/workflows ... 2>/dev/null` (issue #899)
check_pattern ERROR \
  "redirection-operator" \
  '^- .*!`[^`]* [0-9]*>\/\?[^`]*`' \
  "remove redirection; failed commands produce empty output which is handled gracefully"

# Commands that write to stderr when $1 is empty/missing
# (wc, file, stat produce "No such file" errors on empty args)
check_pattern ERROR \
  "stderr-on-empty-arg" \
  '^- .*!`\(wc\|file\|stat\) [^`]*\$[1-9]' \
  "use find for existence checks; these commands write to stderr on empty \$1"

# cat/head/tail with hardcoded paths write to stderr when file is missing
# (use find for detection, or Read tool for file contents)
check_pattern ERROR \
  "cat-hardcoded-path" \
  '^- .*!`cat [^`$]*`' \
  "use find for existence checks or discovery; cat writes to stderr on missing files"

check_pattern ERROR \
  "head-hardcoded-path" \
  '^- .*!`head [^`$]*`' \
  "use find for existence checks or discovery; head writes to stderr on missing files"

check_pattern ERROR \
  "tail-hardcoded-path" \
  '^- .*!`tail [^`$]*`' \
  "use find for existence checks or discovery; tail writes to stderr on missing files"

# grep with multiple hardcoded filenames writes to stderr when files don't exist
# Regression: blueprint-curate-docs used `grep -m1 ... package.json pyproject.toml requirements.txt` (PR #TBD)
check_pattern ERROR \
  "grep-hardcoded-multi-file" \
  '^- .*!`[^`]*grep [^`]* [a-zA-Z_-]*\.\(json\|toml\|txt\|yaml\|yml\|cfg\|ini\) [a-zA-Z_-]*\.\(json\|toml\|txt\|yaml\|yml\|cfg\|ini\)' \
  "replace with find -exec grep: 'find . -maxdepth 1 \\( -name f1 -o -name f2 \\) -exec grep pattern {} +'"

# test -f / test -d require Bash permission that context commands don't have
# Regression: ci-autofix-reusable used `test -f path && echo "EXISTS" || echo "MISSING"` (issue #899)
# Regression: project-distill used test -d .git and failed outside sandbox mode (PR #TBD)
check_pattern ERROR \
  "test-in-context" \
  '^- .*!`test -[fd] [^`]*`' \
  "replace with find: 'test -f path/file' -> 'find path -maxdepth 1 -name file -type f'"

# find/jq on home-directory paths blocked by sandbox (only working directories allowed)
# Regression: health-check used `find ~/.claude/plugins ...` which was blocked by sandbox security (PR #TBD)
check_pattern ERROR \
  "home-dir-in-context" \
  '^- .*!`[^`]*[[:space:]]~/\|[[:space:]]\$HOME/' \
  "remove home-directory context commands; check home-dir files during execution steps instead"

# gh repo view uses GitHub's GraphQL API (TLS-sensitive; fails in proxy/offline/cert-error envs)
# Regression: git-pr-feedback used this and failed with x509 TLS cert error (PR #799)
check_pattern WARN \
  "gh-api-in-context" \
  '^- .*!`[^`]*gh repo view[^`]*`' \
  "replace 'gh repo view' with 'git remote -v'; gh API calls fail with TLS errors in some environments"

# gh issue/pr list without -R requires a configured git remote and fails with
# "no git remotes found" in repos that lack one.
# Regression: feedback-session had 'gh issue list --label ...' in context and failed
# when invoked from a repo without remotes (PR #TBD)
while IFS= read -r match; do
  gh_file="${match%%:*}"; match="${match#*:}"
  gh_line="${match%%:*}"; gh_content="${match#*:}"
  # Skip if command explicitly targets a repo (-R works without a local remote)
  if printf '%s' "$gh_content" | grep -q -- '-R '; then
    continue
  fi
  report ERROR \
    "gh-list-needs-remote" \
    "$gh_file" "$gh_line" "$gh_content" \
    "move 'gh issue/pr list' out of context (needs a remote); fetch during execution steps, or pass '-R owner/repo'"
done < <(grep -rn '^- .*!`[^`]*gh \(issue\|pr\) list' --include='SKILL.md' --include='skill.md' . 2>/dev/null || true)

##############################
# WARNINGS - likely to break
##############################

# && operator in context commands (includes test -f && echo patterns)
# Regression: ci-autofix-reusable used `test -f path && echo "EXISTS" || echo "MISSING"` (issue #899)
check_pattern WARN \
  "shell-operator-and" \
  '^- .*!`[^`]* && [^`]*`' \
  "remove && operator; for file checks use: find . -maxdepth 1 -name 'file'"

# || operator in context commands
# Regression: ci-autofix-reusable used `test -f path && echo "EXISTS" || echo "MISSING"` (issue #899)
check_pattern WARN \
  "shell-operator-or" \
  '^- .*!`[^`]* || [^`]*`' \
  "remove || fallback; failed commands produce empty output which is handled gracefully"

# jq on .claude/settings.json which may not exist (stderr error, and 2>/dev/null is blocked)
# Regression: health-audit used `jq ... .claude/settings.json` which fails when file is missing (PR #TBD)
check_pattern WARN \
  "jq-on-optional-settings" \
  '^- .*!`jq [^`]* \.claude/settings[^`]*`$' \
  "replace with find for existence check; use jq during execution steps where error handling is available"

# Semicolons in context commands
check_pattern WARN \
  "shell-operator-semicolon" \
  '^- .*!`[^`]*; [^`]*`' \
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
