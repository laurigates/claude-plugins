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
# Four further shapes are NOT delegations and are exempt structurally
# (issue #2483, measured over the full-marketplace corpus):
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
#      which is how a guard gets disabled. The class was measured on
#      `blueprint-autopilot`'s "Work-order creation stays human-only
#      (`/blueprint:work-order` keeps `disable-model-invocation: true` — never
#      invoke it from autopilot)". ADR-0024 (#2592) later un-gated that sibling
#      and the sentence was rewritten, so it no longer reaches this class; the
#      class still covers every sentence that states a LIVE gate, such as the
#      `/git:pr-feedback` rows in git-plugin. See GATED_STATEMENT_RE.
#   D. A HEADING LINE. An ATX heading (`#`-prefixed) names a section; it is a
#      label, not an instruction to act. `document-linking` line 402 is the
#      literal H3 `### /blueprint:work-order`, flagged for titling the section
#      that documents that command. Same reasoning as class B, which already
#      exempts the `# /ns:command` H1 this repo puts above the first `## `.
#
# This is the same instruction-vs-explanation discrimination
# `scripts/check-agent-tool-selection.sh` and
# `scripts/check-branch-containment-guidance.sh` already make.
#
# Gated status is read from the sibling's OWN frontmatter, never from a
# hardcoded list, so re-flagging (or unflagging) a skill re-decides every
# reference to it automatically.
#
# Scope: every `*-plugin/skills/*/SKILL.md` in the marketplace, discovered at
# run time rather than listed (a hand-maintained list drifts from the corpus it
# mirrors — the #2164 lesson). The audit set is COUNTED in the output (`SCOPE=`
# / `AUDITED=` / `SCOPE_IS_REPO_WIDE=`) so `STATUS=OK` can never be read as more
# than "every file in the audit set is clean" (#2219's zero-scan lesson).
#
# Each scoped skill is read together with its SIDECARS — every other `*.md` in
# its directory (`REFERENCE.md`, `references/*.md`, `REFERENCE-<topic>.md`).
# Until 2026-10 only SKILL.md was read, so the split that moved reference
# material into `references/` also moved it out of this guard's sight. The
# first widened run found 7 gated-sibling references in sidecars: 2 stated the
# gate in words Class C did not yet know (now added), and 5 were the same
# `/blueprint:work-order` residuals #2483 already declares for their owning
# skills, which the skill-keyed allowlist below now covers. Sidecars are
# counted separately (`SIDECARS_SCANNED=`).
#
# The widening, and the declared residuals (issue #2483, measured 2026-09-04)
# --------------------------------------------------------------------------
# Full-corpus runs, via the CHECK_DELEGATION_SCOPE seam, on the corpus as it
# stood at each date:
#
#   2026-08-23 before  FILES_SCANNED=419  ISSUE_COUNT=47  wall clock 247.3 s
#   2026-08-23 after   FILES_SCANNED=419  ISSUE_COUNT=13  wall clock  15.3 s
#   2026-09-04 re-run  FILES_SCANNED=423  ISSUE_COUNT=13  wall clock  26.6 s
#                      SELF_REFS_SKIPPED=261  GATED_STATEMENT_EXEMPTIONS=3
#   2026-09-04 widened FILES_SCANNED=423  ISSUE_COUNT=0   wall clock   2.7 s
#                      SELF_REFS_SKIPPED=258  GATED_STATEMENT_EXEMPTIONS=3
#                      ALLOWLISTED=12  SCOPE_IS_REPO_WIDE=true
#
# The 34 findings #2487 removed were all false positives (30 self-reference,
# 1 preamble, 3 teaching-the-invariant). Performance stopped being a
# consideration at all: the re-run's 26.6 s was ~4,600 line-level marker
# matches, two `grep` forks each, on lines that mostly resolve to a non-gated
# sibling. Deferring both matches until a reference is KNOWN to be a gated
# cross-skill delegation drops that to ~30 and the sweep to 2.7 s, with the
# same regexes over the same unit — so pre-commit pays ~3 s on a skill edit
# rather than half a minute. `resolve_sibling` returns through a global for the
# same reason: a command substitution forks a subshell per reference.
#
# What DID block widening is that the 13 residuals — all in `blueprint-plugin`,
# all toward `/blueprint:work-order` or `/blueprint:prp-execute` — are each a
# judgement call (reword into the recommendation form, or un-gate the sibling)
# reserved for the repo owner. Widening with them unresolved would put the
# guard red on `main` over unadjudicated content, and a guard that is red on
# `main` gets bypassed.
#
# So they are DECLARED rather than hidden. Class D clears one of the 13; the
# rest are listed in DELEGATION_ALLOWLIST below, keyed on `<file>|<ref>` and
# owned by issue #2483. Consequences, all deliberate:
#
#   * Every skill in the marketplace is audited, and any NEW unreachable
#     delegation anywhere is blocking from this commit on.
#   * `ALLOWLISTED=` is emitted even at 0, so a suppressed finding is never
#     indistinguishable from no finding at all.
#   * An allowlist entry that matches nothing in the audited scope is itself an
#     ERROR (`stale_allowlist_entry`), so the list can only shrink. Deleting the
#     last entry needs no code change — the ratchet ends when #2483 is settled.
#   * The key is `<file>|<ref>`, not `<file>:<line>:<ref>`: a line number drifts
#     on every edit above it, and an allowlist that goes stale on unrelated
#     edits is noise. The cost is coarseness — a NEW bad reference to the same
#     gated sibling in an already-declared file is not caught. Same coarseness
#     as `check-agent-tool-selection.sh`'s directory-prefix allowlist.
#   * `<file>` is the OWNING SKILL.md even when the reference sits in one of its
#     sidecars, so moving declared text into `references/` keeps it declared.
#
# The residuals were settled by un-gating (issue #2592, ADR-0024)
# ---------------------------------------------------------------
# The repo owner chose to un-gate the sibling: `blueprint-work-order` and
# `blueprint-prp-execute` lost `disable-model-invocation: true`, so every
# declared reference became a reachable delegation, every key matched nothing,
# and all nine keys (17 suppressed findings by then, sidecars included) were
# deleted. DELEGATION_ALLOWLIST_DEFAULT is now EMPTY and the real-repo run
# reports `ALLOWLISTED=0 STATUS=OK`. The allowlist machinery stays, unused, so
# a future residual can be declared the same visible way; the regression test
# pins it through the CHECK_DELEGATION_ALLOWLIST seam and a seeded copy of
# this script rather than through the shipped default.
#
# Usage:
#   bash scripts/check-delegation-reachability.sh [--project-dir <path>]
#
# Test seams, each REPLACING the corresponding default so the regression test
# can exercise the checker against fixtures:
#   CHECK_DELEGATION_SCOPE      whitespace-separated repo-relative paths
#   CHECK_DELEGATION_ALLOWLIST  whitespace-separated `<file>|<ref>` keys
#
# They differ deliberately on the empty string. A scope must name at least one
# file to mean anything, so an empty CHECK_DELEGATION_SCOPE falls back to
# discovery; an empty CHECK_DELEGATION_ALLOWLIST is a meaningful value — "no
# declared residuals" — and is the documented way to see the raw residual set,
# so it is honoured rather than treated as unset (the #2521 lesson).
#
# Exit codes:
#   0 - no unreachable delegation found (STATUS=OK)
#   1 - at least one ERROR
#   2 - unknown argument

