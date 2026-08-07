#!/usr/bin/env bash
# Flag skills that grant `Bash` in `allowed-tools` but run no shell at all.
#
# Background: a bare unscoped `Bash` in a SKILL's `allowed-tools` is the ratified
# house standard, not drift — skill frontmatter can only SUBTRACT from the
# session's grants, never add, so enumerating narrow `Bash(<command> *)` patterns
# there buys no safety the settings.json layer isn't already providing while
# costing a prompt for every command the author failed to predict. See
# `.claude/rules/agentic-permissions.md`, which owns that distinction.
#
# The defect worth linting is therefore the OPPOSITE of over-breadth: a `Bash`
# grant in a skill whose body runs no shell. That grant is pure surface — it can
# only widen what the skill may reach for, and it advertises a capability the
# skill never exercises.
#
# Deliberately NOT `plugin-compliance-check.sh`'s `check_bash_patterns()`: CI runs
# that whole script under `|| true` (plugin-pr-checks.yml), so it is advisory *by
# construction* and can never become a ratchet, and a 1600-line monolith cannot
# take a narrow pre-commit `files:` scope. Deliberately not
# `audit-skill-descriptions.py` either: a permissions axis fights its
# `--strict-*` surface, and `allowed-tools` is a single scalar frontmatter line
# in all ~408 files.
#
# WHAT COUNTS AS "RUNS SHELL" (any one of these):
#   1. A fenced code block whose info string is a shell language OR IS EMPTY,
#      containing a line that starts with a known command. Unlabeled fences must
#      count — 30 skills carry their only commands that way — as must a leading
#      `./` or `.venv/` (e.g. comfy-workflow-layout runs `.venv/bin/python …`).
#      Comment lines and lines that are only a `/slash:command` do not count.
#   2. An inline-backtick command matched against the same known-command list.
#      Matching "any word plus an argument" would count prose like `--flag value`
#      and collapse the finding count to near zero.
#   3. A sibling `scripts/` directory (19 of the 191 grantees have one).
#   4. A `` !`…` `` Context command anywhere in the skill.
#   5. Any of the above in a BUNDLED SIDECAR (`REFERENCE.md`, `references/**`,
#      or any other `.md` in the skill dir). Measuring SKILL.md in isolation makes
#      every progressive-disclosure skill look inert —
#      `agent-patterns-plugin/skills/mcp-code-execution` reads as unused from
#      SKILL.md alone while its REFERENCE.md carries the scaffolding steps.
#
# Markdown structure comes from `scripts/lib/extract-md-elements.py` (tree-sitter),
# NOT a hand-rolled fence toggle — that state machine is the source of shipped
# bugs #1744 and #1492 (issue #2009).
#
# Usage:
#   bash scripts/check-unused-bash-grant.sh [--project-dir <path>] [--strict] [SKILL.md ...]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd).
#   --strict        Exit 1 when findings exist (default: advisory, exit 0).
#   SKILL.md ...    Explicit files (pre-commit style); skips discovery.
#
# Exit codes:
#   0 - no findings, or findings in advisory (non-strict) mode
#   1 - findings and --strict
#   2 - unknown argument (fail fast; never swallow a flag — see #2057)

set -uo pipefail

# Skills allowed to keep a `Bash` grant despite no detected shell. Empty by
# design — a genuine keeper gets an entry here plus a one-line why, so the
# blocking flip can require the list to be the only exception.
# Test seam: CHECK_UNUSED_BASH_GRANT_ALLOWLIST (whitespace-separated) extends it.
UNUSED_BASH_GRANT_ALLOWLIST=()
# shellcheck disable=SC2206  # intentional word-split of the test-seam env var
UNUSED_BASH_GRANT_ALLOWLIST+=(${CHECK_UNUSED_BASH_GRANT_ALLOWLIST:-})

