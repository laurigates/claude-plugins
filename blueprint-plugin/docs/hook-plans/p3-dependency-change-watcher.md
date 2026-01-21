# P3: Dependency Change Watcher Hook

**Priority**: P3 (Future)
**Type**: PostToolUse
**Status**: Planned

## Overview

Detect when package manager lock files change and warn if any ai_docs may be affected by dependency updates. Helps maintain documentation freshness by surfacing when library versions change.

## Trigger

```json
{
  "matcher": "Edit(bun.lockb)|Edit(uv.lock)|Edit(Cargo.lock)",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/check-dependency-drift.sh",
      "timeout": 5000,
      "continueOnError": true
    }
  ]
}
```

**Supported Package Managers:**

| Package Manager | Lock File | Manifest |
|-----------------|-----------|----------|
| Bun | `bun.lockb` | `package.json` |
| uv | `uv.lock` | `pyproject.toml` |
| Cargo | `Cargo.lock` | `Cargo.toml` |

## Behavior

### Input

JSON from PostToolUse containing:
- `tool_input.file_path`: Path to the lock file that changed

### Processing

1. **Identify the package manager**
   ```bash
   detect_package_manager() {
     local file="$1"
     case "$file" in
       *bun.lockb*) echo "bun" ;;
       *uv.lock*) echo "uv" ;;
       *Cargo.lock*) echo "cargo" ;;
       *) echo "unknown" ;;
     esac
   }
   ```

2. **Extract changed dependencies**
   - For Bun: Parse lockfile changes
   - For uv: Parse TOML lock file
   - For Cargo: Parse TOML lock file

3. **Check for ai_docs referencing changed packages**
   ```bash
   find_affected_ai_docs() {
     local package="$1"
     local ai_docs_dir="docs/blueprint/ai_docs"

     [ ! -d "$ai_docs_dir" ] && return

     # Search for ai_docs mentioning this package
     grep -rl "$package" "$ai_docs_dir" 2>/dev/null | while read doc; do
       echo "$doc"
     done
   }
   ```

4. **Warn about potentially outdated docs**

### Output

```
INFO: Detected dependency changes in Bun project
WARNING: Package 'react' upgraded: 18.2.0 → 19.0.0
WARNING: ai_docs/libraries/react.md may need review
INFO: Consider running /blueprint:curate-docs react to refresh documentation
```

## Lock File Parsing

### Bun (bun.lockb)

Bun's lockfile is binary. Parse via bun CLI:

```bash
parse_bun_lock() {
  # Get current dependencies
  bun pm ls --json 2>/dev/null | jq -r '
    .dependencies | to_entries[] | "\(.key)@\(.value.version)"
  '
}
```

**Note**: Direct diff of bun.lockb isn't practical. Compare manifest (package.json) changes instead, or use `bun pm ls` before/after.

### uv (uv.lock)

uv uses TOML format:

```bash
parse_uv_lock() {
  local lockfile="$1"
  # Extract package versions from uv.lock
  grep -E "^name = |^version = " "$lockfile" | paste - - | \
    sed 's/name = "\([^"]*\)".* version = "\([^"]*\)"/\1@\2/'
}
```

### Cargo (Cargo.lock)

Cargo uses TOML format:

```bash
parse_cargo_lock() {
  local lockfile="$1"
  # Extract package versions
  grep -E "^name = |^version = " "$lockfile" | paste - - | \
    sed 's/name = "\([^"]*\)".*version = "\([^"]*\)"/\1@\2/'
}
```

## Diff Detection Strategy

Since hooks run after changes, we need to detect what changed:

### Option A: Git Diff