set -uo pipefail

# Declared residuals, keyed `<file>|<ref>`, newline- or space-separated. Each
# would be a reference a maintainer must adjudicate (reword into the
# recommendation form, or un-gate the sibling); until then it is suppressed
# EXPLICITLY rather than by narrowing the scope, and reported through
# ALLOWLISTED=. Remove an entry the moment its reference is settled — a key
# matching nothing is an ERROR, not a no-op.
#
# EMPTY since issue #2592 / ADR-0024 settled the #2483 residuals. Keep this
# assignment on one line: the regression test seeds a copy of this script by
# rewriting exactly this line.
DELEGATION_ALLOWLIST_DEFAULT=""

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

# The default corpus is DISCOVERED, never listed. `.claude/worktrees/` holds
# full clones of this repo and `dist/` holds generated copies; both would be
# double-counted (issues #1492 / #2214). The walk starts at `.` because the cd
# above already put us inside the root (#2219 / #2290).
discover_scope() {
  find . \
    -path './.claude/worktrees/*' -prune -o \
    -path './dist/*' -prune -o \
    -path '*-plugin/skills/*/SKILL.md' -print |
    sed 's|^\./||' |
    sort
}

scope_is_repo_wide=true
if [ -n "${CHECK_DELEGATION_SCOPE:-}" ]; then
  scope="$CHECK_DELEGATION_SCOPE"
  scope_is_repo_wide=false
else
  scope="$(discover_scope)"
fi

