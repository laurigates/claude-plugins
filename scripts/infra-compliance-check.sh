#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015  # SC2016: jq $ refs; SC2015: intentional && ... || true guard
set -euo pipefail

# Infrastructure Compliance Check Script
# Performs registry sync, workflow health, version consistency, skill coverage, and security checks
#
# Usage:
#   ./scripts/infra-compliance-check.sh [--project-dir DIR]
#
#   --project-dir   repo root to scan (default: this script's repo). Exists so the
#                   workflow/security classifiers can be aimed at hermetic fixtures
#                   (scripts/tests/test-infra-compliance-check.sh).
#
# Exit codes:
#   0 - always, having emitted a complete report (see the terminal `exit 0` below)
#   2 - unknown argument

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  echo "Usage: infra-compliance-check.sh [--project-dir DIR]" >&2
}

# An unknown argument is REJECTED, never swallowed (#2057): a silently-ignored
# flag turns a targeted run into a full-repo run that still exits 0.
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "infra-compliance-check.sh: --project-dir requires a directory" >&2
        exit 2
      fi
      REPO_ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "infra-compliance-check.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

cd "$REPO_ROOT"

CURRENT_MONTH=$(date "+%Y-%m")

# Scoring
registry_total=0; registry_pass=0
workflow_total=0; workflow_pass=0
version_total=0; version_pass=0
skill_total=0; skill_pass=0
security_total=0; security_pass=0

# Results storage
registry_rows=()
orphan_entries=()
workflow_rows=()
version_rows=()
skill_rows=()
security_rows=()
# shellcheck disable=SC2034  # recommendations reserved for future use
recommendations=()

total_skills_count=0

##########
# 1. Registry 4-File Sync
##########

plugin_dirs=()
while IFS= read -r -d '' dir; do
  plugin_dirs+=("$(basename "$dir")")
done < <(find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0 | sort -z)

for plugin in "${plugin_dirs[@]}"; do
  has_json="❌"; has_market="❌"; has_config="❌"; has_manifest="❌"

  if [ -f "${plugin}/.claude-plugin/plugin.json" ]; then
    pj_name=$(jq -r '.name // ""' "${plugin}/.claude-plugin/plugin.json" 2>/dev/null)
    [ -n "$pj_name" ] && has_json="✅"
  fi

  if [ -f ".claude-plugin/marketplace.json" ]; then
    mp_entry=$(jq --arg p "$plugin" '.plugins[] | select(.name == $p)' .claude-plugin/marketplace.json 2>/dev/null)
    [ -n "$mp_entry" ] && has_market="✅"
  fi

  if [ -f "release-please-config.json" ]; then
    rp_entry=$(jq --arg p "$plugin" '.packages[$p]' release-please-config.json 2>/dev/null)
    [ "$rp_entry" != "null" ] && [ -n "$rp_entry" ] && has_config="✅"
  fi

  if [ -f ".release-please-manifest.json" ]; then
    rm_entry=$(jq --arg p "$plugin" '.[$p]' .release-please-manifest.json 2>/dev/null)
    [ "$rm_entry" != "null" ] && [ -n "$rm_entry" ] && has_manifest="✅"
  fi

  registry_total=$((registry_total+4))
  [ "$has_json" = "✅" ] && registry_pass=$((registry_pass+1)) || true
  [ "$has_market" = "✅" ] && registry_pass=$((registry_pass+1)) || true
  [ "$has_config" = "✅" ] && registry_pass=$((registry_pass+1)) || true
  [ "$has_manifest" = "✅" ] && registry_pass=$((registry_pass+1)) || true

  row_status="✅"
  for s in "$has_json" "$has_market" "$has_config" "$has_manifest"; do
    [ "$s" = "❌" ] && row_status="❌" && break
  done

  registry_rows+=("$plugin | $has_json | $has_market | $has_config | $has_manifest | $row_status")
done

