#!/usr/bin/env bash
# check-hook-fail-closed.sh — `"onFailure": "block"` sits on exactly the
# hooks-plugin safety hooks, and each of those hooks exits 0 on every path
# where it does not apply.
#
# WHY
# Claude Code 2.1.295 added `onFailure` to command and HTTP hook entries. With
# "block", a hook that cannot start, times out, or exits with a code other than
# 0 or 2 does what exit 2 does on its event: a PreToolUse failure blocks the
# tool call. That is right for a safety block (a crashed branch guard should
# not let `git push` to main through) and wrong for a nudge or a logger, where
# a crash would turn a style preference into a hard block on every matching
# call (.claude/rules/hook-block-vs-nudge.md). It also raises the cost of a
# crash in the safety hooks themselves: secret-protection matches
# Read|Edit|Write|Bash, so an exit 127 there would block every file read.
#
# WHAT IT CHECKS
# 1. Manifest. Every hook entry in every *-plugin hook JSON is read. Each
#    registration of the four safety scripts in hooks-plugin must carry
#    onFailure "block"; no other entry may; any onFailure value outside
#    continue|block is an error; each safety script must be registered.
# 2. Runtime. Each safety script is run on its not-applicable paths and must
#    exit 0 with stdout that is empty or one JSON object (invalid JSON output
#    also counts as a failure under onFailure "block"):
#      unparseable stdin, empty stdin, a JSON array, no jq on PATH, no git on
#      PATH, a `git commit` in a non-git cwd, an ordinary Read, and the same
#      `git commit` with mapfile/readarray disabled (macOS /bin/bash 3.2 has
#      neither). When /bin/bash is older than 4, that case also runs under it.
#
# Usage: bash scripts/check-hook-fail-closed.sh [--project-dir DIR]
# Exit:  0 = OK, 1 = ERROR, 2 = usage
set -uo pipefail

# An inherited GIT_DIR (pre-commit exports one) would make the non-git-cwd
# case resolve the real repo instead (issue #1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      [ $# -ge 2 ] || { echo "ERROR: --project-dir needs a value" >&2; exit 2; }
      PROJECT_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,29p' "$0"; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -d "$PROJECT_DIR" ] || { echo "ERROR: project dir not found: $PROJECT_DIR" >&2; exit 2; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# The fail-closed set. Adding a hook here is a decision recorded in
# .claude/rules/hook-block-vs-nudge.md, not a drive-by.
SAFETY_PLUGIN="hooks-plugin"
SAFETY_HOOKS="branch-protection.sh repo-deletion-safety.sh external-pr-merge-guard.sh secret-protection.sh"

ISSUES=()
add_issue() { ISSUES+=("$1: $2"); }

# ── 1. Manifest ───────────────────────────────────────────────────────────────
MANIFEST_OUT="$(cd "$PROJECT_DIR" && SAFETY_PLUGIN="$SAFETY_PLUGIN" SAFETY_HOOKS="$SAFETY_HOOKS" python3 - <<'PY'
import glob, json, os, re

plugin = os.environ["SAFETY_PLUGIN"]
expected = set(os.environ["SAFETY_HOOKS"].split())
files = sorted(set(glob.glob("*-plugin/hooks.json"))
               | set(glob.glob("*-plugin/hooks/hooks.json"))
               | set(glob.glob("*-plugin/.claude-plugin/plugin.json")))
