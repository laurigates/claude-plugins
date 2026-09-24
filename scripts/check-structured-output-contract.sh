#!/usr/bin/env bash
# check-structured-output-contract.sh — class guard for the STATUS= contract in
# .claude/rules/structured-script-output.md.
#
# THE CONTRACT
# An orchestrating skill rolls many diagnostic scripts up from their summary
# lines alone, so those lines have to carry the verdict AND its cause:
#   STATUS=OK|WARN|ERROR    the canonical three; a rollup keyed on them reads
#                           STATUS=FAIL or STATUS=PASS as "unknown"
#   ISSUE_COUNT=<int>       always, and equal to the rows under ISSUES: when
#                           that block is present
#   REASON=<one line>       on WARN/ERROR only, <= 200 characters, never on OK
#
# WHY A GUARD (#2691)
# Before REASON= existed, STATUS=ERROR plus ISSUE_COUNT=3 said how many things
# failed and never which, so the caller re-ran the script unfiltered or read its
# source to find out. The same sweep found four scripts emitting STATUS=FAIL or
# STATUS=PASS, and git-triage.sh printing ISSUE_COUNT=0 beneath ten populated
# issue rows (#2714) -- a count a rollup would trust.
#
# TWO MODES
#   Static sweep (default): every scripts/check-*.sh that emits STATUS= must
#     - emit only OK / WARN / ERROR, whether as a literal or through a variable
#       whose literal assignments are traced in the same file
#     - emit ISSUE_COUNT=
#     - emit REASON=, unless listed in scripts/structured-output-reason-pending.txt
#   The pending list is a ratchet: an entry that now emits REASON=, or is no
#   longer a STATUS= emitter, is itself an error, so the list only shrinks.
#   Static analysis proves REASON= is emitted somewhere; it cannot prove the
#   line sits on the non-OK path. That half is --validate's job.
#
#   --validate [FILE|-]: check one captured output block against the runtime
#   contract (single STATUS= line, canonical value, integer ISSUE_COUNT= equal
#   to the ISSUES: rows, REASON= present and bounded iff STATUS is not OK). The
#   test twins of the migrated scripts pipe their failing and passing fixture
#   output through it.
#
# Usage:
#   bash scripts/check-structured-output-contract.sh [--strict] [--project-dir DIR]
#   bash scripts/check-structured-output-contract.sh --validate [FILE|-]
#
# Output: structured KEY=VALUE per .claude/rules/structured-script-output.md.
#
# Exit codes:
#   0 - contract holds (sweep without --strict always exits 0)
#   1 - violation found (sweep with --strict, or any --validate violation)
#   2 - usage / environment error

set -uo pipefail

STRICT=0
MODE=sweep
ROOT_DIR=""
TARGET=""

usage() {
  echo "Usage: check-structured-output-contract.sh [--strict] [--project-dir DIR]" >&2
  echo "       check-structured-output-contract.sh --validate [FILE|-]" >&2
}

# An unknown argument is REJECTED, never swallowed (#2057): a silently ignored
# flag turns a gate into a no-op that still exits 0.
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-structured-output-contract.sh: --project-dir requires a directory" >&2
        exit 2
      fi
      ROOT_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    --validate)
      MODE=validate
      if [ -n "${2:-}" ] && { [ "$2" = "-" ] || [ "${2#-}" = "$2" ]; }; then
        TARGET="$2"; shift
      fi
      shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "check-structured-output-contract.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "check-structured-output-contract.sh: python3 not found on PATH" >&2
  exit 2
fi

# `python3 -c` rather than `python3 - <<PY`: --validate reads the target block
# from stdin, which a heredoc-fed interpreter would have consumed. `read -d ''`
# rather than `$(cat <<PY)`: bash 3.2 misparses a heredoc inside `$(...)` whose
# body holds unbalanced parentheses, and the regexes below are full of them.
IFS= read -r -d '' PY_SRC <<'PY' || true
import os
import re
import sys

CANON = ("OK", "WARN", "ERROR")
REASON_MAX = 200
CAUSE_MAX = 180

# An emission is STATUS= inside the string an echo / printf / print( writes.
# `[^|#\n]*?` stops at a pipe, so `printf '%s' "$out" | grep '^STATUS='` (a
# script PARSING another script's output) is not mistaken for an emission.
EMIT = r"(?:\becho\b|\bprintf\b|\bprint\()[^|#\n]*?(?<![A-Za-z0-9_])"
STATUS_EMIT = re.compile(EMIT + r"STATUS=(.*)$")
REASON_EMIT = re.compile(EMIT + r"REASON=")
COUNT_EMIT = re.compile(EMIT + r"ISSUE_COUNT=")