# Orphaned entries
if [ -f ".claude-plugin/marketplace.json" ]; then
  while IFS= read -r mp_name; do
    [ ! -d "$mp_name" ] && orphan_entries+=("marketplace.json: '$mp_name' (no directory)")
  done < <(jq -r '.plugins[].name' .claude-plugin/marketplace.json 2>/dev/null)
fi

if [ -f "release-please-config.json" ]; then
  while IFS= read -r rp_name; do
    [ ! -d "$rp_name" ] && orphan_entries+=("release-please-config.json: '$rp_name' (no directory)")
  done < <(jq -r '.packages | keys[]' release-please-config.json 2>/dev/null)
fi

##########
# 2. Workflow Health
##########

# The checkout column asks whether the repo's pins AGREE, not whether they match
# a version named here. It used to hardcode `v4` as the good value, which
# inverted the moment the repo moved on: all 28 refs are `@v6`, so every row
# warned permanently, the report told the reader to "update workflow action
# versions" on actions already at the newest major, and an actual DOWNGRADE to
# `@v4` scored a tick. A currency check written as a literal in an audit script
# is guaranteed to rot -- the same disease as the version ledger and the
# subagent-depth ceiling. Currency belongs to Renovate, which manages this
# surface (`.claude/rules/version-pinning.md`); drift is what a repo audit can
# actually see.
#
# The dominant major is computed from the repo, so a Renovate bump that lands
# everywhere keeps every row green, while a PARTIAL bump flags the laggards --
# which is the state worth reporting.
# Computed in ONE awk pass: under `set -euo pipefail` a `grep` that matches
# nothing exits 1 and a mid-pipeline `head` can SIGPIPE its upstream (141),
# either of which would abort the whole audit -- the trap #1744/#2462 record.
# awk always exits 0 and prints exactly one line.
# One grep + one awk, and nothing else: this runs under `set -euo pipefail`,
# where a `grep` that matches nothing exits 1 and a mid-pipeline `head` can
# SIGPIPE its upstream (141) -- either aborts the whole audit (#1744, #2462).
# The trailing `|| true` absorbs the empty-repo case; awk always exits 0 and
# prints exactly one line. Deliberately no `find`/`xargs`: the audit's own test
# harness runs it under a restricted PATH shim carrying neither.
checkout_mode="$(
  { grep -rhoE 'actions/checkout@[^ "]+' .github/workflows 2>/dev/null || true; } \
    | awk '
        { v = substr($0, 18); n[v]++ }
        END {
          best = "N/A"; max = 0
          for (k in n) if (n[k] > max || (n[k] == max && k < best)) { max = n[k]; best = k }
          print best
        }'
)"
if [ -z "$checkout_mode" ]; then checkout_mode="N/A"; fi

