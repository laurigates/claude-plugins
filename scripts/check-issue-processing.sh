#!/usr/bin/env bash
# Every machine-filed or feedback issue says who processes it and when it
# closes (#3346, docs/issue-lifecycle.md).
#
# Before this, scheduled audits and feedback issues stated neither, so they
# piled up open: five unprocessed research radars, ten positive-feedback issues
# nothing read, three stale monthly reports. Each generator now writes a
# `## Processing` section into the body it files. This check keeps it there.
#
# Checked sites (every `.github/workflows/*.yml`, parsed with PyYAML):
#   - a `uses: ./.github/actions/script-to-issue` step with a `script:`
#     (full mode, so it files an issue) must pass `processing:` containing a
#     `## Processing` heading
#   - a step whose `with.prompt` asks Claude to run `gh issue create` must carry
#     `## Processing` in that prompt (the body template lives there)
#   - a `run:` step that runs `gh issue create` must write `## Processing`
# plus:
#   - feedback-plugin/skills/feedback-session/references/issue-format.md, the
#     feedback issue template, must contain `## Processing`
#   - every label (and title) on scripts/issue-grouping-exempt.txt, the list of
#     recurring machine-filed and feedback issues, except `epic`, must be named
#     in docs/issue-lifecycle.md
#
# A workflow that files ordinary actionable issues (a CI-failure report, a
# follow-up from a changelog) is exempt by job in EXEMPT_SITES below, with the
# reason; those issues follow the normal fix-and-close lifecycle.
#
# Usage: bash scripts/check-issue-processing.sh [--project-dir DIR]
# Exit: 0 OK, 1 ERROR, 2 usage error.

set -uo pipefail

PROJECT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      if [ $# -lt 2 ]; then echo "Usage: check-issue-processing.sh [--project-dir DIR]" >&2; exit 2; fi
      PROJECT_DIR="$2"; shift 2 ;;
    -h|--help) echo "Usage: check-issue-processing.sh [--project-dir DIR]"; exit 0 ;;
    *) echo "check-issue-processing.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "check-issue-processing.sh: PyYAML is required" >&2
  exit 2
fi

python3 - "$PROJECT_DIR" <<'PY'
import os
import re
import sys

import yaml

root = sys.argv[1]

# workflow file : job id -> reason. Their issues are actionable work items with
# the ordinary lifecycle (fixed by a PR, closed on merge), not reports.
EXEMPT_SITES = {
    ".github/workflows/github-workflow-auto-fix.yml:auto-fix":
        "files one actionable CI-failure issue; closed by the fix",
    ".github/workflows/obsidian-cli-changelog.yml:claude-review":
        "files actionable follow-up issues for work its PR leaves out; closed by the PR that does it",
}

SCRIPT_TO_ISSUE = "./.github/actions/script-to-issue"
FEEDBACK_TEMPLATE = "feedback-plugin/skills/feedback-session/references/issue-format.md"
LIFECYCLE_DOC = "docs/issue-lifecycle.md"
EXEMPT_LIST = "scripts/issue-grouping-exempt.txt"
HEADING = re.compile(r"^\s*(?:echo\s+[\"']?)?## Processing\b", re.M)
# In a `run:` script, a line that RUNS `gh issue create` (optionally inside a
# quoted string the step prints for Claude); a comment naming the command is
# not a filing site. In a Claude prompt, any mention is: "open an issue via
# `gh issue create`" in prose files issues as surely as a code block does.
CREATE = re.compile(r"^\s*[\"']?\s*gh issue create\b", re.M)
CREATE_IN_PROMPT = re.compile(r"\bgh issue create\b")

issues = []  # (severity, type, msg)
sites_checked = 0
exempted = 0


def has_heading(text):
    return bool(HEADING.search(text or ""))


wf_dir = os.path.join(root, ".github", "workflows")
workflow_files = sorted(
    f for f in (os.listdir(wf_dir) if os.path.isdir(wf_dir) else [])
    if f.endswith((".yml", ".yaml"))
)

