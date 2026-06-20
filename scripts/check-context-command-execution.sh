#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2094  # skill commands contain $ literally; run_one executes in $sandbox, not the file being read
# Execution harness for SKILL.md `## Context` backtick commands.
#
# WHY THIS EXISTS
#   Claude Code runs each `- Label: !`cmd`` Context command at skill-invocation
#   time and ABORTS the skill if the command writes to stderr or exits non-zero.
#   The common trigger is a fresh / not-yet-onboarded project that lacks a file,
#   directory, or git state the command assumes (e.g.
#   `grep -m1 "^standards_version:" .project-standards.yaml`,
#   `find .claude/rules ...`, `git config --get remote.origin.url`).
#
#   scripts/lint-context-commands.sh is a DENYLIST of known-bad command *shapes*
#   (regex). It is fast but only catches variants someone already got burned by.
#   This harness is the SEMANTIC backstop: it actually EXECUTES every Context
#   command in a bare sandbox (a one-commit git repo — the minimal real project)
#   and asserts exit 0 + empty stderr, catching the whole abort class regardless
#   of the command's shape.
#
# SANDBOX
#   A fresh `mktemp -d`, `git init`-ed with one empty commit (so HEAD/`git log`/
#   `git rev-list` resolve — every real project has at least one commit), HOME
#   pointed inside it, and a minimal env. It contains NO project files, subdirs,
#   or remote — so a command reaching for an optional file/dir/remote fails
#   exactly as it would on a freshly-onboarded repo. That gap is the abort class
#   this harness exists to catch. `${CLAUDE_SKILL_DIR}` / `${CLAUDE_PLUGIN_ROOT}`
#   are exported (resolved to the skill's own dir / plugin root) because Claude
#   Code defines them at runtime.
#
# CLASSIFICATION (per command)
#   PASS          exit 0 AND empty stderr
#   FAIL          non-zero exit OR non-empty stderr (the abort class) — the gate
#   ENV_MISSING   stderr says the harness env lacks a tool/auth (command not
#                 found, `gh auth login`, taskwarrior rc, *_TOKEN, rustup
#                 toolchain) — environment, not a skill bug; does NOT fail the gate
#   UNPARSEABLE   the harness mis-extracted the command (e.g. a literal backtick
#                 inside it); reported, does NOT fail the gate
#   SKIPPED       command matches the mutating/network denylist (never executed)
#
# USAGE
#   check-context-command-execution.sh [--strict] [--json] [--verbose]
#                                      [--repo-root DIR] [--files "f1 f2 ..."]
#   --strict   exit 1 when any FAIL is found (default: report only, exit 0)
#   --json     emit a JSON array of findings instead of the KEY=VALUE report
#   --files    space-separated explicit file list (default: tracked SKILL.md /
#              skill.md via `git ls-files`); used by the regression test
#
# Output follows .claude/rules/structured-script-output.md.
set -uo pipefail

strict=0
json=0
verbose=0
repo_root=""
files_override=""
declare -a positional_files=()

while [ $# -gt 0 ]; do
  case "$1" in
    --strict) strict=1 ;;
    --json) json=1 ;;
    --verbose) verbose=1 ;;
    --repo-root) repo_root="$2"; shift ;;
    --files) files_override="$2"; shift ;;
    --*) echo "unknown arg: $1" >&2; exit 2 ;;
    *) positional_files+=("$1") ;;  # pre-commit passes staged filenames here
  esac
  shift
done

if [ -z "$repo_root" ]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "$script_dir/.." && pwd)"
fi
cd "$repo_root" || { echo "cannot cd to repo root: $repo_root" >&2; exit 2; }

