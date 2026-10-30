#!/usr/bin/env bash
# Validate configure-plugin/policy/repo-baseline.json, the machine-readable
# floor for a repo's .claude/settings.json and .mcp.json (#3318).
#
# The policy is read by /configure:claude-plugins, /configure:mcp and the
# portfolio reconciler, so a plugin key it names that resolves to no plugin is
# copied into every repo it reconciles — and Claude Code silently ignores an
# enabledPlugins key that names no plugin. The skill docs carried exactly that
# defect: six official LSP names without their `-lsp` suffix
# (`pyright@claude-plugins-official` instead of `pyright-lsp@…`).
#
# Checks (all ERROR):
#   1. The policy parses as JSON.
#   2. The floor's extraKnownMarketplaces key equals the .name in
#      .claude-plugin/marketplace.json (the `@suffix` every key relies on).
#   3. Every `<plugin>@<marketplace>` key the policy names (stacks[].plugins,
#      settings.floor.enabledPlugins):
#        - `@<marketplace .name>`         → the plugin is published in marketplace.json
#        - `@<officialMarketplace.name>`  → the plugin is in officialMarketplace.lspPlugins
#        - any other suffix               → unknown_marketplace_suffix
#   4. Every `<name>@<officialMarketplace.name>` token in
#      configure-plugin/skills/**/*.md is in officialMarketplace.lspPlugins
#      (pins the doc fix; a `<placeholder>@…` is not a token).
#   5. Zero skill docs scanned is ERROR nothing_scanned, not a silent OK.
#
# Emits the structured KEY=value / STATUS= convention
# (.claude/rules/structured-script-output.md).
#
# Usage:
#   check-repo-baseline-policy.sh [--project-dir <path>] [--strict]
#
#   --project-dir   Repo root to audit (default: git toplevel, else cwd)
#   --strict        Exit 1 when an ERROR is found (default: always exit 0)
#
# Exit codes: 0 OK (or any result without --strict), 1 ERROR under --strict,
# 2 usage error (an unknown flag is rejected, never swallowed — #2057).
set -uo pipefail

proj_dir=""
strict=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      if [ -z "${2:-}" ]; then
        echo "check-repo-baseline-policy.sh: --project-dir requires a path" >&2
        exit 2
      fi
      proj_dir="$2"; shift 2 ;;
    --strict) strict=true; shift ;;
    *)
      echo "check-repo-baseline-policy.sh: unknown argument: $1" >&2
      echo "Usage: check-repo-baseline-policy.sh [--project-dir <path>] [--strict]" >&2
      exit 2 ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

policy_rel="configure-plugin/policy/repo-baseline.json"
docs_rel="configure-plugin/skills"
policy="$proj_dir/$policy_rel"
marketplace="$proj_dir/.claude-plugin/marketplace.json"

issue_count=0
declare -a issues=()

add_issue() {
  # add_issue <severity> <type> <message>
  issues+=("  - SEVERITY=$1 TYPE=$2 MSG=$3")
  issue_count=$((issue_count + 1))
}

jq_available=true
command -v jq >/dev/null 2>&1 || jq_available=false

policy_version=""
mkt_name=""
official_name=""
policy_plugin_count=0
lsp_count=0
docs_scanned=0
doc_refs=0

if [ "$jq_available" = false ]; then
  add_issue ERROR missing_jq "jq is required to validate the repo baseline policy but is not installed"
elif [ ! -f "$policy" ]; then
  add_issue ERROR missing_policy "$policy_rel not found under $proj_dir"
elif ! jq -e 'type == "object"' "$policy" >/dev/null 2>&1; then
  add_issue ERROR policy_invalid_json "$policy_rel does not parse as a JSON object"
elif [ ! -f "$marketplace" ]; then
  add_issue ERROR missing_marketplace ".claude-plugin/marketplace.json not found under $proj_dir"
