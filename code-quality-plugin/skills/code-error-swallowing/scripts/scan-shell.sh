#!/usr/bin/env bash
# scan-shell.sh — shell/bash error-swallowing scanner for
# /code:error-swallowing. Paired rules: REFERENCE-shell.md
#
# Output format (pipe-delimited, stable for machine parsing):
#   <severity>|<rule>|<file>:<line>|<snippet>
#
# Exit codes:
#   0 - no Medium/High findings
#   1 - Medium findings present, no High
#   2 - High findings present
#
# Usage:
#   scan-shell.sh <path> [--min-severity low|med|high]
#   scan-shell.sh --self-test
set -uo pipefail

# Defensive: allow this script to be invoked outside a shell that sets -e,
# so that grep-miss exit codes don't terminate the whole scan.

scan_path=""
min_sev="med"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --min-severity) min_sev="$2"; shift 2 ;;
    --self-test)
      # Re-exec against the bundled fixture
      fixture_dir="$(dirname "$0")/../fixtures"
      if [[ ! -d "$fixture_dir" ]]; then
        echo "self-test: fixture dir missing: $fixture_dir" >&2
        exit 3
      fi
      exec bash "$0" "$fixture_dir" --min-severity low
      ;;
    --) shift; break ;;
    -*) shift ;;
    *) scan_path="$1"; shift ;;
  esac
done
scan_path="${scan_path:-.}"

if [[ ! -e "$scan_path" ]]; then
  echo "scan-shell.sh: path not found: $scan_path" >&2
  exit 3
fi

# High-operation promotion regex. Any line containing one of these promotes
# a Medium finding to High.
high_op_regex='(npm publish|yarn publish|pnpm publish|cargo publish|gh release|git push|git tag|docker push|helm upgrade|kubectl apply|terraform apply|aws s3 (cp|sync)|rclone copy|psql.*(INSERT|UPDATE|DELETE|DROP)|curl.*(-X *POST|-X *PUT|-X *DELETE|--request POST|--request PUT|--request DELETE)|rm -rf)'

# Low-allowlist: line content patterns that downgrade to Low regardless of
# default severity. These mirror REFERENCE-shell.md "Allowlist".
allowlist_regex='(head -[0-9]+ "?\$[a-zA-Z_]+"? *\| *grep -m1 "\^[a-zA-Z_]+:"|command -v [a-zA-Z0-9_./-]+ *>/dev/null|rm -f [^|;&]+$|mkdir -p |2>/dev/null\s*\|\|\s*true)'

# Allowlisted function-name prefixes (if the enclosing function name begins
# with one of these, treat the line as Low).
allowlist_fn_prefix_regex='^(extract|probe|has|is|check)_'

# Collect shell files. Accept a single file too.
declare -a files
if [[ -f "$scan_path" ]]; then
  files=("$scan_path")
else
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(
    find "$scan_path" -type f \
      \( -name '*.sh' -o -name '*.bash' \) \
      -not -path '*/node_modules/*' \
      -not -path '*/.git/*' \
      -not -path '*/vendor/*' \
      -print0 2>/dev/null
  )
fi

if [[ ${#files[@]} -eq 0 ]]; then
  exit 0
fi

high_count=0
med_count=0
low_count=0

sev_rank() {
  case "$1" in
    High) echo 3 ;;
    Medium) echo 2 ;;
    Low) echo 1 ;;
    *) echo 0 ;;
  esac
}
min_rank=$(case "$min_sev" in
  high) echo 3 ;;
  med|medium) echo 2 ;;
  low) echo 1 ;;
  *) echo 2 ;;
esac)

# Track enclosing function name per-file using a simple forward scan.
# Used to demote lines inside probe_*/extract_*/... to Low.

scan_file() {
  local file="$1"
  local lineno=0
  local fn_name=""
  while IFS= read -r line; do
    lineno=$((lineno + 1))

    # Update fn_name when we see a function opener.
    # Patterns: `funcname() {` or `function funcname {`.
    # Reset on a closing `}` at column 0 — naive but sufficient for the
    # conventions in this codebase.
    if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\(\)[[:space:]]*\{ ]]; then
      fn_name="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
      fn_name="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^\}[[:space:]]*$ ]]; then
      fn_name=""
    fi

    # Skip comments/blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue

    local rule="" sev=""

    # sh-or-true: `cmd || true` or `cmd || :` (but NOT `|| echo ""` and
    # not `|| <cmd-that-actually-handles>` — we treat "handles" as anything
    # besides `true` / `:`).
    if [[ "$line" =~ \|\|[[:space:]]+(true|:)([[:space:]]|$) ]]; then
      rule="sh-or-true"; sev="Medium"
    # sh-both-null: `>/dev/null 2>&1` or `&>/dev/null`
    elif [[ "$line" =~ \>/dev/null[[:space:]]+2\>\&1 ]] || [[ "$line" =~ \&\>/dev/null ]]; then
      rule="sh-both-null"; sev="Medium"
    # sh-stderr-null: `2>/dev/null`
    elif [[ "$line" =~ 2\>/dev/null ]]; then
      rule="sh-stderr-null"; sev="Medium"
    # sh-set-plus-e
    elif [[ "$line" =~ ^[[:space:]]*set[[:space:]]+\+e([[:space:]]|$) ]]; then
      rule="sh-set-plus-e"; sev="Medium"
    # sh-trap-empty: trap '' ERR or trap - ERR
    elif [[ "$line" =~ ^[[:space:]]*trap[[:space:]]+(\'\'|-)[[:space:]]+ERR ]]; then
      rule="sh-trap-empty"; sev="Medium"
    else
      continue
    fi

    # Allowlist → Low
    if [[ "$line" =~ $allowlist_regex ]]; then
      sev="Low"
    elif [[ -n "$fn_name" && "$fn_name" =~ $allowlist_fn_prefix_regex ]]; then
      sev="Low"
    # Promote to High on dangerous operations
    elif [[ "$line" =~ $high_op_regex ]]; then
      sev="High"
    fi

    # Filter by min severity
    local rank
    rank=$(sev_rank "$sev")
    if [[ "$rank" -lt "$min_rank" ]]; then
      continue
    fi

    # Trim snippet
    local snippet="${line#"${line%%[![:space:]]*}"}"
    snippet="${snippet//|/\\|}"
    if [[ ${#snippet} -gt 160 ]]; then
      snippet="${snippet:0:157}..."
    fi

    printf '%s|%s|%s:%d|%s\n' "$sev" "$rule" "$file" "$lineno" "$snippet"

    case "$sev" in
      High) high_count=$((high_count + 1)) ;;
      Medium) med_count=$((med_count + 1)) ;;
      Low) low_count=$((low_count + 1)) ;;
    esac
  done < "$file"
}

for f in "${files[@]}"; do
  scan_file "$f"
done

# Summary on stderr so stdout stays pipe-friendly
printf '\n' >&2
printf 'scan-shell summary: high=%d medium=%d low=%d files=%d\n' \
  "$high_count" "$med_count" "$low_count" "${#files[@]}" >&2

if [[ "$high_count" -gt 0 ]]; then
  exit 2
elif [[ "$med_count" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