while IFS= read -r -d '' wf; do
  wf_name=$(basename "$wf")

  # Every ref, not just the first: five workflows here carry more than one, and
  # `grep -m1` made a stale pin in any later step invisible.
  # Every ref, not just the first: five workflows here carry more than one, and
  # `grep -m1` made a stale pin in any later step invisible. One awk pass again,
  # for the same exit-code reason as the tally above.
  checkout_ver="$(awk '
      match($0, /actions\/checkout@[^ "]+/) {
        v = substr($0, RSTART + 17, RLENGTH - 17)
        if (!(v in seen)) { seen[v] = 1; out = (out == "" ? v : out "," v) }
      }
      END { print (out == "" ? "N/A" : out) }' "$wf" 2>/dev/null)"
  if [ -z "$checkout_ver" ]; then checkout_ver="N/A"; fi
  checkout_ok="✅"
  if [ "$checkout_ver" != "N/A" ]; then
    case "$checkout_ver" in
      # Two distinct pins in one file is drift on its face.
      *,*) checkout_ok="⚠️" ;;
      # One pin that disagrees with the rest of the repo is a laggard.
      # Written as an `if`, not a `&&` chain: under `set -e` a false test as the
      # last command of a case branch aborts the run.
      *)
        if [ "$checkout_mode" != "N/A" ] && [ "$checkout_ver" != "$checkout_mode" ]; then
          checkout_ok="⚠️"
        fi
        ;;
    esac
  fi

  claude_ver="N/A"
  if grep -q 'anthropics/claude-code-action@' "$wf" 2>/dev/null; then
    claude_ver=$(grep -m1 -oE 'anthropics/claude-code-action@[^ "]+' "$wf" | sed 's/anthropics\/claude-code-action@//')
  fi
  claude_ok="✅"
  if [ "$claude_ver" != "N/A" ] && [ "$claude_ver" != "v1" ]; then
    claude_ok="⚠️"
  fi

  perms_ok="✅"
  if grep -q 'write-all' "$wf" 2>/dev/null; then
    perms_ok="⚠️"
  fi

  # Trigger-aware path-filter check (#2555).
  #
  # This used to `grep -q 'pull_request:'` / `grep -q 'paths:'` over the WHOLE
  # file, comments included, and so failed in BOTH directions:
  #   - stranded-work-audit.yml (cron + workflow_dispatch only) was flagged ⚠️
  #     because a prose comment mentions `pull_request: closed`;
  #   - plugin-pr-checks.yml falsely PASSED because comments containing the
  #     string `paths:` satisfied the check while ARGUING it deliberately has
  #     no path filter.
  #
  # Now: read the trigger structurally with `yq` when available, else from a
  # comment-stripped view. A workflow that deliberately carries no `paths:`
  # (a REQUIRED status check — a path-filtered workflow never REPORTS its
  # context and wedges the merge permanently, #2258) declares that with an
  # `infra-compliance: paths-exempt` marker comment rather than being flagged.
  # The comment-stripped view is captured ONCE into a variable and matched with
  # here-strings, never `grep -v … | grep -q …`: under `set -o pipefail` a
  # `grep -q` that matches closes the pipe while the producer is still writing,
  # the producer takes SIGPIPE, and the pipeline reports 141 — so a real match
  # reads as "no match", nondeterministically, by file size (#1744, #2462).
  #
  # TWO invariants this block exists to hold, both of which a naive version
  # silently breaks:
  #
  #   1. A PRESENT-BUT-UNUSABLE `yq` must NOT read as "no pull_request
  #      trigger". `command -v yq` only proves a binary is on PATH — the
  #      mikefarah Go binary and the python-yq jq wrapper take different
  #      flags, and either can fail on a malformed workflow. Swallowing that
  #      failure with `2>/dev/null` and treating the empty result as `false`
  #      turns every PR workflow into Filters=N/A — the exact false negative
  #      this check exists to eliminate. So the probe is CAPTURED and only a
  #      literal `true`/`false` answer is trusted; anything else (non-zero
  #      exit, empty, an error string) falls through to the grep fallback.
  #
  #   2. The `paths:` lookup must be scoped to the pull_request trigger
  #      ITSELF. A grep-anywhere match is satisfied by a `paths:` belonging to
  #      a different trigger (a `push:` filter is the common shape) or sitting
  #      inside a `run: |` block, so a PR workflow with no path filter reads
  #      ✅. The yq branch asks the pull_request node directly; the fallback
  #      slices the indented block under `pull_request:` with awk first.
  wf_code="$(grep -vE '^[[:space:]]*#' "$wf" 2>/dev/null || true)"

  filters_ok="N/A"
  has_pr=false
  pr_has_paths=false
  trigger_resolved=false
  if command -v yq >/dev/null 2>&1; then
    # One probe answers both questions, so a broken yq is distinguishable from
    # a genuine "no pull_request trigger" answer.
    yq_probe="$(yq -r '
      ((.on // .true) // {}) as $on
      | (($on | type) == "object") as $ok
      | (if $ok then ($on | has("pull_request")) else false end) as $pr
      | (if $pr
         then (($on["pull_request"] // {})
               | ((type == "object") and (has("paths") or has("paths-ignore"))))
         else false end) as $p
      | "\($pr) \($p)"' "$wf" 2>/dev/null || true)"
    case "$yq_probe" in
      "true true")  trigger_resolved=true; has_pr=true;  pr_has_paths=true ;;
      "true false") trigger_resolved=true; has_pr=true;  pr_has_paths=false ;;
      "false false") trigger_resolved=true; has_pr=false; pr_has_paths=false ;;
      *) : ;;  # unusable yq — fall through to the comment-stripped grep
    esac
  fi
  if [ "$trigger_resolved" != true ]; then
    if grep -q '^[[:space:]]*pull_request:' <<<"$wf_code"; then
      has_pr=true
      # Slice the block indented UNDER `pull_request:` — a `paths:` anywhere
      # else in the file belongs to another trigger or to a `run:` body.
      pr_block="$(awk '
        { if (inblk) {
            if ($0 ~ /^[[:space:]]*$/) next
            match($0, /^[[:space:]]*/)
            if (RLENGTH > base) { print; next }
            inblk = 0
          }
          if ($0 ~ /^[[:space:]]*pull_request:/) {
            match($0, /^[[:space:]]*/); base = RLENGTH; inblk = 1
          }
        }' <<<"$wf_code")"
      grep -qE '^[[:space:]]*(paths|paths-ignore):' <<<"$pr_block" && pr_has_paths=true || true
    fi
  fi
  if [ "$has_pr" = true ]; then
    if grep -q 'infra-compliance: paths-exempt' "$wf" 2>/dev/null; then
      filters_ok="N/A"
    elif [ "$pr_has_paths" = true ]; then
      filters_ok="✅"
    else
      filters_ok="⚠️"
    fi
  fi

  # Count checks
  checks=("$checkout_ok" "$claude_ok" "$perms_ok" "$filters_ok")
  for c in "${checks[@]}"; do
    [ "$c" != "N/A" ] && workflow_total=$((workflow_total+1)) || true
    [ "$c" = "✅" ] && workflow_pass=$((workflow_pass+1)) || true
  done

  row_status="✅"
  for s in "${checks[@]}"; do
    [ "$s" = "⚠️" ] && row_status="⚠️"
    [ "$s" = "❌" ] && row_status="❌" && break
  done

  workflow_rows+=("$wf_name | ${checkout_ver} | ${claude_ver} | $perms_ok | $filters_ok | $row_status")
