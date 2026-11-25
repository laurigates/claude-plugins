#!/usr/bin/env bash
# shellcheck disable=SC2317,SC2329   # file-level: p_* probes are called indirectly through bool
# Rank every configure-plugin component for ONE repo from file indicators:
#   APPLY  - the repo has the thing this component configures; run it
#   REVIEW - plausibly useful, no strong signal; look before running
#   SKIP   - the subject is absent, or the component excludes this project type
# The roster comes from components.yaml via list-components.sh (single source of
# truth); this script only decides relevance. Detection only - never mutates.
# Usage: bash detect-relevance.sh [--project-dir <dir>] [--type <type>]
#                                 [--manifest <path>] [--skills-dir <path>]

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="${script_dir}/../components.yaml"
skills_dir="${script_dir}/../.."
project_dir="."
type_override=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) project_dir="$2"; shift 2 ;;
    --type) type_override="$2"; shift 2 ;;
    --manifest) manifest="$2"; shift 2 ;;
    --skills-dir) skills_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "=== CONFIGURE RELEVANCE ==="

dr_issue_count=0
dr_status="OK"
dr_issues_list=""
dr_first_error=""

add_issue() {
  dr_issues_list="${dr_issues_list}  - SEVERITY=$1 TYPE=$2 MSG=$3\n"
  dr_issue_count=$((dr_issue_count + 1))
  if [ "$1" = "ERROR" ]; then
    dr_status="ERROR"
    [ -z "$dr_first_error" ] && dr_first_error="$2: $3"
  fi
}

finish() {
  echo "STATUS=${dr_status}"
  [ "$dr_status" != "OK" ] && echo "REASON=$(printf '%s' "$dr_first_error" | tr -s '[:space:]' ' ' | cut -c1-180)"
  echo "ISSUE_COUNT=${dr_issue_count}"
  if [ -n "$dr_issues_list" ]; then
    echo "ISSUES:"
    echo -e "$dr_issues_list" | sed '/^$/d'
  fi
  echo "=== END CONFIGURE RELEVANCE ==="
  [ "$dr_status" = "ERROR" ] && exit 1
  exit 0
}

if [ ! -d "$project_dir" ]; then
  add_issue "ERROR" "no_project_dir" "project dir not found: ${project_dir}"
  finish
fi
cd "$project_dir" || exit 1

lister_out="$(bash "${script_dir}/list-components.sh" --manifest "$manifest" --skills-dir "$skills_dir")" || true
if [ "$(grep -m1 '^STATUS=' <<<"$lister_out" | cut -d= -f2)" = "ERROR" ]; then
  add_issue "ERROR" "manifest_error" "list-components.sh reported ERROR; run it for details"
  finish
fi

# ---------------------------------------------------------------------------
# File probes. Prune node_modules, .git and agent worktrees: a Claude worktree
# holds a full checkout, so unpruned finds and Jest roots count it twice.
# ---------------------------------------------------------------------------
find_files() { # <maxdepth> <find-args...>
  local depth="$1"; shift
  find . -maxdepth "$depth" \( -path '*/node_modules' -o -path './.git' -o -path './.claude/worktrees' -o -path '*/target' -o -path '*/.venv' \) -prune -o -type f "$@" -print 2>/dev/null
}
has_dir() { [ -n "$(find . -maxdepth 3 \( -path '*/node_modules' -o -path './.git' -o -path './.claude/worktrees' \) -prune -o -type d -name "$1" -print 2>/dev/null | head -n1)" ]; }
bool() { if "$@"; then echo true; else echo false; fi; }

pkg_files="$(find_files 2 -name package.json)"
py_files="$(find_files 2 \( -name pyproject.toml -o -name requirements.txt \))"
dep_in_pkg() { # <regex> : dependency name present in any package.json
  [ -n "$pkg_files" ] || return 1
  # shellcheck disable=SC2086
  grep -qE "\"(${1})\"[[:space:]]*:" $pkg_files 2>/dev/null
}
dep_in_py() {
  [ -n "$py_files" ] || return 1
  # shellcheck disable=SC2086
  grep -qiE "(${1})" $py_files 2>/dev/null
}

