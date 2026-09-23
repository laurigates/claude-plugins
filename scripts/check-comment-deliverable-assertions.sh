#!/usr/bin/env bash
# Verify every Claude workflow step whose deliverable is a PR comment is
# followed by a delivery assertion and an upload of its execution transcript.
#
# Background (#2630 Rec 1, #2719). `claude-code-action` exits 0 when Claude's
# tool calls are denied, so a step whose ONLY output is a PR comment can report
# success having posted nothing. release-pr-doc-audit.yml did exactly that on
# every release PR from 2026-09-01 (4 denials per green run), and the Claude
# Skill Quality Review step in plugin-pr-checks.yml did it on PR #2664. Neither
# workflow uploaded the transcript, so the denied call could not even be named.
#
# In scope: a `claude-code-action` step in AUTOMATION mode (it has a `prompt:`)
# whose `--allowedTools` grants a comment-posting tool — `Bash(gh pr comment`,
# `Bash(gh issue comment`, `Bash(gh pr review`, `mcp__github_comment`, or
# `mcp__github_inline_comment`. Each such step must have:
#
#   missing_step_id              an `id:`, so later steps can read its outcome
#                                and its `execution_file` output
#   missing_delivery_assertion   a LATER step in the same job that runs
#                                scripts/assert-pr-comment-delivered.sh
#   missing_transcript_upload    a LATER step referencing
#                                `steps.<id>.outputs.execution_file`, plus a later
#                                actions/upload-artifact step
#
# Out of scope, and counted rather than silently dropped: TAG mode (no
# `prompt:`), where the action creates its own tracking comment; steps with no
# `--allowedTools` (nothing declared to check against); and issue-filers, whose
# liveness is scripts/check-audit-liveness.sh's concern.
#
# Usage:
#   bash scripts/check-comment-deliverable-assertions.sh [--project-dir <path>] [workflow.yml ...]
#
# Exit codes:
#   0 - every in-scope step carries both
#   1 - one or more in-scope steps are missing one
#   2 - usage / environment error
#
# There is deliberately no `--strict`: the script already exits 1 on any
# finding, so accepting one would advertise a tightening mode that does not
# exist (#2057).

set -euo pipefail

usage() {
  echo "Usage: check-comment-deliverable-assertions.sh [--project-dir DIR] [workflow.yml ...]" >&2
}

proj_dir=""
explicit_files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-comment-deliverable-assertions.sh: --project-dir requires a directory" >&2
        usage
        exit 2
      fi
      proj_dir="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "check-comment-deliverable-assertions.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
    *) explicit_files+=("$1"); shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "check-comment-deliverable-assertions.sh: python3 not found on PATH" >&2
  exit 2
fi

python3 - "$proj_dir" "${explicit_files[@]+"${explicit_files[@]}"}" <<'PY'
import os
import re
import sys

proj_dir = sys.argv[1]
explicit = sys.argv[2:]

try:
    import yaml
except ImportError:  # pragma: no cover - environment error, never a silent pass
    sys.stderr.write(
        "check-comment-deliverable-assertions.sh: PyYAML is required to parse workflow YAML\n"
    )
    sys.exit(2)

CLAUDE_ACTION = "anthropics/claude-code-action"
ASSERT_SCRIPT = "scripts/assert-pr-comment-delivered.sh"
UPLOAD_ACTION = "actions/upload-artifact"
COMMENT_GRANTS = (
    "Bash(gh pr comment",
    "Bash(gh issue comment",
    "Bash(gh pr review",
    "mcp__github_comment",
    "mcp__github_inline_comment",
)


def workflow_files():
    if explicit:
        return explicit
    wf_dir = os.path.join(proj_dir, ".github", "workflows")
    if not os.path.isdir(wf_dir):
        return []
    return [
        os.path.join(wf_dir, name)
        for name in sorted(os.listdir(wf_dir))
        if name.endswith((".yml", ".yaml"))
    ]


def allowed_tools(claude_args):
    if not isinstance(claude_args, str):
        return None
    m = re.search(r'--allowedTools\s+"([^"]*)"', claude_args)
    if not m:
        return None
    return [t.strip() for t in m.group(1).split(",") if t.strip()]


