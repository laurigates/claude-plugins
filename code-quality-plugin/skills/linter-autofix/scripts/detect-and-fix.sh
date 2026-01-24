#!/usr/bin/env bash
# Linter Autofix Detection and Execution Script
# Auto-detects project linters and runs appropriate autofix commands.
# Usage: bash detect-and-fix.sh [--check-only] [path]
#
# Replaces manual project type detection + linter selection with one call.
# Outputs structured results showing what was fixed.

set -uo pipefail

CHECK_ONLY=false
TARGET_PATH="."

for arg in "$@"; do
  case "$arg" in
    --check-only) CHECK_ONLY=true ;;
    *) TARGET_PATH="$arg" ;;
  esac
done

cd "$TARGET_PATH"

echo "=== LINTER DETECTION ==="

declare -a DETECTED_LINTERS=()
declare -a FIX_COMMANDS=()
declare -a CHECK_COMMANDS=()

# JavaScript/TypeScript: Biome
if [ -f "biome.json" ] || [ -f "biome.jsonc" ]; then
  DETECTED_LINTERS+=("biome")
  FIX_COMMANDS+=("npx @biomejs/biome check --write .")
  CHECK_COMMANDS+=("npx @biomejs/biome check --reporter=github --max-diagnostics=20 .")
fi

# JavaScript/TypeScript: ESLint
if [ -f ".eslintrc" ] || [ -f ".eslintrc.js" ] || [ -f ".eslintrc.json" ] || [ -f "eslint.config.js" ] || [ -f "eslint.config.mjs" ]; then
  DETECTED_LINTERS+=("eslint")
  FIX_COMMANDS+=("npx eslint --fix .")
  CHECK_COMMANDS+=("npx eslint --format=unix --max-warnings=0 .")
fi

# JavaScript/TypeScript: Prettier (formatter only)
if [ -f ".prettierrc" ] || [ -f ".prettierrc.json" ] || [ -f "prettier.config.js" ] || [ -f "prettier.config.mjs" ]; then
  DETECTED_LINTERS+=("prettier")
  FIX_COMMANDS+=("npx prettier --write .")
  CHECK_COMMANDS+=("npx prettier --check .")
fi

# Python: Ruff
if [ -f "ruff.toml" ] || [ -f ".ruff.toml" ] || ([ -f "pyproject.toml" ] && grep -q "\[tool.ruff\]" pyproject.toml 2>/dev/null); then
  DETECTED_LINTERS+=("ruff")
  FIX_COMMANDS+=("ruff check --fix . && ruff format .")
  CHECK_COMMANDS+=("ruff check --output-format=github . && ruff format --check .")
fi

# Python: Black (if no ruff)
if [ -f "pyproject.toml" ] && grep -q "\[tool.black\]" pyproject.toml 2>/dev/null && ! printf '%s\n' "${DETECTED_LINTERS[@]}" | grep -q "ruff"; then
  DETECTED_LINTERS+=("black")
  FIX_COMMANDS+=("black .")
  CHECK_COMMANDS+=("black --check .")
fi

# Python: isort (if no ruff)
if [ -f "pyproject.toml" ] && grep -q "\[tool.isort\]" pyproject.toml 2>/dev/null && ! printf '%s\n' "${DETECTED_LINTERS[@]}" | grep -q "ruff"; then
  DETECTED_LINTERS+=("isort")
  FIX_COMMANDS+=("isort .")
  CHECK_COMMANDS+=("isort --check-only .")
fi

# Rust: Clippy + rustfmt
if [ -f "Cargo.toml" ]; then
  DETECTED_LINTERS+=("clippy")
  FIX_COMMANDS+=("cargo clippy --fix --allow-dirty --allow-staged 2>&1 | tail -20")
  CHECK_COMMANDS+=("cargo clippy --message-format=short 2>&1 | tail -20")
  DETECTED_LINTERS+=("rustfmt")
  FIX_COMMANDS+=("cargo fmt")
  CHECK_COMMANDS+=("cargo fmt --check")
fi

# Go: gofmt + go vet
if [ -f "go.mod" ]; then
  DETECTED_LINTERS+=("gofmt")
  FIX_COMMANDS+=("gofmt -w .")
  CHECK_COMMANDS+=("gofmt -l .")
  DETECTED_LINTERS+=("govet")
  FIX_COMMANDS+=("go vet ./...")
  CHECK_COMMANDS+=("go vet ./...")
fi

# Go: golangci-lint
if [ -f ".golangci.yml" ] || [ -f ".golangci.yaml" ]; then
  DETECTED_LINTERS+=("golangci-lint")
  FIX_COMMANDS+=("golangci-lint run --fix ./...")
  CHECK_COMMANDS+=("golangci-lint run ./...")
fi

# Shell: ShellCheck (check-only, no autofix)
if command -v shellcheck >/dev/null 2>&1; then
  sh_files=$(find . -maxdepth 3 -name "*.sh" ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | head -1)
  if [ -n "$sh_files" ]; then
    DETECTED_LINTERS+=("shellcheck")
    FIX_COMMANDS+=("echo 'shellcheck: no autofix available (check-only)'")
    CHECK_COMMANDS+=("find . -maxdepth 3 -name '*.sh' ! -path '*/node_modules/*' -exec shellcheck -f gcc {} + 2>/dev/null | head -20")
  fi
fi

# Report detection results
echo "DETECTED: ${DETECTED_LINTERS[*]:-none}"
echo ""

if [ ${#DETECTED_LINTERS[@]} -eq 0 ]; then
  echo "NO_LINTERS_FOUND=true"
  echo "HINT: No linter configuration files detected in this project."
  echo "=== DONE ==="
  exit 0
fi

# Execute
echo "=== EXECUTION ==="

exit_code=0
for i in "${!DETECTED_LINTERS[@]}"; do
  linter="${DETECTED_LINTERS[$i]}"
  echo "--- ${linter} ---"

  if [ "$CHECK_ONLY" = true ]; then
    cmd="${CHECK_COMMANDS[$i]}"
    echo "CMD: $cmd"
    eval "$cmd" 2>&1 | head -30
  else
    cmd="${FIX_COMMANDS[$i]}"
    echo "CMD: $cmd"
    eval "$cmd" 2>&1 | head -30
  fi

  cmd_exit=$?
  echo "EXIT: $cmd_exit"
  [ $cmd_exit -ne 0 ] && exit_code=$cmd_exit
  echo ""
done

echo "=== RESULTS ==="
echo "OVERALL_EXIT=$exit_code"

# Show what files changed (if fixing)
if [ "$CHECK_ONLY" = false ]; then
  changed=$(git diff --name-only 2>/dev/null | head -20)
  if [ -n "$changed" ]; then
    echo "FILES_MODIFIED:"
    echo "$changed" | sed 's/^/  - /'
  else
    echo "FILES_MODIFIED: none"
  fi
fi

echo "=== DONE ==="
exit $exit_code