allowlist="${CHECK_DELEGATION_ALLOWLIST-$DELEGATION_ALLOWLIST_DEFAULT}"
declare -A ALLOWLIST_HIT=()
declare -A ALLOWLIST_KEYS=()
for entry in $allowlist; do
  ALLOWLIST_KEYS[$entry]=1
  ALLOWLIST_HIT[$entry]=0
done

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

# Resolve `/<ns>:<token>` to a sibling SKILL.md inside the same plugin. The hit
# lands in RESOLVED_SIBLING rather than on stdout: a command substitution forks
# a subshell per reference, and this runs thousands of times per sweep.
RESOLVED_SIBLING=""
resolve_sibling() {
  local plugin_dir="$1" token="$2"
  index_plugin "$plugin_dir"
  RESOLVED_SIBLING="${SIBLING_INDEX[$plugin_dir|$token]:-}"
  [ -n "$RESOLVED_SIBLING" ] || return 1
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
#
# `human-invoked` and `stays (with) the human` were added when the scan was
# widened to sidecars (2026-10): blueprint-autonomy-level3/REFERENCE.md
# ("promotion stays the human `/blueprint:work-order --from-issue N` act") and
# the v3.3->v3.4 migration ("the committing act stays with the human-invoked
# `/blueprint:work-order`") both state the gate, naming the human as the only
# actor. Both sentences were rewritten when ADR-0024 (#2592) un-gated that
# sibling; the two spellings stay, because they still describe a live gate
# wherever one exists.
GATED_STATEMENT_RE='never[[:space:]]+(invoke|call|run|use|dispatch|delegate)|(do[[:space:]]+not|does[[:space:]]+not|don.t|must[[:space:]]+not|may[[:space:]]+not|cannot|can.t|is[[:space:]]+not|are[[:space:]]+not)[[:space:]]+(be[[:space:]]+)?(invoke|invoked|invocable|call|called|run|reach|reachable|dispatch|delegated)|disable-model-invocation|human-only|human[[:space:]]+only|human-invoked|stays[[:space:]]+(with[[:space:]]+)?the[[:space:]]+human|model[[:space:]]+cannot[[:space:]]+reach|unreachable[[:space:]]+from[[:space:]]+the[[:space:]]+model'

files_scanned=0
scope_size=0
audited=""
issue_count=0
self_refs_skipped=0
gated_statement_exemptions=0
allowlisted=0
issues=()
allowlist_rows=()

# Paths are normalized to the repo-relative form the sibling glob produces, so
# the Class A self-reference comparison below is a plain string equality
# regardless of how the caller spelled the scope entry.
declare -A SCOPE_SET=()
for skill_path in $scope; do
  skill_path="${skill_path#./}"
  scope_size=$((scope_size + 1))
  SCOPE_SET[$skill_path]=1
  audited="${audited:+$audited,}$skill_path"
done

# Sidecars: every other `*.md` in a skill's directory — `REFERENCE.md`, the
# `references/*.md` files the 2026-10 split moved content into, and
# `REFERENCE-<topic>.md`. A gated sibling presented as an action there is the
# same dead end as in SKILL.md: the agent reads it while running the skill,
# usually out of context. Discovered ONCE and grouped by owning skill directory,
# so the per-skill cost is a lookup rather than a `find` fork.
declare -A SIDECARS=()
while IFS= read -r sidecar; do
  sidecar_rest="${sidecar#*/skills/}"
  sidecar_owner="${sidecar%%/skills/*}/skills/${sidecar_rest%%/*}"
  SIDECARS[$sidecar_owner]="${SIDECARS[$sidecar_owner]:-} $sidecar"
done < <(find . \
  -path './.claude/worktrees/*' -prune -o \
  -path './dist/*' -prune -o \
  -path '*-plugin/skills/*' -name '*.md' ! -name 'SKILL.md' -type f -print |
  sed 's|^\./||' |
  sort)

# Each scan unit is `<owning SKILL.md>|<file to scan>`. The owner is what
# Class A compares against (a sidecar naming its own skill's command documents
# that skill, it delegates nowhere); the scanned file is what FILE= and the
# allowlist key name.
scan_units=()
for skill_path in $scope; do
  skill_path="${skill_path#./}"
  scan_units+=("$skill_path|$skill_path")
  [ -f "$skill_path" ] || continue
  for sidecar in ${SIDECARS[${skill_path%/SKILL.md}]:-}; do
    scan_units+=("$skill_path|$sidecar")
  done
done

sidecars_scanned=0

for scan_unit in "${scan_units[@]}"; do
  skill_path="${scan_unit%%|*}"
  scan_file="${scan_unit#*|}"
  if [ ! -f "$scan_file" ]; then
    issues+=("  - SEVERITY=ERROR TYPE=scoped_skill_missing FILE=$scan_file MSG=scoped skill not found")
    issue_count=$((issue_count + 1))
    continue
  fi
  if [ "$scan_file" = "$skill_path" ]; then
    files_scanned=$((files_scanned + 1))
  else
    sidecars_scanned=$((sidecars_scanned + 1))
  fi

  plugin_dir="${skill_path%%/skills/*}"
  section=""
  # Class B (issue #2483): everything before the first `## ` heading — the YAML
  # frontmatter, the `# /ns:command` H1 title, any lead paragraph — is not an
  # action section. `section` is only set on H2, so that whole region used to be
  # judged with `section=""`, which `is_navigational_section` does not exempt.
  #
  # SKILL.md only. A sidecar has no frontmatter and no invocation title, and a
  # `references/*.md` file is often a single H1 over plain prose: exempting its
  # preamble would exempt the whole file. Headings are still skipped (Class D).
  if [ "$scan_file" = "$skill_path" ]; then
    seen_h2=0
  else
    seen_h2=1
  fi
  in_fence=0

  # Buffer the file: the referral marker is matched over the reference's
  # LOGICAL UNIT, not its raw line (#2442 review). This repo wraps prose at ~80
  # columns, so "recommend the user run" and the `/ns:token` it hedges routinely
  # land on different lines — a line-scoped match false-positives on correct
  # content the moment a paragraph is reflowed.
  file_lines=()
  while IFS= read -r line; do
    file_lines+=("$line")
  done < "$scan_file"

  total_lines=${#file_lines[@]}
  for (( idx = 0; idx < total_lines; idx++ )); do
    line="${file_lines[$idx]}"
    line_no=$((idx + 1))

    # Fence state, tracked only so Class D below can tell a heading from a shell
    # comment. Everything else is deliberately unchanged: content inside a fence
    # was judged before this class existed and still is.
    case "$line" in
      '```'*|'~~~'*) in_fence=$((1 - in_fence)) ;;
    esac

    case "$line" in
      "## "*)
        section="${line#\#\# }"
        seen_h2=1
        continue
        ;;
    esac

    # Class D (issue #2483): an ATX heading of any level names a section.
    # `### /blueprint:work-order` titles the block documenting that command; it
    # instructs nothing. Only H2 carries a section name, so the other levels are
    # simply skipped rather than recorded.
    #
    # Gated on NOT being inside a fenced block, because `#` also opens a shell
    # comment: an exemption blind to the fence would let a real delegation
    # written as `# Address it via /ns:gated-thing` inside a ```bash block
    # escape a guard that judged it before this class existed.
    if [ "$in_fence" -eq 0 ]; then
      case "$line" in
        "#"*) continue ;;
      esac
    fi

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

    # The two marker matches are the only forks left on this path, and they run
    # once per LINE carrying a `/ns:token`, most of which resolve to a
    # non-gated sibling or to the file itself. So they are computed LAZILY —
    # only once a reference is known to be a gated cross-skill delegation, the
    # rare case. Same regexes, same unit, same verdict; ~4,600 line-level
    # matches on a full-corpus sweep become ~30 (issue #2483).
    markers_ready=0
    hedged=0
    gated_statement=0

    for ref in $refs; do
      token="${ref#*:}"
      resolve_sibling "$plugin_dir" "$token" || continue
      target="$RESOLVED_SIBLING"
      # Class A: a reference resolving to the scanned file ITSELF documents this
      # skill's own invocation. There is no delegation and no other skill.
      if [ "$target" = "$skill_path" ]; then
        self_refs_skipped=$((self_refs_skipped + 1))
        continue
      fi
      is_gated "$target" || continue

      if [ "$markers_ready" -eq 0 ]; then
        markers_ready=1
        # Matched with a HERE-STRING, never a pipe: under `pipefail` a `grep -q`
        # that matches and closes the pipe early can SIGPIPE the writer, so the
        # `if` flips nondeterministically on a long unit (#1744, #2462).
        if grep -qiE "$USER_REFERRAL_RE" <<<"$unit"; then
          hedged=1
        fi
        # Class C: the unit teaches that the sibling is gated / human-only /
        # must not be invoked. Counted separately from the user-referral hedge
        # so the exemption is visible in the report rather than folded in.
        if grep -qiE "$GATED_STATEMENT_RE" <<<"$unit"; then
          gated_statement=1
        fi
      fi

      [ "$hedged" -eq 0 ] || continue
      if [ "$gated_statement" -eq 1 ]; then
        gated_statement_exemptions=$((gated_statement_exemptions + 1))
        continue
      fi

      # Declared residual (issue #2483): suppressed, counted, and named — never
      # silent. Applied LAST so a reference the classes above already exempt
      # never marks an allowlist key hit, which would hide the key going stale.
      # Keyed on the OWNING skill, not the scanned file: a declaration covers
      # the skill, and a skill is its SKILL.md plus its sidecars. Keyed on the
      # file, every split that moves declared text into `references/` would
      # turn one residual into a new error AND a stale-entry error.
      allow_key="$skill_path|$ref"
      if [ -n "${ALLOWLIST_KEYS[$allow_key]+set}" ]; then
        ALLOWLIST_HIT[$allow_key]=1
        allowlisted=$((allowlisted + 1))
        allowlist_rows+=("  - TYPE=allowlisted_delegation FILE=$scan_file LINE=$line_no REF=$ref TARGET=$target SECTION=${section:-<none>} OWNER=#2483")
        continue
      fi

      issues+=("  - SEVERITY=ERROR TYPE=unreachable_delegation FILE=$scan_file LINE=$line_no REF=$ref TARGET=$target SECTION=${section:-<none>} MSG=gated sibling presented as an agent action; recommend it to the user instead")
      issue_count=$((issue_count + 1))
    done
  done
