#!/usr/bin/env bash
# Verify every repo script a workflow RUNS is reachable from that workflow's own
# pull_request `paths:` triggers.
#
# Background (issue #2219, mechanism 1): `.github/workflows/plugin-pr-checks.yml`
# ran six `scripts/check-*.sh` guards behind a `paths:` filter that listed
# `*-plugin/**`, `**/skills/**`, `.github/workflows/**`, `**/*.py` … and NO
# `scripts/**`. `**/*.py` caught Python under `scripts/`, but every guard listed
# was a `.sh`. So a PR changing only `scripts/check-*.sh` + `scripts/tests/test-*.sh`
# never ran them in CI — observed on #2215, #2217, #2218, each registering only
# `conventional-commits` and a skipped `doc-audit`. Pre-commit DID run the hooks
# locally, so the changes looked covered while CI was blind.
#
# A guard that cannot be triggered by a change to itself is a guard with no CI
# signal for its own regressions. That is the invariant this script pins.
#
# #2258 has since removed the `paths:` filter from `plugin-pr-checks.yml`
# entirely (a path-filtered workflow never REPORTS its context, which would wedge
# a required check permanently). So the repo satisfies this invariant today by
# having no filter at all. This guard exists so that re-adding a `paths:` filter
# — a natural cost-saving impulse, and the issue's own acceptance criteria float
# a narrower `scripts/**.sh` filter as a "judgement call" — cannot silently
# re-orphan the guards.
#
# Usage:
#   bash scripts/check-workflow-script-triggers.sh [--strict] [--project-dir DIR]
#
#   --strict        exit 1 when ERROR_COUNT > 0 (default: report only)
#   --project-dir   repo root to scan (default: this script's repo)
#
# Exit codes:
#   0 - no unreachable script invocations (or not --strict)
#   1 - --strict and at least one unreachable invocation
#   2 - unknown argument / missing dependency

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STRICT=0

usage() {
  echo "Usage: check-workflow-script-triggers.sh [--strict] [--project-dir DIR]" >&2
}

# An unknown argument is REJECTED, never swallowed (#2057): a silently-ignored
# flag turns a gate into a no-op that still exits 0.
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-workflow-script-triggers.sh: --project-dir requires a directory" >&2
        exit 2
      fi
      ROOT_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "check-workflow-script-triggers.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "check-workflow-script-triggers.sh: python3 not found on PATH" >&2
  exit 2
fi

WORKFLOW_DIR="$ROOT_DIR/.github/workflows"

python3 - "$WORKFLOW_DIR" "$STRICT" <<'PY'
import os
import re
import sys

workflow_dir, strict = sys.argv[1], sys.argv[2] == "1"

try:
    import yaml
except ImportError:
    print("check-workflow-script-triggers.sh: PyYAML not available", file=sys.stderr)
    sys.exit(2)


def path_matches(pattern, path):
    """Approximate GitHub's `paths:` glob semantics.

    `**` crosses directory separators; `*` and `?` do not. Anything else is
    literal. GitHub matches against the repo-relative path with no implicit
    prefix, so the pattern must cover the whole path.
    """
    out, i = [], 0
    while i < len(pattern):
        c = pattern[i]
        if pattern.startswith("**", i):
            # `**/` may also match zero directories ("**/x" matches "x").
            if pattern.startswith("**/", i):
                out.append("(?:.*/)?")
                i += 3
                continue
            out.append(".*")
            i += 2
        elif c == "*":
            out.append("[^/]*")
            i += 1
        elif c == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(c))
            i += 1
    return re.fullmatch("".join(out), path) is not None


# Collect every `scripts/....sh` (or other repo-relative .sh/.py) a run: block invokes.
INVOKE_RE = re.compile(r"(?<![\w./-])((?:scripts|[\w.-]+-plugin)/[\w./-]+\.(?:sh|py))")


def run_blocks(node):
    """Yield every `run:` string in a workflow document."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "run" and isinstance(v, str):
                yield v
            else:
                yield from run_blocks(v)
    elif isinstance(node, list):
        for v in node:
            yield from run_blocks(v)


rows = []
errors = 0
workflows_scanned = 0
invocations_total = 0

if not os.path.isdir(workflow_dir):
    print("=== WORKFLOW SCRIPT TRIGGERS ===")
    print("WORKFLOWS_SCANNED=0")
    print("SCANNED_EMPTY=true")
    print("STATUS=OK")
    print("ISSUE_COUNT=0")
    print("=== END WORKFLOW SCRIPT TRIGGERS ===")
    sys.exit(0)

for fname in sorted(os.listdir(workflow_dir)):
    if not fname.endswith((".yml", ".yaml")):
        continue
    full = os.path.join(workflow_dir, fname)
    try:
        with open(full, encoding="utf-8") as fh:
            doc = yaml.safe_load(fh)
    except Exception as exc:  # noqa: BLE001 - report, don't crash the gate
        rows.append(f"  - SEVERITY=WARN TYPE=unparseable WORKFLOW={fname} MSG={exc}")
        continue
    if not isinstance(doc, dict):
        continue
    workflows_scanned += 1

    # `on:` parses as the YAML boolean True in some documents.
    triggers = doc.get("on", doc.get(True)) or {}
    if not isinstance(triggers, dict):
        continue
    pr = triggers.get("pull_request")
    if not isinstance(pr, dict):
        continue
    paths = pr.get("paths")
    if not paths:
        # No paths filter => every change triggers it => nothing can be orphaned.
        continue

    invoked = set()
    for block in run_blocks(doc):
        for m in INVOKE_RE.finditer(block):
            invoked.add(m.group(1))

    for script in sorted(invoked):
        invocations_total += 1
        if not any(path_matches(p, script) for p in paths):
            errors += 1
            rows.append(
                f"  - SEVERITY=ERROR TYPE=unreachable_script WORKFLOW={fname} "
                f"SCRIPT={script} MSG=invoked by this workflow but matches none of its "
                f"pull_request paths: filters, so a PR changing only this script never runs it"
            )

status = "ERROR" if errors else ("WARN" if rows else "OK")

print("=== WORKFLOW SCRIPT TRIGGERS ===")
print(f"WORKFLOWS_SCANNED={workflows_scanned}")
print(f"SCANNED_EMPTY={'true' if workflows_scanned == 0 else 'false'}")
print(f"PATH_FILTERED_INVOCATIONS={invocations_total}")
print(f"STATUS={status}")
print(f"ISSUE_COUNT={len(rows)}")
print(f"ERROR_COUNT={errors}")
if rows:
    print("ISSUES:")
    for r in rows:
        print(r)
print("=== END WORKFLOW SCRIPT TRIGGERS ===")

sys.exit(1 if (strict and errors) else 0)
PY
