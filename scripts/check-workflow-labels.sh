#!/usr/bin/env bash
# Verify every GitHub label a workflow ATTACHES is also PROVISIONED by that same
# workflow (or is externally managed and allowlisted below).
#
# Background: `gh issue create --label "<a>,<b>"` hard-fails with
# `could not add label: '<a>' not found` and exits 1 when ANY label in the list
# is unknown to the repo. The failure lands on the LAST line of the job, after
# all the real work has already succeeded — so the run is red, the analysis is
# thrown away, and the error looks nothing like its cause.
#
# This is not hypothetical. Three scheduled audits in this repo ran red for up
# to five months on exactly this (2026-03-01 -> 2026-08-21, 0 green runs):
#
#   scheduled-audits.yml     blueprint-health, infra-compliance,
#                            docs-index, agentic-audit    (4 jobs, every run)
#   fleet-drift-audit.yml    fleet-drift                  (after a 77-finding audit)
#   workflow-model-audit.yml workflow-model-audit         (latent behind a second bug)
#
# Six labels, never created, no labels-as-code file anywhere in the repo. The
# `maintenance` label paired with each of them DID exist, which is why the calls
# looked plausible on review.
#
# The fix this guard enforces is self-provisioning: an idempotent
# `gh label create <name> --force` step ahead of the create call, so a label that
# is deleted (or was never created) can never re-red the workflow. `--force`
# creates-or-updates and exits 0, so it is also parallel-safe
# (`.claude/rules/parallel-safe-queries.md`).
#
# Prefer `--force` over the older `2>/dev/null || true` form used at
# golden-set-evaluation.yml:97 and research-radar.yml:44: that form also swallows
# genuine auth failures, deferring the error to a much more expensive step.
#
# Usage:
#   bash scripts/check-workflow-labels.sh [--strict] [--project-dir <path>] [workflow.yml ...]
#
#   --strict        Also fail on labels whose value could not be resolved
#                   statically (e.g. `--label "$VAR"`).
#   --project-dir   Repo root to scan (default: git toplevel, else cwd).
#   workflow.yml …  Explicit files to check (pre-commit style); when present,
#                   discovery is skipped and only these files are checked.
#
# Exit codes:
#   0 - every attached label is provisioned in-workflow or allowlisted
#   1 - one or more labels are attached but never provisioned
#   2 - usage / environment error
set -euo pipefail

# Labels managed OUTSIDE any workflow. A label belongs here only when it was
# verified to exist in the repo AND something else genuinely owns its lifecycle
# -- never to silence a finding. Each entry below was confirmed present via the
# GitHub label API on 2026-08-21.
#
# One entry per LINE, not per word: GitHub label names may contain spaces
# (release-please ships "autorelease: pending"), so a whitespace-split allowlist
# would silently shred them into unmatchable fragments.
#
# Test seam: CHECK_WORKFLOW_LABELS_ALLOWLIST (newline-separated) REPLACES this
# list so the regression test can exercise both the honoring and the flagging
# path without a real exemption.
DEFAULT_ALLOWLIST='maintenance
bug
stranded-work
comfyui-plugin'

STRICT=0
ROOT_DIR=""
FILES=()

usage() {
  echo "Usage: check-workflow-labels.sh [--strict] [--project-dir DIR] [workflow.yml ...]" >&2
}

# An unknown argument is REJECTED, never swallowed (#2057): a silently-ignored
# flag turns a gate into a no-op that still exits 0.
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-workflow-labels.sh: --project-dir requires a directory" >&2
        exit 2
      fi
      ROOT_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do FILES+=("$1"); shift; done ;;
    -*)
      echo "check-workflow-labels.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

if [ -z "$ROOT_DIR" ]; then
  ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "check-workflow-labels.sh: python3 not found on PATH" >&2
  exit 2
fi

ALLOWLIST="${CHECK_WORKFLOW_LABELS_ALLOWLIST-$DEFAULT_ALLOWLIST}"

python3 - "$ROOT_DIR" "$STRICT" "$ALLOWLIST" "${FILES[@]+"${FILES[@]}"}" <<'PY'
import os
import re
import sys

root_dir = sys.argv[1]
strict = sys.argv[2] == "1"
allowlist = {s.strip() for s in sys.argv[3].splitlines() if s.strip()}
explicit = [a for a in sys.argv[4:] if a]

workflow_dir = os.path.join(root_dir, ".github", "workflows")

if explicit:
    files = [f if os.path.isabs(f) else os.path.join(root_dir, f) for f in explicit]
    files = [f for f in files if os.path.isfile(f)]
