#!/usr/bin/env bash
# Verify a catalog-present skill never presents a `disable-model-invocation`
# sibling as an action the agent can take.
#
# Background (issue #2442): `git-pr-watch` is catalog-present, and its reaction
# table said "Address it via `/git:pr-feedback`". `git-pr-feedback` carries
# `disable-model-invocation: true`, so the model cannot reach it. Unlike #1843
# — where the delegation went through the `Skill` tool and failed loudly
# ("cannot be used with Skill tool due to disable-model-invocation") — this
# delegation is PROSE, so there is no tool call to refuse: the agent reads the
# instruction, cannot act on it, and improvises or drops the thread. Nothing is
# logged anywhere. That silence is why a guard is needed at all.
#
# The rule enforced: inside an ACTION section, a reference to a gated sibling
# must carry a user-referral marker that names the USER as the actor
# ("recommend the user run …", "surface it for the user", "hand it to the
# user"), so the skill tells the agent to hand the work off rather than perform
# it. A bare `recommend` / `suggest` / `manual` / `user-invocable` somewhere on
# the line does NOT qualify — see USER_REFERRAL_RE below. Purely navigational
# sections ("When to Use This Skill", "Related Skills", "See Also") are exempt —
# a pointer there is not an instruction to act.
#
# Gated status is read from the sibling's OWN frontmatter, never from a
# hardcoded list, so re-flagging (or unflagging) a skill re-decides every
# reference to it automatically.
#
# Scope: the audited skills, listed in DELEGATION_SCOPE_DEFAULT below. The audit
# set is NAMED in the output (`SCOPE=` / `AUDITED=`) so `STATUS=OK` can never be
# read as "the whole repo is clean" — it means "every file in AUDITED is clean"
# (#2219's zero-scan lesson, applied to a scoped guard). Widening the sweep to
# every catalog-present skill in every plugin is tracked separately as
# issue #2483; this guard covers git-plugin, where the reported defect lived.
#
# Usage:
#   bash scripts/check-delegation-reachability.sh [--project-dir <path>]
#
# Test seam: CHECK_DELEGATION_SCOPE (whitespace-separated repo-relative paths)
# REPLACES the default scope so the regression test can exercise the checker
# against fixtures.
#
# Exit codes:
#   0 - no unreachable delegation found (STATUS=OK)
#   1 - at least one ERROR
#   2 - unknown argument

set -uo pipefail

# Skills audited for this defect. Repo-relative paths.
# Every git-plugin skill that references a gated sibling from an action section.
DELEGATION_SCOPE_DEFAULT="git-plugin/skills/git-pr-watch/SKILL.md
git-plugin/skills/git-pr-sync-check/SKILL.md
git-plugin/skills/git-triage/SKILL.md
git-plugin/skills/git-coworker-check/SKILL.md
git-plugin/skills/deadbranch/SKILL.md"

proj_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      proj_dir="${2:-}"
      shift 2
      ;;
    *)
      printf 'check-delegation-reachability.sh: unknown argument: %s\n' "$1" >&2
      printf 'usage: check-delegation-reachability.sh [--project-dir <path>]\n' >&2
      exit 2
      ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Run discovery from INSIDE the root against relative paths: an absolute scan
# base whose own path contains `.claude/worktrees/` matches its own prune and
# silently scans nothing (issue #2219).
cd "$proj_dir" 2>/dev/null || {
  printf 'check-delegation-reachability.sh: cannot enter project dir: %s\n' "$proj_dir" >&2
  exit 2
}

scope="${CHECK_DELEGATION_SCOPE:-$DELEGATION_SCOPE_DEFAULT}"

# Frontmatter field read (`.claude/rules/shell-scripting.md`).
extract_field() {
  local skill_file="$1" field="$2"
  head -30 "$skill_file" | grep -m1 "^${field}:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r"'
}

is_gated() {
  local skill_file="$1"
  head -30 "$skill_file" | grep -qE '^disable-model-invocation:[[:space:]]*true'
}