done

# Zero discovered skills while plugin directories exist is a misfired walk, not
# a clean marketplace, and the two must never report the same thing (#2219 /
# #2290). A tree with no plugin directories at all stays OK — a guard that
# errors on a legitimately empty corpus gets disabled.
if [ "$scope_is_repo_wide" = "true" ] && [ "$scope_size" -eq 0 ]; then
  if compgen -G '*-plugin/skills' >/dev/null 2>&1; then
    issues+=("  - SEVERITY=ERROR TYPE=nothing_scanned MSG=plugin skill directories exist but discovery found no SKILL.md; the walk misfired")
    issue_count=$((issue_count + 1))
  fi
fi

# An allowlist key that matched nothing is stale — the reference it declared is
# gone, renamed, or already fixed — so it must be REMOVED, not left to suppress
# a future finding silently. Only keys whose file is in the audited scope are
# judged: under a narrowing seam the rest are simply out of view, not stale.
for allow_key in "${!ALLOWLIST_KEYS[@]}"; do
  [ "${ALLOWLIST_HIT[$allow_key]}" -eq 0 ] || continue
  allow_file="${allow_key%%|*}"
  [ -n "${SCOPE_SET[$allow_file]+set}" ] || continue
  issues+=("  - SEVERITY=ERROR TYPE=stale_allowlist_entry KEY=$allow_key MSG=allowlisted delegation no longer found; remove the entry from DELEGATION_ALLOWLIST_DEFAULT")
  issue_count=$((issue_count + 1))
