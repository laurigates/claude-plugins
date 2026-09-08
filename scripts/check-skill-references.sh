#!/usr/bin/env bash
# Resolve every `<name>-plugin:<artifact>` citation against the skills and
# agents that actually exist on disk.
#
# Skills, rules and REFERENCE files cite sibling artifacts by their
# plugin-qualified ID ("invoke `git-plugin:git-commit`"). Nothing validates
# those strings: rename a skill directory, or delete one, and every citation
# keeps reading as authoritative while pointing at an ID the Skill tool cannot
# resolve. The agent burns a round trip on `Skill(...)` -> "not found" and then
# reinvents whatever the cited skill encoded — the exact failure the citation
# existed to prevent.
#
# This is a RESOLUTION check, not a denylist: ground truth is rebuilt from the
# tree on every run, so a rename is caught the moment it lands without anyone
# adding an entry here. Contrast `lint-mcp-tool-references.sh`, which must
# enumerate bad names because the MCP servers' tool lists are not on disk.
#
# GROUND TRUTH — an ID resolves if it matches either:
#   * `<plugin>/skills/<name>/SKILL.md`  -> `<plugin>:<name>`
#   * `<plugin>/agents/<name>.md`        -> `<plugin>:<name>`
# There are no `commands/` directories in this repo; add a third arm here if
# that changes.
#
# COVERAGE — what this script reads. It is NOT repo-wide:
#   * `SKILL.md` / `skill.md` / `REFERENCE.md` anywhere in the repo
#   * `*.workflow.js` — workflow scripts bundled beside a skill, which carry
#     skill IDs in their agent prompts
#   * `.claude/rules/*.md` — always-loaded rules that route the agent to a
#     skill by ID. A dead ID here misroutes every session, so unlike the MCP
#     linter (which excludes rules because they cite broken tool names on
#     purpose) this scan includes them. The two intentional-broken-citation
#     shapes that live in rules are handled by the allowlist below.
# Deliberately OUT of scope:
#   * `docs/**` — ADRs and benchmark judgments are immutable records. ADR-0007
#     cites `git-plugin:commit`, a pre-rename name that was correct when the
#     decision was written; "fixing" it would falsify the record.
#   * `CHANGELOG.md` — release-please generated, and a changelog entry about a
#     rename necessarily names the old ID.
#   * `README.md` / `docs/PLUGIN-MAP.md` counts — already covered by
#     `check-docs-index.sh`; this script must not double-gate them.
#
# Lines starting with `>` (markdown blockquote) are skipped, matching
# `lint-mcp-tool-references.sh`, so a callout can cite a dead ID as an example.
#
# Exit codes:
#   0 - every citation resolves
#   1 - one or more dead citations found
set -euo pipefail

errors=0

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# Citation shape. Two guards earn their keep, both found by running this
# against the tree:
#   * LEFT BOUNDARY `(^|[^A-Za-z0-9_-])` — without it the prose word
#     "Cross-plugin:" yields a phantom `ross-plugin:`. The class must exclude
#     UPPER case too; `[^a-z0-9_-]` still matches the `C` and re-admits it.
#   * NON-EMPTY NAME `[a-z0-9-]+` — a bare `<plugin>:` prefix is not a
#     citation. Without the `+`, the changelog heading `**testing-plugin:**`
#     and the shell line `echo "macos-plugin: not Darwin"` both register as
#     dead IDs (7 of the 9 false positives on the first run).
# The leading boundary character is captured by `grep -o` and stripped after;
# it is never `[a-z]`, so `s/^[^a-z]+//` cannot eat part of a real ID.
id_re='(^|[^A-Za-z0-9_-])[a-z][a-z0-9-]*-plugin:[a-z0-9-]+'

# Enter the scan root before discovery so the relative paths `find .` emits
# resolve for the reads below too. A discovery subshell that cd'd while the
# consumer ran in the caller's cwd is the silent no-scan class of #2219/#2290.
cd "$repo_root" || exit 1