else:
    files = []
    if os.path.isdir(workflow_dir):
        for name in sorted(os.listdir(workflow_dir)):
            if name.endswith((".yml", ".yaml")):
                files.append(os.path.join(workflow_dir, name))

# Labels are ATTACHED via `--label <value>` on `gh issue create` / `gh pr create`.
# We scan raw text rather than parsed YAML on purpose: one real call site lives
# inside a Claude prompt heredoc (scheduled-audits.yml, the agentic-audit job),
# where a run-block walk would never see it -- and Claude does execute it.
#
# Scoping to CREATE is load-bearing, not tidiness. `gh issue list --label <x>`
# on an unknown label returns an empty connection and exits 0 -- harmless -- so
# counting reads would flag call sites that cannot fail. It would also drag in
# prose ("omit the --label flag", "e.g. gh issue list --label LABEL"), which is
# how an earlier revision of this guard reported `flag` and `LABEL` as labels.
CREATE_RE = re.compile(r"gh\s+(?:issue|pr)\s+create\b")
LABEL_VALUE_RE = re.compile(r"--label[=\s]+(\"[^\"]*\"|'[^']*'|[^\s\\]+)")

# Labels are PROVISIONED via `gh label create <name>`. The name is always the
# first positional token, on the same line, even when flags continue onto the
# next line with a backslash.
PROVISION_RE = re.compile(r"gh\s+label\s+create\s+(\"[^\"]*\"|'[^']*'|[^\s\\]+)")


def unquote(tok):
    if len(tok) >= 2 and tok[0] == tok[-1] and tok[0] in "\"'":
        return tok[1:-1]
    return tok


def split_labels(value):
    """`--label "a,b"` attaches two labels; `--label a` attaches one."""
    return [p.strip() for p in value.split(",") if p.strip()]


findings = []       # (file, label) attached but never provisioned
unresolved = []     # (file, raw) value we could not evaluate statically
scanned = 0
attach_sites = 0

for path in files:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        print("check-workflow-labels.sh: cannot read %s: %s" % (path, exc), file=sys.stderr)
        sys.exit(2)

    scanned += 1
    rel = os.path.relpath(path, root_dir)

    provisioned = {unquote(m.group(1)) for m in PROVISION_RE.finditer(text)}

    # A `gh issue create` is routinely spread over many lines with backslash
    # continuations, with `--label` several lines below the command itself.
    # Fold each continued command back into one logical line before matching so
    # the command and its flags can be seen together.
    joined = re.sub(r"\\\s*\n\s*", " ", text)

    for line in joined.splitlines():
        if not CREATE_RE.search(line):
            continue
        for m in LABEL_VALUE_RE.finditer(line):
            raw = unquote(m.group(1))
            attach_sites += 1
            # A value built from a shell/Actions expression cannot be resolved here.
            if "$" in raw or "{{" in raw:
                unresolved.append((rel, raw))
                continue
            for label in split_labels(raw):
                if label in provisioned or label in allowlist:
                    continue
                if (rel, label) not in findings:
                    findings.append((rel, label))

print("=== WORKFLOW LABEL PROVISIONING ===")
print("WORKFLOWS_SCANNED=%d" % scanned)
print("SCANNED_EMPTY=%s" % ("true" if scanned == 0 else "false"))
print("ATTACH_SITES=%d" % attach_sites)
print("ALLOWLIST_SIZE=%d" % len(allowlist))
print("UNPROVISIONED_COUNT=%d" % len(findings))
print("UNRESOLVED_COUNT=%d" % len(unresolved))

if findings:
    print("")
    print("=== UNPROVISIONED LABELS ===")
    for rel, label in findings:
        print("UNPROVISIONED=%s\tLABEL=%s" % (rel, label))

if unresolved:
    print("")
    print("=== UNRESOLVED LABEL VALUES ===")
    for rel, raw in unresolved:
        print("UNRESOLVED=%s\tVALUE=%s" % (rel, raw))

failed = bool(findings) or (strict and bool(unresolved))

if failed:
    print("")
    print("=== REMEDY ===")
    print("Add an idempotent provisioning step ahead of the create call:")
    print("")
    print("  - name: Ensure labels exist")
    print("    env:")
    print("      GH_TOKEN: ${{ github.token }}")
    print("    run: |")
    print("      gh label create <name> --repo \"$GITHUB_REPOSITORY\" \\")
    print("        --color <hex> --description \"<why this label exists>\" --force")
    print("")
    print("`--force` creates-or-updates and exits 0, so it is idempotent and")
    print("parallel-safe. The workflow needs `issues: write`, which every")
    print("issue-creating workflow already declares.")

print("")
print("STATUS=%s" % ("FAIL" if failed else "OK"))
sys.exit(1 if failed else 0)
PY