done

echo "=== DELEGATION REACHABILITY ==="
# SCOPE / AUDITED / SCOPE_IS_REPO_WIDE name the audit set, so a consumer cannot
# read STATUS=OK as more than "every file in the audit set is clean" (#2442
# review). The repo-wide default names the DISCOVERY RULE rather than listing
# 400+ paths, which would bury every other line of the report.
echo "SCOPE=$scope_size"
if [ "$scope_is_repo_wide" = "true" ]; then
  echo "AUDITED=<discovered> *-plugin/skills/*/SKILL.md + sidecar *.md"
else
  echo "AUDITED=$audited"
fi
echo "SCOPE_IS_REPO_WIDE=$scope_is_repo_wide"
echo "FILES_SCANNED=$files_scanned"
# Sidecars are counted apart from FILES_SCANNED so a skill count stays a skill
# count, and so a walk that stopped finding sidecars is visible as a 0 here.
echo "SIDECARS_SCANNED=$sidecars_scanned"
if [ "$files_scanned" -eq 0 ]; then
  echo "SCANNED_EMPTY=true"
else
  echo "SCANNED_EMPTY=false"
fi
# Emitted even at 0: an exemption that is never reported is indistinguishable
# from a checker that stopped judging anything (#2219 / #2255).
echo "SELF_REFS_SKIPPED=$self_refs_skipped"
echo "GATED_STATEMENT_EXEMPTIONS=$gated_statement_exemptions"
echo "ALLOWLISTED=$allowlisted"
if [ "$allowlisted" -gt 0 ]; then
  echo "ALLOWLISTED_DELEGATIONS:"
  for entry in "${allowlist_rows[@]}"; do
    echo "$entry"
  done
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
