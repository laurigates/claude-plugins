#!/usr/bin/env bash
# Lint all shell scripts for compliance with shell-scripting.md standards
#
# Checks:
# 1. Shebang: must be #!/usr/bin/env bash (not #!/bin/bash)
# 2. Error handling: must have set -euo pipefail (or documented variant)
# 3. Block function: hook scripts using exit 2 should use block() function
# 4. Variable naming: TOOL_NAME not TOOL for tool name extraction
# 5. Portable in-place sed: neither the BSD-only nor the GNU-only spelling
#    of an in-place edit, since these scripts run on macOS and on CI runners
#
# Usage: bash scripts/lint-shell-scripts.sh [--fix] [ROOT_DIR]
#        --fix      auto-fix shebang issues (other issues require manual fixes)
#        ROOT_DIR   optional directory to scan (default: repo root). Used by the
#                   regression test to point the linter at fixture trees.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FIX_MODE=""
ROOT_OVERRIDE=""
for arg in "$@"; do
    case "$arg" in
        --fix) FIX_MODE="--fix" ;;
        *) ROOT_OVERRIDE="$arg" ;;
    esac
done
ROOT_DIR="${ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"

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

# Find all .sh files. Prune (don't descend into) .git, node_modules, vendor,
# the gitignored dist/ OpenCode export build output, and .claude/worktrees/ agent
# clones — scanning those re-lints generated output and sibling checkouts
# (the #1492/#1548 worktrees-prune lesson) and bloats a repo-wide gate. The
# dist/worktrees prunes are anchored to "$ROOT_DIR/…" (not a bare glob) so the
# linter still works when run from inside a worktree, mirroring
# check-git-sandbox-guards.sh.
#
# This linter's own regression test embeds deliberately-bad fixtures (a #!/bin/bash
# shebang, a TOOL= line) inside `cat <<EOF` heredoc bodies; scanning it would flag
# its own fixtures. Exclude it — a linter does not lint its own fixtures.
SELF_TEST="$ROOT_DIR/scripts/tests/test-lint-shell-scripts.sh"
SCRIPTS=$(find "$ROOT_DIR" \
    \( -path "*/.git/*" -o -path "*/node_modules/*" -o -path "*/vendor/*" \
       -o -path "$ROOT_DIR/dist/*" -o -path "$ROOT_DIR/.claude/worktrees/*" \
       -o -path "$SELF_TEST" \) -prune \
    -o -name "*.sh" -print \
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
            # Suffix ATTACHED: the detached form is GNU-only and aborts on
            # macOS, so --fix never worked there (Check 5 now catches this).
            sed -i.bak '1s|^#!/bin/bash|#!/usr/bin/env bash|' "$script"
            rm -f "$script.bak"
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

    # --- Check 5: Portable in-place sed ---
    # The two single-platform spellings of an in-place edit, each of which
    # fails on the other platform WITHOUT editing anything:
    #
    #   BSD-only   empty suffix       GNU parses it as the script, then reads
    #                                 the real script as a filename -> exit 2
    #   GNU-only   detached script    BSD consumes the script as the backup
    #                                 suffix, then reads the file as the script
    #
    # Attaching the suffix is the only form both accept. Measured on bsdtar-era
    # macOS sed and GNU sed 4.9. These scripts run on macOS AND on ubuntu CI
    # runners, so either single-platform spelling is a latent break.
    #
    # Stripped before matching: full-line comments, and any line tagged
    # portable-sed-ok — the escape hatch for a deliberate try-GNU-then-fall-
    # back-to-BSD pair, which is portable despite containing both spellings.
    #
    # test-*.sh is skipped wholesale: this repo's hook tests carry both
    # spellings as fixture STRINGS, which are data rather than commands.
    if ! echo "$REL_PATH" | grep -qE '(^|/)test-[^/]*\.sh$'; then
        SED_CODE=$(grep -vE '^[[:space:]]*#' "$script" | grep -v 'portable-sed-ok' || true)
        if echo "$SED_CODE" | grep -qE "sed( +-[a-zA-Z.]+)* +-i +''"; then
            error "$REL_PATH: BSD-only in-place sed (empty suffix) — GNU sed exits 2 without editing. Attach the suffix: sed -i.bak ... then rm the backup"
        fi
        if echo "$SED_CODE" | grep -qE "sed( +-[a-zA-Z.]+)* +-i +['\"][^'\"]"; then
            error "$REL_PATH: GNU-only in-place sed (detached script) — BSD sed eats the script as a backup suffix. Attach the suffix: sed -i.bak ... then rm the backup"
        fi
    fi
done

echo ""
echo "Shell script lint: ${ERRORS} error(s), ${WARNINGS} warning(s)"

if [ "$ERRORS" -gt 0 ]; then
    echo "Run with --fix to auto-fix shebang issues."
    exit 1
fi

exit 0
