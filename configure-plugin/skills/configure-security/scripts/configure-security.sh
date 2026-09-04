#!/usr/bin/env bash
# Detect security-scanning posture for a project.
# Scans --project-dir for language/tool signals and the three security layers
# (dependency automation / SAST / secret detection) plus a SECURITY.md policy,
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
# Layer 1: dependency automation — Renovate OR Dependabot
#
# The two are alternatives, not complements: both open dependency-update PRs and
# both rewrite lockfiles, so installing a second bot on a repo that already runs
# one makes them race each other (issue #2495). Detect the incumbent and treat
# the layer as satisfied when EITHER is configured.
# -----------------------------------------------------------------------------
dependabot=false
if [ -f "${project_dir}/.github/dependabot.yml" ] || [ -f "${project_dir}/.github/dependabot.yaml" ]; then
  dependabot=true
fi
echo "DEPENDABOT=${dependabot}"

# Renovate reads the first config file it finds from this set, plus a top-level
# "renovate" key in package.json.
renovate=false
for renovate_cfg in \
  "${project_dir}/renovate.json" \
  "${project_dir}/renovate.json5" \
  "${project_dir}/.renovaterc" \
  "${project_dir}/.renovaterc.json" \
  "${project_dir}/.renovaterc.json5" \
  "${project_dir}/.github/renovate.json" \
  "${project_dir}/.github/renovate.json5" \
  "${project_dir}/.gitlab/renovate.json"; do
  if [ -f "$renovate_cfg" ]; then
    renovate=true
    break
  fi
done

# package.json "renovate" key. This must be the TOP-LEVEL key, not any mention
# of the word: a naive `grep renovate package.json` also matches a devDependency
# on the renovate CLI, or a script name. jq answers this exactly; without jq,
# fall back to an anchored key match (which can still be fooled by a nested
# "renovate": key, so jq is strongly preferred).
if [ "$renovate" = "false" ] && [ "$lang_js" = "true" ]; then
  if command -v jq >/dev/null 2>&1; then
    if jq -e 'type == "object" and has("renovate")' "${project_dir}/package.json" >/dev/null 2>&1; then
      renovate=true
    fi
  elif grep -Eq '^[[:space:]]*"renovate"[[:space:]]*:' "${project_dir}/package.json" 2>/dev/null; then
    renovate=true
  fi
fi
echo "RENOVATE=${renovate}"

# Layer verdict: either tool satisfies dependency automation.
dep_automation=false
if [ "$dependabot" = "true" ] || [ "$renovate" = "true" ]; then
  dep_automation=true
fi
echo "DEPENDENCY_AUTOMATION=${dep_automation}"

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
# CodeQL availability (issue #2498)
#
# A missing CodeQL workflow is only a GAP where CodeQL can actually run. On a
# private repository without GitHub code security, every `github/codeql-action/*`
# step fails with HTTP 403, so recommending the workflow produces something whose
# only fix is deleting it again. Probe availability before choosing the severity
# of a missing SAST layer.
#
# The probe is deliberately narrow:
#   * it runs ONLY when no CodeQL workflow was found — the sole case where the
#     answer changes the report — so a configured repo pays no network call;
#   * it is skipped entirely with no git remote, a non-GitHub remote, no `gh`, or
#     CONFIGURE_SECURITY_NO_GHAS_PROBE set. Every skip reports `unknown`, never a
#     fabricated verdict;
#   * `unknown` falls back to today's WARN, so an offline, unauthenticated, or
#     rate-limited run is never WORSE than it was before the probe existed.
#
# CODEQL_AVAILABLE=yes|no|unknown and CODEQL_AVAILABILITY_REASON=<token> are both
# emitted unconditionally: a key that appears in only one branch is
# indistinguishable from a key nobody emitted.
# -----------------------------------------------------------------------------
codeql_available="unknown"
codeql_reason="not-probed"

gh_probe_timeout="${CONFIGURE_SECURITY_GH_TIMEOUT:-8}"
case "$gh_probe_timeout" in
  ''|*[!0-9]*) gh_probe_timeout=8 ;;
esac

