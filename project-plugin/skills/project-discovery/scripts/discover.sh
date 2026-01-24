#!/usr/bin/env bash
# Project Discovery Script
# Consolidates the 5-phase discovery workflow into a single execution.
# Outputs structured text that Claude can parse efficiently.
# Usage: bash discover.sh [directory]
#
# Replaces ~20 individual tool calls with one script execution,
# saving tokens and providing consistent output format.

set -euo pipefail

TARGET_DIR="${1:-.}"
cd "$TARGET_DIR"

# Phase 1: Git State Analysis
echo "=== PHASE 1: GIT STATE ==="

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "NOT_A_GIT_REPO=true"
  echo "=== END PHASE 1 ==="
  echo ""
  echo "=== DISCOVERY COMPLETE ==="
  exit 0
fi

current_branch=$(git branch --show-current 2>/dev/null || echo "DETACHED")
echo "BRANCH=$current_branch"

git_status=$(git status --porcelain 2>/dev/null)
staged_count=$(echo "$git_status" | grep -c "^[MADRC]" 2>/dev/null || echo "0")
unstaged_count=$(echo "$git_status" | grep -c "^.[MADRC?]" 2>/dev/null || echo "0")
untracked_count=$(echo "$git_status" | grep -c "^??" 2>/dev/null || echo "0")
echo "STAGED=$staged_count"
echo "UNSTAGED=$unstaged_count"
echo "UNTRACKED=$untracked_count"
echo "CLEAN=$([ -z "$git_status" ] && echo "true" || echo "false")"

# Remote sync
if git rev-parse --verify "@{u}" >/dev/null 2>&1; then
  ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo "0")
  behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo "0")
  echo "AHEAD=$ahead"
  echo "BEHIND=$behind"
else
  echo "NO_UPSTREAM=true"
fi

# Recent commits
echo "RECENT_COMMITS:"
git log --oneline --decorate -n 5 2>/dev/null | sed 's/^/  /'

# Conventional commits detection
conv_count=$(git log --oneline -n 20 2>/dev/null | grep -cE "^[a-f0-9]+ (feat|fix|docs|style|refactor|test|chore|build|ci|perf|revert)(\(.+\))?:" || echo "0")
echo "CONVENTIONAL_COMMITS=$conv_count/20"

# Last commit info
last_commit=$(git log -1 --format='%H|%s|%an|%ar' 2>/dev/null || echo "")
echo "LAST_COMMIT=$last_commit"

# Risk flags
echo "RISK_FLAGS:"
[ "$current_branch" = "main" ] || [ "$current_branch" = "master" ] && [ -n "$git_status" ] && echo "  - ON_MAIN_WITH_CHANGES"
[ "$current_branch" = "DETACHED" ] && echo "  - DETACHED_HEAD"
[ "${behind:-0}" -gt 0 ] && echo "  - BEHIND_REMOTE_BY_${behind}"
[ -n "$git_status" ] && echo "  - UNCOMMITTED_CHANGES"

echo "=== END PHASE 1 ==="
echo ""

# Phase 2: Project Type Detection
echo "=== PHASE 2: PROJECT TYPE ==="

echo "MANIFESTS:"
for manifest in package.json Cargo.toml pyproject.toml go.mod Gemfile pom.xml build.gradle composer.json mix.exs deno.json bun.lockb; do
  [ -f "$manifest" ] && echo "  - $manifest"
done

# Detect monorepo
manifest_count=$(find . -maxdepth 3 \( -name "package.json" -o -name "Cargo.toml" -o -name "pyproject.toml" -o -name "go.mod" \) ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | wc -l)
echo "MANIFEST_COUNT=$manifest_count"
echo "MONOREPO=$([ "$manifest_count" -gt 2 ] && echo "likely" || echo "no")"

# Language detection
echo "LANGUAGES:"
[ -f "package.json" ] && echo "  - javascript/typescript"
[ -f "Cargo.toml" ] && echo "  - rust"
[ -f "pyproject.toml" ] || [ -f "setup.py" ] && echo "  - python"
[ -f "go.mod" ] && echo "  - go"
[ -f "Gemfile" ] && echo "  - ruby"
[ -f "pom.xml" ] || [ -f "build.gradle" ] && echo "  - java"
[ -f "composer.json" ] && echo "  - php"
[ -f "mix.exs" ] && echo "  - elixir"

# Framework detection
echo "FRAMEWORKS:"
if [ -f "package.json" ]; then
  for fw in react vue next nuxt svelte angular express fastify nest remix astro; do
    grep -q "\"$fw\"" package.json 2>/dev/null && echo "  - $fw"
  done