done < <(find .github/workflows -maxdepth 1 -name '*.yml' -print0 2>/dev/null | sort -z)

##########
# 3. Version Consistency
##########

for plugin in "${plugin_dirs[@]}"; do
  version_total=$((version_total+1))

  pj_ver="N/A"; mf_ver="N/A"; mp_ver="N/A"

  [ -f "${plugin}/.claude-plugin/plugin.json" ] && \
    pj_ver=$(jq -r '.version // "N/A"' "${plugin}/.claude-plugin/plugin.json" 2>/dev/null)
  [ -f ".release-please-manifest.json" ] && \
    mf_ver=$(jq -r --arg p "$plugin" '.[$p] // "N/A"' .release-please-manifest.json 2>/dev/null)
  [ -f ".claude-plugin/marketplace.json" ] && \
    mp_ver=$(jq -r --arg p "$plugin" '(.plugins[] | select(.name == $p) | .version) // "N/A"' .claude-plugin/marketplace.json 2>/dev/null)

  match="✅"
  vers=()
  [ "$pj_ver" != "N/A" ] && vers+=("$pj_ver")
  [ "$mf_ver" != "N/A" ] && vers+=("$mf_ver")
  [ "$mp_ver" != "N/A" ] && vers+=("$mp_ver")

  if [ ${#vers[@]} -ge 2 ]; then
    first="${vers[0]}"
    for v in "${vers[@]}"; do
      [ "$v" != "$first" ] && match="❌" && break
    done
  fi

  [ "$match" = "✅" ] && version_pass=$((version_pass+1)) || true
  version_rows+=("$plugin | $pj_ver | $mf_ver | $mp_ver | $match")
done

##########
# 4. Skill Coverage
##########

for plugin in "${plugin_dirs[@]}"; do
  skill_total=$((skill_total+1))

  sc=0
  [ -d "${plugin}/skills" ] && \
    sc=$(find "${plugin}/skills" -type f \( -iname "SKILL.md" -o -iname "skill.md" \) 2>/dev/null | wc -l | tr -d ' ')

  total_skills_count=$((total_skills_count + sc))
  has_skills="✅"
  [ "$sc" -eq 0 ] && has_skills="❌"
  [ "$has_skills" = "✅" ] && skill_pass=$((skill_pass+1)) || true

  skill_rows+=("$plugin | $sc | $has_skills")
done

avg_skills="N/A"
[ "$skill_total" -gt 0 ] && avg_skills=$(echo "scale=1; $total_skills_count / $skill_total" | bc 2>/dev/null || echo "N/A")

##########
# 5. Security Posture
##########

while IFS= read -r -d '' wf; do
  wf_name=$(basename "$wf")
  security_total=$((security_total+1))

  # Length-anchored token patterns (#2555). The bare `sk-` alternative matched the
  # literal `task-` (taskwarrior-plugin paths, `test-task-id-stability.sh`,
  # `task-3.4.2.tar.gz`, `task-list tools`) — 4 false positives across two
  # workflows that reference no secret at all. No `\b`: GNU-only, breaks BSD grep
  # (.claude/rules/shell-scripting.md).
  if grep -qiE '(ghp_|gho_|github_pat_|sk-[A-Za-z0-9_-]{20,}|Bearer [A-Za-z0-9_.-]{20,})' "$wf" 2>/dev/null; then
    security_rows+=("🔴 | $wf_name | Token pattern detected")
  elif grep -qiE '(token|key|secret|password)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9+/=]{20,}' "$wf" 2>/dev/null; then
    security_rows+=("🔴 | $wf_name | Potential hardcoded secret")
  else
    security_pass=$((security_pass+1)) || true
  fi
done < <(find .github/workflows -maxdepth 1 -name '*.yml' -print0 2>/dev/null | sort -z)

# NOTE: a "Broad Bash permission (no command pattern)" 🟡 check used to sit here,
# flagging every skill whose `allowed-tools` grants a bare unscoped `Bash`. It was
# REMOVED deliberately — do not reinstate it.
#
# A bare `Bash` in a *skill's* `allowed-tools` is the ratified house standard, not a
# finding (see `.claude/rules/agentic-permissions.md`). Skill frontmatter can only
# SUBTRACT from the session's grants, never add, so enumerating narrow
# `Bash(<command> *)` patterns there buys no safety the settings.json layer isn't
# already providing — while costing a permission prompt for every command the author
# failed to predict. Narrow patterns belong in `settings.json`, which is where they
# actually gate anything.
#
# Left in place, this check scored the repo down for following its own standard: it
# fired on 191 of 408 SKILL.md files and inflated `security_total` once per offender
# while never incrementing `security_pass`, so the Security Posture score fell as the
# corpus grew more compliant. Its `find . -path '*/skills/*'` also had no
# `.claude/worktrees/` or `dist/` prune, so it re-walked every agent worktree clone
# and the OpenCode export build output (the #1492 / #1548 / #2214 class) — the >120s runtime
# and a double count.
#
# The real defect worth linting is the opposite one: a `Bash` grant in a skill that
# runs no shell at all. That is `scripts/check-unused-bash-grant.sh`, not this file.

##########
# Scoring
##########

calc_score() {
  local pass=$1 total=$2 weight=$3
  [ "$total" -eq 0 ] && echo "$weight" && return
  echo "$(( (pass * weight) / total ))"
}

score_registry=$(calc_score $registry_pass $registry_total 25)
score_workflow=$(calc_score $workflow_pass $workflow_total 25)
score_version=$(calc_score $version_pass $version_total 20)
score_skill=$(calc_score $skill_pass $skill_total 15)
score_security=$(calc_score $security_pass $security_total 15)
overall_score=$((score_registry + score_workflow + score_version + score_skill + score_security))

##########
# Output
##########

echo "## Infrastructure Compliance Dashboard: $CURRENT_MONTH"
echo ""
echo "### Overall Score: ${overall_score}/100"
echo ""

echo "### Registry Consistency"
echo "| Plugin | plugin.json | marketplace | release-config | manifest | Status |"
echo "|--------|-------------|-------------|----------------|----------|--------|"
for row in "${registry_rows[@]}"; do
  echo "| $row |"
done
echo ""

if [ ${#orphan_entries[@]} -gt 0 ]; then
  echo "**Orphaned entries:**"
  for entry in "${orphan_entries[@]}"; do
    echo "- $entry"
  done
  echo ""
fi

echo "### Workflow Health"
echo "| Workflow | Checkout | Claude Action | Permissions | Filters | Status |"
echo "|----------|----------|---------------|-------------|---------|--------|"
for row in "${workflow_rows[@]}"; do
  echo "| $row |"
done
echo ""

echo "### Version Consistency"
echo "| Plugin | plugin.json | manifest | marketplace | Match? |"
echo "|--------|-------------|----------|-------------|--------|"
for row in "${version_rows[@]}"; do
  echo "| $row |"
done
echo ""

echo "### Skill Coverage"
echo "| Plugin | Skills | Has Skills? |"
echo "|--------|--------|-------------|"
for row in "${skill_rows[@]}"; do
  echo "| $row |"
done
echo ""
echo "Total: ${#plugin_dirs[@]} plugins, $total_skills_count skills (avg ${avg_skills} skills/plugin)"
echo ""

echo "### Security Findings"
if [ ${#security_rows[@]} -gt 0 ]; then
  echo "| Severity | File | Finding |"
  echo "|----------|------|---------|"
  for row in "${security_rows[@]}"; do
    echo "| $row |"
  done
else
  echo "No security issues found."
fi
echo ""

echo "### Recommendations"
[ "$registry_pass" -lt "$registry_total" ] && echo "- Fix registry sync issues — ensure all plugins are in all 4 config files"
[ "$workflow_pass" -lt "$workflow_total" ] && echo "- Update workflow action versions and add path filters where missing"
[ "$version_pass" -lt "$version_total" ] && echo "- Resolve version mismatches across plugin.json, manifest, and marketplace"
[ "$skill_pass" -lt "$skill_total" ] && echo "- Add skills to plugins with 0 skills or consider removing empty plugins"
[ ${#security_rows[@]} -gt 0 ] && echo "- Address security findings — review flagged files"
if [ "$overall_score" -ge 95 ]; then
  echo "- All checks passed! Infrastructure is in good health."
fi
echo ""

echo "### Score Breakdown"
echo "| Category | Weight | Score | Details |"
echo "|----------|--------|-------|---------|"
echo "| Registry sync | 25% | ${score_registry}/25 | ${registry_pass}/${registry_total} checks passed |"
echo "| Workflow health | 25% | ${score_workflow}/25 | ${workflow_pass}/${workflow_total} checks passed |"
echo "| Version consistency | 20% | ${score_version}/20 | ${version_pass}/${version_total} plugins consistent |"
echo "| Skill coverage | 15% | ${score_skill}/15 | ${skill_pass}/${skill_total} plugins have skills |"
echo "| Security posture | 15% | ${score_security}/15 | ${security_pass}/${security_total} files clean |"

# Explicit terminal exit. Both audit scripts are REPORT GENERATORS consumed by
# scheduled-audits.yml, which gates on the report body, not on the exit code — so
# the contract is "always exit 0, having emitted a complete report". Without this
# line that contract is *incidental*: the exit status is whatever the last
# statement happened to return, so appending any command that can fail silently
# changes it and freezes the monthly job (the class scripts/tests/test-audit-scripts-exit.sh
# guards). State it rather than inherit it.
exit 0
