#!/usr/bin/env bash
# Verify feedback-plugin's friction-learner still reads BOTH fast-loop labels.
#
# Background (issue #3346, item 4): `/feedback:session` files positive findings
# under `positive-feedback` ONLY; bugs and enhancements get `session-feedback`.
# friction-learner's Step 0 fetched only `--label session-feedback`, so 8 of 10
# open positive-feedback issues were read by nothing. The agent now fetches the
# positive set in a second query and treats it as stability markers.
#
# This is a SEMANTIC gate (.claude/rules/regression-testing.md). The agent file
# passes only when:
#   - Step 0 (the `### Step 0` section) carries, inside a code fence, a
#     `gh issue list` command with `--label session-feedback` and `--json`, and
#     a separate one with `--label positive-feedback` and `--json`. A combined
#     `--label a,b` does not count: gh matches only issues carrying BOTH labels,
#     which is exactly the set that was already being read.
#   - The positive-feedback fetch covers ANY state (`--state all`) within a
#     date window (a `created:` / `closed:` / `updated:` search qualifier).
#     Closure policy (#3346 decision 1, hybrid): the agent closes a positive
#     issue once its weekly PR cites it, so an open-only fetch would stop
#     seeing every praised behaviour after one run.
#   - Step 3 still applies the positive set: it names `positive-feedback`, the
#     phrase `stability marker`, and the `Preserves #` cross-link.
#   - Step 5 still lists the positive set in `## Fast-loop signal`.
#   - Step 6 still closes the cited issues: a fenced `gh issue close` command
#     with `--comment` (naming the PR that cited it).
#
# Usage:
#   bash scripts/check-friction-learner-fast-loop.sh [--project-dir <path>] [--file <agent.md>]
#
# Output: structured KEY=VALUE per .claude/rules/structured-script-output.md.
#
# Exit codes:
#   0 - all invariants hold
#   1 - one or more findings (STATUS=ERROR)
#   2 - usage error, or the agent file is missing

set -uo pipefail

proj_dir=""
agent_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-friction-learner-fast-loop.sh: --project-dir requires a directory" >&2
        exit 2
      fi
      proj_dir="$2"; shift 2 ;;
    --file)
      if [ -z "${2:-}" ]; then
        echo "check-friction-learner-fast-loop.sh: --file requires a path" >&2
        exit 2
      fi
      agent_file="$2"; shift 2 ;;
    *)
      echo "check-friction-learner-fast-loop.sh: unknown argument: $1" >&2
      echo "Usage: check-friction-learner-fast-loop.sh [--project-dir <path>] [--file <agent.md>]" >&2
      exit 2 ;;
  esac
done

if [ -z "$agent_file" ]; then
  if [ -z "$proj_dir" ]; then
    proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  agent_file="$proj_dir/feedback-plugin/agents/friction-learner.md"
fi

if [ ! -f "$agent_file" ]; then
  echo "check-friction-learner-fast-loop.sh: agent file not found: $agent_file" >&2
  exit 2
fi

# The parser prints one finding per line as `<type>|<msg>`; nothing on success.
findings_raw="$(python3 - "$agent_file" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read().replace("\r\n", "\n")
lines = text.split("\n")


def section(prefix):
    """Lines of the first `### <prefix>` section, up to the next ##/### heading
    outside a fence."""
    out, inside, fence = [], False, False
    for line in lines:
        if line.startswith("```"):
            fence = not fence
        if not fence and re.match(r"^#{2,3} ", line):
            if inside:
                break
            if line.startswith("### " + prefix):
                inside = True
                continue
        if inside:
            out.append(line)
    return out


def fenced_commands(sec, prefix="gh issue list"):
    """`<prefix>` commands inside fences, backslash continuations joined."""
    cmds, fence, buf = [], False, ""
    for line in sec:
        if line.startswith("```"):
            fence = not fence
            buf = ""
            continue
        if not fence:
            continue
        stripped = line.rstrip()
        if stripped.endswith("\\"):
            buf += stripped[:-1] + " "
            continue
        full = (buf + stripped).strip()
        buf = ""
        if full.startswith(prefix):
            cmds.append(full)
    return cmds


