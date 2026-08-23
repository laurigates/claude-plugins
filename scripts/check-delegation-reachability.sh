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
# Three further shapes are NOT delegations and are exempt structurally
# (issue #2483, measured over the full 419-skill corpus):
#
#   A. SELF-REFERENCE. A skill naming its OWN slash command is documenting its
#      invocation, not delegating anywhere. `git-api-pr` writing `/git:api-pr`
#      in its own Quick Reference table is the modal case (6 of the 30).
#   B. THE PREAMBLE. Everything before the first `## ` heading — the YAML
#      frontmatter, the `# /ns:command` H1 title this repo puts there by
#      convention, and any lead paragraph — is not an instruction to the agent.
#      The scanner only sets `section` on H2, so that whole region used to be
#      judged with `section=""`, which `is_navigational_section` does not exempt.
#   C. TEACHING THE INVARIANT. A unit that states the sibling is gated,
#      human-only, or must not be invoked is stating this guard's OWN rule
#      correctly — flagging it would make the guard red on correct content,
#      which is how a guard gets disabled. `blueprint-autopilot` line 82
#      ("Work-order **creation stays human-only** (`/blueprint:work-order`
#      keeps `disable-model-invocation: true` — never invoke it from
#      autopilot)") is the canonical case. See GATED_STATEMENT_RE.
#
# This is the same instruction-vs-explanation discrimination
# `scripts/check-agent-tool-selection.sh` and
# `scripts/check-branch-containment-guidance.sh` already make.
#
# Gated status is read from the sibling's OWN frontmatter, never from a
# hardcoded list, so re-flagging (or unflagging) a skill re-decides every
# reference to it automatically.
#
# Scope: the audited skills, listed in DELEGATION_SCOPE_DEFAULT below. The audit
# set is NAMED in the output (`SCOPE=` / `AUDITED=`) so `STATUS=OK` can never be
# read as "the whole repo is clean" — it means "every file in AUDITED is clean"
# (#2219's zero-scan lesson, applied to a scoped guard).
#
# Why the scope is still git-plugin (issue #2483, measured 2026-08-23)
# --------------------------------------------------------------------
# A full-corpus run (all 419 `*-plugin/skills/*/SKILL.md`, via the
# CHECK_DELEGATION_SCOPE seam) was taken before and after the three exemptions
# above plus the sibling-resolution memoization:
#
#   before   FILES_SCANNED=419  ISSUE_COUNT=47  STATUS=ERROR  wall clock 247.3 s
#   after    FILES_SCANNED=419  ISSUE_COUNT=13  STATUS=ERROR  wall clock  15.4 s
#            SELF_REFS_SKIPPED=258  GATED_STATEMENT_EXEMPTIONS=3
#
# The 34 findings removed were all false positives (30 self-reference,
# 1 preamble, 3 teaching-the-invariant). PERFORMANCE IS NO LONGER THE BLOCKER:
# 15.4 s is inside a pre-commit budget, and 94% of the original 247 s was one
# `printf | grep -oE` per scanned LINE, not the sibling re-globbing.
#
# THE RESIDUAL FINDINGS ARE THE BLOCKER. All 13 are in `blueprint-plugin`, and
# each is a JUDGEMENT call — whether the reference should be rewritten into the
# recommendation form, or the sibling un-gated instead — reserved for the repo
# owner. Widening the default scope now would make this guard red on `main`
# over content nobody has adjudicated, and a guard that is red on `main` gets
# bypassed. So the scope stays git-plugin (where the #2442 defect lived) and
# `SCOPE_IS_REPO_WIDE=false` stays accurate; the residual list is recorded on
# issue #2483. Re-run the sweep with the seam above once those 13 are settled.
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

