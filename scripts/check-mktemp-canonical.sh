#!/usr/bin/env bash
# check-mktemp-canonical.sh — guard against the macOS /var vs /private/var
# fixture-path mismatch (issues #2939, #2949).
#
# THE HAZARD
# On macOS `mktemp -d` returns /var/folders/…, and /var is a symlink to
# /private/var. A test that builds an EXPECTED path from the raw temp root
#     fixture=$(mktemp -d)
#     bash "$SUT" "$fixture/out"
#     grep -q "$fixture/out/run.py" "$fixture/out/hooks.json" || fail
# fails only on macOS whenever the code under test reports a canonical path
# (`pwd -P`, `realpath`, `readlink -f`, `git rev-parse --show-toplevel`,
# `os.path.realpath`, `Path.resolve()`). Linux has no symlink in front of /tmp,
# so CI stays green and the bug ships. Simulate it on Linux with a symlinked
# temp root: `real=$(mktemp -d); ln -s "$real" /tmp/l$$; TMPDIR=/tmp/l$$ bash <test>`.
#
# THE RULE THIS ENFORCES
# In a test the skill-script runner discovers (`test-*.sh` under
# `*/scripts/tests/`, `*/hooks/`, `experiments/*/tests/`), a `VAR=$(mktemp -d …)`
# root whose raw value reaches an EXPECTED-PATH comparison is canonicalised once,
# right after creation (after the empty/is-dir guard):
#     VAR=$(cd -P -- "$VAR" && pwd -P) || { echo "cannot resolve" >&2; exit 1; }
# Any re-assignment of VAR through `pwd -P` / `realpath` / `readlink -f` counts,
# as does creating it canonical: `VAR=$(cd "$(mktemp -d)" && pwd -P)`.
#
# The heuristic is deliberately narrow — it reports what is plausibly broken,
# not every temp dir a test touches. A finding needs ALL of:
#   1. ROOT: a `VAR=$(mktemp -d …)` never re-assigned canonically. Variables
#      assigned from it (`sub="$VAR/x"`) inherit its status, transitively.
#   2. COMPARISON: the root (or a derived var) is the EXPECTED side of a check —
#        - the pattern argument of `grep` (`grep -q "$VAR/x" file`);
#        - an operand of `=`/`==`/`!=` inside `[ … ]` / `[[ … ]]`, outside `$(…)`;
#        - a top-level argument of an `assert*`/`check*`/`expect*` call
#          (inside `$(…)` it is an input to the command, not an expectation);
#        - an `expected*=` / `want*=` assignment.
#   3. REACH: a canonicalising code path is in reach — the test's own code, or
#      a script it names (`<name>.sh` / `<name>.py`, looked up across the repo,
#      tests excluded) uses one of the canonicalising calls above. A comparison
#      whose both sides are string-built never trips this gate.
#
# Escape hatch: a line carrying `# mktemp-canonical: ok` is never a comparison
# (for an assertion that deliberately compares the logical spelling).
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
    echo "=== MKTEMP CANONICAL ==="
    echo "STATUS=ERROR"
    echo "REASON=missing_dependency: python3 not found"
    echo "ISSUE_COUNT=1"
    echo "ISSUES:"
    echo "  - SEVERITY=ERROR TYPE=missing_dependency MSG=python3 not found"
    echo "=== END MKTEMP CANONICAL ==="
    exit 1
fi

python3 - "$ROOT_DIR" "$STRICT" <<'PY'
import os
import re
import sys

root, strict = sys.argv[1], sys.argv[2] == "1"
SELF_TEST = "scripts/tests/test-check-mktemp-canonical.sh"