WORD = r"[A-Z][A-Z_]+"
LEAD_LITERAL = re.compile(r"^[\"']?(" + WORD + r")\b")
ECHO_WORD = re.compile(r"\becho\s+[\"']?(" + WORD + r")\b")
QUOTED_WORD = re.compile(r"[\"'](" + WORD + r")[\"']")
SH_VAR = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)")
PY_FVAR = re.compile(r"\{([a-z_][a-z0-9_]*)\}")
PY_PCT_VAR = re.compile(r"[\"']\s*%\s*\(?\s*([a-z_][a-z0-9_]*)\b")


def one_line(text):
    return " ".join(str(text).split())


def reason_of(issues):
    cause = one_line("%s: %s" % issues[0])[:CAUSE_MAX]
    if len(issues) > 1:
        cause += " (+%d more)" % (len(issues) - 1)
    return cause


def words(fragment):
    found = set()
    lead = LEAD_LITERAL.match(fragment)
    if lead:
        found.add(lead.group(1))
    found.update(ECHO_WORD.findall(fragment))
    found.update(QUOTED_WORD.findall(fragment))
    return found


def status_values(rest, code_lines):
    values = words(rest)
    names = set(SH_VAR.findall(rest)) | set(PY_FVAR.findall(rest)) | set(PY_PCT_VAR.findall(rest))
    for name in names:
        assign = re.compile(r"(?<![A-Za-z0-9_.${])" + re.escape(name) + r"\s*=(?!=)\s*(.*)$")
        for line in code_lines:
            match = assign.search(line)
            if match:
                values |= words(match.group(1))
    return values


def emit(title, keys, issues):
    status = "ERROR" if issues else "OK"
    print("=== %s ===" % title)
    for key, value in keys:
        print("%s=%s" % (key, value))
    print("STATUS=%s" % status)
    if issues:
        print("REASON=%s" % reason_of(issues))
    print("ISSUE_COUNT=%d" % len(issues))
    if issues:
        print("ISSUES:")
        for itype, msg in issues:
            print("  - SEVERITY=ERROR TYPE=%s MSG=%s" % (itype, one_line(msg)))
    print("=== END %s ===" % title)
    return status


def sweep(root, strict):
    os.chdir(root)
    pending_rel = "scripts/structured-output-reason-pending.txt"
    pending = []
    if os.path.isfile(pending_rel):
        with open(pending_rel, encoding="utf-8") as fh:
            for raw in fh:
                entry = raw.split("#", 1)[0].strip()
                if entry:
                    pending.append(entry)

    # Relative glob from inside the root (#2219): an absolute base under
    # .claude/worktrees/ cannot collapse the scan to nothing.
    scripts_dir = "scripts"
    candidates = []
    if os.path.isdir(scripts_dir):
        candidates = sorted(
            os.path.join(scripts_dir, name)
            for name in os.listdir(scripts_dir)
            if name.startswith("check-") and name.endswith(".sh")
        )

    issues = []
    emitters = {}
    for rel in candidates:
        try:
            with open(rel, encoding="utf-8") as fh:
                text = fh.read()
        except OSError as exc:
            issues.append(("unreadable", "%s: %s" % (rel, exc)))
            continue
        code = [ln for ln in text.splitlines() if not ln.lstrip().startswith("#")]
        rests = [m.group(1) for m in (STATUS_EMIT.search(ln) for ln in code) if m]
        if not rests:
            continue
        values = set()
        for rest in rests:
            values |= status_values(rest, code)
        emitters[rel] = {
            "bad": sorted(v for v in values if v not in CANON),
            "reason": any(REASON_EMIT.search(ln) for ln in code),
            "count": any(COUNT_EMIT.search(ln) for ln in code),
        }

    if not candidates:
        issues.append(("nothing_scanned",
                       "no scripts/check-*.sh under %s; the sweep checked nothing" % root))

    for rel, info in emitters.items():
        for value in info["bad"]:
            issues.append(("noncanonical_status",
                           "%s emits STATUS=%s; use OK, WARN or ERROR" % (rel, value)))
        if not info["count"]:
            issues.append(("missing_issue_count", "%s emits STATUS= but never ISSUE_COUNT=" % rel))
        if not info["reason"] and rel not in pending:
            issues.append(("missing_reason",
                           "%s emits STATUS= but never REASON= on its non-OK path" % rel))

    for rel in pending:
        if rel not in emitters:
            issues.append(("stale_pending",
                           "%s is in %s but is not a STATUS= emitter; delete the entry" % (rel, pending_rel)))
        elif emitters[rel]["reason"]:
            issues.append(("stale_pending",
                           "%s now emits REASON=; delete it from %s" % (rel, pending_rel)))

    keys = [
        ("SCRIPTS_SCANNED", len(candidates)),
        ("SCANNED_EMPTY", "true" if not candidates else "false"),
        ("STATUS_EMITTERS", len(emitters)),
        ("REASON_EMITTERS", sum(1 for info in emitters.values() if info["reason"])),
        ("REASON_PENDING", len(pending)),
    ]
    status = emit("STRUCTURED OUTPUT CONTRACT", keys, issues)
    return 1 if (strict and status != "OK") else 0