```bash
detect_changed_deps() {
  local lockfile="$1"
  local pkg_manager="$2"

  # Get git diff of lockfile
  git diff HEAD~1 -- "$lockfile" 2>/dev/null || return 1

  # Parse diff based on package manager
  case "$pkg_manager" in
    uv|cargo)
      git diff HEAD~1 -- "$lockfile" | \
        grep -E "^\+.*version = " | \
        sed 's/.*"\([^"]*\)"/\1/'
      ;;
    bun)
      # For binary lockfile, compare package.json instead
      git diff HEAD~1 -- package.json | \
        grep -E '^\+.*":' | \
        sed 's/.*"\([^"]*\)": "\([^"]*\)".*/\1@\2/'
      ;;
  esac
}
```

### Option B: Snapshot Comparison

Store a snapshot of dependencies after each successful run:

```bash
SNAPSHOT_FILE=".blueprint/dep-snapshot.json"

# Save current state
save_snapshot() {
  local pkg_manager="$1"
  case "$pkg_manager" in
    bun) bun pm ls --json > "$SNAPSHOT_FILE" ;;
    uv) parse_uv_lock uv.lock > "$SNAPSHOT_FILE" ;;
    cargo) parse_cargo_lock Cargo.lock > "$SNAPSHOT_FILE" ;;
  esac
}

# Compare with snapshot
compare_snapshot() {
  local current="$1"
  local previous="$SNAPSHOT_FILE"
  [ ! -f "$previous" ] && return

  diff "$previous" <(echo "$current") | grep "^>" | sed 's/^> //'
}
```

## ai_docs Mapping

### By Library Name

Map common packages to ai_docs:

```bash
# docs/blueprint/ai_docs/libraries/
# react.md, vue.md, typescript.md, etc.

find_matching_ai_doc() {
  local package="$1"
  local ai_docs="docs/blueprint/ai_docs/libraries"

  # Direct match
  if [ -f "$ai_docs/${package}.md" ]; then
    echo "$ai_docs/${package}.md"
    return
  fi

  # Fuzzy match (e.g., @types/react -> react.md)
  local base=$(echo "$package" | sed 's/@[^/]*\///' | sed 's/@.*//')
  if [ -f "$ai_docs/${base}.md" ]; then
    echo "$ai_docs/${base}.md"
    return
  fi
}
```

### By Content Search

Search ai_docs for package references:

```bash
find_ai_docs_mentioning() {
  local package="$1"
  grep -rl "$package" docs/blueprint/ai_docs/ 2>/dev/null
}
```

## Implementation

### check-dependency-drift.sh

```bash
#!/bin/bash
set -euo pipefail

# Check for bypass
if [ "${BLUEPRINT_SKIP_HOOKS:-0}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Detect package manager
case "$FILE_PATH" in
  *bun.lockb*|*package.json*)
    PKG_MANAGER="bun"
    LOCK_FILE="bun.lockb"
    ;;
  *uv.lock*)
    PKG_MANAGER="uv"
    LOCK_FILE="uv.lock"
    ;;
  *Cargo.lock*)
    PKG_MANAGER="cargo"
    LOCK_FILE="Cargo.lock"
    ;;
  *)
    exit 0  # Not a tracked lock file
    ;;
esac

echo "INFO: Detected dependency changes in $PKG_MANAGER project" >&2

# Check if ai_docs directory exists
AI_DOCS_DIR="docs/blueprint/ai_docs"
if [ ! -d "$AI_DOCS_DIR" ]; then
    echo "INFO: No ai_docs directory found - skipping drift check" >&2
    exit 0
fi

# Get changed packages via git diff
CHANGES=$(git diff HEAD~1 -- "$LOCK_FILE" 2>/dev/null || echo "")

if [ -z "$CHANGES" ]; then
    echo "INFO: No dependency changes detected" >&2
    exit 0
fi

# Extract package names from diff (simplified)
CHANGED_PACKAGES=$(echo "$CHANGES" | grep -oE '"[a-zA-Z0-9@/_-]+"' | tr -d '"' | sort -u | head -20)

# Check each changed package for ai_docs
AFFECTED_DOCS=()
for pkg in $CHANGED_PACKAGES; do
    # Skip version numbers, common strings
    [[ "$pkg" =~ ^[0-9] ]] && continue
    [[ "$pkg" == "version" ]] && continue
    [[ "$pkg" == "name" ]] && continue

    # Check for direct ai_doc match
    if [ -f "$AI_DOCS_DIR/libraries/${pkg}.md" ]; then
        AFFECTED_DOCS+=("$AI_DOCS_DIR/libraries/${pkg}.md")
        echo "WARNING: Package '$pkg' changed - ai_docs/libraries/${pkg}.md may need review" >&2
    fi

    # Check for references in ai_docs
    REFS=$(grep -rl "$pkg" "$AI_DOCS_DIR" 2>/dev/null | head -5)
    for ref in $REFS; do
        [[ " ${AFFECTED_DOCS[*]} " =~ " $ref " ]] || AFFECTED_DOCS+=("$ref")
    done
done

if [ ${#AFFECTED_DOCS[@]} -gt 0 ]; then
    echo "INFO: Consider running /blueprint:curate-docs to refresh affected documentation" >&2
fi

exit 0
```

