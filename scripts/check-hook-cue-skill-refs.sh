#!/usr/bin/env bash
# Every slash command a hook EMITS at runtime must name a skill/agent ID that
# actually resolves.
#
# Background (issue #2682): `code-quality-preflight-cue.sh` emitted
#
#   "[code-quality] Large/structural edit detected. Run /code-quality:code-lint …"
#
# as a `{"decision":"block","reason":…}` payload. The agent pasted that string
# into the `Skill` tool and got `Unknown skill: code-quality:code-lint`. The
# skill EXISTS (`code-quality-plugin/skills/code-lint/SKILL.md`) — the cue just
# named it with an ID that cannot resolve. Claude Code namespaces plugin skills
# as `<plugin-name>:<skill-name>`, and no plugin is called `code-quality`.
#
# The `/<ns>:<name>` short form is a DOC shorthand this repo invented for README
# tables (`scripts/check-docs-index.sh` Check 7 resolves it by trying plugin
# `<ns>-plugin` and skill dir `<ns>-<name>` or `<name>`). Prose a human reads can
# carry it. A string a hook emits cannot: the agent treats it as an invocation,
# and the failure surfaces only at call time, one wasted tool call later.
#
# This is a RESOLUTION check, not a denylist: ground truth is rebuilt from disk
# on every run, so renaming a skill directory is caught the moment it lands.
# Same shape as `scripts/check-skill-references.sh`, which covers SKILL.md /
# REFERENCE.md / *.workflow.js / .claude/rules — hook scripts are NOT in that
# script's coverage, which is why this defect went unguarded.
#
# GROUND TRUTH — an ID resolves if it matches either:
#   * `<plugin>/skills/<name>/SKILL.md`  -> `<plugin>:<name>`
#   * `<plugin>/agents/<name>.md`        -> `<plugin>:<name>`
#
# ENFORCED SCOPE (fails the build) — `code-quality-plugin/hooks/*.sh`, excluding
# `hooks/test-*.sh`. This is deliberately NARROWER than the live instances of
# the defect, and the narrowness is reported rather than hidden: the same short
# form is still emitted by hooks in ~12 other plugins. Sweeping them is a
# mechanical follow-up that touches 9 plugin directories at once, which is why
# it is staged rather than bundled here — the same staging
# `check-delegation-reachability.sh` used between #2442 (git-plugin only) and
# #2483 (whole marketplace). A guard that goes red on unrelated, unfixed files
# gets disabled, which is worse than a guard with an honest, reported scope.
#
# ADVISORY SCOPE (never fails, always reported) — every other
# `*-plugin/hooks/*.sh`. Unresolvable IDs there are counted and listed under
# `ADVISORY_*` so the remaining sweep is visible and SELF-UPDATING: when the
# follow-up lands, `ADVISORY_ISSUE_COUNT` drops to 0 on its own and the enforced
# scope can be widened by editing `ENFORCED_SCOPE_DIRS` below. Nothing here is a
# hand-maintained list of known-bad files (the drift trap of #2164).
#
# COMMENT LINES (`^[[:space:]]*#`) are skipped in both scopes and counted. A
# comment is not emitted output, and header comments legitimately quote the
# unresolvable short form in order to teach the invariant — flagging those is
# how a guard goes red on correct content.
#
# Exit codes:
#   0 - every emitted ID in the enforced scope resolves
#   1 - one or more unresolvable IDs in the enforced scope, or a broken walk
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Directories whose emitted hook cues are ENFORCED. Widen this list (and the
# pre-commit `files:` trigger) when the repo-wide sweep lands.
ENFORCED_SCOPE_DIRS="code-quality-plugin/hooks"

# Citation shape inside an emitted line: `/<ns>:<name>`.
#
# The left boundary `(^|[^A-Za-z0-9_/-])` earns its keep twice:
#   * it stops prose like "Cross-plugin:" yielding a phantom `ross-plugin:`;
#   * excluding `/` stops a git refspec (`refs/heads/x:refs/heads/x`) and any
#     other path-like `a/b:c` from reading as a slash command.
id_re='(^|[^A-Za-z0-9_/-])/[a-z][a-z0-9-]*:[a-z][a-z0-9-]*'

truth="$(mktemp)"
trap 'rm -f "$truth"' EXIT

{
  find . -type f -name 'SKILL.md' \
    -not -path './.claude/worktrees/*' -not -path './dist/*' \
    -not -path '*/node_modules/*' -print |
    sed -n 's#^\./\([^/]*\)/skills/\([^/]*\)/SKILL\.md$#\1:\2#p'
  find . -type f -name '*.md' -path '*/agents/*' \
    -not -path './.claude/worktrees/*' -not -path './dist/*' \
    -not -path '*/node_modules/*' -print |
    sed -n 's#^\./\([^/]*\)/agents/\([^/]*\)\.md$#\1:\2#p'
} | sort -u >"$truth"

truth_count="$(wc -l <"$truth" | tr -d ' ')"

# A ground truth of zero means the discovery walk broke, not that the tree is
# clean. Fail loudly: an unrun check and a passing check look identical
# otherwise (the empty-negative trap, #2219).
if [ "$truth_count" -eq 0 ]; then
  echo "=== HOOK CUE SKILL REFS ==="
  echo "TRUTH_COUNT=0"
  echo "ISSUE_COUNT=1"
  echo "STATUS=ERROR"
  echo "ISSUES:"
  echo "  - SEVERITY=error TYPE=broken_walk MSG=resolved 0 skills/agents on disk"
  echo "=== END HOOK CUE SKILL REFS ==="
  exit 1
fi

# Derive the resolvable replacement for a short-form ID, using the same
# shorthand mapping `scripts/check-docs-index.sh` Check 7 applies to README
# rows: plugin `<ns>-plugin`, skill dir `<ns>-<name>` or `<name>`.
suggest() {
  # `name` is a common shell collision (.claude/rules/shell-scripting.md) — prefix it.
  # `${ns}:${art_name}` is deliberately absent: it reconstructs `$id` itself,
  # and `suggest` is only reached after `grep -qxF "$id" "$truth"` has already
  # proved that ID absent from ground truth — so it could never match.
  local ns="${1%%:*}" art_name="${1#*:}" cand
  for cand in "${ns}-plugin:${ns}-${art_name}" "${ns}-plugin:${art_name}"; do
    if grep -qxF "$cand" "$truth"; then
      printf '%s' "$cand"
      return 0
    fi
  done
  return 1
}

files_scanned=0
refs_checked=0
comments_skipped=0
issue_count=0
issues=()

advisory_files_scanned=0
advisory_refs_checked=0
advisory_issue_count=0
advisory_files=()

scan_file() {
  local file="$1" enforced="$2" line_no content id fix leading_ws stripped
  local hits=0
  while IFS=: read -r line_no content; do
    # A comment is a line whose FIRST non-whitespace character is `#`. Test only
    # the leading run: the glob `[[:space:]]*\#*` reads as "one whitespace char,
    # then ANYTHING, then a `#`" — it matched any INDENTED line containing a `#`
    # anywhere, so an emitted cue citing an issue number (`(issue #2682)`) inside
    # an indented `case` block — exactly the shape of the real hook — silently
    # skipped the check it exists to enforce.
    leading_ws="${content%%[![:space:]]*}"
    stripped="${content#"$leading_ws"}"
    case "$stripped" in
      \#*)
        comments_skipped=$((comments_skipped + 1))
        continue
        ;;
    esac
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      if [ "$enforced" = "true" ]; then
        refs_checked=$((refs_checked + 1))
      else
        advisory_refs_checked=$((advisory_refs_checked + 1))
      fi
      grep -qxF "$id" "$truth" && continue
      hits=$((hits + 1))
      if [ "$enforced" = "true" ]; then
        if fix="$(suggest "$id")"; then
          issues+=("  - SEVERITY=error TYPE=unresolvable_cue_skill_id FILE=${file#./} LINE=${line_no} ID=${id} FIX=${fix}")
        else
          issues+=("  - SEVERITY=error TYPE=unresolvable_cue_skill_id FILE=${file#./} LINE=${line_no} ID=${id} FIX=<no skill or agent matches; check ${id%%:*}-plugin/skills/>")
        fi
        issue_count=$((issue_count + 1))
      else
        advisory_issue_count=$((advisory_issue_count + 1))
      fi
    done < <(printf '%s\n' "$content" | grep -oE "$id_re" | sed -E 's#^.*/##' || true)
  done < <(grep -nE "$id_re" "$file" || true)

  if [ "$enforced" != "true" ] && [ "$hits" -gt 0 ]; then
    advisory_files+=("  - FILE=${file#./} UNRESOLVABLE=${hits}")
  fi
}

while IFS= read -r -d '' file; do
  case "${file##*/}" in
    test-*) continue ;;
  esac
  enforced=false
  for dir in $ENFORCED_SCOPE_DIRS; do
    case "${file#./}" in
      "$dir"/*) enforced=true ;;
    esac
  done
  if [ "$enforced" = "true" ]; then
    files_scanned=$((files_scanned + 1))
  else
    advisory_files_scanned=$((advisory_files_scanned + 1))
  fi
  scan_file "$file" "$enforced"
done < <(find . -type f -name '*.sh' -path '*-plugin/hooks/*' \
  -not -path './.claude/worktrees/*' -not -path './dist/*' \
  -not -path '*/node_modules/*' -print0 | sort -z)

echo "=== HOOK CUE SKILL REFS ==="
echo "TRUTH_COUNT=$truth_count"
echo "ENFORCED_SCOPE=$ENFORCED_SCOPE_DIRS"
echo "SCOPE_IS_REPO_WIDE=false"
echo "FILES_SCANNED=$files_scanned"
echo "REFS_CHECKED=$refs_checked"
echo "COMMENTS_SKIPPED=$comments_skipped"
echo "ADVISORY_FILES_SCANNED=$advisory_files_scanned"
echo "ADVISORY_REFS_CHECKED=$advisory_refs_checked"
echo "ADVISORY_ISSUE_COUNT=$advisory_issue_count"
if [ "$advisory_issue_count" -gt 0 ]; then
  echo "ADVISORY_FILES:"
  printf '%s\n' "${advisory_files[@]}"
fi
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "STATUS=ERROR"
  echo "ISSUES:"
  printf '%s\n' "${issues[@]}"
else
  echo "STATUS=OK"
fi
echo "=== END HOOK CUE SKILL REFS ==="

[ "$issue_count" -eq 0 ] || exit 1
exit 0