def validate(text, target):
    lines = text.splitlines()
    issues = []

    statuses = [ln[len("STATUS="):] for ln in lines if ln.startswith("STATUS=")]
    counts = [ln[len("ISSUE_COUNT="):] for ln in lines if ln.startswith("ISSUE_COUNT=")]
    reasons = [ln[len("REASON="):] for ln in lines if ln.startswith("REASON=")]

    rows = None
    for idx, line in enumerate(lines):
        if line.rstrip() == "ISSUES:":
            rows = rows or 0
            nxt = idx + 1
            while nxt < len(lines) and re.match(r"^\s+- ", lines[nxt]):
                rows += 1
                nxt += 1

    status = statuses[0] if len(statuses) == 1 else None
    if len(statuses) != 1:
        issues.append(("status_line_count",
                       "expected exactly one STATUS= line, found %d" % len(statuses)))
    elif status not in CANON:
        issues.append(("noncanonical_status", "STATUS=%s; use OK, WARN or ERROR" % status))

    count = None
    if len(counts) != 1:
        issues.append(("issue_count_line_count",
                       "expected exactly one ISSUE_COUNT= line, found %d" % len(counts)))
    elif not re.fullmatch(r"\d+", counts[0]):
        issues.append(("bad_issue_count", "ISSUE_COUNT=%s is not a non-negative integer" % counts[0]))
    else:
        count = int(counts[0])

    if count is not None and rows is not None and rows != count:
        issues.append(("issue_count_mismatch",
                       "ISSUE_COUNT=%d but %d row(s) under ISSUES:" % (count, rows)))

    if status is not None:
        if status == "OK" and reasons:
            issues.append(("reason_on_ok", "STATUS=OK must not carry REASON="))
        elif status != "OK" and not reasons:
            issues.append(("missing_reason", "STATUS=%s carries no REASON=" % status))
    if len(reasons) > 1:
        issues.append(("reason_line_count", "expected at most one REASON= line, found %d" % len(reasons)))
    for reason in reasons[:1]:
        if not reason.strip():
            issues.append(("empty_reason", "REASON= is empty"))
        elif len(reason) > REASON_MAX:
            issues.append(("reason_too_long",
                           "REASON= is %d characters; the bound is %d" % (len(reason), REASON_MAX)))

    keys = [
        ("TARGET", target),
        ("TARGET_STATUS", status if status is not None else "none"),
        ("TARGET_ISSUE_COUNT", counts[0] if len(counts) == 1 else "none"),
        ("TARGET_ISSUE_ROWS", rows if rows is not None else "none"),
        ("TARGET_REASON", "present" if reasons else "absent"),
    ]
    result = emit("STRUCTURED OUTPUT VALIDATION", keys, issues)
    return 0 if result == "OK" else 1


mode = sys.argv[1]
if mode == "sweep":
    sys.exit(sweep(sys.argv[2], sys.argv[3] == "1"))
target = sys.argv[2]
if target in ("", "-"):
    sys.exit(validate(sys.stdin.read(), "stdin"))
try:
    with open(target, encoding="utf-8") as fh:
        body = fh.read()
except OSError as exc:
    print("check-structured-output-contract.sh: cannot read %s: %s" % (target, exc), file=sys.stderr)
    sys.exit(2)
sys.exit(validate(body, target))
PY

if [ "$MODE" = validate ]; then
  python3 -c "$PY_SRC" validate "$TARGET"
  exit $?
fi

if [ -z "$ROOT_DIR" ]; then
  ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
python3 -c "$PY_SRC" sweep "$ROOT_DIR" "$STRICT"
exit $?
