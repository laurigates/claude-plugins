#!/usr/bin/env bash
# A blocking hook's test suite must read what the block SAYS, not only that it
# fired.
#
# Background (issue #2715): validate-pr-issue-links.sh and
# validate-kubectl-context.sh were credited with block messages that name the
# offending input and the concrete corrected form ("Commits in this branch
# reference:  Closes #1418 …", "kubectl --context=CONTEXT_NAME <command>"), so a
# block cost one retry. Both suites asserted only the exit code: their
# assert_exit helper ran the hook with `>/dev/null 2>&1`. Deleting the
# commit-derived keyword line, or reducing the kubectl block to a bare
# `block "blocked"`, left 22/22 and 53/53 green. check-pr-metadata-on-push.sh's
# suite had the same shape.
#
# SCOPE — every `<plugin>/hooks/test-<name>.sh` whose paired `<name>.sh` calls
# `block "…"` (the standard block() helper, .claude/rules/shell-scripting.md),
# at the start of a line or after a shell separator.
# Suites with no paired hook, and hooks that never call `block "`, are counted
# and skipped: a hook that signals through JSON `permissionDecision` has its own
# output contract and is not this class.
#
# ENFORCED (fails the build):
#   * output_never_captured — no logical line of the suite runs the hook with
#     stderr captured (`2>&1` inside `$(…)`/`<(…)` or piped onward, not in the
#     discarding `>/dev/null 2>&1` / `&>/dev/null` form; or `2>` to a file other
#     than /dev/null). block() writes to stderr, so a suite that never keeps
#     stderr cannot have asserted any message.
#   * message_unpinned — a block message whose headline tag (the leading
#     upper-case `WORD WORD:`, e.g. `KUBECTL SAFETY:`) is unique within its hook
#     does not have that tag on any non-comment line of the suite.
#
# REPORTED, NOT ENFORCED — messages whose headline tag is shared with another
# block in the same hook (`REMINDER:` ×16 in bash-antipatterns.sh), or that have
# no tag at all, cannot be told apart by a literal token, so the guard does not
# claim to have checked them. They are counted in MESSAGES_UNCHECKED and listed
# per suite under UNCHECKED, so the gap stays visible rather than passing as
# covered.
#
# This is a tripwire, not a proof: a tag in a test description string satisfies
# message_unpinned without an assertion reading it. The suites' own assertions,
# mutation-verified when they landed, carry the teeth; this guard stops a new
# blocking hook from shipping with an exit-code-only suite.
#
# Discovery runs from INSIDE the project root against relative paths at a fixed
# depth, so a root that is itself an agent worktree still scans (the #2219
# prune collapse). Zero suites found is STATUS=ERROR, never OK.
#
# Usage: check-hook-message-pins.sh [--project-dir DIR]
#
# Exit codes:
#   0 - every blocking-hook suite captures output and pins each unique headline
#   1 - one or more ENFORCED findings, nothing scanned, or bad arguments
set -euo pipefail

proj_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      [ $# -ge 2 ] || { echo "check-hook-message-pins: --project-dir needs a value" >&2; exit 1; }
      proj_dir="$2"
      shift 2
      ;;
    --project-dir=*)
      proj_dir="${1#*=}"
      shift
      ;;
    -h | --help)
      sed -n '2,/^set -euo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "check-hook-message-pins: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

cd "$proj_dir"

# Non-comment logical lines of a shell file: backslash continuations are joined
# so a hook invocation split across lines is judged as one command, and a line
# whose first non-whitespace character is `#` is dropped (a comment is neither
# an assertion nor a capture).
logical_lines() {
  awk '
    {
      line = $0
      if (sub(/\\$/, "", line)) { buf = buf line " "; next }
      line = buf line
      buf = ""
      probe = line
      sub(/^[[:space:]]+/, "", probe)
      if (substr(probe, 1, 1) == "#") next
      print line
    }
    END { if (buf != "") print buf }
  ' "$1"
}

# Does this logical line run the hook and keep its stderr?
captures_hook_stderr() {
  local line="$1" hook_base="$2" target
  # shellcheck disable=SC2016  # matching the literal text `$HOOK`, not expanding it
  case "$line" in
    *'$HOOK'* | *'${HOOK'* | *"$hook_base"*) ;;
    *) return 1 ;;
  esac
  # `$HOOK_DIR`-style siblings share the prefix; that over-match only widens
  # what counts as a hook reference, and the redirect test below still decides.
  if grep -qE '2>&1' <<<"$line"; then
    if grep -qE '>[[:space:]]*/dev/null[[:space:]]+2>&1|&>[[:space:]]*/dev/null' <<<"$line"; then
      return 1
    fi
    # Piped onward means a single `|`: `2>&1 || true` is an OR-list whose
    # output still goes to the suite's own stdout, unread.
    if grep -qE '\$\(|<\(' <<<"$line" || grep -qE '2>&1[^|]*\|([^|]|$)' <<<"$line"; then
      return 0
    fi
    return 1
  fi
  # `2>"$errfile"` / `2>/tmp/x` — stderr kept in a file the suite reads later.
  while IFS= read -r target; do
    target="${target#2>}"
    target="${target#"${target%%[![:space:]]*}"}"
    target="${target#[\"\']}"
    case "$target" in
      /dev/null*) ;;
      ?*) return 0 ;;
    esac
  done < <(grep -oE '2>[[:space:]]*[^&[:space:]][^[:space:]]*' <<<"$line" || true)
  return 1
}