p_pkg() { [ -n "$pkg_files" ]; }
p_py() { [ -n "$py_files" ]; }
p_cargo() { [ -f Cargo.toml ]; }
p_tf() { [ -n "$(find_files 2 -name '*.tf' | head -n1)" ] || has_dir helm || has_dir argocd; }
p_frontend() { dep_in_pkg 'vue|react|svelte|@angular/core|next|nuxt'; }
p_dockerfile() { [ -n "$(find_files 3 \( -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.Dockerfile' \) | head -n1)" ]; }
p_workflows() { [ -d .github/workflows ]; }
p_tests() { has_dir tests || has_dir test || has_dir __tests__ || [ -n "$(find_files 3 \( -name '*.test.*' -o -name '*.spec.*' -o -name 'test_*.py' \) | head -n1)" ]; }
p_integration() { has_dir integration || has_dir e2e; }
p_http_api() { dep_in_pkg 'express|fastify|koa|hono|@nestjs/core' || dep_in_py 'fastapi|flask|django'; }
p_relplease() { [ -f release-please-config.json ] || [ -f .release-please-manifest.json ]; }
p_k8s() { has_dir k8s || has_dir kubernetes; }
p_skaffold() { [ -f skaffold.yaml ]; }
p_argocd() { has_dir argocd; }
p_sentry() { dep_in_pkg '@sentry/[a-z-]+' || dep_in_py 'sentry-sdk'; }
p_flags() { dep_in_pkg '@openfeature/[a-z-]+|@flagd/[a-z-]+|launchdarkly-[a-z-]+'; }
p_mise() { [ -f mise.toml ] || [ -f .mise.toml ] || [ -f .tool-versions ]; }
p_justfile() { [ -f justfile ] || [ -f Justfile ]; }
p_makefile() { [ -f Makefile ]; }
p_env() { [ -n "$(find_files 2 -name '.env*' | head -n1)" ] || [ -f .claude/settings.local.json ]; }
p_mcp_json() { [ -f .mcp.json ]; }
p_mcp_enabled() { grep -qs 'enabledMcpjsonServers' .claude/settings.json; }
p_docs() { [ -d docs ] || [ -f mkdocs.yml ] || [ -f typedoc.json ]; }
p_cli_bin() { grep -qs '"bin"' package.json || grep -qs '^\[\[bin\]\]' Cargo.toml; }
p_changelog() { [ -f CHANGELOG.md ]; }

s_pkg=$(bool p_pkg); s_py=$(bool p_py); s_cargo=$(bool p_cargo); s_tf=$(bool p_tf)
s_frontend=$(bool p_frontend); s_dockerfile=$(bool p_dockerfile); s_workflows=$(bool p_workflows)
s_tests=$(bool p_tests); s_integration=$(bool p_integration); s_http_api=$(bool p_http_api)
s_relplease=$(bool p_relplease); s_k8s=$(bool p_k8s); s_skaffold=$(bool p_skaffold)
s_argocd=$(bool p_argocd); s_sentry=$(bool p_sentry); s_flags=$(bool p_flags)
s_mise=$(bool p_mise); s_justfile=$(bool p_justfile); s_makefile=$(bool p_makefile)
s_env=$(bool p_env); s_mcp_json=$(bool p_mcp_json); s_mcp_enabled=$(bool p_mcp_enabled)
s_docs=$(bool p_docs); s_cli_bin=$(bool p_cli_bin); s_changelog=$(bool p_changelog)
s_lockfiles="$(find_files 2 \( -name package-lock.json -o -name bun.lock -o -name bun.lockb -o -name pnpm-lock.yaml -o -name yarn.lock -o -name uv.lock \) | wc -l | tr -d ' ')"

# ---------------------------------------------------------------------------
# Project type: override > .project-standards.yaml > file indicators
# ---------------------------------------------------------------------------
declared_type=""
[ -f .project-standards.yaml ] && declared_type="$(awk -F'"' '/^project_type:/ {print $2; exit}' .project-standards.yaml)"
if [ -n "$type_override" ]; then
  project_type="$type_override"; type_source="override"
elif [ -n "$declared_type" ]; then
  project_type="$declared_type"; type_source="standards_file"