# Discovery runs against root-RELATIVE paths, so a `.claude/worktrees` prune
# can never swallow the scan root when the root IS an agent worktree (#2219).
PRUNE = {".git", "node_modules"}
tests, sources = [], {}
for dirpath, dirnames, filenames in os.walk(root):
    rel_dir = os.path.relpath(dirpath, root)
    rel_dir = "" if rel_dir == "." else rel_dir
    dirnames[:] = sorted(
        d for d in dirnames
        if d not in PRUNE
        and os.path.join(rel_dir, d) not in (".claude/worktrees", "dist")
    )
    for fn in filenames:
        rel = os.path.join(rel_dir, fn)
        if fn.endswith((".sh", ".py")):
            sources.setdefault(fn, []).append(rel)
        if not (fn.startswith("test-") and fn.endswith(".sh")) or rel == SELF_TEST:
            continue
        parts = rel.split(os.sep)
        if ("/scripts/tests/" in "/" + rel or "/hooks/" in "/" + rel
                or (parts[0] == "experiments" and "tests" in parts)):
            tests.append(rel)
tests.sort()

CANON = re.compile(r"pwd -P|\brealpath\b|readlink -f|--show-toplevel|os\.path\.realpath|\.resolve\(\)")
NAME = r"[A-Za-z_][A-Za-z0-9_]*"
ASSIGN = re.compile(r"^\s*(?:local\s+|export\s+|declare\s+(?:-\w+\s+)?)?(" + NAME + r")=(.*)$")
MKTEMP_DIR = re.compile(r"""^["']?\$\(mktemp\s+(?:-[A-Za-z]*d[A-Za-z]*|--directory)\b""")
# Only assertion helpers whose NAME says they compare (assert_eq, check_line,
# expect_contains, assert_stderr_contains, …). A bare `check`/`expect`/`assert`
# takes positional arguments of unknown role — often an input path — so it is
# too noisy to read as an expectation.
CALL = re.compile(r"^\s*(?:if\s+!?\s*|!\s*)?((?:assert|check|expect)\w*(?:eq|equal|equals|same|line|contains|match|matches|text|has|absent)\w*)\s+(\"[^\"]*\"|'[^']*'|\S+)")
EXPECT_ASSIGN = re.compile(r"^\s*(?:local\s+)?(?:expected|want)\w*=")
OK_MARK = "mktemp-canonical: ok"


def code_lines(text):
    """(lineno, code) with full-line comments blanked."""
    out = []
    for i, line in enumerate(text.splitlines(), 1):
        out.append((i, "" if line.lstrip().startswith("#") else line))
    return out


def depth_map(line):
    """Command-substitution depth at each character index ($( opens, ) closes)."""
    depth, d, i = [], 0, 0
    while i < len(line):
        if line.startswith("$(", i):
            depth.extend([d, d]); d += 1; i += 2; continue
        if line[i] == ")" and d > 0:
            d -= 1
        depth.append(d); i += 1
    return depth


def refs(var):
    return re.compile(r"\$(?:\{" + var + r"\}|" + var + r"\b)")


def is_comparison(line, var):
    """Does `line` use $var as the EXPECTED side of a check?"""
    if OK_MARK in line:
        return False
    rx = refs(var)
    hits = [m.start() for m in rx.finditer(line)]
    if not hits:
        return False
    # grep pattern position: grep [opts] [-e] <pattern> — wherever it sits.
    for g in re.finditer(r"\bgrep((?:\s+-[-\w]*)*)\s+(?:-e\s+)?(\S+)", line):
        pat = g.group(2)
        if rx.search(pat) and not g.group(1).rstrip().endswith(("-f", "--file")):
            return True
    if EXPECT_ASSIGN.match(line):
        return True
    depth = depth_map(line)
    top = [h for h in hits if depth[h] == 0]
    if not top:
        return False
    call = CALL.match(line)
    if call and any(h >= call.end(2) for h in top):  # not inside the label argument
        return True
    for t in re.finditer(r"\[\[?\s(.*?)\s\]\]?", line):
        if re.search(r"\s(=|==|!=)\s", t.group(1)) and any(t.start(1) <= h < t.end(1) for h in top):
            return True
    return False


reach_cache = {}