fi
if [ -f "pyproject.toml" ]; then
  for fw in django fastapi flask pyramid; do
    grep -qi "$fw" pyproject.toml 2>/dev/null && echo "  - $fw"
  done
fi

# Directory structure
echo "TOP_DIRS:"
ls -d */ 2>/dev/null | head -15 | sed 's/^/  - /'

echo "=== END PHASE 2 ==="
echo ""

# Phase 3: Development Tooling
echo "=== PHASE 3: TOOLING ==="

# Package scripts
if [ -f "package.json" ]; then
  echo "NPM_SCRIPTS:"
  jq -r '.scripts | keys[]' package.json 2>/dev/null | head -20 | sed 's/^/  - /' || true
fi

# Makefile targets
if [ -f "Makefile" ]; then
  echo "MAKE_TARGETS:"
  grep -E "^[a-zA-Z0-9_-]+:" Makefile 2>/dev/null | cut -d: -f1 | head -15 | sed 's/^/  - /'
fi

# Justfile targets
if [ -f "Justfile" ] || [ -f "justfile" ]; then
  echo "JUST_TARGETS:"
  just --list --unsorted 2>/dev/null | tail -n +2 | head -15 | sed 's/^/  - /' || grep -E "^[a-zA-Z0-9_-]+:" [Jj]ustfile 2>/dev/null | cut -d: -f1 | head -15 | sed 's/^/  - /'
fi

# Linters/formatters
echo "CODE_QUALITY:"
for tool in .eslintrc .eslintrc.js .eslintrc.json eslint.config.js eslint.config.mjs biome.json biome.jsonc .prettierrc .prettierrc.json prettier.config.js ruff.toml .ruff.toml rustfmt.toml .golangci.yml .golangci.yaml; do
  [ -f "$tool" ] && echo "  - $tool"
done
[ -f "pyproject.toml" ] && grep -q "\[tool.ruff\]" pyproject.toml 2>/dev/null && echo "  - ruff (in pyproject.toml)"
[ -f "pyproject.toml" ] && grep -q "\[tool.black\]" pyproject.toml 2>/dev/null && echo "  - black (in pyproject.toml)"

# Test frameworks
echo "TEST_CONFIG:"
for cfg in vitest.config.ts vitest.config.js jest.config.ts jest.config.js pytest.ini conftest.py .pytest.ini setup.cfg playwright.config.ts cypress.config.ts; do
  [ -f "$cfg" ] && echo "  - $cfg"
done
[ -f "pyproject.toml" ] && grep -q "\[tool.pytest" pyproject.toml 2>/dev/null && echo "  - pytest (in pyproject.toml)"

# Pre-commit
echo "PRE_COMMIT:"
if [ -f ".pre-commit-config.yaml" ]; then
  echo "  CONFIGURED=true"
  grep -E "^\s+- id:" .pre-commit-config.yaml 2>/dev/null | sed 's/.*- id:/  -/' | head -10
else
  echo "  CONFIGURED=false"
fi

# CI/CD
echo "CI_CD:"
if [ -d ".github/workflows" ]; then
  ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null | xargs -I{} basename {} | sed 's/^/  - github: /'
fi
[ -f ".gitlab-ci.yml" ] && echo "  - gitlab-ci"
[ -f ".circleci/config.yml" ] && echo "  - circleci"
[ -f "Jenkinsfile" ] && echo "  - jenkins"

echo "=== END PHASE 3 ==="
echo ""

# Phase 4: Documentation
echo "=== PHASE 4: DOCUMENTATION ==="

echo "DOC_FILES:"
for doc in README.md README.rst README.txt CONTRIBUTING.md CHANGELOG.md LICENSE LICENSE.md ARCHITECTURE.md SECURITY.md; do
  [ -f "$doc" ] && echo "  - $doc"
done
[ -d "docs" ] && echo "  - docs/ ($(find docs -type f 2>/dev/null | wc -l) files)"

# README summary (first meaningful line)
if [ -f "README.md" ]; then
  echo "README_TITLE: $(head -5 README.md | grep -m1 "^#" | sed 's/^#* //')"
  echo "README_LINES: $(wc -l < README.md)"
fi

echo "=== END PHASE 4 ==="
echo ""

# Phase 5: Summary
echo "=== PHASE 5: SUMMARY ==="

# Determine risk level
risk_level="SAFE"
[ -n "$git_status" ] && risk_level="WARNING"
[ "$current_branch" = "main" ] || [ "$current_branch" = "master" ] && [ -n "$git_status" ] && risk_level="CRITICAL"
[ "$current_branch" = "DETACHED" ] && risk_level="CRITICAL"
echo "RISK_LEVEL=$risk_level"

echo "=== DISCOVERY COMPLETE ==="