# Frontmatter read, in PURE BASH rather than the `head | grep | sed | tr`
# pipeline `.claude/rules/shell-scripting.md` documents. The pipeline is the
# right default; here it is the hot path — the whole-corpus sweep reads the
# frontmatter of all 419 skills, and four processes per read is ~1,700
# processes before a single line is judged (issue #2483). The parse is the
# same: first `^<field>:` line in the first 30, value trimmed of leading
# whitespace, `\r` and `"`.
FM_NAME=""
FM_GATED=0
read_frontmatter() {
  local skill_file="$1"
  local fm_line count=0 value
  FM_NAME=""
  FM_GATED=0
  while IFS= read -r fm_line; do
    count=$((count + 1))
    [ "$count" -le 30 ] || break
    case "$fm_line" in
      name:*)
        if [ -z "$FM_NAME" ]; then
          value="${fm_line#name:}"
          value="${value#"${value%%[![:space:]]*}"}"
          value="${value//$'\r'/}"
          value="${value//\"/}"
          FM_NAME="$value"
        fi
        ;;
      disable-model-invocation:*)
        # Mirrors the former `^disable-model-invocation:[[:space:]]*true`
        # exactly: leading whitespace only, then `true` — a value of
        # `false  # not true` must NOT read as gated.
        value="${fm_line#disable-model-invocation:}"
        value="${value#"${value%%[![:space:]]*}"}"
        case "$value" in
          true*) FM_GATED=1 ;;
        esac
        ;;
    esac
  done < "$skill_file"
}

declare -A GATED_CACHE=()

is_gated() {
  local skill_file="$1"
  if [ -z "${GATED_CACHE[$skill_file]+set}" ]; then
    read_frontmatter "$skill_file"
    GATED_CACHE[$skill_file]="$FM_GATED"
  fi
  [ "${GATED_CACHE[$skill_file]}" = "1" ]
}

# Sibling resolution is MEMOIZED per plugin (issue #2483). The unmemoized form
# re-globbed a plugin's skills — and ran a `head|grep|sed|tr` frontmatter read
# per sibling — for EVERY reference, so a 419-skill sweep spent 247 s almost
# entirely on re-reading the same frontmatter. Each plugin is indexed once.
declare -A SIBLING_INDEX=()
declare -A PLUGIN_INDEXED=()

index_plugin() {
  local plugin_dir="$1"
  [ -z "${PLUGIN_INDEXED[$plugin_dir]+set}" ] || return 0
  PLUGIN_INDEXED[$plugin_dir]=1

  local short="${plugin_dir%-plugin}"
  local sibling sibling_name key dir
  for sibling in "$plugin_dir"/skills/*/SKILL.md; do
    [ -f "$sibling" ] || continue
    read_frontmatter "$sibling"
    GATED_CACHE[$sibling]="$FM_GATED"
    sibling_name="$FM_NAME"
    if [ -z "$sibling_name" ]; then
      dir="${sibling%/SKILL.md}"
      sibling_name="${dir##*/}"
    fi
    # A reference resolves against the skill's own `name` and against the name
    # with the plugin prefix stripped (`/git:pr-feedback` -> `git-pr-feedback`),
    # which is how this marketplace spells invocations. Registering both keys
    # here reproduces the pre-memoization match rule; first writer wins, which
    # preserves the old first-match-in-glob-order behaviour.
    for key in "$sibling_name" "${sibling_name#"${short}-"}"; do
      [ -n "$key" ] || continue
      [ -n "${SIBLING_INDEX[$plugin_dir|$key]+set}" ] || SIBLING_INDEX[$plugin_dir|$key]="$sibling"
    done
  done
}

# Resolve `/<ns>:<token>` to a sibling SKILL.md inside the same plugin.
resolve_sibling() {
  local plugin_dir="$1" token="$2"
  index_plugin "$plugin_dir"
  local hit="${SIBLING_INDEX[$plugin_dir|$token]:-}"
  [ -n "$hit" ] || return 1
  printf '%s\n' "$hit"
  return 0
}

# A `/<ns>:<token>` invocation as this marketplace spells it.
REF_RE='/[a-z0-9][a-z0-9-]*:[a-z0-9][a-z0-9-]*'

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

# Class C (issue #2483): a unit that STATES the sibling is gated / human-only /
# must not be invoked is teaching this guard's own rule, not delegating. It is
# the single most important exemption: without it the guard is red on correct
# content, and a guard that is red on correct content gets disabled.
#
# Deliberately narrow — it must not swallow a bare imperative. Every
# alternative names the GATE itself (the flag, "human-only") or a PROHIBITION
# on invoking ("never invoke", "must not be run"). A hedge that merely mentions
# `manual` / `user-invocable` / `recommended` is NOT a gated statement, exactly
# as it is not a user referral.
GATED_STATEMENT_RE='never[[:space:]]+(invoke|call|run|use|dispatch|delegate)|(do[[:space:]]+not|does[[:space:]]+not|don.t|must[[:space:]]+not|may[[:space:]]+not|cannot|can.t|is[[:space:]]+not|are[[:space:]]+not)[[:space:]]+(be[[:space:]]+)?(invoke|invoked|invocable|call|called|run|reach|reachable|dispatch|delegated)|disable-model-invocation|human-only|human[[:space:]]+only|model[[:space:]]+cannot[[:space:]]+reach|unreachable[[:space:]]+from[[:space:]]+the[[:space:]]+model'

