#!/usr/bin/env bash
# install-pi.sh — install this marketplace's skills into a pi (pi.dev) skills
# directory, curated by tier (pi/tiers.yaml).
#
# pi loads Claude Code SKILL.md files unmodified but does not budget the
# up-front skill-description listing, so dumping all ~400 skills wedges a
# local model's small context. This installer copies only the tier-appropriate
# set: the `general` tier into pi's global skills dir (~/.pi/agent/skills), a
# `domain` category into the per-project skills dir (<cwd>/.pi/skills). `exclude`
# plugins are never copied. Cherry-picked plugins (a `skills:` list in the
# manifest) install only their listed skills.
#
# The copy is ADDITIVE: existing skills under the target are preserved.
#
# Usage:
#   install-pi.sh [--scope global|project] [--category <cat>]
#                 [--dry-run] [--list] [--root <repo-root>]
#
#   (no flags)          general tier -> global scope
#   --category <cat>    that domain category -> project scope
#   --scope <s>         override the derived scope
#   --list              print the install plan (what lands where); no writes
#   --dry-run           rehearse a full run; no writes
#   --root <dir>        repo root holding pi/tiers.yaml + plugins (default: ../)
#
# Env overrides (for tests / non-standard layouts):
#   PI_HOME         global pi agent dir (default: ~/.pi/agent) -> $PI_HOME/skills
#   PI_PROJECT_DIR  project dir (default: $PWD)                -> .pi/skills
set -euo pipefail

pi_script_dir="$(cd "$(dirname "$0")" && pwd)"
pi_root="$(cd "$pi_script_dir/.." && pwd)"
pi_scope=""
pi_category=""
pi_dry_run=false
pi_list=false

while [ $# -gt 0 ]; do
  case "$1" in
    --scope) pi_scope="$2"; shift 2 ;;
    --category) pi_category="$2"; shift 2 ;;
    --dry-run) pi_dry_run=true; shift ;;
    --list) pi_list=true; shift ;;
    --root) pi_root="$2"; shift 2 ;;
    *) echo "install-pi.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

pi_manifest="${pi_root}/pi/tiers.yaml"

echo "=== PI INSTALL ==="

if [ ! -f "$pi_manifest" ]; then
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_manifest MSG=pi/tiers.yaml not found at ${pi_manifest}"
  echo "=== END PI INSTALL ==="
  exit 1
fi

# Mode + default scope. A category selects the domain tier and defaults to a
# per-project install; otherwise the general tier defaults to a global install.
if [ -n "$pi_category" ]; then
  pi_mode="domain"
  [ -n "$pi_scope" ] || pi_scope="project"
else
  pi_mode="general"
  [ -n "$pi_scope" ] || pi_scope="global"
fi

case "$pi_scope" in
  global) pi_dest="${PI_HOME:-$HOME/.pi/agent}/skills" ;;
  project) pi_dest="${PI_PROJECT_DIR:-$PWD}/.pi/skills" ;;
  *) echo "install-pi.sh: --scope must be global or project, got: $pi_scope" >&2; exit 2 ;;
esac

# Expand a leading ~ (env overrides may carry one).
if [ "${pi_dest#\~}" != "$pi_dest" ]; then
  pi_dest="${HOME}${pi_dest#\~}"
fi

echo "MODE=$pi_mode"
echo "SCOPE=$pi_scope"
[ -n "$pi_category" ] && echo "CATEGORY=$pi_category"
echo "DEST=$pi_dest"

