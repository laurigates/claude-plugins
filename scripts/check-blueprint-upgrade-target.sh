#!/usr/bin/env bash
set -euo pipefail

# check-blueprint-upgrade-target.sh
#
# Regression check: ensure blueprint-upgrade/SKILL.md advertises the latest
# format version implied by the migration documents in
# blueprint-plugin/skills/blueprint-migration/migrations/.
#
# Bug fixed: PR #1026 added monorepo support via migrations/v3.2-to-v3.3.md,
# but blueprint-upgrade/SKILL.md still said v3.2.0 was the latest. Users
# running /blueprint:upgrade were told they were up to date when they
# were not.
#
# This script fails (exit 1) if:
#   - The highest migration target version is not set as
#     `**Current Format Version**: X.Y.Z` in blueprint-upgrade/SKILL.md
#   - That version is missing from the `target="X.Y.Z"` assignment
#   - That version is not present in the Version compatibility matrix
#
# Usage: bash scripts/check-blueprint-upgrade-target.sh

cd "$(dirname "$0")/.." || exit 1

migrations_dir="blueprint-plugin/skills/blueprint-migration/migrations"
upgrade_skill="blueprint-plugin/skills/blueprint-upgrade/SKILL.md"

if [ ! -d "$migrations_dir" ]; then
  echo "ERROR: migrations directory not found: $migrations_dir" >&2
  exit 2
fi

if [ ! -f "$upgrade_skill" ]; then
  echo "ERROR: upgrade skill not found: $upgrade_skill" >&2
  exit 2
fi

# Extract target versions from migration filenames (vA.B-to-vX.Y.md or vA.x-to-vX.Y.md).
# We only care about the right-hand "to" version.
#
# sort -V gives correct semver-ish ordering for X.Y.Z strings.
latest_target=$(
  find "$migrations_dir" -maxdepth 1 -type f -name 'v*-to-v*.md' -print \
    | sed -E 's|.*-to-v([0-9]+\.[0-9]+)(\.md)$|\1.0|; s|.*-to-v([0-9]+\.[0-9]+\.[0-9]+)\.md$|\1|' \
    | sort -V \
    | tail -n1
)

if [ -z "$latest_target" ]; then
  echo "ERROR: could not infer latest target version from $migrations_dir" >&2
  exit 2
fi

# Normalize to X.Y.Z (migration filenames sometimes drop the patch).
if ! [[ "$latest_target" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  latest_target="${latest_target}.0"
fi

failures=0

check_pattern() {
  local label="$1"
  local pattern="$2"
  if ! grep -qE "$pattern" "$upgrade_skill"; then
    echo "FAIL: $label"
    echo "  Expected pattern: $pattern"
    echo "  File: $upgrade_skill"
    failures=$((failures + 1))
  fi
}

# 1. Current Format Version line must match the latest migration target.
check_pattern \
  "Current Format Version header advertises v${latest_target}" \
  "^\*\*Current Format Version\*\*: ${latest_target}$"

# 2. The target= shell assignment inside step 2 must match.
check_pattern \
  "target=\"${latest_target}\" assignment present in step 2" \
  "target=\"${latest_target}\""

# 3. The version compatibility matrix must include the latest version.
check_pattern \
  "Compatibility matrix includes row for v${latest_target}" \
  "\| *${latest_target} *\| *${latest_target} *\| *Already up to date"

if [ "$failures" -eq 0 ]; then
  echo "OK: blueprint-upgrade/SKILL.md is in sync with migrations (latest: v${latest_target})"
  exit 0
fi

cat <<EOF >&2

Detected $failures drift(s) between migrations/ and blueprint-upgrade/SKILL.md.
Latest migration target: v${latest_target}

Fix by updating these locations in $upgrade_skill:
  - Header:     **Current Format Version**: ${latest_target}
  - Step 2:     target="${latest_target}"
  - Matrix:     | ${latest_target} | ${latest_target} | Already up to date |
  - Add a delegation step pointing at the corresponding migration document.

See .claude/rules/regression-testing.md for the prevention rationale.
EOF

exit 1
