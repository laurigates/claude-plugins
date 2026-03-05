#!/usr/bin/env bash
# Lint all shell scripts for compliance with shell-scripting.md standards
#
# Checks:
# 1. Shebang: must be #!/usr/bin/env bash (not #!/bin/bash)
# 2. Error handling: must have set -euo pipefail (or documented variant)
# 3. Block function: hook scripts using exit 2 should use block() function
# 4. Variable naming: TOOL_NAME not TOOL for tool name extraction
#
# Usage: bash scripts/lint-shell-scripts.sh [--fix]
#        --fix  auto-fix shebang issues (other issues require manual fixes)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIX_MODE="${1:-}"

ERRORS=0
WARNINGS=0

error() {
    echo "ERROR: $1" >&2
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo "WARN:  $1" >&2
    WARNINGS=$((WARNINGS + 1))
}

info() {
    echo "INFO:  $1"
}

# Find all .sh files, excluding node_modules, .git, vendor
SCRIPTS=$(find "$ROOT_DIR" -name "*.sh" \
    -not -path "*/.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/vendor/*" \
    | sort)

for script in $SCRIPTS; do
    REL_PATH="${script#"$ROOT_DIR"/}"

    # Skip ShellSpec test files — framework manages execution environment
    if echo "$REL_PATH" | grep -qE '/spec/.*_spec\.sh$|/spec/spec_helper\.sh$'; then
        continue
    fi

    # --- Check 1: Shebang ---
    SHEBANG=$(head -1 "$script")
    if [ "$SHEBANG" = "#!/bin/bash" ]; then
        if [ "$FIX_MODE" = "--fix" ]; then
            sed -i '1s|^#!/bin/bash|#!/usr/bin/env bash|' "$script"
            info "$REL_PATH: Fixed shebang"
        else
            error "$REL_PATH: Uses #!/bin/bash instead of #!/usr/bin/env bash"
        fi
    elif [ "$SHEBANG" != "#!/usr/bin/env bash" ]; then
        # Allow non-bash scripts (e.g., python, sh) — skip remaining checks
        continue
    fi

    # --- Check 2: Error handling flags ---
    if ! grep -qE '^set -[a-z]*[euo]' "$script"; then
        # Distinguish hook scripts (which must have set flags) from other scripts
        if echo "$REL_PATH" | grep -qE '/hooks/'; then
            error "$REL_PATH: Missing 'set -euo pipefail' (or documented variant)"
        else
            warn "$REL_PATH: Missing 'set -euo pipefail' (recommended)"
        fi
    fi

    # --- Check 3: Block function consistency (hook scripts only) ---
    if echo "$REL_PATH" | grep -qE '/hooks/'; then
        # Check for non-standard block function names
        if grep -qE '^block_(with_reminder|error)\(\)' "$script"; then
            FUNC_NAME=$(grep -oE 'block_(with_reminder|error)' "$script" | head -1)
            error "$REL_PATH: Uses non-standard '${FUNC_NAME}()' — rename to 'block()'"
        fi

        # Check for inline exit 2 without block() function
        if grep -qE 'exit 2' "$script" && ! grep -qE '^block\(\)' "$script"; then
            # Only flag if there's an echo >&2 + exit 2 pattern (inline blocking)
            if grep -qE 'echo .* >&2' "$script" && grep -qE '^\s*exit 2' "$script"; then
                warn "$REL_PATH: Has inline 'echo >&2; exit 2' — consider extracting block() function"
            fi
        fi
    fi

    # --- Check 4: Variable naming ---
    if grep -qE '^\s*TOOL=\$\(.*jq.*tool_name' "$script"; then
        error "$REL_PATH: Uses 'TOOL' variable — rename to 'TOOL_NAME'"
    fi
done

echo ""
echo "Shell script lint: ${ERRORS} error(s), ${WARNINGS} warning(s)"

if [ "$ERRORS" -gt 0 ]; then
    echo "Run with --fix to auto-fix shebang issues."
    exit 1
fi

exit 0