else
  policy_version="$(jq -r '.version // empty' "$policy")"
  mkt_name="$(jq -r '.name // empty' "$marketplace")"
  official_name="$(jq -r '.officialMarketplace.name // empty' "$policy")"

  declare -A mkt_set=()
  while IFS= read -r p; do
    [ -n "$p" ] && mkt_set["$p"]=1
  done < <(jq -r '.plugins[]?.name // empty' "$marketplace")

  declare -A lsp_set=()
  while IFS= read -r p; do
    [ -n "$p" ] && lsp_set["$p"]=1
  done < <(jq -r '.officialMarketplace.lspPlugins[]? // empty' "$policy")
  lsp_count=${#lsp_set[@]}

  [ -n "$mkt_name" ] || add_issue ERROR marketplace_unnamed ".claude-plugin/marketplace.json has no top-level .name"
  [ -n "$official_name" ] || add_issue ERROR official_marketplace_unnamed "$policy_rel has no officialMarketplace.name"
  [ "$lsp_count" -gt 0 ] || add_issue ERROR official_lsp_list_empty "$policy_rel officialMarketplace.lspPlugins is empty or missing"

  # Check 2: the floor's marketplace key is the marketplace .name.
  floor_keys="$(jq -r '(.settings.floor.extraKnownMarketplaces // {}) | keys | join(",")' "$policy")"
  if [ -n "$mkt_name" ] && [ "$floor_keys" != "$mkt_name" ]; then
    add_issue ERROR marketplace_key_mismatch \
      "settings.floor.extraKnownMarketplaces keys are '$floor_keys'; expected exactly '$mkt_name' (the marketplace .name every @suffix resolves against)"
  fi

  # Check 3: every plugin key the policy names resolves.
  mapfile -t policy_plugins < <(
    jq -r '[(.stacks[]?.plugins[]?), ((.settings.floor.enabledPlugins // {}) | keys[])] | .[]' "$policy"
  )
  policy_plugin_count=${#policy_plugins[@]}
  for key in "${policy_plugins[@]}"; do
    [ -n "$key" ] || continue
    plugin_name="${key%@*}"
    plugin_suffix="${key##*@}"
    if [ "$plugin_name" = "$key" ]; then
      add_issue ERROR unknown_marketplace_suffix "$key has no @<marketplace> suffix"
    elif [ -n "$mkt_name" ] && [ "$plugin_suffix" = "$mkt_name" ]; then
      [ -n "${mkt_set[$plugin_name]:-}" ] || add_issue ERROR unknown_marketplace_plugin \
        "$key is named in $policy_rel but $plugin_name is not published in .claude-plugin/marketplace.json"
    elif [ -n "$official_name" ] && [ "$plugin_suffix" = "$official_name" ]; then
      [ -n "${lsp_set[$plugin_name]:-}" ] || add_issue ERROR unknown_official_plugin \
        "$key is not an official LSP plugin; officialMarketplace.lspPlugins names the real ones (e.g. pyright-lsp)"
    else
      add_issue ERROR unknown_marketplace_suffix \
        "$key uses @$plugin_suffix, which is neither '$mkt_name' nor '$official_name'"
    fi
  done

  # Check 4/5: official plugin names cited in the configure-plugin skill docs.
  # Relative paths from inside the project root, so a root that is itself an
  # agent worktree is still scanned (regression-testing.md, worktree-root row).
  if [ -n "$official_name" ]; then
    if [ -d "$proj_dir/$docs_rel" ]; then
      docs_scanned="$(cd "$proj_dir" && find "$docs_rel" -type f -name '*.md' | wc -l | tr -d '[:space:]')"
    fi
    if [ "${docs_scanned:-0}" -eq 0 ]; then
      add_issue ERROR nothing_scanned "no *.md files found under $docs_rel — the doc check scanned nothing"
    else
      official_re="${official_name//./\\.}"
      while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        hit_rest="${hit#*:}"
        hit_line="${hit_rest%%:*}"
        hit_token="${hit_rest#*:}"
        doc_plugin="${hit_token%@*}"
        if [ -n "${lsp_set[$doc_plugin]:-}" ]; then
          doc_refs=$((doc_refs + 1))
        else
          add_issue ERROR doc_unknown_official_plugin \
            "$hit_file:$hit_line names $hit_token, which is not in officialMarketplace.lspPlugins"
        fi
      # A process substitution's exit status is discarded, so grep finding no
      # token (exit 1) needs no `|| true` here.
      done < <(cd "$proj_dir" && grep -rHnoE --include='*.md' "[A-Za-z0-9._-]+@${official_re}" "$docs_rel")
    fi
  fi
fi

# --- Status -------------------------------------------------------------------
overall_status="OK"
exit_severity=0
for line in "${issues[@]}"; do
  case "$line" in
    *SEVERITY=ERROR*) overall_status="ERROR"; exit_severity=1 ;;
  esac
done
if [ "$overall_status" = "OK" ] && [ "$issue_count" -gt 0 ]; then
  overall_status="WARN"
fi

# --- Output -------------------------------------------------------------------
echo "=== REPO BASELINE POLICY ==="
echo "JQ_AVAILABLE=$jq_available"
echo "POLICY_FILE=$policy_rel"
echo "POLICY_VERSION=$policy_version"
echo "MARKETPLACE_NAME=$mkt_name"
echo "OFFICIAL_MARKETPLACE_NAME=$official_name"
echo "POLICY_PLUGINS=$policy_plugin_count"
echo "LSP_PLUGINS=$lsp_count"
echo "DOCS_SCANNED=$docs_scanned"
echo "DOC_OFFICIAL_REFS=$doc_refs"
echo "STATUS=$overall_status"
if [ "$overall_status" != "OK" ]; then
  # REASON= is the first finding at the reported severity as `<TYPE>: <MSG>`,
  # one line, cut to 180 chars, plus ` (+N more)` when other findings exist
  # (.claude/rules/structured-script-output.md, #2760).
  reason=""
  for line in "${issues[@]}"; do
    case "$line" in *"SEVERITY=$overall_status "*) ;; *) continue ;; esac
    [ -z "$reason" ] || continue
    reason_type="${line#*TYPE=}"
    reason_type="${reason_type%% *}"
    reason="$(printf '%s: %s' "$reason_type" "${line#*MSG=}" | tr -s '[:space:]' ' ' | cut -c1-180)"
  done
  [ "$issue_count" -gt 1 ] && reason="$reason (+$((issue_count - 1)) more)"
  echo "REASON=$reason"
fi
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "ISSUES:"
  printf '%s\n' "${issues[@]}"
fi
echo "=== END REPO BASELINE POLICY ==="

if [ "$strict" = true ]; then
  exit "$exit_severity"
fi
exit 0
