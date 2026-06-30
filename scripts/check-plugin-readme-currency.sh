#!/usr/bin/env bash
# Advisory README-currency nudge for plugin commits.
#
# When a commit's staged changes touch a plugin's skills/, agents/, or
# .claude-plugin/ but do NOT also stage that plugin's README.md, emit a
# friendly nudge to check whether the README still matches. This is ADVISORY
# only: the script ALWAYS exits 0, so the commit proceeds. It is wired into
# .pre-commit-config.yaml with `verbose: true` so pre-commit surfaces the nudge
# even though the hook "passes".
#
# Why a nudge and not a hard block: whether a given skill/agent edit warrants a
# README prose change is a judgment call (a one-line bug fix usually doesn't; a
# behavioral change does), so a hard gate would fire constantly and get
# muscle-memory-bypassed. The mechanical *count* dimension ("a skill was
# added/removed but the README count is stale") is already enforced separately
# by scripts/check-docs-index.sh (Check 3); this nudge covers the residual
# content-currency gap. See .claude/rules/docs-currency.md.
#
# Opt out: set CLAUDE_HOOKS_DISABLE_README_CURRENCY=1.
#
# Test seam: set PLUGIN_README_CURRENCY_STAGED to a newline-separated list of
# staged paths to bypass `git diff --cached` (used by the regression test).
#
# Emits the structured KEY=VALUE / STATUS= convention
# (.claude/rules/structured-script-output.md). STATUS=WARN signals nudges; the
# script still exits 0 (WARN is the signal, not the exit code).
#
# -e is intentionally omitted: this is an advisory diagnostic that must always
# exit 0 so it can never block a commit.
set -uo pipefail

emit_section() {
  # emit_section <plugins_changed> <issue_count> <status> [disabled]
  echo "=== PLUGIN README CURRENCY ==="
  [ "${4:-}" = "disabled" ] && echo "DISABLED=true"
  echo "PLUGINS_CHANGED=$1"
  echo "PLUGINS_MISSING_README_UPDATE=$2"
  echo "STATUS=$3"
  echo "ISSUE_COUNT=$2"
}

if [ "${CLAUDE_HOOKS_DISABLE_README_CURRENCY:-}" = "1" ]; then
  emit_section 0 0 OK disabled
  echo "=== END PLUGIN README CURRENCY ==="
  exit 0
fi

if [ -n "${PLUGIN_README_CURRENCY_STAGED:-}" ]; then
  staged_raw="$PLUGIN_README_CURRENCY_STAGED"
else
  staged_raw="$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)"
fi

declare -A plugin_substantive=()   # plugin -> first substantive staged path
declare -A plugin_readme_staged=() # plugin -> 1 if its README.md is staged

while IFS= read -r staged_path; do
  [ -n "$staged_path" ] || continue

  top="${staged_path%%/*}"
  # Skip dot-dirs (e.g. .claude-plugin, the repo-level marketplace dir, which
  # also matches the *-plugin glob) and anything not shaped like a plugin dir.
  case "$top" in
    .*) continue ;;
  esac
  [[ "$top" == *-plugin ]] || continue

  rest="${staged_path#"$top"/}"
  if [ "$rest" = "README.md" ]; then
    plugin_readme_staged["$top"]=1
    continue
  fi

  sub="${rest%%/*}"
  case "$sub" in
    skills | agents | .claude-plugin)
      if [ -z "${plugin_substantive[$top]:-}" ]; then
        plugin_substantive["$top"]="$staged_path"
      fi
      ;;
  esac
done <<< "$staged_raw"

declare -a nudges=()
plugins_changed=0
for plugin_name in "${!plugin_substantive[@]}"; do
  plugins_changed=$((plugins_changed + 1))
  if [ -z "${plugin_readme_staged[$plugin_name]:-}" ]; then
    nudges+=("$plugin_name|${plugin_substantive[$plugin_name]}")
  fi
done

issue_count=${#nudges[@]}
overall_status="OK"
[ "$issue_count" -gt 0 ] && overall_status="WARN"

if [ "$issue_count" -gt 0 ]; then
  echo "NUDGE: the following plugin(s) changed without a README.md update in this commit."
  echo "       If the change affects documented behavior, update the plugin README in the"
  echo "       same commit (advisory only — your commit will proceed; see"
  echo "       .claude/rules/docs-currency.md)."
  while IFS='|' read -r plugin_name first_path; do
    echo "  - $plugin_name (e.g. staged: $first_path; $plugin_name/README.md not staged)"
  done < <(printf '%s\n' "${nudges[@]}" | sort)
fi

emit_section "$plugins_changed" "$issue_count" "$overall_status"
if [ "$issue_count" -gt 0 ]; then
  echo "ISSUES:"
  while IFS='|' read -r plugin_name first_path; do
    echo "  - SEVERITY=INFO TYPE=readme_not_updated PLUGIN=$plugin_name STAGED=$first_path"
  done < <(printf '%s\n' "${nudges[@]}" | sort)
fi
echo "=== END PLUGIN README CURRENCY ==="
exit 0
