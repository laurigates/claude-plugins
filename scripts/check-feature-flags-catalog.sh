#!/usr/bin/env bash
# Guard against drift between the env feature-flags defined in plugin sources and
# the catalog that documents them (hooks-plugin/docs/feature-flags.md).
#
# The catalog is a hand-maintained index, so a newly-added CLAUDE_HOOKS_* /
# CLAUDE_TASKWARRIOR_* flag can silently land in a hook without a catalog entry —
# exactly the drift `documentation-plugin:docs-single-source` warns about. This
# makes the check
# deterministic instead of relying on someone re-running the regeneration grep.
#
# The check: every flag READ in a plugin source must appear in the catalog. A
# new flag added to a hook without a catalog row fails the gate.
#
# Sources scanned: *.sh under plugin dirs + the native-hook templates/ files.
# Excluded: generated copies (dist/), this script, and dedicated tests/ dirs.
# tests/ are excluded because fixtures construct *fake* flags (e.g. a SAMPLE flag
# to prove the gate fires) that would read as undocumented. A name-based test-*.sh
# exclusion is NOT used — it would wrongly drop the real test-verification.sh
# hook; the test-*.sh fixtures that live beside hooks only reference real,
# already-cataloged flags, so scanning them is harmless.
#
# The catalog may legitimately document MORE than the scan finds — e.g. flags
# read by hooks the skills GENERATE into a user's project (permission-request)
# rather than ship as an in-repo .sh — so a "dangling" reverse-check would
# false-positive and is deliberately omitted.
#
# Emits the structured KEY=value / STATUS= convention
# (.claude/rules/structured-script-output.md) so scheduled-audits can roll it up.
#
# Usage:
#   check-feature-flags-catalog.sh [--project-dir <path>] [--strict]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd)
#   --strict        Exit 1 when a source flag is missing from the catalog
#                   (default: always exit 0; DANGLING is a warning either way)
set -uo pipefail

PROJECT_DIR=""
STRICT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --strict) STRICT=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

DOC_REL="hooks-plugin/docs/feature-flags.md"
DOC="$PROJECT_DIR/$DOC_REL"

FLAG_RE='CLAUDE_HOOKS_[A-Z_]+|CLAUDE_TASKWARRIOR_[A-Z_]+'

echo "=== FEATURE FLAGS CATALOG ==="

if [ ! -f "$DOC" ]; then
    echo "DOC=$DOC_REL"
    echo "STATUS=ERROR"
    echo "ISSUE_COUNT=1"
    echo "ISSUES:"
    echo "  - SEVERITY=ERROR TYPE=missing_doc MSG=catalog not found at $DOC_REL"
    echo "=== END FEATURE FLAGS CATALOG ==="
    [ "$STRICT" = "1" ] && exit 1 || exit 0
fi

# Source discovery: `find` + `grep`, NOT `rg`.
#
# This guard used `rg` with `-g` globs and swallowed its stderr, so on a runner
# without ripgrep — which is every GitHub `ubuntu-latest` runner; rg is not in
# the image — `command not found` vanished, the command substitution yielded
# empty, both counts read 0, MISSING_COUNT was 0, and STATUS was OK. Exit 0.
# The guard reported a clean catalog having opened no file at all, and its two
# negative controls could not fail by construction (#2333). `find`+`grep` are
# POSIX and present wherever this runs, so there is one code path everywhere
# rather than a fast path that is silently a no-op in CI.
#
# Discovery runs from INSIDE the root against RELATIVE paths (#2219/#2290):
# with an absolute base the bare `*/.claude/worktrees/*` prune fires on the
# whole tree whenever the root is ITSELF an agent worktree, and the scan
# collapses to zero — the same false-clean this comment is about.
#
# The prunes replace what rg previously got for free from .gitignore
# (`.claude/worktrees/` agent clones, `dist/` OpenCode export build output — #1492,
# #2214) plus its explicit `!**/tests/**` glob: test fixtures construct FAKE
# flags to prove the gate fires, which would read as undocumented.
#
# Collected with a `while read -r -d ''` loop rather than `mapfile -d ''`:
# the latter needs bash 4.4+, and macOS still ships bash 3.2 as /bin/bash, so
# a caller invoking this as `bash scripts/check-...sh` with the system bash
# first on PATH would hit `mapfile: command not found` — and under `set -u`
# that cascades into unbound-variable errors, i.e. another silent no-scan.
source_files=()
files_scanned=0
while IFS= read -r -d '' f; do
    source_files+=("$f")
    files_scanned=$((files_scanned + 1))