probe_codeql_availability() {
  # Sets codeql_available / codeql_reason. Always returns 0 and never writes to
  # stderr — a failed probe degrades to "unknown"; it does not fail the check.
  if [ -n "${CONFIGURE_SECURITY_NO_GHAS_PROBE:-}" ]; then
    codeql_reason="opt-out"
    return 0
  fi

  # Local, offline preconditions first, so a repo that cannot be probed costs no
  # subprocess at all.
  local remote_url
  remote_url=$(git -C "$project_dir" config --get remote.origin.url 2>/dev/null || true)
  if [ -z "$remote_url" ]; then
    codeql_reason="no-remote"
    return 0
  fi
  case "$remote_url" in
    *github*) : ;;
    *) codeql_reason="not-github"; return 0 ;;
  esac

  if ! command -v gh >/dev/null 2>&1; then
    codeql_reason="gh-missing"
    return 0
  fi

  local out_file err_file
  out_file=$(mktemp) || { codeql_reason="mktemp-failed"; return 0; }
  err_file=$(mktemp) || { rm -f "$out_file"; codeql_reason="mktemp-failed"; return 0; }

  # `gh api` expands {owner}/{repo} from the repository of the current directory,
  # and --jq runs gh's embedded jq, so no local jq is required. GitHub renamed
  # security_and_analysis.advanced_security to .code_security; read either.
  # `.private` is projected with tostring rather than `//` — jq's `//` treats
  # `false` as null-ish, so `.private // ""` would erase exactly the public-repo
  # case this probe exists to detect.
  local gh_pid wd_pid rc
  ( cd "$project_dir" && gh api 'repos/{owner}/{repo}' --jq \
      '[(.private | tostring), (.security_and_analysis.code_security.status // .security_and_analysis.advanced_security.status // "")] | join(" ")' \
  ) >"$out_file" 2>"$err_file" &
  gh_pid=$!
  # A watchdog rather than timeout(1): timeout is GNU coreutils and absent from a
  # stock macOS (.claude/rules/shell-scripting.md).
  ( sleep "$gh_probe_timeout"; kill -TERM "$gh_pid" ) >/dev/null 2>&1 &
  wd_pid=$!
  wait "$gh_pid"
  rc=$?
  kill -TERM "$wd_pid" >/dev/null 2>&1
  wait "$wd_pid" >/dev/null 2>&1

  if [ "$rc" -eq 0 ]; then
    local is_private ghas_status
    is_private=$(awk 'NR==1{print $1}' "$out_file")
    ghas_status=$(awk 'NR==1{print $2}' "$out_file")
    rm -f "$out_file" "$err_file"
    if [ "$is_private" = "false" ]; then
      # Code scanning is free on public repositories, so a missing workflow there
      # is a genuine gap regardless of the plan tier.
      codeql_available="yes"
      codeql_reason="public-repo"
      return 0
    fi
    case "$ghas_status" in
      enabled)  codeql_available="yes"; codeql_reason="code-security-enabled" ;;
      disabled) codeql_available="no";  codeql_reason="code-security-disabled" ;;
      "")       codeql_reason="status-field-absent" ;;
      *)        codeql_reason="status-unrecognised" ;;
    esac
    return 0
  fi

  # Classify the failure so the report says WHY it could not answer. Matching uses
  # a here-string, never `printf | grep -q`: under pipefail a grep that matches and
  # closes the pipe early makes the pipeline report SIGPIPE (issue #1744/#2462).
  local api_err
  api_err=$(tr -d '\r' < "$err_file")
  rm -f "$out_file" "$err_file"
  if [ "$rc" -eq 143 ] || [ "$rc" -eq 137 ]; then
    codeql_reason="timeout"
  elif grep -qiE 'gh auth login|authentication|bad credentials|HTTP 401' <<<"$api_err"; then
    codeql_reason="gh-unauthenticated"
  elif grep -qiE 'HTTP 404|not found' <<<"$api_err"; then
    codeql_reason="repo-not-found"
  else
    codeql_reason="api-error"
  fi
  return 0
}

if [ "$codeql" = "false" ]; then
  probe_codeql_availability
fi
echo "CODEQL_AVAILABLE=${codeql_available}"
echo "CODEQL_AVAILABILITY_REASON=${codeql_reason}"

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
[ "$dep_automation" = "true" ] && present_layers=$((present_layers + 1))
[ "$codeql" = "true" ] && present_layers=$((present_layers + 1))
[ "$gitleaks_config" = "true" ] && present_layers=$((present_layers + 1))
echo "SECURITY_LAYERS_PRESENT=${present_layers}"

# Advisory issues — informational, drive STATUS to WARN.
[ "$dep_automation" = "false" ] && add_issue "WARN" "missing_dependency_automation" "no dependency automation (Renovate or Dependabot)"
# SAST: severity is gated on whether CodeQL can run here at all (issue #2498).
# `no` downgrades to INFO and states the cause; `yes` and `unknown` keep the WARN
# so the pre-probe behaviour is the floor, not the ceiling.
if [ "$codeql" = "false" ]; then
  if [ "$codeql_available" = "no" ]; then
    # The API reports whether code security is enabled HERE, not whether the org
    # is licensed for it, so the message names the repo's state and both
    # remediations rather than asserting a plan tier it cannot see.
    add_issue "INFO" "sast_unavailable" \
      "GitHub code security is not enabled for this repository (${codeql_reason}), so a CodeQL workflow would fail with HTTP 403 on every run — enable code scanning in the repository's security settings where the plan allows it, otherwise use a SARIF-free scanner (standalone Trivy, dependency alerts)"
  else
    add_issue "WARN" "missing_sast" \
      "no CodeQL workflow or codeql-action reference (CodeQL availability: ${codeql_available}, ${codeql_reason})"
  fi
fi
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