else
  type_source="detected"
  if [ "$s_tf" = "true" ]; then project_type="infrastructure"
  elif [ "$s_cargo" = "true" ]; then project_type="rust"
  elif [ "$s_py" = "true" ]; then project_type="python"
  elif [ "$s_pkg" = "true" ] && [ "$s_frontend" = "true" ]; then project_type="frontend"
  elif [ "$s_pkg" = "true" ]; then project_type="node"
  else project_type="unknown"
  fi
fi

echo "PROJECT_DIR=$(pwd)"
echo "PROJECT_TYPE=${project_type}"
echo "PROJECT_TYPE_SOURCE=${type_source}"
echo "STANDARDS_VERSION=$(grep -m1 '^STANDARDS_VERSION=' <<<"$lister_out" | cut -d= -f2)"
for sig in pkg py cargo tf frontend dockerfile workflows tests integration http_api relplease k8s skaffold argocd sentry flags mise justfile makefile env mcp_json mcp_enabled docs cli_bin changelog; do
  v="s_${sig}"
  echo "SIGNAL_$(printf '%s' "$sig" | tr '[:lower:]' '[:upper:]')=${!v}"
done
echo "SIGNAL_LOCKFILES=${s_lockfiles}"

# ---------------------------------------------------------------------------
# Tier per component. tier_for prints "<TIER> <reason>".
# ---------------------------------------------------------------------------
code_project=false
{ [ "$s_pkg" = "true" ] || [ "$s_py" = "true" ] || [ "$s_cargo" = "true" ]; } && code_project=true