def fetches(cmds, label):
    pat = re.compile(r"--label[ =]" + re.escape(label) + r"(\s|$)")
    return [c for c in cmds if pat.search(c) and "--json" in c]


step0 = section("Step 0")
if not step0:
    print("missing_step0|no '### Step 0' section in the agent body")
    sys.exit(0)

cmds = fenced_commands(step0)
for label in ("session-feedback", "positive-feedback"):
    if not fetches(cmds, label):
        print(
            f"missing_{label.replace('-', '_')}_fetch|Step 0 has no fenced "
            f"'gh issue list --label {label} ... --json' command (a combined "
            f"--label a,b matches only issues carrying both labels; #3346)"
        )

positive = fetches(cmds, "positive-feedback")
if positive:
    if not any(re.search(r"--state[ =]all(\s|$)", c) for c in positive):
        print(
            "positive_fetch_not_any_state|the positive-feedback fetch lacks "
            "'--state all'; closed (already cited) issues stop acting as "
            "stability markers (#3346 decision 1)"
        )
    if not any(re.search(r"(created|closed|updated):[<>]?=?", c) for c in positive):
        print(
            "positive_fetch_no_window|the positive-feedback fetch has no "
            "created:/closed:/updated: date window; '--state all' alone reads "
            "every positive issue ever filed"
        )

step3 = "\n".join(section("Step 3"))
for needle, kind in (
    ("positive-feedback", "step3_no_positive_set"),
    ("stability marker", "step3_no_stability_marker"),
    ("Preserves #", "step3_no_preserves_link"),
):
    if needle not in step3:
        print(f"{kind}|Step 3 does not contain '{needle}'; the positive set is fetched but never applied")

step5 = "\n".join(section("Step 5"))
if "## Fast-loop signal" not in step5 or "positive-feedback" not in step5:
    print("step5_no_positive_listing|Step 5 does not list positive-feedback issues in '## Fast-loop signal'")

step6 = section("Step 6")
closes = [c for c in fenced_commands(step6, "gh issue close") if "--comment" in c]
if not closes or "positive-feedback" not in "\n".join(step6):
    print(
        "step6_no_close_after_cite|Step 6 has no fenced 'gh issue close ... "
        "--comment' for cited positive-feedback issues (closed = processed; "
        "#3346 decision 1)"
    )
PY
)"
parser_rc=$?
if [ "$parser_rc" -ne 0 ]; then
  echo "check-friction-learner-fast-loop.sh: parser failed (exit $parser_rc)" >&2
  exit 2
fi

issue_count=0
findings=""
first_reason=""
rel_file="${agent_file#"${proj_dir:+$proj_dir/}"}"
while IFS= read -r row; do
  [ -n "$row" ] || continue
  issue_count=$((issue_count + 1))
  row_type="${row%%|*}"
  row_msg="${row#*|}"
  [ -n "$first_reason" ] || first_reason="$row_type: $row_msg"
  findings="${findings}  - SEVERITY=ERROR TYPE=$row_type FILE=$rel_file MSG=$row_msg
"
done <<<"$findings_raw"

echo "=== FRICTION LEARNER FAST LOOP ==="
echo "AGENT_FILE=$rel_file"
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "STATUS=ERROR"
  reason="$first_reason"
  [ "$issue_count" -gt 1 ] && reason="${reason:0:170} (+$((issue_count - 1)) more)"
  echo "REASON=${reason:0:200}"
  echo "ISSUES:"
  printf '%s' "$findings"
else
  echo "STATUS=OK"
fi
echo "=== END FRICTION LEARNER FAST LOOP ==="

[ "$issue_count" -gt 0 ] && exit 1
exit 0