scanned = 0
blocked = 0
seen = set()
for path in files:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        print(f"ISSUE parse_error {path}: {exc}")
        continue
    scanned += 1
    hooks = data.get("hooks") if isinstance(data, dict) else None
    if not isinstance(hooks, dict):
        continue
    owner = path.split("/", 1)[0]
    for event, blocks in hooks.items():
        for block in blocks if isinstance(blocks, list) else []:
            if not isinstance(block, dict):
                continue
            matcher = block.get("matcher", "")
            for h in block.get("hooks") or []:
                if not isinstance(h, dict):
                    continue
                text = " ".join([str(h.get("command", ""))] + [str(a) for a in h.get("args") or []])
                m = re.search(r"/hooks/([A-Za-z0-9_.-]+\.sh)", text)
                script = m.group(1) if m else ""
                where = f"{path} event={event} matcher={matcher!r} script={script or '-'}"
                has = "onFailure" in h
                val = h.get("onFailure")
                if has and val not in ("continue", "block"):
                    print(f"ISSUE invalid_onfailure_value {where} onFailure={val!r}")
                is_safety = owner == plugin and script in expected
                if is_safety:
                    seen.add(script)
                    if val != "block":
                        print(f"ISSUE missing_fail_closed {where} (add \"onFailure\": \"block\")")
                    else:
                        blocked += 1
                elif val == "block":
                    print(f"ISSUE unexpected_fail_closed {where} (only safety blocks fail closed; see hook-block-vs-nudge.md)")
for script in sorted(expected - seen):
    print(f"ISSUE safety_hook_not_registered {plugin}: {script} has no hook entry")
print(f"FILES {scanned}")
print(f"BLOCKED {blocked}")
PY
)" || add_issue manifest_scan_failed "python3 manifest scan exited non-zero"

FILES_SCANNED=0
FAIL_CLOSED_ENTRIES=0
while IFS= read -r line; do
  case "$line" in
    "ISSUE "*) rest="${line#ISSUE }"; add_issue "${rest%% *}" "${rest#* }" ;;
    "FILES "*) FILES_SCANNED="${line#FILES }" ;;
    "BLOCKED "*) FAIL_CLOSED_ENTRIES="${line#BLOCKED }" ;;
  esac
done <<<"$MANIFEST_OUT"
[ "$FILES_SCANNED" -gt 0 ] || add_issue nothing_scanned "found no *-plugin hook JSON under $PROJECT_DIR"

# ── 2. Runtime: not-applicable paths exit 0 ──────────────────────────────────
BASH_BIN="$(command -v bash)"
WORK="$(mktemp -d)" || { echo "ERROR: mktemp -d failed" >&2; exit 2; }
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then echo "ERROR: mktemp -d failed" >&2; exit 2; fi
trap 'rm -rf "$WORK"' EXIT
NONGIT="$WORK/not-a-repo"
mkdir -p "$NONGIT" "$WORK/bin-nojq" "$WORK/bin-nogit"

