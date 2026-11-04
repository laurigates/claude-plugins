#!/usr/bin/env bash
# check-skill-portability.sh -- shipped skills, agents and hooks stay
# environment-neutral: no maintainer repositories, hosts or checkout paths
# written as things to act on (#3308).
#
# WHY
# The plugins are public. A skill that says "open a PR against <maintainer>/gitops"
# or "cd ~/repos/<x>" is read by an agent in someone else's session as an
# instruction, and that agent then tries to reach a repository or a layout that
# does not exist in its user's setup. The authoring rule is
# .claude/rules/skill-portability.md; this script is its mechanical half.
#
# WHAT IT SCANS
# Tracked files (`git ls-files`) under `*-plugin/skills/**`, `*-plugin/agents/**`
# and `*-plugin/hooks/**`, read from the working tree. Untracked files and
# everything outside those three trees are out of scope. Binary files (any NUL
# byte) are skipped.
#
# CONFIG (scripts/skill-portability.conf, override with --config)
#   [identifiers]  one Python regex per line; every match is a hit. A fork or
#                  another maintainer replaces this list with their own.
#   [allow]        `path<TAB>matched text<TAB>reason` -- accepted lines
#                  (provenance, a published default, a test fixture). Every
#                  occurrence of that text in that file passes. An entry that
#                  matches nothing is ERROR (stale_allowlist).
#   Lines starting with `#` and blank lines are ignored.
#
# BASELINE (scripts/skill-portability-baseline.txt, override with --baseline)
#   `path<TAB>matched text<TAB>count` -- hits that predate the rule and wait
#   for the per-plugin sweep. They are reported as WARN and exit 0. A key ABOVE
#   its count, or not in the baseline, is ERROR (new_hit). A key BELOW its count,
#   or whose file is gone, is also ERROR (stale_baseline), so the baseline only
#   tightens. `--update-baseline` lowers entries and never raises one; when the
#   baseline file does not exist it seeds it from the current hits, once.
#
# Usage:
#   bash scripts/check-skill-portability.sh [--project-dir DIR] [--config FILE]
#       [--baseline FILE] [--update-baseline] [--verbose]
#   --verbose prints a HIT= line for every hit, not only the ones that fail.
#
# Exit: 0 = OK or WARN (baseline hits only), 1 = ERROR, 2 = usage error
#       (unknown argument, missing config, invalid regex, no identifiers,
#       not a git work tree).
set -uo pipefail

# An inherited GIT_DIR (pre-commit sets it) overrides `git -C` (#1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
proj_dir="$(cd "$script_dir/.." && pwd)"
config=""
baseline=""
update_baseline=0
verbose=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$(cd "$2" && pwd)" || exit 2; shift 2 ;;
    --config) config="$2"; shift 2 ;;
    --baseline) baseline="$2"; shift 2 ;;
    --update-baseline) update_baseline=1; shift ;;
    --verbose) verbose=1; shift ;;
    *) echo "check-skill-portability.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$config" ] || config="$proj_dir/scripts/skill-portability.conf"
[ -n "$baseline" ] || baseline="$proj_dir/scripts/skill-portability-baseline.txt"

if [ ! -f "$config" ]; then
  echo "check-skill-portability.sh: config not found: $config" >&2
  exit 2
fi

# `read -d ''` rather than a heredoc-fed `python3 -`: stdin stays free, and bash
# 3.2 misparses a heredoc inside `$(...)` with unbalanced parentheses.
IFS= read -r -d '' PY_SRC <<'PY' || true
import os
import re
import subprocess
import sys

proj_dir, config, baseline, update, verbose = sys.argv[1:6]
update = update == "1"
verbose = verbose == "1"

SCOPE = ["*-plugin/skills/**", "*-plugin/agents/**", "*-plugin/hooks/**"]


def usage_error(msg):
    print("check-skill-portability.sh: %s" % msg, file=sys.stderr)
    sys.exit(2)


def one_line(text):
    return " ".join(str(text).split())


