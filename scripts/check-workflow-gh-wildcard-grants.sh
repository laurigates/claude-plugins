#!/usr/bin/env bash
# Flag a workflow Claude step whose `--allowedTools` grants a whole `gh`
# command group (`Bash(gh pr *)`, `Bash(gh issue *)`, `Bash(gh label *)`, ...)
# instead of the verbs its prompt actually runs.
#
# Background (#2769). A `Bash(<pattern>)` grant is a PREFIX match on the whole
# command string, so `Bash(gh pr *)` reaches `gh pr view` and also
# `gh pr create`, `gh pr merge`, `gh pr close` and `gh pr edit`. Four workflows
# granted group wildcards where their prompts ran one or two verbs:
#
#   auto-resolve-conflicts    Bash(gh pr *)                 prompt runs gh pr comment
#   obsidian-cli-changelog    Bash(gh pr|issue|label *)     prompt runs the three creates
#   research-radar            Bash(gh issue *), gh label *  prompt runs gh issue create
#   github-workflow-auto-fix  Bash(gh pr|issue|run *)       prompt runs comment/view/list/create
#
# Each of those steps feeds the agent untrusted text (PR titles and conflict
# hunks, a third-party doc, paper abstracts, CI logs), so the grant is the
# boundary a prompt injection would test, and a group wildcard puts every
# publishing verb inside it. #2720 is the other cost: an agent that can retry
# any verb can turn one partial failure into duplicate artifacts.
#
# WHAT THIS CHECKS. Every `--allowedTools "<list>"` in a workflow file, whether
# in a claude-code-action `claude_args` or a `run:` block that invokes the CLI
# directly (auto-resolve-conflicts does the latter, so a claude-code-action-only
# scan would miss it). An entry is flagged when it is:
#
#   Bash(gh)  Bash(gh *)  Bash(gh:*)            the whole gh CLI
#   Bash(gh <group> *)  Bash(gh <group>:*)      a whole command group, for a
#                                               group that has publishing verbs
#
# `gh api` is deliberately NOT a group here: its HTTP method is a flag
# (`-X POST`), so no verb-level grant exists to narrow it to. That needs a
# different control and is out of this guard's scope.
#
# Usage:
#   bash scripts/check-workflow-gh-wildcard-grants.sh [--project-dir <path>] [workflow.yml ...]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd).
#   workflow.yml …  Explicit files to check; when present, discovery is skipped.
#
# Exit codes:
#   0 - no group-wildcard gh grant
#   1 - one or more group-wildcard gh grants, or no allowlist found at all
#   2 - usage / environment error

set -euo pipefail

usage() {
  echo "Usage: check-workflow-gh-wildcard-grants.sh [--project-dir DIR] [workflow.yml ...]" >&2
}

proj_dir=""
explicit_files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-workflow-gh-wildcard-grants.sh: --project-dir requires a directory" >&2
        usage
        exit 2
      fi
      proj_dir="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "check-workflow-gh-wildcard-grants.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
    *) explicit_files+=("$1"); shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "check-workflow-gh-wildcard-grants.sh: python3 not found on PATH" >&2
  exit 2
fi

python3 - "$proj_dir" "${explicit_files[@]+"${explicit_files[@]}"}" <<'PY'
import os
import re
import sys

proj_dir = sys.argv[1]
explicit = sys.argv[2:]

# gh command groups with at least one verb that writes to GitHub
# (create/comment/edit/close/merge/delete/rerun/cancel/set/...).
PUBLISH_GROUPS = {
    "pr", "issue", "label", "release", "run", "repo", "gist", "workflow",
    "secret", "variable", "project", "cache", "ruleset", "discussion",
}

# `--allowedTools "..."` or `--allowedTools '...'`; the leading `--` keeps
# `--disallowedTools` out.
ALLOWLIST = re.compile(r"""(?<![A-Za-z-])--allowedTools\s+(?:"([^"]*)"|'([^']*)')""")
GH_ENTRY = re.compile(r"^Bash\(\s*gh(?:\s+([A-Za-z][A-Za-z-]*))?\s*(\*|:\*)?\s*\)$")


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


def wildcard_kind(entry):
    """Return a description when `entry` grants a whole gh group, else None."""
    m = GH_ENTRY.match(entry.strip())
    if not m:
        return None
    group, star = m.group(1), m.group(2)
    if group is None:
        return "whole gh CLI"
    if star and group in PUBLISH_GROUPS:
        return "gh %s group" % group
    return None


scanned = 0
allowlists = 0
entries_checked = 0
issues = []

for path in workflow_files():
    if not os.path.isfile(path):
        continue
    scanned += 1
    rel = os.path.relpath(path, proj_dir)
    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            if line.lstrip().startswith("#"):
                continue
            for m in ALLOWLIST.finditer(line):
                allowlists += 1
                value = m.group(1) if m.group(1) is not None else m.group(2)
                for raw in value.split(","):
                    entry = raw.strip()
                    if not entry:
                        continue
                    entries_checked += 1
                    kind = wildcard_kind(entry)
                    if kind:
                        issues.append(
                            "  - SEVERITY=ERROR TYPE=gh_group_wildcard FILE=%s LINE=%d "
                            "GRANT='%s' MSG=grants the %s, publishing verbs included - "
                            "grant only the verbs the prompt runs, as Bash(gh <group> <verb> *)"
                            % (rel, lineno, entry, kind)
                        )

if allowlists == 0:
    issues.insert(0,
        "  - SEVERITY=ERROR TYPE=nothing_scanned FILES=%d MSG=no --allowedTools "
        "list found; a scan that saw none cannot vouch for any" % scanned
    )

status = "ERROR" if issues else "OK"

print("=== WORKFLOW GH WILDCARD GRANTS ===")
print("WORKFLOWS_SCANNED=%d" % scanned)
print("ALLOWLISTS=%d" % allowlists)
print("ENTRIES_CHECKED=%d" % entries_checked)
print("STATUS=%s" % status)
if issues:
    first = re.search(r"TYPE=(\S+)\s+(.*)$", issues[0])
    reason = ("%s: %s" % first.groups()) if first else issues[0].strip()
    reason = " ".join(reason.split())[:180]
    if len(issues) > 1:
        reason += " (+%d more)" % (len(issues) - 1)
    print("REASON=%s" % reason)
print("ISSUE_COUNT=%d" % len(issues))
if issues:
    print("ISSUES:")
    for row in issues:
        print(row)
print("=== END WORKFLOW GH WILDCARD GRANTS ===")

if issues:
    sys.stderr.write(
        "\nFound %d gh grant problem(s). A Bash(<pattern>) grant is a PREFIX match,\n"
        "so Bash(gh pr *) also reaches gh pr create/merge/close/edit. Grant the\n"
        "verbs the prompt runs instead. See #2769.\n" % len(issues)
    )
    sys.exit(1)

print("All %d --allowedTools entr(y/ies) name gh verbs, not groups." % entries_checked)
PY
