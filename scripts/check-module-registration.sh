#!/usr/bin/env bash
# check-module-registration.sh — every path-loaded Python module is registered
# in sys.modules before exec_module runs (issue #3805).
#
# THE HAZARD
# A script with a hyphenated name cannot be imported, so callers load it by path:
#     spec = importlib.util.spec_from_file_location(name, path)
#     mod = importlib.util.module_from_spec(spec)
#     spec.loader.exec_module(mod)
# If the loaded module combines `from __future__ import annotations` with
# `@dataclass`, exec_module raises AttributeError on Python 3.12-3.14: dataclasses
# resolves string annotations through sys.modules[cls.__module__], which is
# missing. Python 3.15 loads it, so a loader passes on a 3.15 laptop and fails on
# an older CI interpreter (#3790). A loader is safe only until its target gains
# both, so the registration goes in every loader, not only the ones that break.
#
# THE RULE THIS ENFORCES
# In every tracked-shape .py / .sh / .bash file, each `<spec>.loader.exec_module(`
# call is preceded by a `sys.modules[...] = ...` assignment (or
# `sys.modules.setdefault(`) that sits after the nearest preceding
# `spec_from_file_location(`. Statements are compared by position, so a shell
# one-liner (`python3 -c '...; sys.modules[s.name] = m; s.loader.exec_module(m)'`)
# and a heredoc body are covered the same way as a .py file. The pattern is
# documented in python-plugin:python-testing § Load a Script File as a Module.
#
# Escape hatch: a line carrying `# module-registration: ok` is never flagged.
#
# Output: structured KEY=VALUE per .claude/rules/structured-script-output.md.
#   --strict  exit 1 when ISSUE_COUNT > 0 (pre-commit / CI). Default: report only.
#   <dir>     scan root (default: the repo root). Used by the self-test.

set -uo pipefail

STRICT=0
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for arg in "$@"; do
    case "$arg" in
        --strict) STRICT=1 ;;
        -*) echo "unknown option: $arg" >&2; exit 2 ;;
        *)
            if [ -d "$arg" ]; then
                ROOT_DIR="$(cd "$arg" && pwd)"
            else
                echo "not a directory: $arg" >&2; exit 2
            fi
            ;;
    esac
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "=== MODULE REGISTRATION ==="
    echo "STATUS=ERROR"
    echo "REASON=missing_dependency: python3 not found"
    echo "ISSUE_COUNT=1"
    echo "ISSUES:"
    echo "  - SEVERITY=ERROR TYPE=missing_dependency MSG=python3 not found"
    echo "=== END MODULE REGISTRATION ==="
    exit 1
fi

python3 - "$ROOT_DIR" "$STRICT" <<'PY'
import os
import re
import sys

root, strict = sys.argv[1], sys.argv[2] == "1"
# This guard and its self-test name the pattern in prose and fixtures.
SELF = {"scripts/check-module-registration.sh", "scripts/tests/test-check-module-registration.sh"}
EXTS = (".py", ".sh", ".bash")
OK_MARK = "module-registration: ok"

SPEC = re.compile(r"spec_from_file_location\(")
EXEC = re.compile(r"\b(\w+)\.loader\.exec_module\(")
REGISTER = re.compile(r"sys\.modules\s*\[[^\]]+\]\s*=(?!=)|sys\.modules\.setdefault\(")

# Discovery runs against root-RELATIVE paths, so a `.claude/worktrees` prune
# can never swallow the scan root when the root IS an agent worktree (#2219).
PRUNE = {".git", "node_modules", ".venv", "__pycache__"}
files = []
for dirpath, dirnames, filenames in os.walk(root):
    rel_dir = os.path.relpath(dirpath, root)
    rel_dir = "" if rel_dir == "." else rel_dir
    dirnames[:] = sorted(
        d for d in dirnames
        if d not in PRUNE and os.path.join(rel_dir, d) not in (".claude/worktrees", "dist")
    )
    for fn in filenames:
        rel = os.path.join(rel_dir, fn)
        if fn.endswith(EXTS) and rel not in SELF:
            files.append(rel)
files.sort()


def strip_comments(text):
    """Blank full-line comments, keeping offsets and line numbers intact."""
    return "\n".join(
        " " * len(line) if line.lstrip().startswith("#") else line
        for line in text.split("\n")
    )


loaders = 0
issues = []
for rel in files:
    try:
        with open(os.path.join(root, rel), errors="replace") as fh:
            raw = fh.read()
    except OSError:
        continue
    if "exec_module" not in raw:
        continue
    text = strip_comments(raw)
    raw_lines = raw.split("\n")
    for m in EXEC.finditer(text):
        lineno = text.count("\n", 0, m.start()) + 1
        if OK_MARK in raw_lines[lineno - 1]:
            continue
        specs = [s.start() for s in SPEC.finditer(text, 0, m.start())]
        if not specs:
            continue  # not a path-based loader
        loaders += 1
        if REGISTER.search(text, specs[-1], m.start()):
            continue
        issues.append((rel, lineno, m.group(1)))

count = len(issues)
print("=== MODULE REGISTRATION ===")
print(f"FILES_SCANNED={len(files)}")
print(f"LOADERS_SCANNED={loaders}")
if not files:
    print("SCANNED_EMPTY=true")
print(f"STATUS={'ERROR' if count else 'OK'}")
if count:
    rel, n, _ = issues[0]
    reason = f"unregistered_module: {rel} line {n}"
    if count > 1:
        reason += f" (+{count - 1} more)"
    print(f"REASON={reason[:200]}")
print(f"ISSUE_COUNT={count}")
if count:
    print("ISSUES:")
    for rel, n, spec in issues:
        print(f"  - SEVERITY=ERROR TYPE=unregistered_module FILE={rel} LINE={n} "
              f"MSG={spec}.loader.exec_module runs with no sys.modules registration after "
              f"spec_from_file_location; a dataclass + future-annotations target fails on Python 3.12-3.14")
    print("FIX: register the module between module_from_spec and exec_module:")
    print("  mod = importlib.util.module_from_spec(spec)")
    print("  sys.modules[spec.name] = mod  # before exec_module (dataclass + future annotations)")
    print("  spec.loader.exec_module(mod)")
print("=== END MODULE REGISTRATION ===")
sys.exit(1 if (strict and count) else 0)
PY
