#!/usr/bin/env bash
# Lint plugin skill files for install/import references to package names that
# do not exist on their public registry — across every package ecosystem the
# skills document (npm, PyPI, crates.io, RubyGems, Go modules, etc.).
#
# A skill that documents `npm install @scope/does-not-exist`,
# `pip install does-not-exist`, `cargo add does-not-exist`, etc. is a
# dependency-confusion hazard: the name is unclaimed, so anyone can publish
# malicious code under it and every user who copy-pastes the skill's install
# command runs it. It is also just broken documentation — the install fails
# or resolves to a squatted package.
#
# Design note: this is a *denylist* of confirmed-nonexistent / wrong names,
# not a live registry probe. Pre-commit must be network-free and
# deterministic, so we encode each name once it's been found rather than
# querying npm/PyPI/crates.io at lint time. Add a new triple whenever a skill
# is found referencing a package name that is not published under that name
# in its ecosystem.
#
# COVERAGE: `SKILL.md` / `skill.md` / `REFERENCE.md` anywhere in the repo, and
# every other `*.md` under a `skills/` directory — the `references/*.md` and
# `REFERENCE-<topic>.md` sidecars the 2026-10 split moved install commands and
# import examples into. A copy-pasteable install line is as dangerous there as
# in SKILL.md.
#
# Lines starting with `>` (markdown blockquote) are skipped so documented
# gotcha callouts can still cite the broken form as an example.
#
# Regression: langchain-plugin/skills/deep-agents referenced the npm package
# `@langchain/deep-agents` in its install command and eight import
# statements. That name returns 404 on the npm registry — the real package
# is `deepagents` (https://github.com/langchain-ai/deepagentsjs). A security
# researcher flagged the unclaimed-name dependency-confusion risk.
#
# Exit codes:
#   0 - no issues
#   1 - errors found
set -euo pipefail

errors=0

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# Enter the scan root before discovery so the RELATIVE paths `find .` emits
# resolve for the `grep` below too. Discovery used to run in a
# `(cd "$repo_root" && find .)` subshell while the grep ran in the caller's cwd,
# so an invocation from anywhere other than the repo root opened no file and
# still exited 0 — the silent no-scan class of #2219/#2290, fixed the same way
# in lint-mcp-tool-references.sh.
cd "$repo_root" || exit 1

# Denylist of (ecosystem, wrong-name, suggested-fix) triples. Each triple is
# three adjacent entries in the same array so bash 3.2 (macOS default) still
# works without associative arrays. The wrong-name is matched as a fixed
# substring (grep -F); keep it specific enough (scope, hyphenation) that it
# can't false-positive on a legitimate package.
denylist=(
  "npm"
  "@langchain/deep-agents"
  "this package does not exist on npm (404). Use the real package: npm install deepagents / import { createDeepAgent } from \"deepagents\" (https://github.com/langchain-ai/deepagentsjs)"
)

# Iterate over the denylist in triples.
i=0
while [ $i -lt ${#denylist[@]} ]; do
  ecosystem="${denylist[$i]}"
  pkg="${denylist[$((i + 1))]}"
  fix="${denylist[$((i + 2))]}"

  while IFS= read -r -d '' file; do
    while IFS=: read -r line_no content; do
      # Skip blockquote lines (gotcha callouts cite the broken form on purpose).
      case "$content" in
        '>'* | *[[:space:]]'>'*) continue ;;
      esac
      printf "ERROR [nonexistent-package]: %s:%s\n" "${file#./}" "$line_no"
      printf "  Found:     %s\n" "$content"
      printf "  Package:   %s (%s — not published under this name)\n" "$pkg" "$ecosystem"
      printf "  Fix:       %s\n\n" "$fix"
      errors=$((errors + 1))
    done < <(grep -nF "$pkg" "$file" || true)
  done < <(find . -type f \
              \( -name 'SKILL.md' -o -name 'skill.md' -o -name 'REFERENCE.md' \
                 -o \( -path '*/skills/*' -name '*.md' \) \) \
              -not -path './.claude/worktrees/*' \
              -not -path '*/node_modules/*' \
              -print0)

  i=$((i + 3))
done

if [ "$errors" -gt 0 ]; then
  printf "Found %d nonexistent-package reference(s) in skill files\n" "$errors"
  exit 1
fi

printf "All package references in skill files OK\n"
exit 0
