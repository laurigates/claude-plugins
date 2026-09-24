#!/usr/bin/env bash
# Verify every Bash command a Claude workflow's PROMPT tells Claude to run is
# actually reachable through that same step's `--allowedTools` grants.
#
# Background (#2493). `claude-code-action`'s `Bash(<pattern>)` grants are PREFIX
# matches against the whole command string, and three revived audits learned
# that the expensive way on their first post-fix scheduled runs:
#
#   workflow-model-audit  run 34234073610 (2026-09-08) — FAILED with
#     "Claude reported a successful result after 42 turns, exceeding the
#      configured maximum of 40", carrying 4 permission denials.
#   golden-set-evaluation run 34981573686 (2026-09-15) — succeeded, but drew
#     59 of 60 turns while losing 6 calls to permission denials.
#
# Seven of those ten denied calls were commands that were ALREADY GRANTED and
# were denied anyway, because the call did not BEGIN with the granted prefix:
#
#   for id in A B; do gh run view $id --json jobs; done   # begins with `for`
#   gh issue list --label x ... ; echo "EXIT=$?"          # joined, not one cmd
#   RUN_DIR=$(bash prepare_run.sh gc-001)                 # begins with `RUN_DIR=`
#
# The remaining three were plain commands (`mkdir`, `cp`, `wc`, `grep`,
# `gh issue list`) that simply had no grant at all. Each denial still burns a
# turn, so the two failure classes compound into a max-turns overrun.
#
# WHAT THIS CHECKS (and what it deliberately does not). Only the bash commands
# written LITERALLY into a prompt's fenced ```bash blocks are checkable
# statically — commands Claude composes at runtime are not, and never will be.
# That is still worth gating: every one of those fenced snippets is an
# instruction the workflow author is telling Claude to run verbatim, so a
# snippet that cannot match a grant is a denial the author has pre-committed to.
# Two findings per snippet:
#
#   ungranted_command   the command's leading token matches no Bash grant
#   unprefixable_shape  the command is granted-in-principle but cannot prefix
#                       match: a for/while loop, a `;`/`&&`/`||` chain, or a
#                       leading `VAR=$(...)` assignment
#
# A step whose `claude_args` carries no `--allowedTools` is SKIPPED, not failed:
# with no declared boundary there is nothing to check against, and flagging it
# would report every unbounded workflow as broken.
#
# Usage:
#   bash scripts/check-workflow-tool-grants.sh [--project-dir <path>] [workflow.yml ...]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd).
#   workflow.yml …  Explicit files to check (pre-commit style); when present,
#                   discovery is skipped and only these files are checked.
#
# Exit codes:
#   0 - every fenced prompt command matches a grant and is prefix-matchable
#   1 - one or more commands are ungranted or unprefixable
#   2 - usage / environment error
#
# There is deliberately no `--strict`: the script already exits 1 on any
# finding, so accepting one would advertise a tightening mode that does not
# exist (#2057).

set -euo pipefail

usage() {
  echo "Usage: check-workflow-tool-grants.sh [--project-dir DIR] [workflow.yml ...]" >&2
}

proj_dir=""
explicit_files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-workflow-tool-grants.sh: --project-dir requires a directory" >&2
        usage
        exit 2
      fi
      proj_dir="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "check-workflow-tool-grants.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
    *) explicit_files+=("$1"); shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "check-workflow-tool-grants.sh: python3 not found on PATH" >&2
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
        "check-workflow-tool-grants.sh: PyYAML is required to parse workflow YAML\n"
    )
    sys.exit(2)

CLAUDE_ACTION = "anthropics/claude-code-action"

# Line shapes that are a CONTINUATION fragment of the previous command rather
# than the start of a new one (`)"` closing a heredoc-bearing substitution, a
# bare flag left on its own line, a pipe head).
FRAGMENT_START = re.compile(r"^[)\]}|&\"'`,-]")

SHAPE_KEYWORD = re.compile(r"^(for|while|until|if|case|select|function)\b")
LEADING_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def workflow_files():
    if explicit:
        return explicit
    wf_dir = os.path.join(proj_dir, ".github", "workflows")
    if not os.path.isdir(wf_dir):
        return []
    out = []
    for name in sorted(os.listdir(wf_dir)):
        if name.endswith((".yml", ".yaml")):
            out.append(os.path.join(wf_dir, name))
    return out