# ---------------------------------------------------------------------------
# Parse the manifest into per-plugin tier/category + cherry-pick skill lists.
# Records: PLUGIN <name> | TIER <name> <val> | CATEGORY <name> <val>
#          | SKILL <name> <skill>
# ---------------------------------------------------------------------------
pi_records="$(awk '
  /^  [a-z][a-z0-9-]*-plugin:/ {
    line=$0
    sub(/^  /, "", line)
    name=line
    sub(/:.*/, "", name)
    plugin=name
    print "PLUGIN " plugin
    # Flow form: `name: { tier: X, category: Y }` on the same line.
    if (line ~ /{/) {
      braces=line
      sub(/^[^{]*{/, "", braces)
      if (match(braces, /tier:[[:space:]]*[a-z]+/)) {
        t=substr(braces, RSTART, RLENGTH); sub(/tier:[[:space:]]*/, "", t)
        print "TIER " plugin " " t
      }
      if (match(braces, /category:[[:space:]]*[a-z]+/)) {
        c=substr(braces, RSTART, RLENGTH); sub(/category:[[:space:]]*/, "", c)
        print "CATEGORY " plugin " " c
      }
    }
    next
  }
  /^    tier:[[:space:]]*[a-z]+/ {
    t=$2; print "TIER " plugin " " t; next
  }
  /^    category:[[:space:]]*[a-z]+/ {
    c=$2; print "CATEGORY " plugin " " c; next
  }
  /^      - [a-z][a-z0-9-]+[[:space:]]*$/ {
    print "SKILL " plugin " " $2; next
  }
' "$pi_manifest")"

declare -A pi_tier=()
declare -A pi_cat=()
declare -A pi_cherry=()   # plugin -> space-separated cherry-picked skills
declare -a pi_plugin_order=()
while IFS= read -r rec; do
  # shellcheck disable=SC2086  # deliberate word-split of a space-joined record
  set -- $rec
  case "$1" in
    PLUGIN) pi_plugin_order+=("$2") ;;
    TIER) pi_tier["$2"]="$3" ;;
    CATEGORY) pi_cat["$2"]="$3" ;;
    SKILL) pi_cherry["$2"]="${pi_cherry[$2]:-} $3" ;;
  esac
done <<< "$pi_records"

# ---------------------------------------------------------------------------
# Select the plugins for this run and resolve each to its skill dirs.
# ---------------------------------------------------------------------------
pi_planned=0
pi_copied=0
pi_issue_count=0
pi_issues=""

skills_of() {
  # Emit the skill dir names to install for a plugin: the cherry-pick list if
  # present, else every skill dir on disk.
  local plugin="$1"
  if [ -n "${pi_cherry[$plugin]:-}" ]; then
    # shellcheck disable=SC2086  # deliberate word-split of the space-joined skill list
    printf '%s\n' ${pi_cherry[$plugin]}
  else
    local d
    for d in "${pi_root}/${plugin}/skills"/*/; do
      [ -d "$d" ] || continue
      basename "$d"
    done
  fi
}

for plugin in "${pi_plugin_order[@]}"; do
  tier="${pi_tier[$plugin]:-}"
  if [ "$pi_mode" = "general" ]; then
    [ "$tier" = "general" ] || continue
  else
    [ "$tier" = "domain" ] || continue
    [ "${pi_cat[$plugin]:-}" = "$pi_category" ] || continue
  fi

  while IFS= read -r skill; do
    [ -n "$skill" ] || continue
    src="${pi_root}/${plugin}/skills/${skill}"
    if [ ! -f "${src}/SKILL.md" ]; then
      pi_issues="${pi_issues}  - SEVERITY=WARN TYPE=skill_missing MSG=${plugin}/skills/${skill}/SKILL.md not found; skipped\n"
      pi_issue_count=$((pi_issue_count + 1))
      continue
    fi
    pi_planned=$((pi_planned + 1))
    echo "PLAN=${pi_dest}/${skill} <- ${plugin}/skills/${skill}"
    if [ "$pi_dry_run" = false ] && [ "$pi_list" = false ]; then
      mkdir -p "${pi_dest}/${skill}"
      cp -R "${src}/." "${pi_dest}/${skill}/"
      pi_copied=$((pi_copied + 1))
    fi
  done < <(skills_of "$plugin")
done

echo "PLANNED_SKILLS=$pi_planned"

pi_receipt=".claude-plugins-pi-receipt"
if [ "$pi_dry_run" = true ] || [ "$pi_list" = true ]; then
  echo "DRY_RUN=true"
  echo "COPIED_SKILLS=0"
else
  echo "COPIED_SKILLS=$pi_copied"
  # Drop a receipt so a later run can detect a prior install into this dir.
  mkdir -p "$pi_dest"
  printf 'installed_at=%s\nmode=%s\nscope=%s\ncategory=%s\nskills=%s\n' \
    "$pi_dest" "$pi_mode" "$pi_scope" "${pi_category:-}" "$pi_copied" \
    > "${pi_dest}/${pi_receipt}"
  echo "RECEIPT=${pi_dest}/${pi_receipt}"
fi

if [ "$pi_issue_count" -gt 0 ]; then
  echo "STATUS=WARN"
  echo "ISSUE_COUNT=$pi_issue_count"
  echo "ISSUES:"
  echo -e "$pi_issues" | sed '/^$/d'
else
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
fi
echo "=== END PI INSTALL ==="
exit 0