done < <(cd "$PROJECT_DIR" && find . \
    -path '*/.claude/worktrees/*' -prune -o \
    -path '*/dist/*' -prune -o \
    -path '*/node_modules/*' -prune -o \
    -path '*/.git/*' -prune -o \
    -path '*/tests/*' -prune -o \
    -path './scripts/check-feature-flags-catalog.sh' -prune -o \
    \( -name '*.sh' -o -path '*/templates/*' \) \
    -type f -print0 2>/dev/null | sort -z)

# `files_scanned` is counted in the loop rather than read as `${#array[@]}`:
# expanding an EMPTY array is itself an unbound-variable error under `set -u`
# on older bash, which would abort exactly in the zero-file case this counter
# exists to report.

# Flags actually read in plugin sources (the authoritative set).
source_flags=""
if [ "$files_scanned" -gt 0 ]; then
    source_flags=$( (cd "$PROJECT_DIR" && printf '%s\0' "${source_files[@]}" \
        | xargs -0 grep -hoE "$FLAG_RE") | sort -u)
fi

# Flags named anywhere in the catalog.
catalog_flags=$(grep -hoE "$FLAG_RE" "$DOC" | sort -u)

source_count=$(printf '%s\n' "$source_flags" | grep -c . || true)
catalog_count=$(printf '%s\n' "$catalog_flags" | grep -c . || true)

# MISSING: read in a source, absent from the catalog.
missing=$(comm -23 <(printf '%s\n' "$source_flags") <(printf '%s\n' "$catalog_flags"))
missing_count=$(printf '%s\n' "$missing" | grep -c . || true)

# A scan that opened NO file cannot report a clean catalog — "found nothing" and
# "checked nothing" must not look alike (#2290's class, and the defect that hid
# the missing-rg bug for the whole life of this guard). The catalog doc resolved
# above, so there IS a project here; zero scannable sources means the walk
# misfired, not that the repo is clean.
nothing_scanned=0
if [ "$files_scanned" -eq 0 ]; then
    nothing_scanned=1
fi

issue_count=$((missing_count + nothing_scanned))

if [ "$issue_count" -gt 0 ]; then
    overall="ERROR"
else
    overall="OK"
fi

echo "DOC=$DOC_REL"
echo "FILES_SCANNED=$files_scanned"
if [ "$files_scanned" -eq 0 ]; then
    echo "SCANNED_EMPTY=true"
else
    echo "SCANNED_EMPTY=false"
fi
echo "SOURCE_FLAG_COUNT=$source_count"
echo "CATALOG_FLAG_COUNT=$catalog_count"
echo "MISSING_COUNT=$missing_count"
echo "STATUS=$overall"
echo "ISSUE_COUNT=$issue_count"

if [ "$issue_count" -gt 0 ]; then
    echo "ISSUES:"
    if [ "$nothing_scanned" -eq 1 ]; then
        echo "  - SEVERITY=ERROR TYPE=nothing_scanned MSG=no .sh or templates/ file found under $PROJECT_DIR; the walk misfired, so a clean result would be meaningless"
    fi
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        echo "  - SEVERITY=ERROR TYPE=missing_from_catalog FLAG=$f MSG=flag read in a source but absent from $DOC_REL"
    done <<< "$missing"
fi

echo "=== END FEATURE FLAGS CATALOG ==="

if [ "$STRICT" = "1" ] && [ "$issue_count" -gt 0 ]; then
    exit 1
fi
exit 0