def claude_steps(doc):
    """Yield (job_id, step_index, with_mapping) for every claude-code-action step."""
    if not isinstance(doc, dict):
        return
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict):
        return
    for job_id, job in jobs.items():
        if not isinstance(job, dict):
            continue
        steps = job.get("steps")
        if not isinstance(steps, list):
            continue
        for idx, step in enumerate(steps):
            if not isinstance(step, dict):
                continue
            uses = step.get("uses")
            if not isinstance(uses, str) or CLAUDE_ACTION not in uses:
                continue
            with_map = step.get("with")
            if isinstance(with_map, dict):
                yield job_id, idx, with_map


def extract_allowed_tools(claude_args):
    """Pull the --allowedTools value out of a claude_args string, or None."""
    if not isinstance(claude_args, str):
        return None
    m = re.search(r'--allowedTools\s+"([^"]*)"', claude_args)
    if m:
        return m.group(1)
    m = re.search(r"--allowedTools\s+'([^']*)'", claude_args)
    if m:
        return m.group(1)
    m = re.search(r"--allowedTools\s+(\S+)", claude_args)
    if m:
        return m.group(1)
    return None


def bash_grants(allowed):
    """Return (patterns, grants_all). A bare `Bash` grant permits everything."""
    patterns = []
    grants_all = False
    for raw in allowed.split(","):
        entry = raw.strip()
        if not entry:
            continue
        if entry == "Bash":
            grants_all = True
            continue
        m = re.fullmatch(r"Bash\((.*)\)", entry)
        if m:
            pattern = m.group(1).strip()
            if pattern in ("*", ":*"):
                grants_all = True
            else:
                patterns.append(pattern)
    return patterns, grants_all


def bash_fences(prompt):
    """Every ```bash / ```sh / ```shell fenced block body in the prompt."""
    if not isinstance(prompt, str):
        return []
    return re.findall(r"^[ \t]*```(?:bash|sh|shell)[ \t]*\n(.*?)^[ \t]*```",
                      prompt, re.S | re.M)


def logical_commands(fence):
    """Split a fence body into the logical commands it actually issues.

    Skips comment lines, heredoc bodies, blank lines and continuation
    fragments, and joins backslash continuations, so `gh issue create \\ ...
    --body "$(cat <<'EOF' ... EOF )"` reads as ONE command beginning with
    `gh issue create`.
    """
    commands = []
    pending_heredocs = []
    continuing = False
    for raw in fence.splitlines():
        line = raw.rstrip("\n")
        stripped = line.strip()

        if pending_heredocs:
            if stripped == pending_heredocs[0]:
                pending_heredocs.pop(0)
            continue

        if continuing:
            for _q, word in HEREDOC.findall(line):
                pending_heredocs.append(word)
            continuing = stripped.endswith("\\")
            continue

        if not stripped or stripped.startswith("#"):
            continue
        if FRAGMENT_START.match(stripped):
            continue

        commands.append(stripped)
        for _q, word in HEREDOC.findall(line):
            pending_heredocs.append(word)
        continuing = stripped.endswith("\\")
    return commands


def strip_trailing_comment(cmd):
    """Drop a trailing ` # comment`, respecting quotes."""
    out = []
    in_single = in_double = False
    prev = ""
    for ch in cmd:
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "#" and not in_single and not in_double and prev in (" ", "\t"):
            break
        out.append(ch)
        prev = ch
    return "".join(out).strip()


def has_top_level_chain(cmd):
    """True when `;`, `&&` or `||` joins two commands outside quotes/substitutions."""
    in_single = in_double = False
    depth = 0
    i = 0
    n = len(cmd)
    while i < n:
        ch = cmd[i]
        if ch == "\\" and not in_single:
            i += 2
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif not in_single and not in_double:
            if cmd.startswith("$(", i) or ch == "(":
                depth += 1
                i += 2 if cmd.startswith("$(", i) else 1
                continue
            if ch == ")":
                depth = max(0, depth - 1)
            elif depth == 0:
                if ch == ";":
                    return True
                if cmd.startswith("&&", i) or cmd.startswith("||", i):
                    return True
        i += 1
    return False


def leading_token(cmd):
    parts = cmd.split()
    return parts[0] if parts else ""


def matches_grant(cmd, patterns):
    normalized = " ".join(cmd.split())
    for pattern in patterns:
        if pattern.endswith("*"):
            prefix = " ".join(pattern[:-1].split())
            if not prefix:
                return True
            if normalized == prefix or normalized.startswith(prefix + " "):
                return True
        else:
            if normalized == " ".join(pattern.split()):
                return True
    return False