# Allowlist of citation PREFIXES that are correct despite not resolving. Each
# entry is a `case` glob matched against the extracted ID.
allowlist=(
  # `my-plugin:` is the placeholder namespace used by authoring examples
  # (agent-development.md, obsidian dev-tools). It names no real plugin by
  # design — a doc showing "how to cite a skill" needs a stand-in.
  'my-plugin:*'

  # A trailing `-` is the extractor hitting a glob form in prose, e.g.
  # `typescript-plugin:bun-*` in regression-testing.md, which cites a FAMILY
  # of skills rather than one ID. The bare stem never resolves and should not.
  '*-'
)

allowed() {
  local id="$1" pat
  for pat in "${allowlist[@]}"; do
    # shellcheck disable=SC2254  # glob matching of $pat is intentional
    case "$id" in
      $pat) return 0 ;;
    esac
  done
  return 1
}

# Build ground truth. A plain sorted file + `grep -qxF` keeps this working on
# bash 3.2 (macOS default), which has no associative arrays.
truth="$(mktemp)"
trap 'rm -f "$truth"' EXIT

{
  find . -type f -name 'SKILL.md' \
    -not -path './.claude/worktrees/*' -not -path './dist/*' \
    -not -path '*/node_modules/*' -print |
    sed -n 's#^\./\([^/]*\)/skills/\([^/]*\)/SKILL\.md$#\1:\2#p'
  find . -type f -name '*.md' -path '*/agents/*' \
    -not -path './.claude/worktrees/*' -not -path './dist/*' \
    -not -path '*/node_modules/*' -print |
    sed -n 's#^\./\([^/]*\)/agents/\([^/]*\)\.md$#\1:\2#p'
} | sort -u >"$truth"

truth_count="$(wc -l <"$truth" | tr -d ' ')"

# A ground truth of zero means the walk found nothing — a broken scan, not a
# clean tree. Fail loudly rather than pass every citation by vacuous default
# (the empty-negative trap: an unrun check and a passing check look identical).
if [ "$truth_count" -eq 0 ]; then
  printf "ERROR: resolved 0 skills/agents on disk -- the discovery walk is broken, not the tree clean\n" >&2
  exit 1
fi

while IFS= read -r -d '' file; do
  while IFS=: read -r line_no content; do
    # Blockquote callouts cite dead IDs on purpose.
    case "$content" in
      '>'* | *[[:space:]]'>'*) continue ;;
    esac
    # A single line may carry several citations.
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      allowed "$id" && continue
      grep -qxF "$id" "$truth" && continue
      printf "ERROR [dead-skill-reference]: %s:%s\n" "${file#./}" "$line_no"
      printf "  Found: %s\n" "$id"
      # Offer the closest surviving ID under the same plugin, if there is one.
      plugin="${id%%:*}"
      name="${id#*:}"
      suggestion="$(grep "^${plugin}:" "$truth" | grep -- "$name" | head -1 || true)"
      if [ -n "$suggestion" ]; then
        printf "  Fix:   did you mean %s ?\n\n" "$suggestion"
      else
        printf "  Fix:   no skill or agent with this ID exists; check %s/skills/ and %s/agents/\n\n" "$plugin" "$plugin"
      fi
      errors=$((errors + 1))
    done < <(printf '%s\n' "$content" | grep -oE "$id_re" | sed -E 's/^[^a-z]+//' || true)
  done < <(grep -nE "$id_re" "$file" || true)
# dist/ is gitignored OpenCode export output and worktree clones are copies of
# sources already scanned — findings there have no fix site. Same pruning as
# lint-mcp-tool-references.sh.
done < <(find . -type f \
  \( -name 'SKILL.md' -o -name 'skill.md' -o -name 'REFERENCE.md' \
  -o -name '*.workflow.js' -o -path './.claude/rules/*.md' \) \
  -not -path './.claude/worktrees/*' \
  -not -path './dist/*' \
  -not -path '*/node_modules/*' \
  -print0)

if [ "$errors" -gt 0 ]; then
  printf "Found %d dead skill/agent reference(s) against %s IDs on disk\n" "$errors" "$truth_count"
  exit 1
fi

printf "All skill/agent references resolve (%s IDs on disk)\n" "$truth_count"
exit 0