tier_for() {
  case "$1" in
    configure-workflows)
      [ "$s_workflows" = "true" ] && echo "APPLY .github/workflows present" || echo "APPLY no CI workflows yet" ;;
    configure-reusable-workflows)
      [ "$s_workflows" = "true" ] && echo "REVIEW compare callers with org reusable workflows" || echo "SKIP no workflows" ;;
    configure-release-please)
      [ "$s_relplease" = "true" ] && echo "APPLY release-please config present" || echo "REVIEW no release-please config" ;;
    configure-pre-commit) echo "APPLY baseline hygiene hooks" ;;
    configure-github-pages)
      [ "$s_docs" = "true" ] && echo "REVIEW docs site candidate" || echo "SKIP no docs source" ;;
    configure-argocd-automerge)
      [ "$s_argocd" = "true" ] && echo "APPLY argocd directory present" || echo "SKIP no ArgoCD" ;;
    configure-claude-plugins) echo "APPLY marketplace and Claude workflows" ;;
    configure-completions)
      [ "$s_cli_bin" = "true" ] && echo "REVIEW CLI binary declared" || echo "SKIP not a CLI" ;;
    configure-gitattributes)
      { [ "$s_changelog" = "true" ] || [ "$s_lockfiles" -gt 0 ]; } && echo "APPLY lockfile or changelog to mark" || echo "REVIEW" ;;
    configure-gitignore) echo "APPLY Claude runtime-state entries" ;;
    configure-worktreeinclude)
      [ "$s_env" = "true" ] && echo "APPLY env or local settings files to carry" || echo "REVIEW no env files found" ;;
    configure-dockerfile|configure-container)
      [ "$s_dockerfile" = "true" ] && echo "APPLY Dockerfile present" || echo "SKIP no Dockerfile" ;;
    configure-skaffold)
      if [ "$s_skaffold" = "true" ]; then echo "APPLY skaffold.yaml present"
      elif [ "$s_k8s" = "true" ]; then echo "REVIEW k8s directory without skaffold"
      else echo "SKIP no Kubernetes"; fi ;;
    configure-tests)
      [ "$s_tests" = "true" ] && echo "APPLY tests present" || echo "REVIEW no tests found" ;;
    configure-coverage)
      [ "$s_tests" = "true" ] && echo "APPLY tests present" || echo "SKIP no tests" ;;
    configure-api-tests)
      if [ "$s_http_api" = "true" ] && [ "$s_tests" = "true" ]; then echo "APPLY HTTP API with tests"
      elif [ "$s_http_api" = "true" ]; then echo "REVIEW HTTP API without tests"
      else echo "SKIP no HTTP API"; fi ;;
    configure-integration-tests)
      if [ "$s_integration" = "true" ]; then echo "APPLY integration or e2e directory"
      elif [ "$s_tests" = "true" ]; then echo "REVIEW tests without an integration tier"
      else echo "SKIP no tests"; fi ;;
    configure-load-tests)
      [ "$s_http_api" = "true" ] && echo "REVIEW HTTP API" || echo "SKIP no HTTP API" ;;
    configure-memory-profiling) echo "REVIEW python only" ;;
    configure-ux-testing) echo "REVIEW frontend only" ;;
    configure-linting) echo "APPLY lint config and CI coverage" ;;
    configure-formatting) echo "APPLY formatter config and enforcement" ;;
    configure-dead-code)
      [ "$code_project" = "true" ] && echo "REVIEW unused-code scan" || echo "SKIP no code" ;;
    configure-security) echo "APPLY dependency and secret scanning" ;;
    configure-docs)
      [ "$code_project" = "true" ] && echo "REVIEW code documentation" || echo "SKIP no code" ;;
    configure-readme) echo "APPLY README shape" ;;
    configure-surface) echo "SKIP surf.toml opt-in" ;;
    configure-feature-flags)
      [ "$s_flags" = "true" ] && echo "APPLY feature-flag SDK present" || echo "SKIP no flag SDK" ;;
    configure-package-management)
      if [ "$s_lockfiles" -gt 1 ]; then echo "REVIEW ${s_lockfiles} lockfiles"
      elif [ "$s_pkg" = "true" ] || [ "$s_py" = "true" ]; then echo "APPLY package manifest present"
      else echo "SKIP no package manifest"; fi ;;
    configure-mise)
      [ "$s_mise" = "true" ] && echo "APPLY mise or tool-versions file present" || echo "REVIEW no tool pinning" ;;
    configure-cache-busting) echo "REVIEW frontend assets" ;;
    configure-editor) echo "APPLY editorconfig" ;;
    configure-mcp)
      { [ "$s_mcp_json" = "true" ] || [ "$s_mcp_enabled" = "true" ]; } && echo "APPLY MCP servers enabled or configured" || echo "REVIEW no MCP config" ;;
    configure-makefile)
      [ "$s_makefile" = "true" ] && echo "APPLY Makefile present" || echo "SKIP no Makefile" ;;
    configure-justfile)
      [ "$s_justfile" = "true" ] && echo "APPLY justfile present" || echo "REVIEW no justfile" ;;
    configure-web-session) echo "REVIEW web-session tool installs" ;;
    configure-instrumentation)
      [ "$s_http_api" = "true" ] && echo "REVIEW service logging and tracing" || echo "SKIP no service" ;;
    configure-sentry)
      [ "$s_sentry" = "true" ] && echo "APPLY Sentry SDK present" || echo "SKIP no Sentry SDK" ;;
    *) echo "REVIEW unknown component, no rule" ;;
  esac
}

type_allows() { # <types> : does the component's TYPES list include this project type
  [ "$1" = "all" ] && return 0
  case ",${1}," in *",${project_type},"*) return 0 ;; esac
  return 1
}

apply_n=0; review_n=0; skip_n=0

while IFS= read -r row; do
  case "$row" in COMPONENT=*) ;; *) continue ;; esac
  cname="${row#COMPONENT=}"; cname="${cname%% *}"
  ctypes="${row##* TYPES=}"
  if ! type_allows "$ctypes"; then
    tier="SKIP"; reason="type ${project_type} not in ${ctypes}"
  else
    read -r tier reason <<<"$(tier_for "$cname")"
  fi
  echo "RELEVANCE=${cname} TIER=${tier} REASON=${reason// /_}"
  case "$tier" in
    APPLY) apply_n=$((apply_n + 1)) ;;
    REVIEW) review_n=$((review_n + 1)) ;;
    *) skip_n=$((skip_n + 1)) ;;
  esac
done <<<"$lister_out"

echo "APPLY_COUNT=${apply_n}"
echo "REVIEW_COUNT=${review_n}"
echo "SKIP_COUNT=${skip_n}"
finish