def canonical_in_reach(rel, text):
    if rel in reach_cache:
        return reach_cache[rel]
    code = "\n".join(c for _, c in code_lines(text))
    hit = bool(CANON.search(code))
    if not hit:
        for name in sorted(set(re.findall(r"[A-Za-z0-9_.-]+\.(?:sh|py)\b", code))):
            if name.startswith("test-") or name.startswith("test_"):
                continue
            for cand in sources.get(name, []):
                if "/tests/" in "/" + cand or os.path.basename(cand).startswith("test-"):
                    continue
                try:
                    with open(os.path.join(root, cand), errors="replace") as fh:
                        body = "\n".join(c for _, c in code_lines(fh.read()))
                except OSError:
                    continue
                if CANON.search(body):
                    hit = True
                    break
            if hit:
                break
    reach_cache[rel] = hit
    return hit


issues = []
for rel in tests:
    try:
        with open(os.path.join(root, rel), errors="replace") as fh:
            text = fh.read()
    except OSError:
        continue
    lines = code_lines(text)
    roots, canonical, derived_from, canon_like = {}, set(), {}, set()
    for n, code in lines:
        m = ASSIGN.match(code)
        if not m:
            continue
        var, rhs = m.group(1), m.group(2)
        src = re.match(r"""^["']?\$(?:\{(""" + NAME + r""")\}|(""" + NAME + r"""))""", rhs)
        if MKTEMP_DIR.match(rhs):
            # `mktemp -d "$parent/x.XXXX"` / `-p "$parent"` under an already
            # canonical parent returns a canonical path: nothing to resolve.
            if any(refs(c).search(rhs) for c in canon_like):
                canon_like.add(var)
            else:
                roots.setdefault(var, n)
        elif CANON.search(rhs) and (refs(var).search(rhs) or "mktemp" in rhs):
            canonical.add(var)
            canon_like.add(var)
        elif src:
            parent = src.group(1) or src.group(2)
            derived_from.setdefault(var, parent)
            if parent in canon_like:
                canon_like.add(var)
    live = {v for v in roots if v not in canonical}
    if not live:
        continue
    # A derived var follows its source root, transitively (bounded).
    family = {v: v for v in live}
    for _ in range(5):
        for var, src in derived_from.items():
            if var not in family and src in family and var not in canonical:
                family[var] = family[src]
    seen_roots = set()
    for n, code in lines:
        for var, root_var in family.items():
            if root_var in seen_roots or n == roots.get(var):
                continue
            if is_comparison(code, var):
                if not canonical_in_reach(rel, text):
                    break
                seen_roots.add(root_var)
                via = "" if var == root_var else f" via ${var}"
                issues.append((rel, n, root_var,
                               f"raw mktemp -d root ${root_var}{via} is an expected path at line {n} "
                               f"beside a canonicalising code path; on macOS /var -> /private/var it never matches"))

count = len(issues)
status = "ERROR" if count else "OK"
print("=== MKTEMP CANONICAL ===")
print(f"TESTS_SCANNED={len(tests)}")
if not tests:
    print("SCANNED_EMPTY=true")
print(f"STATUS={status}")
if count:
    first = issues[0]
    reason = f"uncanonical_mktemp_root: {first[0]} ${first[2]} compared at line {first[1]}"[:180]
    if count > 1:
        reason += f" (+{count - 1} more)"
    print(f"REASON={reason[:200]}")
print(f"ISSUE_COUNT={count}")
if count:
    print("ISSUES:")
    for rel, n, var, msg in issues:
        print(f"  - SEVERITY=ERROR TYPE=uncanonical_mktemp_root FILE={rel} LINE={n} VAR={var} MSG={msg}")
    print("FIX: canonicalise the root once, right after creating and guarding it:")
    print('  VAR=$(mktemp -d) || { echo "mktemp failed" >&2; exit 1; }')
    print('  [ -n "$VAR" ] && [ -d "$VAR" ] || { echo "bad temp dir" >&2; exit 1; }')
    print('  VAR=$(cd -P -- "$VAR" && pwd -P) || { echo "cannot resolve" >&2; exit 1; }')
print("=== END MKTEMP CANONICAL ===")
sys.exit(1 if (strict and count) else 0)
PY