proj_dir=""
strict=0
explicit_files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      proj_dir="${2:-}"
      if [ -z "$proj_dir" ]; then
        echo "check-unused-bash-grant.sh: --project-dir requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --strict) strict=1; shift ;;
    -h|--help)
      sed -n '/^# Usage:/,/^#   2 - unknown/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "check-unused-bash-grant.sh: unknown argument: $1" >&2
      echo "" >&2
      sed -n '/^# Usage:/,/^#   2 - unknown/p' "$0" | sed 's/^# \{0,1\}//' >&2
      exit 2
      ;;
    *) explicit_files+=("$1"); shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Resolve the markdown parser relative to THIS SCRIPT, never to --project-dir.
# The scanned tree is not necessarily this repo (fixtures, another checkout), and
# a helper resolved against it silently disappears — which would make every
# grantee look like it runs no shell and report a false finding for all 191.
script_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper="$script_self_dir/lib/extract-md-elements.py"

# Collect candidate SKILL.md files. Explicit args win (pre-commit passes changed
# files); otherwise discover under proj_dir. Both `.claude/worktrees/` (agent
# worktree clones are full repo copies — #1492 / #1548) and `dist/` (the gitignored
# rulesync export — #2214) are pruned; scanning either re-counts the same skills.
#
# Discovery runs from INSIDE proj_dir against RELATIVE paths (#2219). With an
# absolute base, the bare `*/.claude/worktrees/*` prune fires on the whole tree
# whenever proj_dir is ITSELF an agent worktree — its own path contains
# `/.claude/worktrees/`, so every descendant matches, the scan root is pruned
# entirely, and this guard reports SKILLS_SCANNED=0 / ISSUE_COUNT=0 / STATUS=OK
# having checked nothing. That reading also VACUOUSLY satisfies the "expect
# ISSUE_COUNT=0" gate for flipping this lint to --strict (#2255), which is why the
# prune fix had to land first. Relative paths make the root `.`, so its absolute
# prefix cannot match while copies nested anywhere below it still prune correctly.
# Same fix, and same reasoning, as scripts/check-subagent-types.sh.
#
# `helper` above is resolved from BASH_SOURCE before this cd, so it is unaffected.
skill_files=()
plugin_dirs=()
if [ ${#explicit_files[@]} -gt 0 ]; then
  skill_files=("${explicit_files[@]}")
else
  cd "$proj_dir" || { echo "check-unused-bash-grant.sh: cannot cd to $proj_dir" >&2; exit 2; }

  while IFS= read -r -d '' d; do
    plugin_dirs+=("$d")
  done < <(find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0 2>/dev/null)

  if [ ${#plugin_dirs[@]} -gt 0 ]; then
    while IFS= read -r -d '' f; do
      skill_files+=("$f")
    done < <(
      find "${plugin_dirs[@]}" -path '*/.claude/worktrees/*' -prune -o -path '*/dist/*' -prune -o \
        -path '*/skills/*' \( -name 'SKILL.md' -o -name 'skill.md' \) -type f -print0 2>/dev/null
    )
  fi
fi

echo "=== UNUSED BASH GRANT ==="

if [ ${#skill_files[@]} -eq 0 ]; then
  # Zero files is two very different states, and they must not look alike (#2219).
  # Plugin dirs present but no skills discovered = the scan misfired (a prune that
  # matched the scan root); no plugin dirs at all = genuinely nothing to check.
  if [ ${#plugin_dirs[@]} -gt 0 ] && [ ${#explicit_files[@]} -eq 0 ]; then
    echo "SKILLS_SCANNED=0"
    echo "BASH_GRANTEES=0"
    echo "PLUGIN_DIRS=${#plugin_dirs[@]}"
    echo "STATUS=ERROR"
    echo "ISSUE_COUNT=1"
    echo "ISSUES:"
    echo "  - SEVERITY=ERROR TYPE=nothing_scanned MSG=${#plugin_dirs[@]} plugin dirs but zero skills discovered; scan misfired (see #2219)"
    echo "=== END UNUSED BASH GRANT ==="
    exit 1
  fi
  # A checker that errors on a genuinely empty corpus gets disabled. Report and succeed.
  echo "SKILLS_SCANNED=0"
  echo "BASH_GRANTEES=0"
  echo "PLUGIN_DIRS=0"
  echo "SCANNED_EMPTY=true"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END UNUSED BASH GRANT ==="
  exit 0
fi

# is_allowlisted <skill-dir-or-file>
is_allowlisted() {
  local candidate="${1#./}"
  local entry
  for entry in ${UNUSED_BASH_GRANT_ALLOWLIST[@]+"${UNUSED_BASH_GRANT_ALLOWLIST[@]}"}; do
    entry="${entry#./}"
    [ -z "$entry" ] && continue
    case "$candidate" in
      "$entry" | */"$entry" | "$entry"* | */"$entry"*) return 0 ;;
    esac
  done
  return 1
}

# --- Stage 1: which skills grant a bare `Bash`? -------------------------------
grantees=()
scanned=0
for sf in "${skill_files[@]}"; do
  [ -f "$sf" ] || continue
  scanned=$((scanned + 1))
  at_field="$(head -60 "$sf" 2>/dev/null | grep -m1 '^allowed-tools:' | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')"
  [ -n "$at_field" ] || continue
  # A BARE `Bash` token: not `Bash(...)`. Comma-delimited list.
  if grep -qE '(^|,)[[:space:]]*Bash[[:space:]]*(,|$)' <<<"$at_field"; then
    grantees+=("$sf")
  fi
done

if [ ${#grantees[@]} -eq 0 ]; then
  echo "SKILLS_SCANNED=$scanned"
  echo "BASH_GRANTEES=0"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END UNUSED BASH GRANT ==="
  exit 0
fi

# --- Stage 2: gather every markdown file belonging to a grantee skill ---------
# Sidecars count as skill content (criterion 5), so the parse set is the whole
# skill directory, not just SKILL.md.
scan_list="$(mktemp)" || exit 1
[ -n "$scan_list" ] || exit 1
trap 'rm -f "$scan_list"' EXIT

for sf in "${grantees[@]}"; do
  skill_dir="$(dirname "$sf")"
  find "$skill_dir" -type f -name '*.md' -print 2>/dev/null
done | sort -u > "$scan_list"

# --- Stage 3: classify ---------------------------------------------------------
# Known commands. A skill "runs shell" when a fence line or inline span STARTS
# with one of these (optionally behind `sudo`, an `ENV=val` prefix, or `$ `).
KNOWN_CMDS='git|gh|glab|bash|sh|zsh|fish|source|export|cd|pushd|popd|python|python3|uv|uvx|pip|pipx|node|npm|npx|bun|bunx|yarn|pnpm|deno|cargo|rustup|go|gofmt|make|just|task|docker|podman|nerdctl|kubectl|helm|kustomize|skaffold|argocd|terraform|tofu|tflint|ansible|vagrant|jq|yq|rg|fd|sed|awk|grep|egrep|find|ls|cat|head|tail|cut|sort|uniq|wc|tr|xargs|tee|diff|patch|cp|mv|rm|mkdir|rmdir|touch|ln|chmod|chown|stat|realpath|basename|dirname|pwd|echo|printf|read|test|curl|wget|ssh|scp|rsync|tar|unzip|zip|gzip|gunzip|openssl|base64|shasum|sha256sum|md5sum|date|sleep|env|which|type|command|pytest|tox|nox|ruff|black|mypy|ty|basedpyright|vulture|biome|eslint|prettier|oxlint|oxfmt|tsc|vitest|jest|playwright|cypress|knip|stylua|shellcheck|shfmt|actionlint|gitleaks|trufflehog|semgrep|bandit|pre-commit|mise|asdf|brew|apt|apt-get|systemctl|launchctl|defaults|osascript|pmset|powermetrics|ps|top|kill|pkill|lsof|netstat|ss|ip|ifconfig|dig|nslookup|ping|traceroute|nmap|d2|mmdc|ffmpeg|magick|convert|identify|odiff|comfy|obsidian|telegram-notify|telegram-ask|telegram-poll|hyperfine|watch|tmux|kitty|open|code|nvim|vim'

report="$(mktemp)" || exit 1
[ -n "$report" ] || exit 1
trap 'rm -f "$scan_list" "$report"' EXIT

# FAIL CLOSED on a missing/broken parser. Without this the parse yields no rows,
# every grantee looks inert, and the check reports a false finding for all of
# them — a false-positive storm is far worse than a hard error.
if [ ! -x "$helper" ] && [ ! -f "$helper" ]; then
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=0"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_helper MSG=markdown parser not found at $helper"
  echo "=== END UNUSED BASH GRANT ==="
  exit 1
fi

# One parse pass over the whole set (923ms for 410 files at corpus scale).
"$helper" --types fence_line,inline_code --files-from "$scan_list" 2>/dev/null \
  | awk -F'\t' -v cmds="$KNOWN_CMDS" '
    function skilldir(p,   m) {
      # everything up to and including .../skills/<name>
      if (match(p, /^.*\/skills\/[^\/]+/)) return substr(p, RSTART, RLENGTH)
      return p
    }
    function strip(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/^\$[[:space:]]+/, "", s)          # a "$ cmd" prompt line
      sub(/^sudo[[:space:]]+/, "", s)
      while (s ~ /^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/)   # ENV=val prefixes
        sub(/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/, "", s)
      return s
    }
    function is_command(s) {
      s = strip(s)
      if (s == "") return 0
      if (s ~ /^#/) return 0                  # comment
      if (s ~ /^\//) return 0                 # a /slash:command (or an absolute path used as prose)
      if (s ~ /^\.\//) return 1               # ./script.sh
      if (s ~ /^\.venv\//) return 1           # .venv/bin/python
      if (s ~ /^\.[a-zA-Z0-9_-]+\//) return 1 # any dot-dir-relative executable
      # An executable reached through a PLACEHOLDER or variable path prefix. Docs
      # routinely write the interpreter that way and it is still a real command:
      #   <venv>/bin/python -c "..."      (comfy-subgraphs-app-mode)
      #   ${CLAUDE_SKILL_DIR}/scripts/x.sh
      #   ~/bin/tool
      if (s ~ /^<[^>]+>\//) return 1
      if (s ~ /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\//) return 1
      if (s ~ /^~\//) return 1
      return (s ~ ("^(" cmds ")([[:space:]]|$)"))
    }
    $1 == "fence_line" {
      lang = tolower($4)
      # shell-ish language OR an UNLABELED fence (empty info string)
      if (lang == "" || lang ~ /^(bash|sh|shell|zsh|console|shell-session|shellsession|fish|command|terminal)$/) {
        if (is_command($5)) used[skilldir($2)] = 1
      }
      next
    }
    $1 == "inline_code" {
      if ($6 == "1") { used[skilldir($2)] = 1; next }   # is_bang: a !`…` Context command
      if (is_command($7)) used[skilldir($2)] = 1
      next
    }
    END { for (d in used) print d }
  ' | sort -u > "$report"

# --- Stage 4: report -----------------------------------------------------------
issues=0
exempt=0
declare -a issue_rows=()
for sf in "${grantees[@]}"; do
  skill_dir="$(dirname "$sf")"
  # criterion 3: a sibling scripts/ directory
  if [ -d "$skill_dir/scripts" ]; then continue; fi
  # criteria 1/2/4/5
  if grep -qxF "$skill_dir" "$report"; then continue; fi
  if is_allowlisted "$skill_dir" || is_allowlisted "$sf"; then
    exempt=$((exempt + 1))
    continue
  fi
  issues=$((issues + 1))
  issue_rows+=("  - SEVERITY=WARN TYPE=unused_bash_grant SKILL=${skill_dir#"$proj_dir"/} MSG=grants Bash but no shell detected in the skill or its sidecars")
done

echo "SKILLS_SCANNED=$scanned"
echo "BASH_GRANTEES=${#grantees[@]}"
echo "EXEMPTED=$exempt"
if [ "$issues" -eq 0 ]; then
  echo "STATUS=OK"
else
  echo "STATUS=WARN"
fi
echo "ISSUE_COUNT=$issues"
if [ "$issues" -gt 0 ]; then
  echo "ISSUES:"
  printf '%s\n' "${issue_rows[@]}"
fi
echo "=== END UNUSED BASH GRANT ==="

if [ "$issues" -gt 0 ] && [ "$strict" -eq 1 ]; then
  exit 1
fi
exit 0