# pre-commit and CI may invoke this with GIT_DIR / GIT_INDEX_FILE / GIT_WORK_TREE
# pointing at the REAL repo. Those override `git -C`, breaking both the
# `git ls-files` discovery below (in a worktree, .git is a FILE) and the sandbox
# `git init`/`commit` setup (silently operating on the wrong repo, leaving the
# sandbox with no HEAD so every `git rev-list HEAD` fails 128). Clear them up
# front so discovery and the sandbox are truly isolated. Per-command execution
# additionally uses `env -i`.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT 2>/dev/null || true

# Commands we refuse to execute even in a sandbox (mutating / networked). These
# should never appear in a read-only Context block; lint-context-commands.sh
# already flags pipes/redirection. Listing them here is defense-in-depth so the
# harness never runs something destructive extracted from a file.
DENY_RE='(^|[^a-zA-Z])(rm|mv|cp|curl|wget|ssh|scp|dd|mkfs|shutdown|reboot|chmod|chown|kill|git[[:space:]]+push|gh[[:space:]]+[a-z-]+[[:space:]]+(create|delete|merge|close))([^a-zA-Z]|$)'

# Discover files: tracked SKILL.md/skill.md (excludes dist/ and worktrees, which
# git ignores) unless an explicit list is given. `.claude/skills/` is excluded:
# those are this repo's own internal meta-skills (e.g. docs-refresh runs a
# repo-local script), invoked only here — the "fresh project" premise this
# harness tests does not apply to them. The gate guards PUBLISHED plugin skills,
# which run in arbitrary projects.
if [ "${#positional_files[@]}" -gt 0 ]; then
  # pre-commit passes staged filenames; keep only SKILL.md/skill.md, drop .claude/
  files=()
  for pf in "${positional_files[@]}"; do
    case "$pf" in
      .claude/*) continue ;;
      */SKILL.md|*/skill.md|SKILL.md|skill.md) files+=("$pf") ;;
    esac
  done
elif [ -n "$files_override" ]; then
  # shellcheck disable=SC2206
  files=($files_override)
else
  mapfile -t files < <(git ls-files '*/SKILL.md' '*/skill.md' 'SKILL.md' 'skill.md' 2>/dev/null \
    | grep -v '^\.claude/')
fi

# One sandbox for the whole run (commands are read-only by contract).
sandbox="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -n "$sandbox" ] && [ -d "$sandbox" ] || { echo "invalid sandbox dir: '$sandbox'" >&2; exit 1; }
trap 'rm -rf "$sandbox"' EXIT
git -C "$sandbox" init -q 2>/dev/null
git -C "$sandbox" config user.email "harness@example.com" 2>/dev/null
git -C "$sandbox" config user.name "harness" 2>/dev/null
git -C "$sandbox" commit -q --allow-empty -m "init" 2>/dev/null
harness_path="$PATH"

pass=0
fail=0
env_missing=0
unparseable=0
skipped=0
declare -a findings_file findings_line findings_cmd findings_exit findings_err findings_kind

# stderr signatures that mean "the harness environment lacks something", NOT
# "the skill aborts in a fresh project". These are not skill bugs.
ENV_RE='command not found|: not found|gh auth login|not logged into any GitHub|Cannot proceed without rc file|TFE_TOKEN|GITHUB_TOKEN|rustup could not choose|no default (toolchain|is configured)'
# stderr signatures that mean the harness mis-extracted the command (e.g. a
# literal backtick inside it), not a skill bug.
UNPARSEABLE_RE='unexpected EOF while looking for matching|syntax error near unexpected token'