# PATH sandboxes: symlink only the tools a case keeps. Each hook checks its
# own dependencies with `command -v` before using them, so a short list is
# enough; a hook that reaches for a tool not listed here crashes, and that is
# the defect this case exists to catch.
link_tools() { # link_tools <dir> <tool>...
  local dir="$1" t p; shift
  for t in "$@"; do
    p="$(command -v "$t" 2>/dev/null)" || continue
    case "$p" in /*) ln -sf "$p" "$dir/$t" ;; esac
  done
}
COMMON_TOOLS="cat grep awk sed head tail tr cut sort uniq wc dirname basename mktemp find printf env pwd realpath readlink"
# shellcheck disable=SC2086  # word-split the tool list on purpose
link_tools "$WORK/bin-nojq" $COMMON_TOOLS git gh
# shellcheck disable=SC2086
link_tools "$WORK/bin-nogit" $COMMON_TOOLS jq
printf 'enable -n mapfile readarray 2>/dev/null || true\n' > "$WORK/no-mapfile.env"

bash_input() { # bash_input <command> <cwd>
  jq -nc --arg c "$1" --arg d "$2" \
    '{hook_event_name:"PreToolUse",permission_mode:"default",tool_name:"Bash",tool_input:{command:$c},cwd:$d}'
}
READ_INPUT="$(jq -nc --arg d "$NONGIT" '{hook_event_name:"PreToolUse",permission_mode:"default",tool_name:"Read",tool_input:{file_path:($d + "/README.md")},cwd:$d}')"
COMMIT_INPUT="$(bash_input 'git commit -m x' "$NONGIT")"
STATUS_INPUT="$(bash_input 'git status' "$NONGIT")"

CASES_RUN=0
# run_case <hook-path> <label> <stdin> <path> <bash-env> [<bash-binary>]
run_case() {
  local hook="$1" label="$2" input="$3" path="$4" benv="$5" bin="${6:-$BASH_BIN}"
  local out rc
  CASES_RUN=$((CASES_RUN + 1))
  out="$(cd "$NONGIT" && printf '%s' "$input" | env -u CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION \
      -u CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION -u CLAUDE_HOOKS_DISABLE_REPO_DELETION_SAFETY \
      -u CLAUDE_HOOKS_DISABLE_EXTERNAL_PR_MERGE \
      PATH="$path" BASH_ENV="$benv" HOME="$WORK" "$bin" "$hook" 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    add_issue not_applicable_crash "$(basename "$hook") case=$label exit=$rc (want 0; onFailure \"block\" turns this into a block)"
    return
  fi
  if [ -n "$out" ] && ! printf '%s' "$out" | jq -e 'type == "object"' >/dev/null 2>&1; then
    case "$out" in
      "{"*|"["*) add_issue invalid_json_output "$(basename "$hook") case=$label stdout is not one JSON object" ;;
    esac
  fi
}

OLD_BASH=""
if [ -x /bin/bash ]; then
  # shellcheck disable=SC2016  # expanded by the child bash, not here
  major="$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null || echo "")"
  case "$major" in [0-3]) OLD_BASH=/bin/bash ;; esac
fi

HOOKS_CHECKED=0
for name in $SAFETY_HOOKS; do
  hook="$PROJECT_DIR/$SAFETY_PLUGIN/hooks/$name"
  [ -f "$hook" ] || { add_issue safety_hook_missing "$SAFETY_PLUGIN/hooks/$name not found"; continue; }
  HOOKS_CHECKED=$((HOOKS_CHECKED + 1))
  run_case "$hook" unparseable_stdin 'not json {' "$PATH" ""
  run_case "$hook" empty_stdin '' "$PATH" ""
  run_case "$hook" json_array '[]' "$PATH" ""
  run_case "$hook" no_jq "$STATUS_INPUT" "$WORK/bin-nojq" ""
  run_case "$hook" no_git "$COMMIT_INPUT" "$WORK/bin-nogit" ""
  run_case "$hook" non_git_cwd "$COMMIT_INPUT" "$PATH" ""
  run_case "$hook" ordinary_read "$READ_INPUT" "$PATH" ""
  run_case "$hook" no_mapfile "$COMMIT_INPUT" "$PATH" "$WORK/no-mapfile.env"
  if [ -n "$OLD_BASH" ]; then
    run_case "$hook" bin_bash_3 "$COMMIT_INPUT" "$PATH" "" "$OLD_BASH"
  fi
done

# ── Report ────────────────────────────────────────────────────────────────────
echo "=== HOOK FAIL CLOSED ==="
echo "FILES_SCANNED=$FILES_SCANNED"
echo "FAIL_CLOSED_ENTRIES=$FAIL_CLOSED_ENTRIES"
echo "HOOKS_CHECKED=$HOOKS_CHECKED"
echo "CASES_RUN=$CASES_RUN"
echo "OLD_BASH=${OLD_BASH:-none}"
echo "ISSUE_COUNT=${#ISSUES[@]}"
if [ "${#ISSUES[@]}" -gt 0 ]; then
  echo "STATUS=ERROR"
  reason="$(printf '%s' "${ISSUES[0]}" | tr -s '[:space:]' ' ' | cut -c1-180)"
  [ "${#ISSUES[@]}" -gt 1 ] && reason="$reason (+$((${#ISSUES[@]} - 1)) more)"
  echo "REASON=$reason"
  echo "ISSUES:"
  for i in "${ISSUES[@]}"; do
    echo "  - SEVERITY=ERROR TYPE=${i%%: *} MSG=${i#*: }"
  done
else
  echo "STATUS=OK"
fi
echo "=== END HOOK FAIL CLOSED ==="
[ "${#ISSUES[@]}" -eq 0 ]