suites_scanned=0
suites_unpaired=0
blocking_suites=0
block_messages=0
messages_checked=0
messages_unchecked=0
issue_count=0
issues=()
unchecked=()

while IFS= read -r -d '' suite; do
  suites_scanned=$((suites_scanned + 1))
  suite_rel="${suite#./}"
  hook="${suite%/*}/${suite##*/test-}"
  if [ ! -f "$hook" ]; then
    suites_unpaired=$((suites_unpaired + 1))
    continue
  fi
  hook_rel="${hook#./}"

  # A block() call at the start of a line, or after a separator (`*x*) block
  # "…" ;;`, `&& block "…"`, `then block "…"`). `emit_block "…"` and other
  # helpers whose names merely end in `block` do not match.
  block_lines="$(grep -nE '(^[[:space:]]*|[;&|)][[:space:]]*|(^|[[:space:]])(then|else|do)[[:space:]]+)block "' "$hook" \
    | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
  [ -n "$block_lines" ] || continue
  blocking_suites=$((blocking_suites + 1))

  suite_lines="$(logical_lines "$suite")"

  captures=0
  while IFS= read -r sline; do
    if captures_hook_stderr "$sline" "${hook##*/}"; then
      captures=$((captures + 1))
    fi
  done <<<"$suite_lines"

  # Headline = the literal text after `block "` up to the first expansion,
  # escape, or closing quote. Tag = its leading upper-case `WORD WORD:`.
  line_nos=()
  headlines=()
  tags=()
  while IFS=: read -r line_no content; do
    headline="$(sed -E 's/^.*block "//; s/[$"\\].*$//' <<<"$content")"
    tag="$(grep -oE '^[A-Z][A-Z0-9 _-]*:' <<<"$headline" || true)"
    line_nos+=("$line_no")
    headlines+=("$headline")
    tags+=("$tag")
  done <<<"$block_lines"

  n_blocks=${#line_nos[@]}
  block_messages=$((block_messages + n_blocks))

  if [ "$captures" -eq 0 ]; then
    issues+=("  - SEVERITY=ERROR TYPE=output_never_captured SUITE=${suite_rel} HOOK=${hook_rel} BLOCKS=${n_blocks} MSG=no line runs the hook with stderr kept, so no block message is asserted; capture it with out=\$(printf '%s' \"\$json\" | bash \"\$HOOK\" 2>&1 >/dev/null || true) and grep -qF the message")
    issue_count=$((issue_count + 1))
  fi

  suite_unchecked=0
  for i in "${!line_nos[@]}"; do
    tag="${tags[$i]}"
    uses=0
    if [ -n "$tag" ]; then
      for other in "${tags[@]}"; do
        [ "$other" = "$tag" ] && uses=$((uses + 1))
      done
    fi
    if [ -z "$tag" ] || [ "$uses" -gt 1 ]; then
      suite_unchecked=$((suite_unchecked + 1))
      continue
    fi
    messages_checked=$((messages_checked + 1))
    if ! grep -qF -- "$tag" <<<"$suite_lines"; then
      issues+=("  - SEVERITY=ERROR TYPE=message_unpinned SUITE=${suite_rel} HOOK=${hook_rel}:${line_nos[$i]} TAG=\"${tag}\" MSG=no non-comment suite line carries this block's headline tag; assert the message text, e.g. grep -qF \"${headlines[$i]}\"")
      issue_count=$((issue_count + 1))
    fi
  done

  if [ "$suite_unchecked" -gt 0 ]; then
    messages_unchecked=$((messages_unchecked + suite_unchecked))
    unchecked+=("  - SUITE=${suite_rel} HOOK=${hook_rel} MESSAGES=${suite_unchecked} REASON=headline_tag_shared_or_absent")
  fi
done < <(find . -mindepth 3 -maxdepth 3 -type f -path './*-plugin/hooks/test-*.sh' -print0 | sort -z)

echo "=== HOOK MESSAGE PINS ==="
echo "SUITES_SCANNED=$suites_scanned"
echo "SUITES_UNPAIRED=$suites_unpaired"
echo "BLOCKING_SUITES=$blocking_suites"
echo "BLOCK_MESSAGES=$block_messages"
echo "MESSAGES_CHECKED=$messages_checked"
echo "MESSAGES_UNCHECKED=$messages_unchecked"
if [ "${#unchecked[@]}" -gt 0 ]; then
  echo "UNCHECKED:"
  printf '%s\n' "${unchecked[@]}"
fi

# Zero suites means the walk found nothing to judge — an unrun check and a
# passing check must not look alike (#2219).
if [ "$suites_scanned" -eq 0 ]; then
  issues+=("  - SEVERITY=ERROR TYPE=nothing_scanned MSG=found no <plugin>/hooks/test-*.sh under ${proj_dir}")
  issue_count=$((issue_count + 1))
fi

echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "STATUS=ERROR"
  echo "ISSUES:"
  printf '%s\n' "${issues[@]}"
else
  echo "STATUS=OK"
fi
echo "=== END HOOK MESSAGE PINS ==="

[ "$issue_count" -eq 0 ] || exit 1
exit 0
