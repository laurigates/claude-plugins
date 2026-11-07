#!/usr/bin/env bash
# Check that .claude/rules/release-please.md states the release setup that the
# live config and workflow actually use.
#
# The rule drifted from both for months without anyone noticing (issue #2839,
# Layer-2 audit finding B-5): it said `separate-pull-requests: true` while the
# config said false, and it told readers to configure a `MY_RELEASE_PLEASE_TOKEN`
# secret while the workflow had moved to a GitHub App token. Three checks, each
# against a machine-readable source of truth:
#
#   1. SEPARATE PRS  — every `separate-pull-requests: <bool>` the rule states
#      equals release-please-config.json (release-please's default, false, when
#      the key is absent), and the rule states it at least once.
#   2. AUTH NAMES    — every `secrets.X` / `vars.X` the release-please workflow
#      reads (bar GITHUB_TOKEN) is named in the rule, and the rule names no
#      *_TOKEN / *_PRIVATE_KEY / *_APP_ID identifier the workflow does not read.
#   3. PACKAGE SHAPE — the "Adding a New Plugin" JSON example has the same
#      package keys as the first package in the config, and each of its
#      extra-files jsonpaths (with the example name swapped for that package's)
#      appears in that package's extra-files.
#
# Emits the structured KEY=value / STATUS= convention
# (.claude/rules/structured-script-output.md).
#
# Usage:
#   check-release-please-rule.sh [--project-dir <path>] [--strict]
#
#   --project-dir   Repo root to audit (default: git toplevel, else cwd)
#   --strict        Exit 1 when a finding is reported (default: always exit 0)
set -uo pipefail

proj_dir=""
strict=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$2"; shift 2 ;;
    --strict) strict=true; shift ;;
    *) shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

rule="$proj_dir/.claude/rules/release-please.md"
config="$proj_dir/release-please-config.json"
workflow="$proj_dir/.github/workflows/release-please.yml"

issue_count=0
declare -a issues=()

add_issue() {
  # add_issue <severity> <type> <message>
  issues+=("  - SEVERITY=$1 TYPE=$2 MSG=$3")
  issue_count=$((issue_count + 1))
}

config_separate="unknown"
stated_values=""
workflow_names=""
example_name=""
sample_name=""

for f in "$rule" "$config" "$workflow"; do
  [ -f "$f" ] || add_issue ERROR missing_file "$f not found"
done

if ! command -v jq >/dev/null 2>&1; then
  add_issue ERROR missing_jq "jq is required"
fi

if [ "$issue_count" -eq 0 ]; then
  # --- 1. separate-pull-requests --------------------------------------------
  config_separate="$(jq -r 'if has("separate-pull-requests") then .["separate-pull-requests"] | tostring else "false" end' "$config")"
  stated_values="$(grep -oE 'separate-pull-requests"?:[[:space:]]*(true|false)' "$rule" \
    | grep -oE '(true|false)$' | sort -u | paste -sd, -)"
  if [ -z "$stated_values" ]; then
    add_issue ERROR separate_prs_unstated "the rule never states separate-pull-requests; config has $config_separate"
  else
    for v in ${stated_values//,/ }; do
      if [ "$v" != "$config_separate" ]; then
        add_issue ERROR separate_prs_mismatch "rule states separate-pull-requests: $v, release-please-config.json has $config_separate"
      fi
    done
  fi

  # --- 2. auth names ---------------------------------------------------------
  workflow_names="$(grep -v '^[[:space:]]*#' "$workflow" \
    | grep -oE '(secrets|vars)\.[A-Za-z_][A-Za-z0-9_]*' | sed 's/^[a-z]*\.//' \
    | grep -vx 'GITHUB_TOKEN' | sort -u)"
  if [ -z "$workflow_names" ]; then
    add_issue ERROR no_workflow_auth "release-please.yml reads no secrets.* or vars.* — cannot check the rule's auth section"
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    grep -qw -- "$name" "$rule" \
      || add_issue ERROR auth_unnamed "the workflow reads $name, which the rule does not name"
  done <<< "$workflow_names"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    printf '%s\n' "$workflow_names" | grep -qx -- "$name" \
      || add_issue ERROR auth_stale "the rule names $name, which release-please.yml does not read"
  done < <(grep -oE '\b[A-Z][A-Z0-9_]*_(TOKEN|PRIVATE_KEY|APP_ID)\b' "$rule" | grep -vx 'GITHUB_TOKEN' | sort -u)

  # --- 3. package shape ------------------------------------------------------
  example_json="$(awk '
    /^```json/ { buf = ""; inblock = 1; next }
    inblock && /^```/ { if (buf ~ /"packages"/) { print buf; exit } inblock = 0; next }
    inblock { buf = buf $0 "\n" }
  ' "$rule")"
  if [ -z "$example_json" ] || ! printf '%s' "$example_json" | jq -e '.packages | type == "object" and length > 0' >/dev/null 2>&1; then
    add_issue ERROR example_missing "no parseable \`\`\`json block with a non-empty \"packages\" object in the rule"
  else
    example_name="$(printf '%s' "$example_json" | jq -r '.packages | keys[0]')"
    sample_name="$(jq -r '.packages | keys[0]' "$config")"
    example_keys="$(printf '%s' "$example_json" | jq -r --arg n "$example_name" '.packages[$n] | keys | join(",")')"
    sample_keys="$(jq -r --arg n "$sample_name" '.packages[$n] | keys | join(",")' "$config")"
    if [ "$example_keys" != "$sample_keys" ]; then
      add_issue ERROR example_keys "example package keys [$example_keys] differ from config package $sample_name [$sample_keys]"
    fi
    while IFS= read -r jp; do
      [ -n "$jp" ] || continue
      expected="${jp//$example_name/$sample_name}"
      jq -e --arg n "$sample_name" --arg p "$expected" \
        '[.packages[$n]["extra-files"][]? | .jsonpath] | index($p) != null' "$config" >/dev/null \
        || add_issue ERROR example_jsonpath "example jsonpath $jp has no counterpart in config package $sample_name"
    done < <(printf '%s' "$example_json" | jq -r --arg n "$example_name" '.packages[$n]["extra-files"][]? | .jsonpath')
  fi
fi

item_status=OK
[ "$issue_count" -gt 0 ] && item_status=ERROR

echo "=== RELEASE PLEASE RULE ==="
echo "CONFIG_SEPARATE_PULL_REQUESTS=$config_separate"
echo "RULE_SEPARATE_PULL_REQUESTS=${stated_values:-none}"
echo "WORKFLOW_AUTH_NAMES=$(printf '%s' "$workflow_names" | paste -sd, -)"
echo "EXAMPLE_PACKAGE=${example_name:-none}"
echo "SAMPLE_PACKAGE=${sample_name:-none}"
echo "STATUS=$item_status"
if [ "$issue_count" -gt 0 ]; then
  first_type="${issues[0]#*TYPE=}"
  first_type="${first_type%% *}"
  reason="$(printf '%s: %s' "$first_type" "${issues[0]#*MSG=}" | tr -s '[:space:]' ' ' | cut -c1-180)"
  [ "${#issues[@]}" -gt 1 ] && reason="$reason (+$((${#issues[@]} - 1)) more)"
  echo "REASON=$reason"
fi
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "ISSUES:"
  printf '%s\n' "${issues[@]}"
fi
echo "=== END RELEASE PLEASE RULE ==="

if [ "$strict" = true ] && [ "$issue_count" -gt 0 ]; then
  exit 1
fi
exit 0