def step_text(step):
    """Every string a step carries (run, if, env values, with values)."""
    parts = []
    for key in ("run", "if"):
        value = step.get(key)
        if isinstance(value, str):
            parts.append(value)
    for key in ("env", "with"):
        mapping = step.get(key)
        if isinstance(mapping, dict):
            parts.extend(str(v) for v in mapping.values())
    return "\n".join(parts)


scanned = 0
claude_steps = 0
in_scope = 0
skipped_tag = 0
skipped_no_allowlist = 0
issues = []

for path in workflow_files():
    if not os.path.isfile(path):
        continue
    scanned += 1
    rel = os.path.relpath(path, proj_dir)
    try:
        doc = yaml.safe_load(open(path, encoding="utf-8"))
    except yaml.YAMLError as exc:
        issues.append(f"SEVERITY=ERROR TYPE=yaml_unparsable FILE={rel} MSG={str(exc).splitlines()[0]}")
        continue
    jobs = doc.get("jobs") if isinstance(doc, dict) else None
    if not isinstance(jobs, dict):
        continue
    for job_id, job in jobs.items():
        steps = job.get("steps") if isinstance(job, dict) else None
        if not isinstance(steps, list):
            continue
        for idx, step in enumerate(steps):
            if not isinstance(step, dict):
                continue
            uses = step.get("uses")
            if not isinstance(uses, str) or CLAUDE_ACTION not in uses:
                continue
            claude_steps += 1
            with_map = step.get("with") if isinstance(step.get("with"), dict) else {}
            if "prompt" not in with_map:
                skipped_tag += 1
                continue
            tools = allowed_tools(with_map.get("claude_args"))
            if tools is None:
                skipped_no_allowlist += 1
                continue
            if not any(t.startswith(g) for t in tools for g in COMMENT_GRANTS):
                continue
            in_scope += 1
            step_id = step.get("id")
            label = step_id if isinstance(step_id, str) else f"#{idx}"
            where = f"FILE={rel} JOB={job_id} STEP={label}"
            later = [s for s in steps[idx + 1:] if isinstance(s, dict)]
            if not isinstance(step_id, str):
                issues.append(
                    f"SEVERITY=ERROR TYPE=missing_step_id {where} "
                    "MSG=a comment-posting Claude step needs an id so later steps can read its outcome and execution_file"
                )
            if not any(ASSERT_SCRIPT in step_text(s) for s in later):
                issues.append(
                    f"SEVERITY=ERROR TYPE=missing_delivery_assertion {where} "
                    f"MSG=no later step runs {ASSERT_SCRIPT}, so a run that posts nothing reports green"
                )
            ref = f"steps.{step_id}.outputs.execution_file" if isinstance(step_id, str) else None
            has_ref = bool(ref) and any(ref in step_text(s) for s in later)
            has_upload = any(UPLOAD_ACTION in str(s.get("uses", "")) for s in later)
            if not (has_ref and has_upload):
                issues.append(
                    f"SEVERITY=ERROR TYPE=missing_transcript_upload {where} "
                    "MSG=no later step uploads this step's execution_file, so a denied tool call cannot be named"
                )

status = "ERROR" if issues else "OK"
print("=== COMMENT DELIVERABLE ASSERTIONS ===")
print(f"WORKFLOWS_SCANNED={scanned}")
print(f"CLAUDE_STEPS={claude_steps}")
print(f"COMMENT_DELIVERABLE_STEPS={in_scope}")
print(f"SKIPPED_TAG_MODE={skipped_tag}")
print(f"SKIPPED_NO_ALLOWLIST={skipped_no_allowlist}")
print(f"SCANNED_EMPTY={'true' if scanned == 0 else 'false'}")
print(f"STATUS={status}")
print(f"ISSUE_COUNT={len(issues)}")
if issues:
    print("ISSUES:")
    for row in issues:
        print(f"  - {row}")
print("=== END COMMENT DELIVERABLE ASSERTIONS ===")
sys.exit(1 if issues else 0)
PY