scanned = 0
claude_step_count = 0
steps_with_allowlist = 0
skipped_no_allowlist = 0
calls_checked = 0
issues = []

for path in workflow_files():
    if not os.path.isfile(path):
        continue
    scanned += 1
    try:
        doc = yaml.safe_load(open(path, encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001 - report, do not crash the sweep
        issues.append(
            "  - SEVERITY=ERROR TYPE=unparseable_workflow FILE=%s MSG=%s"
            % (os.path.relpath(path, proj_dir), str(exc).splitlines()[0])
        )
        continue

    rel = os.path.relpath(path, proj_dir)
    for job_id, idx, with_map in claude_steps(doc):
        claude_step_count += 1
        allowed = extract_allowed_tools(with_map.get("claude_args"))
        if allowed is None:
            skipped_no_allowlist += 1
            continue
        steps_with_allowlist += 1
        patterns, grants_all = bash_grants(allowed)

        for fence in bash_fences(with_map.get("prompt")):
            for cmd in logical_commands(fence):
                cmd = strip_trailing_comment(cmd)
                if not cmd:
                    continue
                calls_checked += 1
                where = "FILE=%s JOB=%s STEP=%d" % (rel, job_id, idx)
                short = cmd if len(cmd) <= 90 else cmd[:87] + "..."

                if SHAPE_KEYWORD.match(cmd):
                    issues.append(
                        "  - SEVERITY=ERROR TYPE=unprefixable_shape SHAPE=loop %s "
                        "CMD='%s' MSG=a Bash grant is a PREFIX match; this call "
                        "begins with a loop keyword so it matches no grant - issue "
                        "one call per iteration" % (where, short)
                    )
                    continue
                if LEADING_ASSIGNMENT.match(cmd):
                    issues.append(
                        "  - SEVERITY=ERROR TYPE=unprefixable_shape SHAPE=assignment %s "
                        "CMD='%s' MSG=a Bash grant is a PREFIX match; this call begins "
                        "with a variable assignment so it matches no grant - run the "
                        "inner command as its own call" % (where, short)
                    )
                    continue
                if has_top_level_chain(cmd):
                    issues.append(
                        "  - SEVERITY=ERROR TYPE=unprefixable_shape SHAPE=chain %s "
                        "CMD='%s' MSG=a Bash grant is a PREFIX match; ';'/'&&'/'||' "
                        "joins two commands into one unmatchable string - split it "
                        "into separate calls" % (where, short)
                    )
                    continue
                if grants_all:
                    continue
                if not matches_grant(cmd, patterns):
                    issues.append(
                        "  - SEVERITY=ERROR TYPE=ungranted_command %s TOKEN=%s "
                        "CMD='%s' MSG=no Bash(...) grant in this step's --allowedTools "
                        "matches this command - add one or drop the snippet"
                        % (where, leading_token(cmd), short)
                    )

status = "ERROR" if issues else "OK"

print("=== WORKFLOW TOOL GRANTS ===")
print("WORKFLOWS_SCANNED=%d" % scanned)
print("CLAUDE_STEPS=%d" % claude_step_count)
print("STEPS_WITH_ALLOWLIST=%d" % steps_with_allowlist)
print("SKIPPED_NO_ALLOWLIST=%d" % skipped_no_allowlist)
print("BASH_CALLS_CHECKED=%d" % calls_checked)
print("STATUS=%s" % status)
if issues:
    # The first finding, as "<TYPE>: <rest of the row>", is the cause a rollup
    # reads (#2691); every finding is listed under ISSUES: below.
    first = re.search(r"TYPE=(\S+)\s+(.*)$", issues[0])
    reason = ("%s: %s" % first.groups()) if first else issues[0].strip()
    reason = " ".join(reason.split())[:180]
    if len(issues) > 1:
        reason += " (+%d more)" % (len(issues) - 1)
    print("REASON=%s" % reason)
print("ISSUE_COUNT=%d" % len(issues))
if issues:
    print("ISSUES:")
    for line in issues:
        print(line)
print("=== END WORKFLOW TOOL GRANTS ===")

if issues:
    sys.stderr.write(
        "\nFound %d prompt command(s) that cannot reach a --allowedTools grant.\n"
        "`Bash(<pattern>)` is a PREFIX match on the whole command string: the call\n"
        "must BEGIN with a granted word, so no for/while loops, no ';'/'&&' chains\n"
        "and no leading VAR=$(...) assignment. See #2493.\n" % len(issues)
    )
    sys.exit(1)

print("All %d fenced prompt command(s) match a grant. ✅" % calls_checked)
PY
