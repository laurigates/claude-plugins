#!/usr/bin/env bash
# check-plugin-root-quoting.sh — every shell-form plugin hook command must keep
# ${CLAUDE_PLUGIN_ROOT} inside double quotes.
#
# WHY
# A shell-form hook command such as
#     "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh"
# is handed to a shell, so the expanded plugin root is word-split: install the
# marketplace under a path with a space and the hook runs `bash /Users/a` with
# a stray `b/…/foo.sh` argument. Claude Code 2.1.281's `claude plugin validate`
# warns on exactly this ("…without quotes…"). The repo's 68 hook commands were
# quoted in one sweep; this guard keeps a new or copy-pasted hook from
# reintroducing the unquoted form. The accepted shape is
#     "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh\""
#
# SEMANTIC, NOT A GREP
# Each command string is scanned with a small shell-quoting state machine
# (backslash escapes, '…', "…"), so `${CLAUDE_PLUGIN_ROOT}` / `$CLAUDE_PLUGIN_ROOT`
# is flagged only when it would expand OUTSIDE double quotes. A root inside
# single quotes is also flagged: it never expands, which is a different bug.
# Exec-form hooks (a handler carrying an `args` array) are not shell-parsed and
# are skipped.
#
# SCOPE
# <plugin>/hooks.json, <plugin>/hooks/hooks.json and the inline `hooks` of
# <plugin>/.claude-plugin/plugin.json, for every top-level *-plugin directory.
# Discovery runs from inside the project dir against relative paths, so a scan
# root that is itself an agent worktree still finds files (#2219); a scan that
# finds none is STATUS=ERROR TYPE=nothing_scanned, never a silent OK.
#
# Usage: bash scripts/check-plugin-root-quoting.sh [--project-dir DIR]
# Exit:  0 = OK, 1 = ERROR (unquoted root found, or nothing scanned), 2 = usage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      [ $# -ge 2 ] || { echo "ERROR: --project-dir needs a value" >&2; exit 2; }
      PROJECT_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,32p' "$0"; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -d "$PROJECT_DIR" ] || { echo "ERROR: project dir not found: $PROJECT_DIR" >&2; exit 2; }
cd "$PROJECT_DIR"

python3 - <<'PY'
import glob
import json
import re
import sys

ROOT_RE = re.compile(r"\$(\{CLAUDE_PLUGIN_ROOT\}|CLAUDE_PLUGIN_ROOT(?![A-Za-z0-9_]))")


def unquoted_roots(cmd):
    """Return 'unquoted' / 'single_quoted' for each root reference that a
    shell would not expand inside double quotes."""
    found = []
    state = None  # None | "'" | '"'
    i = 0
    while i < len(cmd):
        c = cmd[i]
        if state == "'":
            if c == "'":
                state = None
            elif ROOT_RE.match(cmd, i):
                found.append("single_quoted")
            i += 1
            continue
        if c == "\\":
            i += 2
            continue
        if state is None and c == "'":
            state = "'"
        elif c == '"':
            state = None if state == '"' else '"'
        elif c == "$" and ROOT_RE.match(cmd, i) and state is None:
            found.append("unquoted")
        i += 1
    return found


def handlers(hooks):
    if not isinstance(hooks, dict):
        return
    for event, blocks in hooks.items():
        for block in blocks if isinstance(blocks, list) else []:
            if not isinstance(block, dict):
                continue
            for h in block.get("hooks") or []:
                if isinstance(h, dict):
                    yield event, block.get("matcher", ""), h


files = sorted(
    set(glob.glob("*-plugin/hooks.json"))
    | set(glob.glob("*-plugin/hooks/hooks.json"))
    | set(glob.glob("*-plugin/.claude-plugin/plugin.json"))
)

issues = []
scanned = 0
commands = 0
quoted = 0
for path in files:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        issues.append(("parse_error", f"{path}: {exc}"))
        continue
    scanned += 1
    hooks = data.get("hooks") if isinstance(data, dict) else None
    for event, matcher, h in handlers(hooks):
        if h.get("type", "command") != "command" or "args" in h:
            continue
        cmd = h.get("command")
        if not isinstance(cmd, str) or not ROOT_RE.search(cmd):
            continue
        commands += 1
        bad = unquoted_roots(cmd)
        if not bad:
            quoted += 1
            continue
        issues.append(
            (
                bad[0] + "_plugin_root",
                f"{path} event={event} matcher={matcher!r} command={cmd!r}"
                ' (wrap it: bash \\"${CLAUDE_PLUGIN_ROOT}/hooks/x.sh\\")',
            )
        )

if scanned == 0:
    issues.append(("nothing_scanned", "found no *-plugin hook JSON under the project dir"))

print("=== PLUGIN ROOT QUOTING ===")
print(f"FILES_SCANNED={scanned}")
print(f"ROOT_COMMANDS={commands}")
print(f"QUOTED_COMMANDS={quoted}")
print(f"ISSUE_COUNT={len(issues)}")
if issues:
    print("STATUS=ERROR")
    kind, msg = issues[0]
    reason = " ".join(f"{kind}: {msg}".split())[:180]
    if len(issues) > 1:
        reason += f" (+{len(issues) - 1} more)"
    print(f"REASON={reason}")
    print("ISSUES:")
    for kind, msg in issues:
        print(f"  - SEVERITY=ERROR TYPE={kind} MSG={msg}")
else:
    print("STATUS=OK")
print("=== END PLUGIN ROOT QUOTING ===")
sys.exit(1 if issues else 0)
PY
