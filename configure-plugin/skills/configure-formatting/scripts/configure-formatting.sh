#!/usr/bin/env bash
# Detect code-formatting posture for a project.
# Scans --project-dir for formatter config-file signals (biome.json /
# .prettierrc / pyproject [tool.ruff.format] / [tool.black] / rustfmt.toml),
# script/hook/CI presence, and emits a recommendation over the detected
# booleans. Generative steps (writing configs) stay with the model.
# Usage: bash configure-formatting.sh --home-dir <path> --project-dir <path>

set -uo pipefail

home_dir=""
project_dir=""

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== CONFIGURE FORMATTING ==="

fmt_issue_count=0
fmt_status="OK"
fmt_issues_list=""

add_issue() {
  fmt_issues_list="${fmt_issues_list}  - SEVERITY=$1 TYPE=$2 MSG=$3\n"
  fmt_issue_count=$((fmt_issue_count + 1))
  if [ "$1" = "ERROR" ]; then
    fmt_status="ERROR"
  elif [ "$1" = "WARN" ] && [ "$fmt_status" = "OK" ]; then
    fmt_status="WARN"
  fi
}

exists_file() { [ -f "$1" ] && echo "true" || echo "false"; }

# -----------------------------------------------------------------------------
# Language indicators
# -----------------------------------------------------------------------------
pkg_json=$(exists_file "${project_dir}/package.json")
pyproject=$(exists_file "${project_dir}/pyproject.toml")
cargo=$(exists_file "${project_dir}/Cargo.toml")
echo "PACKAGE_JSON=${pkg_json}"
echo "PYPROJECT=${pyproject}"
echo "CARGO=${cargo}"

# -----------------------------------------------------------------------------
# Formatter config-file detection
# -----------------------------------------------------------------------------
biome=$(exists_file "${project_dir}/biome.json")
if [ "$biome" = "false" ] && [ -f "${project_dir}/biome.jsonc" ]; then
  biome="true"
fi
echo "BIOME=${biome}"

prettier=false
for f in "${project_dir}"/.prettierrc "${project_dir}"/.prettierrc.* \
         "${project_dir}"/prettier.config.*; do
  [ -f "$f" ] && { prettier=true; break; }
done
echo "PRETTIER=${prettier}"

ruff_format=false
if [ "$pyproject" = "true" ] && grep -q "tool.ruff.format" "${project_dir}/pyproject.toml" 2>/dev/null; then
  ruff_format=true
fi
echo "RUFF_FORMAT=${ruff_format}"

black=false
if [ "$pyproject" = "true" ] && grep -q "tool.black" "${project_dir}/pyproject.toml" 2>/dev/null; then
  black=true
fi
echo "BLACK=${black}"

rustfmt=false
if [ -f "${project_dir}/rustfmt.toml" ] || [ -f "${project_dir}/.rustfmt.toml" ]; then
  rustfmt=true
fi
echo "RUSTFMT=${rustfmt}"

editorconfig=$(exists_file "${project_dir}/.editorconfig")
echo "EDITORCONFIG=${editorconfig}"

# -----------------------------------------------------------------------------
# Script / hook / CI presence scans
# -----------------------------------------------------------------------------
format_script=false
if [ "$pkg_json" = "true" ] && grep -q '"format"' "${project_dir}/package.json" 2>/dev/null; then
  format_script=true
fi
echo "FORMAT_SCRIPT=${format_script}"

precommit_config=$(exists_file "${project_dir}/.pre-commit-config.yaml")
echo "PRE_COMMIT_CONFIG=${precommit_config}"

precommit_format=false
if [ "$precommit_config" = "true" ]; then
  if grep -qE "biome|ruff|rustfmt|prettier|black" "${project_dir}/.pre-commit-config.yaml" 2>/dev/null; then
    precommit_format=true
  fi
fi
echo "PRE_COMMIT_FORMAT=${precommit_format}"

# Commands that run the formatter. `biome check` is Biome 2.x's combined
# command (formatter + linter + import sorting) and `biome ci` its CI-oriented
# variant, so both cover formatting; `biome lint` is lint-only and is
# deliberately absent from this pattern (issue #2497).
fmt_cmd_re='biome check|biome ci|biome format|ruff format|cargo fmt|prettier'

# Body of a package.json script, or empty when unavailable. Degrades silently
# when package.json is absent/unparseable, has no `scripts` key, or jq is not
# installed — the direct-match scan above still works in every such case.
pkg_script_body() {
  local script_name="$1"
  [ "$pkg_json" = "true" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r --arg n "$script_name" '(.scripts[$n] // "") | tostring' \
    "${project_dir}/package.json" 2>/dev/null
}

ci_format=false
workflows_dir="${project_dir}/.github/workflows"
if [ -d "$workflows_dir" ]; then
  for wf in "$workflows_dir"/*.yml "$workflows_dir"/*.yaml; do
    [ -f "$wf" ] || continue
    # Direct invocation in the workflow.
    if grep -qE "$fmt_cmd_re" "$wf" 2>/dev/null; then
      ci_format=true
      break
    fi
    # ONE level of package-script indirection: a workflow step running
    # `bun run lint` / `npm run format:check` / `yarn fmt` carries the real
    # command in package.json's `scripts`. Resolved exactly one level deep —
    # a script that calls another script is out of scope.
    while IFS= read -r script_name; do
      [ -n "$script_name" ] || continue
      script_body="$(pkg_script_body "$script_name")"
      [ -n "$script_body" ] || continue
      if grep -qE "$fmt_cmd_re" <<<"$script_body"; then
        ci_format=true
        break
      fi
    done < <(grep -Eo \
      '(bun|npm|pnpm|yarn)[[:space:]]+run[[:space:]]+[A-Za-z0-9_:.@/-]+|yarn[[:space:]]+[A-Za-z0-9_:.@/-]+' \
      "$wf" 2>/dev/null | awk '{print $NF}')
    if [ "$ci_format" = "true" ]; then
      break
    fi
  done
fi
echo "CI_FORMAT=${ci_format}"

# -----------------------------------------------------------------------------
# Recommendation over detected booleans
# -----------------------------------------------------------------------------
# A modern formatter is one of biome / ruff-format / rustfmt.
modern_formatter=false
[ "$biome" = "true" ] && modern_formatter=true
[ "$ruff_format" = "true" ] && modern_formatter=true
[ "$rustfmt" = "true" ] && modern_formatter=true

recommendation="setup"
if [ "$modern_formatter" = "true" ]; then
  recommendation="configured"
fi
# Legacy formatters present without a modern one → migrate.
if [ "$modern_formatter" = "false" ] && { [ "$prettier" = "true" ] || [ "$black" = "true" ]; }; then
  recommendation="migrate"
fi
echo "RECOMMENDATION=${recommendation}"

case "$recommendation" in
  setup)
    add_issue "WARN" "no_formatter" "no formatter config detected — recommend Biome/Ruff/rustfmt setup"
    ;;
  migrate)
    [ "$prettier" = "true" ] && add_issue "WARN" "legacy_prettier" "Prettier detected — recommend migrating to Biome"
    [ "$black" = "true" ] && add_issue "WARN" "legacy_black" "Black detected — recommend migrating to Ruff format"
    ;;
esac

echo "STATUS=${fmt_status}"
echo "ISSUE_COUNT=${fmt_issue_count}"
if [ -n "$fmt_issues_list" ]; then
  echo "ISSUES:"
  echo -e "$fmt_issues_list" | sed '/^$/d'
fi
echo "=== END CONFIGURE FORMATTING ==="

[ "$fmt_status" = "ERROR" ] && exit 1
exit 0
