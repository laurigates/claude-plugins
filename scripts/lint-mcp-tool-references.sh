#!/usr/bin/env bash
# Lint plugin skill files for references to MCP tool names that aren't
# shipped by the corresponding MCP server.
#
# Skills that document `mcp__<server>__<tool>` names in their body or
# `allowed-tools` create silent failures when the referenced tool isn't
# actually exposed by that server. The user can't bypass via ToolSearch
# either — the schema simply doesn't exist. The agent typically falls
# back to a `gh api graphql` form after a wasted round trip.
#
# This script encodes a denylist of known-unavailable references. Add a
# new entry whenever a skill is found referencing an MCP tool that the
# server doesn't actually ship.
#
# COVERAGE — what this script actually reads. It is NOT repo-wide:
#   * `SKILL.md` / `skill.md` / `REFERENCE.md` anywhere in the repo
#   * `*.workflow.js` — the workflow scripts bundled beside a skill, which
#     carry the same tool names in their comments and agent prompts
#   * `git-repo-agent/src/git_repo_agent/prompts/generated/**/*.md` — the
#     COMPILED subagent prompts. They are derived from the SKILL.md files
#     above and ship in the git-repo-agent wheel, so a source fix that was
#     never recompiled (`just compile-prompts`) is caught here too.
# Deliberately OUT of scope: narrative documentation — `.claude/rules/*.md`,
# `docs/**`, and the release-please-generated `CHANGELOG.md` files — because
# those cite known-broken tool names on purpose (that is what a
# regression-testing row or a changelog entry IS). A walk that included them
# would fire on `.claude/rules/regression-testing.md` itself. Fix a stale
# tool name in those files by hand.
#
# Lines starting with `>` (markdown blockquote) are skipped so the
# documented gotcha callouts in the files that ARE scanned can still cite
# the broken form as an example.
#
# Regression (issue #2437): multi-model-delegation and test-analyze documented
# PAL's tools with a hardcoded `mcp__pal__*` prefix. The callable prefix is
# derived from the name the server is REGISTERED under, which for this repo's
# PAL is `pal-mcp-server`, so every documented lookup missed. Because that
# prefix is registration-dependent rather than universally wrong, its denylist
# entry is PATH-SCOPED to the artifacts that carry the defect — see the
# `scope` field below.
#
# Regression: git-pr-feedback referenced `mcp__github__resolve_review_thread`
# in Step 6, Step 1A.7.4, the Agentic Optimizations table, REFERENCE.md
# resolution criteria, and `allowed-tools` — but the standard github MCP
# server does not expose that tool. Use `gh api graphql` with the
# `resolveReviewThread` mutation instead (issue #1429).
#
# Exit codes:
#   0 - no issues
#   1 - errors found
set -euo pipefail

errors=0

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# Enter the scan root before discovery so the RELATIVE paths `find .` emits
# resolve for the `grep` below too. Discovery used to run in a
# `(cd "$repo_root" && find .)` subshell while the grep ran in the caller's
# cwd, so every invocation from anywhere other than the repo root opened no
# file and still exited 0 — the silent no-scan class of #2219/#2290.
cd "$repo_root" || exit 1

# Denylist of (tool-name, scope, suggested-fix) TRIPLES. Each triple is three
# adjacent entries in the same array so bash 3.2 (macOS default) still works
# without associative arrays.
#
# `scope` is a `case` glob matched against the `./`-prefixed path (`|`
# alternation allowed) limiting where the entry fires. Use `*` for a name NO
# server exposes under any registration; use a narrower pattern for a name
# that is only wrong here — an `mcp__<x>__` prefix is the CORRECT callable
# prefix in any repo that registers a server under the key `<x>`, so banning
# one repo-wide would hardcode exactly the assumption issue #2437 says not to
# make.
denylist=(
  # The github MCP server ships no `resolve_review_thread` under any
  # registration, so this entry is unconditional.
  "mcp__github__resolve_review_thread"
  "*"
  "use gh api graphql with the resolveReviewThread mutation: gh api graphql -f query='mutation(\$id:ID!){resolveReviewThread(input:{threadId:\$id}){thread{isResolved}}}' -F id=\"\$THREAD_ID\""

  # PAL is registered here as `pal-mcp-server`, so the bare `mcp__pal__`
  # prefix resolves to nothing (issue #2437). SCOPED to the two skills that
  # document PAL and to the compiled prompts derived from them: a repo that
  # registers PAL under the key `pal` has `mcp__pal__` as its CORRECT prefix,
  # and this guard must not claim otherwise.
  "mcp__pal__"
  "*/multi-model-delegation/*|*/test-analyze/*|*/prompts/generated/*"
  "the tool prefix is derived from the name the server is registered under -- this repo registers PAL as pal-mcp-server, so use mcp__pal-mcp-server__<tool>; confirm the registration with: claude mcp list"
)

# `case` alternation is SYNTACTIC — a `|` arriving inside a variable is a
# literal character, not an alternation operator — so the scope glob is split
# on `|` first and each branch matched on its own.
scope_match() {
  local file_path="$1" scope_spec="$2" scope_pat matched=1 reglob=""
  # The unquoted `$scope_spec` below is split on `|` -- but it would ALSO be
  # pathname-expanded, and the `*` scope would then become a list of filenames
  # in the cwd instead of the catch-all pattern. Disable globbing for the split
  # and restore it afterwards (`case` patterns are unaffected by `set -f`).
  case "$-" in *f*) ;; *) reglob=1 ;; esac
  set -f
  local IFS='|'
  for scope_pat in $scope_spec; do
    # shellcheck disable=SC2254  # glob matching of $scope_pat is intentional
    case "$file_path" in
      $scope_pat) matched=0; break ;;
    esac
  done
  if [ -n "$reglob" ]; then set +f; fi
  return "$matched"
}

# Iterate over the denylist in triples.
i=0
while [ $i -lt ${#denylist[@]} ]; do
  tool="${denylist[$i]}"
  scope="${denylist[$((i + 1))]}"
  fix="${denylist[$((i + 2))]}"

  while IFS= read -r -d '' file; do
    # A path-scoped entry only fires inside its own artifact family.
    scope_match "$file" "$scope" || continue
    while IFS=: read -r line_no content; do
      # Skip blockquote lines (gotcha callouts cite the broken form on purpose).
      case "$content" in
        '>'* | *[[:space:]]'>'*) continue ;;
      esac
      printf "ERROR [unavailable-mcp-tool]: %s:%s\n" "${file#./}" "$line_no"
      printf "  Found: %s\n" "$content"
      printf "  Tool:  %s (not exposed by its MCP server)\n" "$tool"
      printf "  Fix:   %s\n\n" "$fix"
      errors=$((errors + 1))
    done < <(grep -nF "$tool" "$file" || true)
  done < <(find . -type f \
              \( -name 'SKILL.md' -o -name 'skill.md' -o -name 'REFERENCE.md' \
                 -o -name '*.workflow.js' \
                 -o \( -path './git-repo-agent/src/git_repo_agent/prompts/generated/*' \
                       -name '*.md' \) \) \
              -not -path './.claude/worktrees/*' \
              -not -path '*/node_modules/*' \
              -print0)

  i=$((i + 3))
done

if [ "$errors" -gt 0 ]; then
  printf "Found %d unavailable-MCP-tool reference(s) in skill files\n" "$errors"
  exit 1
fi

printf "All MCP tool references in skill files OK\n"
exit 0