for name in workflow_files:
    rel = f".github/workflows/{name}"
    try:
        doc = yaml.safe_load(open(os.path.join(wf_dir, name), encoding="utf-8")) or {}
    except yaml.YAMLError as exc:
        issues.append(("ERROR", "unparseable_workflow", f"{rel}: {exc}".splitlines()[0]))
        continue
    jobs = doc.get("jobs") or {}
    if not isinstance(jobs, dict):
        continue
    for job_id, job in jobs.items():
        if not isinstance(job, dict):
            continue
        for idx, step in enumerate(job.get("steps") or []):
            if not isinstance(step, dict):
                continue
            with_ = step.get("with") or {}
            if not isinstance(with_, dict):
                with_ = {}
            site = f"{rel}:{job_id}:{step.get('name') or step.get('id') or idx}"
            kind = None
            text = ""
            if str(step.get("uses", "")).strip() == SCRIPT_TO_ISSUE and str(with_.get("script", "")).strip():
                kind, text = "processing input", str(with_.get("processing", ""))
            elif CREATE_IN_PROMPT.search(str(with_.get("prompt", ""))):
                kind, text = "prompt", str(with_.get("prompt", ""))
            elif CREATE.search(str(step.get("run", ""))):
                kind, text = "run script", str(step.get("run", ""))
            if kind is None:
                continue
            if f"{rel}:{job_id}" in EXEMPT_SITES:
                exempted += 1
                continue
            sites_checked += 1
            if not has_heading(text):
                issues.append((
                    "ERROR", "missing_processing",
                    f"{site}: the {kind} files an issue with no '## Processing' section "
                    f"(who processes it, what completed means, when it closes; see {LIFECYCLE_DOC})",
                ))

# The feedback issue template.
fb = os.path.join(root, FEEDBACK_TEMPLATE)
feedback_checked = os.path.isfile(fb)
if feedback_checked:
    if not has_heading(open(fb, encoding="utf-8").read()):
        issues.append(("ERROR", "missing_processing",
                       f"{FEEDBACK_TEMPLATE}: the issue body template has no '## Processing' section"))

# Every recurring type on the exempt list is documented.
exempt_path = os.path.join(root, EXEMPT_LIST)
doc_path = os.path.join(root, LIFECYCLE_DOC)
types = []
if os.path.isfile(exempt_path):
    for line in open(exempt_path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        kind, _, value = line.partition(" ")
        value = value.strip()
        if kind == "label" and value != "epic":
            types.append(("label", value))
        elif kind == "title":
            types.append(("title", value))
if types:
    if not os.path.isfile(doc_path):
        issues.append(("ERROR", "missing_lifecycle_doc", f"{LIFECYCLE_DOC} does not exist"))
    else:
        doc_text = open(doc_path, encoding="utf-8").read()
        for kind, value in types:
            needle = f"`{value}`" if kind == "label" else value.strip("^$")
            if needle not in doc_text:
                issues.append(("ERROR", "undocumented_type",
                               f"{kind} '{value}' is on {EXEMPT_LIST} but {LIFECYCLE_DOC} does not name it"))

if sites_checked == 0:
    issues.insert(0, ("ERROR", "nothing_scanned",
                      f"no issue-filing workflow step found under {root}; refusing to report OK"))

status = "ERROR" if any(s == "ERROR" for s, _, _ in issues) else "OK"

print("=== ISSUE PROCESSING ===")
print(f"WORKFLOWS_SCANNED={len(workflow_files)}")
print(f"SITES_CHECKED={sites_checked}")
print(f"SITES_EXEMPT={exempted}")
print(f"FEEDBACK_TEMPLATE_CHECKED={str(feedback_checked).lower()}")
print(f"STATUS={status}")
if status != "OK":
    first = next(i for i in issues if i[0] == status)
    reason = " ".join(f"{first[1]}: {first[2]}".split())[:180]
    if len(issues) > 1:
        reason += f" (+{len(issues) - 1} more)"
    print(f"REASON={reason}")
print(f"ISSUE_COUNT={len(issues)}")
if issues:
    print("ISSUES:")
    for sev, typ, msg in issues:
        print(f"  - SEVERITY={sev} TYPE={typ} MSG={msg}")
print("=== END ISSUE PROCESSING ===")
sys.exit(1 if status == "ERROR" else 0)
PY