# --- config -----------------------------------------------------------------
patterns = []
allow = {}
section = None
with open(config, encoding="utf-8") as fh:
    for lineno, raw in enumerate(fh, 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.strip() in ("[identifiers]", "[allow]"):
            section = line.strip()
            continue
        if section == "[identifiers]":
            try:
                patterns.append(re.compile(line.strip()))
            except re.error as exc:
                usage_error("%s:%d: invalid identifier regex %r: %s"
                            % (config, lineno, line.strip(), exc))
        elif section == "[allow]":
            parts = line.split("\t")
            if len(parts) < 3 or not parts[2].strip():
                usage_error("%s:%d: allow entry needs path<TAB>matched text<TAB>reason"
                            % (config, lineno))
            allow[(parts[0].strip(), parts[1])] = parts[2].strip()
        else:
            usage_error("%s:%d: line outside [identifiers] / [allow]" % (config, lineno))
if not patterns:
    usage_error("%s lists no identifiers" % config)

# --- baseline ---------------------------------------------------------------
base = {}
seeding = update and not os.path.isfile(baseline)
if os.path.isfile(baseline):
    with open(baseline, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 3 or not parts[2].strip().isdigit():
                usage_error("%s: malformed baseline line %r (want path<TAB>match<TAB>count)"
                            % (baseline, line))
            base[(parts[0], parts[1])] = int(parts[2])

# --- discovery --------------------------------------------------------------
proc = subprocess.run(["git", "-C", proj_dir, "ls-files", "-z", "--"] + SCOPE,
                      capture_output=True)
if proc.returncode != 0:
    usage_error("git ls-files failed in %s: %s"
                % (proj_dir, proc.stderr.decode("utf-8", "replace").strip()))
files = sorted(p for p in proc.stdout.decode("utf-8", "replace").split("\0") if p)

# --- scan -------------------------------------------------------------------
hits = {}       # (path, match) -> [(line_no, text)]
scanned = set()
skipped_binary = 0
for rel in files:
    full = os.path.join(proj_dir, rel)
    if not os.path.isfile(full):
        continue
    with open(full, "rb") as fh:
        data = fh.read()
    if b"\0" in data:
        skipped_binary += 1
        continue
    scanned.add(rel)
    for idx, line in enumerate(data.decode("utf-8", "replace").split("\n"), 1):
        for rx in patterns:
            for m in rx.finditer(line):
                hits.setdefault((rel, m.group(0)), []).append((idx, one_line(line)))

counts = {k: len(v) for k, v in hits.items()}

# --- optional baseline update ----------------------------------------------
if update and scanned:
    candidates = {k: n for k, n in counts.items() if k not in allow}
    if seeding:
        lowered = candidates
    else:
        lowered = {k: min(candidates.get(k, 0), n) for k, n in base.items()}
    base = {k: n for k, n in lowered.items() if n > 0}
    with open(baseline, "w", encoding="utf-8") as fh:
        fh.write("# Skill-portability baseline -- see scripts/check-skill-portability.sh.\n"
                 "# path<TAB>matched text<TAB>count: hits that predate the rule and wait\n"
                 "# for the per-plugin sweep (#3308). Counts may only go down; rewrite with\n"
                 "# --update-baseline, which never raises an entry.\n")
        for (path, match), n in sorted(base.items()):
            fh.write("%s\t%s\t%d\n" % (path, match, n))

# --- judge ------------------------------------------------------------------
errors = []
warns = []
hit_rows = []
allowed_hits = baseline_hits = new_hits = 0

for key in sorted(counts):
    path, match = key
    have = counts[key]
    if key in allow:
        allowed_hits += have
        show = verbose
    else:
        held = base.get(key, 0)
        baseline_hits += min(have, held)
        if have > held:
            new_hits += have - held
            first = hits[key][0][0]
            errors.append(("new_hit",
                           "%s:%d names %r (%d hit(s), baseline %d); take the value from "
                           "context, or allowlist the line with a reason in the config"
                           % (path, first, match, have, held)))
            show = True
        else:
            warns.append(("baseline_hit",
                          "%s names %r %d time(s), held by the baseline until the sweep "
                          "neutralizes or allowlists it" % (path, match, have)))
            show = verbose
    if show:
        for line_no, text in hits[key]:
            hit_rows.append("HIT=%s:%d: [%s] %s" % (path, line_no, match, text[:160]))

for key, held in sorted(base.items()):
    path, match = key
    have = counts.get(key, 0) if key not in allow else 0
    if path not in scanned:
        errors.append(("stale_baseline",
                       "%s is in the baseline but was not scanned; delete the entry "
                       "(--update-baseline)" % path))
    elif have < held:
        errors.append(("stale_baseline",
                       "%s names %r %d time(s), below its baseline %d; lower it so the "
                       "ratchet holds (--update-baseline)" % (path, match, have, held)))

for key, reason in sorted(allow.items()):
    if counts.get(key, 0) == 0:
        errors.append(("stale_allowlist",
                       "allow entry %s %r matches nothing; delete it from the config"
                       % key))

if not scanned:
    errors.append(("nothing_scanned",
                   "no tracked files under %s in %s; the discovery is broken, not the "
                   "tree clean" % (" ".join(SCOPE), proj_dir)))

issues = [("ERROR",) + e for e in errors] + [("WARN",) + w for w in warns]
if errors:
    item_status = "ERROR"
elif warns:
    item_status = "WARN"
else:
    item_status = "OK"

print("=== SKILL PORTABILITY ===")
print("FILES_SCANNED=%d" % len(scanned))
print("FILES_SKIPPED_BINARY=%d" % skipped_binary)
print("SCANNED_EMPTY=%s" % ("true" if not scanned else "false"))
print("IDENTIFIER_PATTERNS=%d" % len(patterns))
print("ALLOW_ENTRIES=%d" % len(allow))
print("BASELINE_ENTRIES=%d" % len(base))
print("BASELINE_TOTAL=%d" % sum(base.values()))
print("HITS_TOTAL=%d" % sum(counts.values()))
print("ALLOWED_HITS=%d" % allowed_hits)
print("BASELINE_HITS=%d" % baseline_hits)
print("NEW_HITS=%d" % new_hits)
for row in hit_rows:
    print(row)
print("STATUS=%s" % item_status)
if issues:
    first = next(i for i in issues if i[0] == item_status)
    reason = one_line("%s: %s" % (first[1], first[2]))[:180]
    if len(issues) > 1:
        reason += " (+%d more)" % (len(issues) - 1)
    print("REASON=%s" % reason)
print("ISSUE_COUNT=%d" % len(issues))
if issues:
    print("ISSUES:")
    for sev, itype, msg in issues:
        print("  - SEVERITY=%s TYPE=%s MSG=%s" % (sev, itype, one_line(msg)))
print("=== END SKILL PORTABILITY ===")
sys.exit(1 if errors else 0)
PY

python3 -c "$PY_SRC" "$proj_dir" "$config" "$baseline" "$update_baseline" "$verbose"
