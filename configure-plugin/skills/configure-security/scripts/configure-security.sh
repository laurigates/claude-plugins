#!/usr/bin/env bash
# Detect security-scanning posture for a project.
# Scans --project-dir for language/tool signals and the three security layers
# (dependency auditing / SAST / secret detection) plus a SECURITY.md policy,
# emitting a structured presence matrix. Generative steps (writing workflows /
# SECURITY.md) stay with the model.
# Usage: bash configure-security.sh --home-dir <path> --project-dir <path>

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

echo "=== CONFIGURE SECURITY ==="

sec_issue_count=0
sec_status="OK"
sec_issues_list=""

add_issue() {
  # severity type message
  sec_issues_list="${sec_issues_list}  - SEVERITY=$1 TYPE=$2 MSG=$3\n"
  sec_issue_count=$((sec_issue_count + 1))
  if [ "$1" = "ERROR" ]; then
    sec_status="ERROR"
  elif [ "$1" = "WARN" ] && [ "$sec_status" = "OK" ]; then
    sec_status="WARN"
  fi
}

exists_file() { [ -f "$1" ] && echo "true" || echo "false"; }

# -----------------------------------------------------------------------------
# Language / package-manager detection (package-file globs)
# -----------------------------------------------------------------------------
lang_js=$(exists_file "${project_dir}/package.json")
lang_python=$(exists_file "${project_dir}/pyproject.toml")
lang_rust=$(exists_file "${project_dir}/Cargo.toml")
lang_go=$(exists_file "${project_dir}/go.mod")

echo "LANG_JS=${lang_js}"
echo "LANG_PYTHON=${lang_python}"
echo "LANG_RUST=${lang_rust}"
echo "LANG_GO=${lang_go}"

detected_langs=0
for v in "$lang_js" "$lang_python" "$lang_rust" "$lang_go"; do
  [ "$v" = "true" ] && detected_langs=$((detected_langs + 1))
done
echo "DETECTED_LANGUAGES=${detected_langs}"

# -----------------------------------------------------------------------------
# Layer 1: dependency auditing — Dependabot
# -----------------------------------------------------------------------------
dependabot=false
if [ -f "${project_dir}/.github/dependabot.yml" ] || [ -f "${project_dir}/.github/dependabot.yaml" ]; then
  dependabot=true
fi
echo "DEPENDABOT=${dependabot}"

# -----------------------------------------------------------------------------
# Layer 2: SAST — CodeQL (workflow file under .github/workflows)
# -----------------------------------------------------------------------------
codeql=false
workflows_dir="${project_dir}/.github/workflows"
if [ -d "$workflows_dir" ]; then
  for wf in "$workflows_dir"/codeql*.yml "$workflows_dir"/codeql*.yaml; do
    [ -f "$wf" ] && { codeql=true; break; }
  done
  # Also catch a CodeQL action referenced inside any workflow file.
  if [ "$codeql" = false ]; then
    for wf in "$workflows_dir"/*.yml "$workflows_dir"/*.yaml; do
      [ -f "$wf" ] || continue
      if grep -q "github/codeql-action" "$wf" 2>/dev/null; then
        codeql=true
        break
      fi
    done
  fi
fi
echo "CODEQL=${codeql}"

# -----------------------------------------------------------------------------
# Layer 3: secret detection — gitleaks config + pre-commit hook reference
# -----------------------------------------------------------------------------
gitleaks_config=$(exists_file "${project_dir}/.gitleaks.toml")
echo "GITLEAKS_CONFIG=${gitleaks_config}"

precommit_config=$(exists_file "${project_dir}/.pre-commit-config.yaml")
echo "PRE_COMMIT_CONFIG=${precommit_config}"

precommit_gitleaks=false
if [ "$precommit_config" = "true" ]; then
  if grep -q "gitleaks" "${project_dir}/.pre-commit-config.yaml" 2>/dev/null; then
    precommit_gitleaks=true
  fi
fi
echo "PRE_COMMIT_GITLEAKS=${precommit_gitleaks}"

# -----------------------------------------------------------------------------
# Security policy
# -----------------------------------------------------------------------------
security_policy=$(exists_file "${project_dir}/SECURITY.md")
if [ "$security_policy" = "false" ] && [ -f "${project_dir}/.github/SECURITY.md" ]; then
  security_policy="true"
fi
echo "SECURITY_POLICY=${security_policy}"

# -----------------------------------------------------------------------------
# Workflow action-name grep: which security workflow actions are referenced
# -----------------------------------------------------------------------------
trufflehog=false
dep_review=false
if [ -d "$workflows_dir" ]; then
  for wf in "$workflows_dir"/*.yml "$workflows_dir"/*.yaml; do
    [ -f "$wf" ] || continue
    grep -q "trufflehog" "$wf" 2>/dev/null && trufflehog=true
    grep -q "dependency-review-action" "$wf" 2>/dev/null && dep_review=true
  done
fi
echo "TRUFFLEHOG=${trufflehog}"
echo "DEPENDENCY_REVIEW=${dep_review}"

# -----------------------------------------------------------------------------
# Presence-matrix rollup
# -----------------------------------------------------------------------------
present_layers=0
[ "$dependabot" = "true" ] && present_layers=$((present_layers + 1))
[ "$codeql" = "true" ] && present_layers=$((present_layers + 1))
[ "$gitleaks_config" = "true" ] && present_layers=$((present_layers + 1))
echo "SECURITY_LAYERS_PRESENT=${present_layers}"

# Advisory issues — informational, drive STATUS to WARN.
[ "$dependabot" = "false" ] && add_issue "WARN" "missing_dependabot" "no Dependabot config (.github/dependabot.yml)"
[ "$codeql" = "false" ] && add_issue "WARN" "missing_sast" "no CodeQL workflow or codeql-action reference"
[ "$gitleaks_config" = "false" ] && add_issue "WARN" "missing_secret_detection" "no .gitleaks.toml secret-scanning config"
[ "$security_policy" = "false" ] && add_issue "WARN" "missing_security_policy" "no SECURITY.md policy"

echo "STATUS=${sec_status}"
echo "ISSUE_COUNT=${sec_issue_count}"
if [ -n "$sec_issues_list" ]; then
  echo "ISSUES:"
  echo -e "$sec_issues_list" | sed '/^$/d'
fi
echo "=== END CONFIGURE SECURITY ==="

[ "$sec_status" = "ERROR" ] && exit 1
exit 0
