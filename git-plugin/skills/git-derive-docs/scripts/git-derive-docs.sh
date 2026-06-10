#!/usr/bin/env bash
# git-derive-docs data-gathering (issue #1552).
# DATA-ONLY: aggregates file-naming patterns, commit-convention frequency, and
# dependency/migration signals from git history. Performs NO writes. The
# "is this issue implemented?" and quick-wins judgment stays with the model.
#
# Repo seam: operates on --project-dir (default cwd). All git reads use
# `git -C "$repo_dir"`, so tests point it at a planted fixture repo — fully
# offline, no network.
#
# Usage: bash git-derive-docs.sh [--home-dir <path>] [--project-dir <path>]
#          [--depth N] [--since <date>]

set -uo pipefail

home_dir=""
project_dir=""
depth="200"
since=""

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --depth) depth="$2"; shift 2 ;;
    --since) since="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

repo_dir="$project_dir"

echo "=== GIT DERIVE DOCS ==="

derive_issues_list=""
derive_issue_count=0
derive_status="OK"

if ! git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
  echo "GIT_REPO=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=not_a_repo MSG=${repo_dir} is not a git repository"
  echo "=== END GIT DERIVE DOCS ==="
  exit 1
fi
echo "GIT_REPO=true"

# Build the common log-range selector: --since takes precedence over -N depth.
log_range=()
if [ -n "$since" ]; then
  log_range=(--since="$since")
else
  log_range=("-${depth}")
fi

commit_count=$(git -C "$repo_dir" rev-list --count HEAD 2>/dev/null || echo "0")
echo "COMMIT_COUNT=${commit_count}"

# --- Commit-convention frequency -----------------------------------------
# Tally conventional-commit type(scope) prefixes. grep -oP not portable on BSD;
# use sed to extract the leading "type" or "type(scope)" token.
echo "=== COMMIT CONVENTIONS ==="
git -C "$repo_dir" log "${log_range[@]}" --format='%s' 2>/dev/null \
  | sed -nE 's/^([a-z]+)(\([^)]+\))?(!)?:.*/\1/p' \
  | sort | uniq -c | sort -rn \
  | while read -r conv_count conv_type; do
      echo "CONV_${conv_type}=${conv_count}"
    done
echo "=== END COMMIT CONVENTIONS ==="

# --- File-naming pattern aggregation -------------------------------------
# Most-touched top-two-path-segment directories (feature-cluster signal) and
# added-file basename-extension distribution.
echo "=== FILE PATTERNS ==="
git -C "$repo_dir" log "${log_range[@]}" --format='' --name-only 2>/dev/null \
  | grep -E '/' \
  | sed -E 's#^([^/]+/[^/]+).*#\1#' \
  | sort | uniq -c | sort -rn | head -10 \
  | while read -r dir_count dir_path; do
      echo "DIR_${dir_count}=${dir_path}"
    done

# Added-file extension distribution.
git -C "$repo_dir" log "${log_range[@]}" --diff-filter=A --name-only --format='' 2>/dev/null \
  | grep -E '\.' \
  | sed -E 's#.*\.([A-Za-z0-9]+)$#\1#' \
  | sort | uniq -c | sort -rn | head -10 \
  | while read -r ext_count ext_name; do
      echo "EXT_${ext_name}=${ext_count}"
    done
echo "=== END FILE PATTERNS ==="

# --- Dependency / migration signal detection -----------------------------
# Counts of commits that touch dependency manifests, and commits whose subject
# matches migration/replacement language (ADR candidates).
echo "=== DEPENDENCY SIGNALS ==="
dep_manifest_commits=$(git -C "$repo_dir" log "${log_range[@]}" --oneline \
  -- 'package.json' 'Cargo.toml' 'pyproject.toml' 'go.mod' 'requirements.txt' 2>/dev/null | wc -l | tr -d ' ')
echo "DEP_MANIFEST_COMMITS=${dep_manifest_commits}"

migration_commits=$(git -C "$repo_dir" log "${log_range[@]}" --format='%s' 2>/dev/null \
  | grep -ciE 'migrate|switch|replace|upgrade|from .+ to' || true)
echo "MIGRATION_COMMITS=${migration_commits}"

refactor_commits=$(git -C "$repo_dir" log "${log_range[@]}" --format='%s' 2>/dev/null \
  | grep -ciE 'refactor|restructure|reorganize|redesign' || true)
echo "REFACTOR_COMMITS=${refactor_commits}"
echo "=== END DEPENDENCY SIGNALS ==="

# --- Existing doc coverage (gap context, read-only) -----------------------
echo "=== DOC COVERAGE ==="
for doc_dir in ".claude/rules" "docs/prds" "docs/adrs" "docs/prps"; do
  doc_key=$(echo "$doc_dir" | tr 'a-z/.' 'A-Z__')
  if [ -d "${repo_dir}/${doc_dir}" ]; then
    doc_files=$(find "${repo_dir}/${doc_dir}" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    echo "DOCS_${doc_key}=${doc_files}"
  else
    echo "DOCS_${doc_key}=absent"
  fi
done
echo "=== END DOC COVERAGE ==="

echo "STATUS=${derive_status}"
echo "ISSUE_COUNT=${derive_issue_count}"
if [ -n "$derive_issues_list" ]; then
  echo "ISSUES:"
  echo -e "$derive_issues_list" | sed '/^$/d'
fi
echo "=== END GIT DERIVE DOCS ==="

[ "$derive_status" = "ERROR" ] && exit 1
exit 0