## Testing Strategy

### Test Cases

1. **Bun: React upgrade**
   - Input: package.json changes react 18 → 19
   - ai_docs/libraries/react.md exists
   - Expected: WARNING about react.md

2. **uv: Django upgrade**
   - Input: uv.lock shows django version change
   - ai_docs/libraries/django.md exists
   - Expected: WARNING about django.md

3. **Cargo: tokio upgrade**
   - Input: Cargo.lock shows tokio version change
   - ai_docs/libraries/tokio.md exists
   - Expected: WARNING about tokio.md

4. **No ai_docs match**
   - Input: Upgrade package with no ai_doc
   - Expected: No warning (INFO only)

5. **No ai_docs directory**
   - Input: Project without ai_docs
   - Expected: Skip check gracefully

### ShellSpec Tests

```shell
Describe "check-dependency-drift.sh"
  BeforeEach() {
    export TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    git init -q
    mkdir -p docs/blueprint/ai_docs/libraries
  }

  AfterEach() {
    cd /
    rm -rf "$TEST_DIR"
  }

  Describe "bun project"
    It "warns when ai_doc matches changed package"
      echo '{"react": "18.2.0"}' > package.json
      echo "# React Documentation" > docs/blueprint/ai_docs/libraries/react.md
      git add -A && git commit -q -m "initial"
      echo '{"react": "19.0.0"}' > package.json
      git add package.json

      input='{"tool_input": {"file_path": "package.json"}}'
      When call bash -c "echo '$input' | bash $HOOK_SCRIPT"
      The status should equal 0
      The stderr should include "WARNING"
      The stderr should include "react"
    End
  End
End
```

## Dependencies

- `jq` for JSON parsing
- `git` for diff detection
- Package manager CLIs (bun, uv, cargo) for detailed parsing

## Estimated Effort

- Implementation: High (lock file parsing complexity)
- Testing: High (multiple package managers)
- Documentation: Medium

## Open Questions

1. How to handle major version upgrades vs minor/patch?
   - **Decision**: Warn on all changes initially. Can add severity levels later.

2. Should we automatically mark ai_docs as stale?
   - **Decision**: No. Just warn and suggest action. Manual review preferred.

3. How to handle monorepos with multiple lock files?
   - **Decision**: Hook triggers per-file. Each lock file change triggers its own check.

4. Binary lock files (bun.lockb)?
   - **Decision**: Monitor package.json changes instead, or compare `bun pm ls` output.

## Future Enhancements

- **Version comparison**: Detect major vs minor vs patch changes
- **Auto-create issues**: Create GitHub issues for major upgrades
- **ai_doc refresh scheduling**: Integrate with cron/CI for periodic checks
- **Breaking change detection**: Cross-reference with library changelogs