files_scanned=0
scope_size=0
audited=""
issue_count=0
self_refs_skipped=0
gated_statement_exemptions=0
issues=()

# Paths are normalized to the repo-relative form the sibling glob produces, so
# the Class A self-reference comparison below is a plain string equality
# regardless of how the caller spelled the scope entry.
for skill_path in $scope; do
  skill_path="${skill_path#./}"
  scope_size=$((scope_size + 1))
  audited="${audited:+$audited,}$skill_path"
done

for skill_path in $scope; do
  skill_path="${skill_path#./}"
  if [ ! -f "$skill_path" ]; then
    issues+=("  - SEVERITY=ERROR TYPE=scoped_skill_missing FILE=$skill_path MSG=scoped skill not found")
    issue_count=$((issue_count + 1))
    continue
  fi
  files_scanned=$((files_scanned + 1))

  plugin_dir="${skill_path%%/skills/*}"
  section=""
  # Class B (issue #2483): everything before the first `## ` heading — the YAML
  # frontmatter, the `# /ns:command` H1 title, any lead paragraph — is not an
  # action section. `section` is only set on H2, so that whole region used to be
  # judged with `section=""`, which `is_navigational_section` does not exempt.
  seen_h2=0

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
        seen_h2=1
        continue
        ;;
    esac

    # Class B: nothing before the first H2 is an instruction to act.
    [ "$seen_h2" -eq 1 ] || continue

    if is_navigational_section "$section"; then
      continue
    fi

    # Collect every `/ns:token` reference on the line.
    #
    # Pure bash, and gated behind a cheap `case` pre-filter. This runs on EVERY
    # line of every scanned file (~125,000 lines at full-corpus scope), so the
    # former `printf | grep -oE` cost two processes per line and was ~98% of the
    # 247 s sweep (issue #2483). Extraction is unchanged: leftmost-first, same
    # ERE, so the same tokens come out in the same order.
    case "$line" in
      *"/"*":"*) ;;
      *) continue ;;
    esac
    refs=""
    rest="$line"
    while [[ $rest =~ $REF_RE ]]; do
      refs="${refs}${BASH_REMATCH[0]}"$'\n'
      rest="${rest#*"${BASH_REMATCH[0]}"}"
    done
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

    # Matched with a HERE-STRING, never a pipe: under `pipefail` a `grep -q`
    # that matches and closes the pipe early can SIGPIPE the writer, so the
    # `if` flips nondeterministically on a long unit (#1744, #2462).
    hedged=0
    if grep -qiE "$USER_REFERRAL_RE" <<<"$unit"; then
      hedged=1
    fi

    # Class C: the unit teaches that the sibling is gated / human-only / must
    # not be invoked. Counted separately from the user-referral hedge so the
    # exemption is visible in the report rather than silently folded in.
    gated_statement=0
    if grep -qiE "$GATED_STATEMENT_RE" <<<"$unit"; then
      gated_statement=1
    fi

    for ref in $refs; do
      token="${ref#*:}"
      target="$(resolve_sibling "$plugin_dir" "$token")" || continue
      # Class A: a reference resolving to the scanned file ITSELF documents this
      # skill's own invocation. There is no delegation and no other skill.
      if [ "$target" = "$skill_path" ]; then
        self_refs_skipped=$((self_refs_skipped + 1))
        continue
      fi
      is_gated "$target" || continue
      [ "$hedged" -eq 0 ] || continue
      if [ "$gated_statement" -eq 1 ]; then
        gated_statement_exemptions=$((gated_statement_exemptions + 1))
        continue
      fi

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
# Emitted even at 0: an exemption that is never reported is indistinguishable
# from a checker that stopped judging anything (#2219 / #2255).
echo "SELF_REFS_SKIPPED=$self_refs_skipped"
echo "GATED_STATEMENT_EXEMPTIONS=$gated_statement_exemptions"
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
