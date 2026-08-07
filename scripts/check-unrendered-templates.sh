#!/usr/bin/env bash
# Fail when a skill body ships Mustache/Jinja/Handlebars-style template
# conditionals that nothing renders.
#
# Background (issue #2265): `code-quality-plugin:code-lint` shipped four
# `{{ if PROJECT_TYPE == "python" }}` / `{{ endif }}` blocks. Claude Code does
# **not** render skill bodies — there is no template engine in the invocation
# path — so all four language branches arrived at the agent verbatim and the
# selection was left as an exercise. `PROJECT_TYPE` was never bound anywhere.
# The failure is silent: the skill loads, every structural lint passes, and the
# agent quietly picks a branch (or pastes `{{ endif }}` into a shell).
#
# Four more skills shipped the same defect (deps-install, project-init,
# bun-add, test-analyze). The fix in every case is the same shape: a detection
# step the agent actually performs, then a lookup table it reads.
#
# What is NOT flagged, and why:
#
#   1. Go / Helm chart templates. Helm genuinely renders these at deploy time,
#      so a skill documenting a chart must show them. Recognised structurally,
#      not by path: a `{{-` / `-}}` trim marker, a bare `{{ end }}` (Go's
#      terminator — Jinja uses `{{ endif }}`, Handlebars `{{/if}}`), or a
#      condition beginning with `.` or `$` (`.Values`, `$.Release`).
#   2. The literal ellipsis form `{{ if ... }}`. That is prose *referring to*
#      the syntax, never a real conditional.
#   3. A file that declares the render directive `markers after substitution`.
#      That phrase marks a generator template the skill instructs the agent to
#      render and strip while writing a file for the user — a deliberate,
#      documented pattern (hooks-plugin's hook-script templates). Declaring it
#      in the file keeps the exemption self-documenting and reviewable.
#
# Usage:
#   bash scripts/check-unrendered-templates.sh [--project-dir <path>]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd).
#
# Exit codes:
#   0 - no unrendered template conditionals
#   1 - at least one unrendered template conditional
#   2 - unknown argument

set -uo pipefail

# A file declaring this phrase is a generator template the skill renders itself.
RENDER_DIRECTIVE='markers after substitution'

# Path-scoped escapes for a file that genuinely cannot declare the directive.
# Format: <path-suffix>. Keep this empty unless there is no alternative — an
# entry here is a claim that unrendered markers in that file are correct.
UNRENDERED_TEMPLATE_EXCEPTIONS=()
# Test seam: extend the exception list without editing the script.
# shellcheck disable=SC2206  # intentional word-split of the test-seam env var
UNRENDERED_TEMPLATE_EXCEPTIONS+=(${CHECK_UNRENDERED_TEMPLATE_EXCEPTIONS:-})

proj_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$2"; shift 2 ;;
    *)
      echo "check-unrendered-templates.sh: unknown argument: $1" >&2
      echo "Usage: check-unrendered-templates.sh [--project-dir <path>]" >&2
      exit 2
      ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Scan from inside proj_dir with relative paths. An absolute base would make the
# `.claude/worktrees/` prune below fire on the whole tree whenever proj_dir is
# itself a worktree (its own path contains `.claude/worktrees/`), silently
# scanning nothing. Same reasoning as check-subagent-types.sh.
cd "$proj_dir" || { echo "check-unrendered-templates.sh: cannot cd to $proj_dir" >&2; exit 2; }

is_exception() {
  local candidate="${1#./}" entry
  for entry in ${UNRENDERED_TEMPLATE_EXCEPTIONS[@]+"${UNRENDERED_TEMPLATE_EXCEPTIONS[@]}"}; do
    [ -z "$entry" ] && continue
    case "$candidate" in
      "$entry" | */"$entry") return 0 ;;
    esac
  done
  return 1
}

plugin_dirs=()
while IFS= read -r -d '' plugin_dir; do
  plugin_dirs+=("$plugin_dir")
done < <(find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0)

