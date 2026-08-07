#!/usr/bin/env bash
# Guard the branch-containment guidance this marketplace hands to agents.
#
# Background (issue #2268): `git-plugin/agents/git-ops.md` told agents to
# "Prefer the encoded recipe" and routed them to `just -g branch-audit` — a
# recipe that lives in a PRIVATE dotfiles repo this marketplace can neither
# version nor regression-test. Ten lines below, the same file gave the correct
# manual ladder (a MERGED PR is authoritative, then `git cherry`), so the
# agent's documented fallback was more correct than the tool it recommended.
#
# Measured 2026-08-04, the recipe's REVIEW bucket was ~90% FALSE on two repos:
#   laurigates/claude-plugins        191 REVIEW rows, 174 had landed  (91%)
#   ForumViriumHelsinki/infrastructure 245 REVIEW rows, 216 had landed (88%)
# Two silent defects caused it, and both are what this guard pins:
#   1. `git merge-tree` used as the PRIMARY signal. Per
#      `~/.claude/rules/pr-merge-hazards.md` #1 tree-containment is one-way:
#      once the base drifts over the same files the trees differ for work that
#      fully landed, so a non-match proves NOTHING. 132 branches lost this way.
#   2. `gh pr list --limit 500` against repos holding 1881 and 1684 PRs. Any
#      branch whose merged PR fell outside the page read as "no PR" and was
#      misclassified. 32 more branches. The exact per-branch form
#      (`gh pr list --head <branch> --state all`) is unaffected by the cap —
#      see `.claude/rules/gh-json-fields.md` § "Default list cap".
#
# Neither defect surfaces as an error, which is why a lint is the only thing
# that keeps the corrected routing from silently reverting.
#
# Rules (all ERROR):
#   (1) branch_audit_uncaveated  — a git-plugin markdown file naming
#       `branch-audit` must carry BOTH caveat tokens (`REVIEW bucket` and
#       `#2268`), so a reader learns the measured false rate at the mention.
#   (2) recipe_before_ladder     — the first `branch-audit` mention must come
#       AFTER the first authoritative `gh pr list ... --head` line. Naming the
#       recipe first is what "prefer the encoded recipe" did.
#   (3) merge_tree_before_pr     — the first `merge-tree` line must come AFTER
#       the first authoritative `gh pr list ... --head` line. merge-tree is a
#       positive-containment shortcut, never the primary signal.
#   (4) merge_tree_uncaveated    — a file using `merge-tree` for BRANCH
#       containment must carry the `positive-containment` token.
#   (6) ladder_missing           — a file giving branch-containment guidance
#       (it names `branch-audit`, or uses merge-tree for containment) with NO
#       authoritative `gh pr list ... --head` line at all. This also keeps
#       rules 2 and 3 from going vacuous if that line is ever deleted.
#   (7) nothing_scanned          — plugin dirs are present but ZERO markdown was
#       discovered, i.e. the walk misfired (#2219). A tree with no plugin dirs
#       at all stays green — a checker that errors on a legitimately empty
#       corpus gets disabled, which would make the loud case worthless.
#   (5) paginated_containment    — a `gh pr list` line that combines a bare
#       `--limit N` / `-L N` with a merged-state determination (`state` or
#       `mergedAt` in `--json`) and NO `--head` is the #2268 defect #2.
#
# Deliberately NARROW so the check does not become noise that gets disabled:
#   - Rules 1-4 scan `git-plugin/**/*.md` only. That is where the routing an
#     agent acts on lives. `.claude/rules/gh-json-fields.md` and
#     `~/.claude/rules/pr-merge-hazards.md` TEACH these traps and must be free
#     to quote the broken forms verbatim — the same instruction-vs-explanation
#     discrimination `check-agent-tool-selection.sh` already makes.
#   - Rule 5 scans `*-plugin/**/*.md` (any plugin can hand out a `gh pr list`),
#     but fires only when the line ALSO asks for `state`/`mergedAt`, i.e. is a
#     containment/merged-state determination. A scope-discovery listing such as
#     `gh pr list --state merged -L 30 --json title` is not flagged.
#   - Blockquote lines (`>`) and lines marked as anti-examples (`# Wrong`,
#     `# Don't`, `# Never`, `# Anti-pattern`, on the line or the one above) are
#     skipped everywhere, so a gotcha callout can still show the broken form.
#
# Usage:
#   bash scripts/check-branch-containment-guidance.sh
#   bash scripts/check-branch-containment-guidance.sh --root <dir>   # test seam
#
# Exit codes:
#   0 - STATUS=OK
#   1 - STATUS=ERROR (one or more issues)
#   2 - unknown argument (fail fast rather than swallow a typo'd flag, #2057)

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  echo "usage: check-branch-containment-guidance.sh [--root <dir>]" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      shift
      [ $# -gt 0 ] || { echo "check-branch-containment-guidance.sh: --root needs a value" >&2; usage; exit 2; }
      ROOT_DIR="$1"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "check-branch-containment-guidance.sh: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

# The literal tokens a caveat must carry. Pinning specific strings (rather than
# "some prose nearby") is what makes this a SEMANTIC gate: a bulk edit that
# tightens the paragraph away trips the check.
CAVEAT_MEASURED="REVIEW bucket"
CAVEAT_ISSUE="#2268"
MERGE_TREE_CAVEAT="positive-containment"

issues=()
files_scanned=0

# collect_md <subdir-relative-to-ROOT_DIR> — emit markdown paths RELATIVE to
# ROOT_DIR, pruning agent worktree clones (#1492/#1548) and the gitignored
# rulesync build output (#2214); both are copies of the repo and would
# double-count.
#
# The walk runs from a `cd "$ROOT_DIR"` with a relative start on purpose. An
# absolute-path walk makes `-path '*/.claude/worktrees/*'` match EVERY result
# whenever ROOT_DIR itself sits inside an agent worktree (a very normal state in
# this repo), silently pruning the entire corpus and reporting a vacuous OK.
collect_md() {
  local sub="$1"
  [ -d "$ROOT_DIR/$sub" ] || return 0
  (
    cd "$ROOT_DIR" || return 0
    find "$sub" \
      -path '*/.claude/worktrees/*' -prune -o \
      -path '*/dist/*' -prune -o \
      -name '*.md' -type f -print
  )
}

# frontmatter_end <file> — last line number of the leading YAML frontmatter, or
# 0. An `allowed-tools: … Bash(git merge-tree *) …` grant is a permission, not
# guidance, and must not be read as the file's primary containment signal.
frontmatter_end() {
  local file="$1"
  awk 'NR==1 && $0 != "---" { print 0; exit } NR==1 { next } $0 == "---" { print NR; exit } NR>200 { print 0; exit } END { print 0 }' "$file" | head -1
}

# is_skippable_line <file> <lineno> — true for frontmatter, a blockquote, or an
# anti-example. A gotcha callout must be able to quote the broken form verbatim.
is_skippable_line() {
  local file="$1" lineno="$2" cur prev fm_end
  fm_end="$(frontmatter_end "$file")"
  [ "$lineno" -le "${fm_end:-0}" ] && return 0
  cur="$(sed -n "${lineno}p" "$file")"
  if grep -Eq '^[[:space:]]*>' <<<"$cur"; then
    return 0
  fi
  if grep -Eqi '(^|[^a-z])(wrong|don.t|do not|never|anti-pattern|bad:|broken)' <<<"$cur"; then
    return 0
  fi
  if [ "$lineno" -gt 1 ]; then
    prev="$(sed -n "$((lineno - 1))p" "$file")"
    if grep -Eqi '^[[:space:]]*#.*(wrong|don.t|do not|never|anti-pattern|bad:|broken)' <<<"$prev"; then
      return 0
    fi
  fi
  return 1
}

# first_line_matching <file> <ere> — line number of the first non-skippable
# match, or empty. Read once via a here-string so an early pipe close cannot
# fake a failure under pipefail.
first_line_matching() {
  local file="$1" pattern="$2" lineno
  while IFS=: read -r lineno _; do
    [ -n "$lineno" ] || continue
    is_skippable_line "$file" "$lineno" && continue
    echo "$lineno"
    return 0
  done < <(grep -nE "$pattern" "$file" 2>/dev/null || true)
  return 0
}

# The authoritative signal: an exact per-branch PR query. `--head` may sit
# either side of `--state all`, so match on `gh pr list` + `--head` together.
AUTHORITATIVE_RE='gh pr list[^`]*--head'

# ---------------------------------------------------------------------------
# Rules 1-4 — git-plugin routing surfaces
# ---------------------------------------------------------------------------
while IFS= read -r rel; do
  file="$ROOT_DIR/$rel"
  [ -f "$file" ] || continue
  files_scanned=$((files_scanned + 1))

  auth_line="$(first_line_matching "$file" "$AUTHORITATIVE_RE")"
  audit_line="$(first_line_matching "$file" 'branch-audit')"
  mt_line="$(first_line_matching "$file" 'merge-tree')"

  # A file that talks about branch containment at all must carry the ladder.
  # Without this, the two ordering rules below go silently vacuous the moment
  # someone deletes the `gh pr list --head` line — which is exactly the
  # regression they exist to catch.
  uses_mt_for_containment=0
  if [ -n "$mt_line" ] && grep -qEi 'squash|--merged|contained in base|branch containment' "$file"; then
    uses_mt_for_containment=1
  fi
  if [ -z "$auth_line" ] && { [ -n "$audit_line" ] || [ "$uses_mt_for_containment" -eq 1 ]; }; then
    issues+=("SEVERITY=ERROR TYPE=ladder_missing FILE=$rel MSG=gives branch-containment guidance without the authoritative signal 'gh pr list --state all --head <branch> --json state,mergedAt'")
  fi

  if [ -n "$audit_line" ]; then
    if ! grep -qF "$CAVEAT_MEASURED" "$file" || ! grep -qF "$CAVEAT_ISSUE" "$file"; then
      issues+=("SEVERITY=ERROR TYPE=branch_audit_uncaveated FILE=$rel LINE=$audit_line MSG=names branch-audit without the measured caveat (needs both '$CAVEAT_MEASURED' and '$CAVEAT_ISSUE')")
    fi
    if [ -n "$auth_line" ] && [ "$audit_line" -lt "$auth_line" ]; then
      issues+=("SEVERITY=ERROR TYPE=recipe_before_ladder FILE=$rel LINE=$audit_line MSG=branch-audit is presented before the authoritative 'gh pr list --head' ladder at line $auth_line")
    fi
  fi

  # Only judge merge-tree when it is used for BRANCH containment. Elsewhere
  # (e.g. a pre-merge conflict probe) merge-tree is a fine primary tool.
  if [ "$uses_mt_for_containment" -eq 1 ]; then
    if ! grep -qiF "$MERGE_TREE_CAVEAT" "$file"; then
      issues+=("SEVERITY=ERROR TYPE=merge_tree_uncaveated FILE=$rel LINE=$mt_line MSG=uses merge-tree for branch containment without the '$MERGE_TREE_CAVEAT' caveat (a non-match proves nothing once the base drifts)")
    fi
    if [ -n "$auth_line" ] && [ "$mt_line" -lt "$auth_line" ]; then
      issues+=("SEVERITY=ERROR TYPE=merge_tree_before_pr FILE=$rel LINE=$mt_line MSG=merge-tree is presented before the authoritative 'gh pr list --head' signal at line $auth_line")
    fi
  fi
done < <(collect_md "git-plugin")

# ---------------------------------------------------------------------------
# Rule 5 — paginated containment determination, any plugin
# ---------------------------------------------------------------------------
plugin_md_scanned=0
while IFS= read -r rel; do
  file="$ROOT_DIR/$rel"
  [ -f "$file" ] || continue
  plugin_md_scanned=$((plugin_md_scanned + 1))

  while IFS=: read -r lineno text; do
    [ -n "$lineno" ] || continue
    is_skippable_line "$file" "$lineno" && continue
    # A bare page size...
    grep -Eq '(--limit[= ]+[0-9]+|-L[= ]+[0-9]+)' <<<"$text" || continue
    # ...used to determine merged state...
    grep -Eq '(--json[^`|]*\b(state|mergedAt)\b|\bmergeCommit\b)' <<<"$text" || continue
    # ...without the exact per-branch query that is immune to the cap.
    grep -Eq -- '--head' <<<"$text" && continue
    issues+=("SEVERITY=ERROR TYPE=paginated_containment FILE=$rel LINE=$lineno MSG=paginated 'gh pr list' used for a merged-state determination; use the exact per-branch form 'gh pr list --state all --head <branch>' (issue #2268)")
  done < <(grep -nE 'gh pr list' "$file" 2>/dev/null || true)
done < <(
  for plugin_dir in "$ROOT_DIR"/*-plugin; do
    [ -d "$plugin_dir" ] || continue
    plugin_name="$(basename "$plugin_dir")"
    case "$plugin_name" in .claude-plugin) continue ;; esac
    collect_md "$plugin_name"
  done
)

# ---------------------------------------------------------------------------
# Zero-scan discriminator (#2219)
# ---------------------------------------------------------------------------
# A zero-file scan must not look like a clean scan. Two very different states:
#   plugin dirs present but nothing discovered  = the scan MISFIRED — be loud
#   no plugin dirs at all                       = genuinely nothing to check
# The second must stay green: a checker that errors on a legitimately empty
# corpus gets disabled, and that would make the loud case worthless.
plugin_dir_count=0
for plugin_dir in "$ROOT_DIR"/*-plugin; do
  [ -d "$plugin_dir" ] || continue
  case "$(basename "$plugin_dir")" in .claude-plugin) continue ;; esac
  plugin_dir_count=$((plugin_dir_count + 1))
done

if [ "$plugin_dir_count" -gt 0 ] && [ "$plugin_md_scanned" -eq 0 ]; then
  issues+=("SEVERITY=ERROR TYPE=nothing_scanned MSG=$plugin_dir_count plugin dirs but zero markdown discovered; scan misfired (see #2219)")
elif [ -d "$ROOT_DIR/git-plugin" ] && [ "$files_scanned" -eq 0 ]; then
  issues+=("SEVERITY=ERROR TYPE=nothing_scanned MSG=git-plugin/ exists but zero markdown discovered; scan misfired (see #2219)")
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
echo "=== BRANCH CONTAINMENT GUIDANCE ==="
echo "ROOT=$ROOT_DIR"
echo "GIT_PLUGIN_FILES_SCANNED=$files_scanned"
echo "PLUGIN_MD_SCANNED=$plugin_md_scanned"
echo "PLUGIN_DIRS=$plugin_dir_count"
echo "SCANNED_EMPTY=$([ "$plugin_md_scanned" -eq 0 ] && echo true || echo false)"
echo "ISSUE_COUNT=${#issues[@]}"
if [ ${#issues[@]} -gt 0 ]; then
  echo "STATUS=ERROR"
  echo "ISSUES:"
  for issue in "${issues[@]}"; do
    echo "  - $issue"
  done
  echo "=== END BRANCH CONTAINMENT GUIDANCE ==="
  exit 1
fi
echo "STATUS=OK"
echo "=== END BRANCH CONTAINMENT GUIDANCE ==="
exit 0
