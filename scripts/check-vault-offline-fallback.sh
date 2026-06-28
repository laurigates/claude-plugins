#!/usr/bin/env bash
# Verify every obsidian-plugin vault-* audit skill documents an offline,
# app-closed data-source path, and that the CLI-bound search-discovery skill
# points readers at that offline path.
#
# Background: the read-only vault audit skills (vault-orphans, vault-wikilinks,
# vault-mocs, vault-tags, vault-stubs) describe a sound detection methodology,
# but several leaned on the `obsidian` CLI / vault-agent analyzers, which need
# the Obsidian app running. With the app closed the CLI errors and the whole
# audit family is unusable for batch / headless work. The fix documents the
# direct `.md`-parsing fallback (frontmatter + [[wikilink]] resolution) the
# `vault-frontmatter` skill already models — see issue #1727.
#
# This is a SEMANTIC gate (per .claude/rules/regression-testing.md): a bulk
# edit that "tightens" these skills could silently drop the offline section
# and revert the app-closed regression. The check asserts the load-bearing
# marker survives.
#
# What counts as compliant:
#   - Each of the five audit skills contains a literal
#     `## Offline Fallback (App Closed)` heading whose body names the
#     `.md`-parsing source (mentions `live-index` and `headless`, the
#     framing that distinguishes the two data sources — catches a stub
#     heading).
#   - search-discovery (CLI-bound) contains an `## Offline Limitation`
#     heading and points at the vault-* audit skills.
#
# Usage:
#   bash scripts/check-vault-offline-fallback.sh
#
# Exit codes:
#   0 - all skills document the offline path
#   1 - one or more skills missing the offline section / pointer

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

skill_dir="obsidian-plugin/skills"
audit_skills=(vault-orphans vault-wikilinks vault-mocs vault-tags vault-stubs)

errors=0
checked=0

require() {
  # require <file> <grep-pattern> <human-description>
  local file="$1" pattern="$2" desc="$3"
  if ! grep -qF -- "$pattern" "$file"; then
    echo "❌ $file: missing $desc" >&2
    errors=$((errors + 1))
    return 1
  fi
  return 0
}

for skill in "${audit_skills[@]}"; do
  file="$skill_dir/$skill/SKILL.md"
  if [ ! -f "$file" ]; then
    echo "❌ $file: not found" >&2
    errors=$((errors + 1))
    continue
  fi
  checked=$((checked + 1))

  require "$file" "## Offline Fallback (App Closed)" "the 'Offline Fallback (App Closed)' section (#1727)" || continue
  # Coarse content sniff: the section must frame the two data sources, not be
  # a stub heading.
  require "$file" "live-index" "the live-index vs headless framing in the offline section" || continue
  require "$file" "headless" "the 'headless' default framing in the offline section" || continue
done

# search-discovery is CLI-bound: it must document the limitation and point at
# the offline audit-skill path rather than carry its own fallback.
sd="$skill_dir/search-discovery/SKILL.md"
if [ ! -f "$sd" ]; then
  echo "❌ $sd: not found" >&2
  errors=$((errors + 1))
else
  checked=$((checked + 1))
  require "$sd" "## Offline Limitation" "the 'Offline Limitation' section (#1727)" || true
  require "$sd" "offline file-parsing path" "the pointer to the offline file-parsing path" || true
fi

if [ $errors -gt 0 ]; then
  echo "" >&2
  echo "Found $errors issue(s) across $checked vault skill file(s)." >&2
  echo "Each vault-* audit skill must document an offline (app-closed) data" >&2
  echo "source, and search-discovery must point at it — see issue #1727." >&2
  exit 1
fi

echo "All $checked vault skill file(s) document an offline path. ✅"
exit 0