run_one() {
  local file="$1" lineno="$2" cmd="$3"
  # Refuse to execute mutating/network commands.
  if printf '%s' "$cmd" | grep -Eq "$DENY_RE"; then
    skipped=$((skipped + 1))
    return
  fi
  # Resolve runtime-defined plugin vars to this skill's real location, matching
  # what Claude Code sets at invocation time.
  local skill_dir plugin_root
  skill_dir="$repo_root/$(dirname "$file")"
  plugin_root="$repo_root/${file%%/*}"
  local out err rc errfile
  errfile="$(mktemp)"
  out="$(cd "$sandbox" && env -i PATH="$harness_path" HOME="$sandbox" TERM=dumb \
        CLAUDE_SKILL_DIR="$skill_dir" CLAUDE_PLUGIN_ROOT="$plugin_root" \
        bash -c "$cmd" 2>"$errfile")"
  rc=$?
  err="$(cat "$errfile")"
  rm -f "$errfile"
  : "$out"  # stdout is irrelevant; only exit code + stderr matter

  if [ $rc -eq 0 ] && [ -z "$err" ]; then
    pass=$((pass + 1))
    return
  fi

  local kind=""
  if printf '%s' "$err" | grep -Eqi "$UNPARSEABLE_RE"; then
    unparseable=$((unparseable + 1)); kind="UNPARSEABLE"
  elif printf '%s' "$err" | grep -Eqi "$ENV_RE"; then
    env_missing=$((env_missing + 1)); kind="ENV_MISSING"
  else
    fail=$((fail + 1)); kind="FAIL"
  fi

  # Always record FAILs; record the others only in --verbose.
  if [ "$kind" = "FAIL" ] || [ "$verbose" -eq 1 ]; then
    findings_file+=("$file"); findings_line+=("$lineno"); findings_cmd+=("$cmd")
    findings_exit+=("$rc"); findings_err+=("${err%%$'\n'*}"); findings_kind+=("$kind")
  fi
}

for file in "${files[@]}"; do
  [ -f "$file" ] || continue
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # Match a Context backtick command:  - <label>: !`<cmd>`
    case "$line" in
      *'!`'*'`'*) : ;;
      *) continue ;;
    esac
    # Extract between the first  !`  and the last  `  on the line.
    cmd="${line#*'!`'}"
    cmd="${cmd%'`'*}"
    [ -n "$cmd" ] || continue
    run_one "$file" "$lineno" "$cmd"
  done < "$file"
done

issue_count=$fail

if [ "$json" -eq 1 ]; then
  printf '['
  first=1
  for i in "${!findings_file[@]}"; do
    [ "${findings_kind[$i]}" = "FAIL" ] || { [ "$verbose" -eq 1 ] || continue; }
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '{"file":"%s","line":%s,"kind":"%s","exit":%s,"cmd":%s,"stderr":%s}' \
      "${findings_file[$i]}" "${findings_line[$i]}" "${findings_kind[$i]}" "${findings_exit[$i]}" \
      "$(printf '%s' "${findings_cmd[$i]}" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
      "$(printf '%s' "${findings_err[$i]}" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')"
  done
  printf ']\n'
else
  echo "=== CONTEXT COMMAND EXECUTION ==="
  echo "FILES_SCANNED=${#files[@]}"
  echo "PASS=$pass"
  echo "ENV_MISSING=$env_missing"
  echo "UNPARSEABLE=$unparseable"
  echo "SKIPPED_DENYLIST=$skipped"
  echo "FAIL=$fail"
  if [ "$fail" -gt 0 ] || { [ "$verbose" -eq 1 ] && [ "${#findings_file[@]}" -gt 0 ]; }; then
    echo "ISSUES:"
    for i in "${!findings_file[@]}"; do
      [ "${findings_kind[$i]}" = "FAIL" ] || { [ "$verbose" -eq 1 ] || continue; }
      echo "  - KIND=${findings_kind[$i]} FILE=${findings_file[$i]}:${findings_line[$i]} EXIT=${findings_exit[$i]}"
      echo "    CMD=${findings_cmd[$i]}"
      echo "    STDERR=${findings_err[$i]}"
    done
  fi
  if [ "$fail" -eq 0 ]; then
    echo "STATUS=OK"
  else
    echo "STATUS=ERROR"
  fi
  echo "ISSUE_COUNT=$issue_count"
  echo "=== END CONTEXT COMMAND EXECUTION ==="
fi

if [ "$strict" -eq 1 ] && [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