# `.claude/worktrees/` copies are full repo checkouts made by concurrently
# running isolated agents; `dist/` is gitignored rulesync build output
# (#1492 / #1548 / #2214 class).
skill_files=()
if [ ${#plugin_dirs[@]} -gt 0 ]; then
  while IFS= read -r -d '' skill_file; do
    skill_files+=("$skill_file")
  done < <(
    find "${plugin_dirs[@]}" \
      -path '*/.claude/worktrees/*' -prune -o \
      -path '*/dist/*' -prune -o \
      -path '*/skills/*' -name '*.md' -type f -print0
  )
fi

errors=0
files_scanned=0
files_exempt=0
error_lines=()

echo "=== UNRENDERED TEMPLATE CONDITIONALS ==="

if [ ${#skill_files[@]} -eq 0 ]; then
  # Zero files is two very different states, and they must not look alike
  # (#2219 / #2290). Plugin dirs present but no skills discovered = the scan
  # misfired (typically a prune that matched the scan root); no plugin dirs at
  # all = genuinely nothing to check.
  if [ ${#plugin_dirs[@]} -gt 0 ]; then
    echo "FILES_SCANNED=0"
    echo "FILES_EXEMPT=0"
    echo "UNRENDERED_CONDITIONALS=0"
    echo "PLUGIN_DIRS=${#plugin_dirs[@]}"
    echo "STATUS=ERROR"
    echo "ISSUE_COUNT=1"
    echo "ISSUES:"
    echo "  - SEVERITY=ERROR TYPE=nothing_scanned MSG=${#plugin_dirs[@]} plugin dirs but zero skill files discovered; scan misfired (see #2219)"
    echo "=== END UNRENDERED TEMPLATE CONDITIONALS ==="
    exit 1
  fi
  # A checker that errors on a genuinely empty corpus gets disabled. Report and succeed.
  echo "FILES_SCANNED=0"
  echo "FILES_EXEMPT=0"
  echo "UNRENDERED_CONDITIONALS=0"
  echo "PLUGIN_DIRS=0"
  echo "SCANNED_EMPTY=true"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END UNRENDERED TEMPLATE CONDITIONALS ==="
  exit 0
fi

for skill_file in ${skill_files[@]+"${skill_files[@]}"}; do
  [ -f "$skill_file" ] || continue
  files_scanned=$((files_scanned + 1))
  rel_path="${skill_file#./}"

  if is_exception "$rel_path"; then
    files_exempt=$((files_exempt + 1))
    continue
  fi

  if grep -qiF "$RENDER_DIRECTIVE" "$skill_file" 2>/dev/null; then
    files_exempt=$((files_exempt + 1))
    continue
  fi

  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    line_no="${hit%%:*}"
    token="${hit#*:}"

    # Go / Helm: trim markers, or a condition rooted at `.` or `$`.
    case "$token" in
      '{{-'*|*'-}}') continue ;;
    esac
    cond="${token#\{\{}"
    cond="${cond#"${cond%%[![:space:]]*}"}"     # ltrim
    cond="${cond#[#/]}"                          # Handlebars open/close sigil
    cond="${cond#"${cond%%[![:space:]]*}"}"
    cond="${cond#if}"; cond="${cond#elif}"; cond="${cond#unless}"
    cond="${cond#for}"; cond="${cond#each}"
    cond="${cond#"${cond%%[![:space:]]*}"}"
    cond="${cond%\}\}}"
    cond="${cond%"${cond##*[![:space:]]}"}"      # rtrim
    # `$.` is Go's root context (`$.Values…`). A bare `$1`/`$3` is a SHELL
    # positional — exactly the defect (project-init shipped
    # `{{ if $3 == "--github" }}`), so the `$` rule must NOT swallow it.
    # `.[A-Za-z]` not a bare `.` — the looser form also swallows the `...`
    # ellipsis below, which would make that rule dead code.
    case "$cond" in
      .[A-Za-z]*|'$.'*) continue ;;              # Go: .Values / $.Release
      '...') continue ;;                         # prose reference to the syntax
    esac

    errors=$((errors + 1))
    error_lines+=("  - SEVERITY=ERROR TYPE=unrendered_template_conditional FILE=$rel_path LINE=$line_no TOKEN=$token")
    # Loop forms (`for`/`endfor`, Handlebars `#each`/`/each`) are in the keyword
    # set; Go's `range` deliberately is NOT — it is the ONLY loop keyword with a
    # legitimate rendered use in this corpus (four Helm chart examples), so
    # including it would trade a hypothetical catch for real false positives.
  done < <(grep -noE '\{\{-?[[:space:]]*[#/]?[[:space:]]*(if|elif|endif|unless|end[[:space:]]+unless|for|endfor|each)([[:space:]][^}]*)?[[:space:]]*-?\}\}' "$skill_file" 2>/dev/null || true)
done

echo "FILES_SCANNED=$files_scanned"
echo "FILES_EXEMPT=$files_exempt"
echo "UNRENDERED_CONDITIONALS=$errors"

if [ $errors -gt 0 ]; then
  echo "STATUS=ERROR"
else
  echo "STATUS=OK"
fi
echo "ISSUE_COUNT=$errors"

if [ $errors -gt 0 ]; then
  echo "ISSUES:"
  for line in ${error_lines[@]+"${error_lines[@]}"}; do echo "$line"; done
fi
echo "=== END UNRENDERED TEMPLATE CONDITIONALS ==="

if [ $errors -gt 0 ]; then
  echo "" >&2
  echo "Found $errors unrendered template conditional(s) in skill markdown." >&2
  echo "Claude Code renders nothing in a skill body — every branch reaches the" >&2
  echo "agent verbatim, and the condition variable is never bound. Replace the" >&2
  echo "conditionals with an explicit detection step plus a lookup table the" >&2
  echo "agent reads (see code-quality-plugin/skills/code-lint/SKILL.md)." >&2
  echo "" >&2
  echo "If the markers ARE a generator template the skill tells the agent to" >&2
  echo "render, say so in the file — a line containing \"$RENDER_DIRECTIVE\"" >&2
  echo "declares that intent and exempts the file (see" >&2
  echo "hooks-plugin/skills/hooks-session-start-hook/REFERENCE.md)." >&2
  echo "See issue #2265 and .claude/rules/agentic-optimization.md." >&2
  exit 1
fi

exit 0