# Resolve `/<ns>:<token>` to a sibling SKILL.md inside the same plugin.
# Accepts the skill's own `name` and the name with the plugin prefix stripped
# (`/git:pr-feedback` -> `git-pr-feedback`), which is how this marketplace
# spells invocations.
resolve_sibling() {
  local plugin_dir="$1" token="$2"
  local short="${plugin_dir%-plugin}"
  local sibling sibling_name
  for sibling in "$plugin_dir"/skills/*/SKILL.md; do
    [ -f "$sibling" ] || continue
    sibling_name="$(extract_field "$sibling" "name")"
    [ -n "$sibling_name" ] || sibling_name="$(basename "$(dirname "$sibling")")"
    if [ "$sibling_name" = "$token" ] || [ "$sibling_name" = "${short}-${token}" ]; then
      printf '%s\n' "$sibling"
      return 0
    fi
  done
  return 1
}

# A section whose job is navigation, not action. A pointer here says "that
# other skill exists"; it never tells the agent to go do something.
is_navigational_section() {
  case "$1" in
    "When to Use This Skill"|Related*|"See Also") return 0 ;;
    *) return 1 ;;
  esac
}

# A user-referral marker must name the USER as the actor. A bare `suggest`,
# `recommend`, `manual` or `user-invocable` ANYWHERE on the line is NOT enough
# (#2442 review): "Address it via `/git:pr-feedback` (user-invocable)" is still
# an imperative aimed at the agent, and the loose form let it through. Each
# alternative below binds a referral verb to "the user".
USER_REFERRAL_RE='(recommend|suggest)[a-z]*[^a-z]+(that[[:space:]]+)?the[[:space:]]+user|surface[a-z]*[^.|]*for[[:space:]]+the[[:space:]]+user|for[[:space:]]+the[[:space:]]+user[[:space:]]+to[[:space:]]+(run|invoke|apply|drive)|the[[:space:]]+user[[:space:]]+(can|should|must|will)[[:space:]]+(run|invoke|apply|type)|ask[[:space:]]+the[[:space:]]+user[[:space:]]+to[[:space:]]+(run|invoke|apply)|hand[a-z]*[^.|]*(off[[:space:]]+)?to[[:space:]]+the[[:space:]]+user|leave[a-z]*[^.|]*to[[:space:]]+the[[:space:]]+user'

files_scanned=0
scope_size=0
audited=""
issue_count=0
issues=()

for skill_path in $scope; do
  scope_size=$((scope_size + 1))
  audited="${audited:+$audited,}$skill_path"
done

for skill_path in $scope; do
  if [ ! -f "$skill_path" ]; then
    issues+=("  - SEVERITY=ERROR TYPE=scoped_skill_missing FILE=$skill_path MSG=scoped skill not found")
    issue_count=$((issue_count + 1))
    continue
  fi
  files_scanned=$((files_scanned + 1))

  plugin_dir="${skill_path%%/skills/*}"
  section=""

  # Buffer the file: the referral marker is matched over the reference's
  # LOGICAL UNIT, not its raw line (#2442 review). This repo wraps prose at ~80
  # columns, so "recommend the user run" and the `/ns:token` it hedges routinely
  # land on different lines — a line-scoped match false-positives on correct
  # content the moment a paragraph is reflowed.
  file_lines=()
  while IFS= read -r line; do
    file_lines+=("$line")
  done < "$skill_path"

  total_lines=${#file_lines[@]}
  for (( idx = 0; idx < total_lines; idx++ )); do
    line="${file_lines[$idx]}"
    line_no=$((idx + 1))

    case "$line" in
      "## "*)
        section="${line#\#\# }"
        continue
        ;;
    esac

    if is_navigational_section "$section"; then
      continue
    fi

    # Collect every `/ns:token` reference on the line.
    refs="$(printf '%s\n' "$line" | grep -oE '/[a-z0-9][a-z0-9-]*:[a-z0-9][a-z0-9-]*' || true)"
    [ -n "$refs" ] || continue

    # The unit a marker may live in:
    #   * a table row  -> that row alone. A markdown row cannot be reflowed
    #     without breaking the table, and merging adjacent rows would let one
    #     row's hedge exempt a different row's imperative.
    #   * prose        -> the contiguous paragraph (bounded by a blank line, a
    #     heading, a fence, or a table row), which is exactly the span a reflow
    #     can move text within.
    case "$line" in
      \|*|[[:space:]]\|*)
        unit="$line"
        ;;
      *)
        unit="$line"
        for (( up = idx - 1; up >= 0; up-- )); do
          case "${file_lines[$up]}" in
            ''|'#'*|'|'*|'```'*|'~~~'*) break ;;
          esac
          unit="${file_lines[$up]} $unit"
        done
        for (( down = idx + 1; down < total_lines; down++ )); do
          case "${file_lines[$down]}" in
            ''|'#'*|'|'*|'```'*|'~~~'*) break ;;
          esac
          unit="$unit ${file_lines[$down]}"
        done
        ;;
    esac

    hedged=0
    if printf '%s\n' "$unit" | grep -qiE "$USER_REFERRAL_RE"; then
      hedged=1
    fi

    for ref in $refs; do
      token="${ref#*:}"
      target="$(resolve_sibling "$plugin_dir" "$token")" || continue
      is_gated "$target" || continue
      [ "$hedged" -eq 0 ] || continue

      issues+=("  - SEVERITY=ERROR TYPE=unreachable_delegation FILE=$skill_path LINE=$line_no REF=$ref TARGET=$target SECTION=${section:-<none>} MSG=gated sibling presented as an agent action; recommend it to the user instead")
      issue_count=$((issue_count + 1))
    done
  done
done

echo "=== DELEGATION REACHABILITY ==="
# SCOPE / AUDITED name the audit set, so a consumer cannot read STATUS=OK as
# "the repo is clean" — it means "every file in AUDITED is clean" (#2442 review).
echo "SCOPE=$scope_size"
echo "AUDITED=$audited"
echo "SCOPE_IS_REPO_WIDE=false"
echo "FILES_SCANNED=$files_scanned"
if [ "$files_scanned" -eq 0 ]; then
  echo "SCANNED_EMPTY=true"
else
  echo "SCANNED_EMPTY=false"
fi
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "STATUS=ERROR"
  echo "ISSUES:"
  for entry in "${issues[@]}"; do
    echo "$entry"
  done
else
  echo "STATUS=OK"
fi
echo "=== END DELEGATION REACHABILITY ==="

[ "$issue_count" -eq 0 ] || exit 1
exit 0
