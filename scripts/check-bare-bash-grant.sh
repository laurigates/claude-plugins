#!/usr/bin/env bash
# check-bare-bash-grant.sh -- ratchet lint for full-shell grants in a skill's
# `allowed-tools` (#3464).
#
# WHY
# A skill's `allowed-tools` PRE-APPROVES the listed tools for the turn that
# invokes it. A bare `Bash` there pre-approves every shell command, and an
# interpreter wildcard such as `Bash(bash *)` or `Bash(python3 *)` admits
# `bash -c '<anything>'` / `python3 -c '<anything>'` by prefix match, which is
# nearly the same grant. The house standard is narrow `Bash(<command> *)`
# patterns (decided on #2839; the grant model is
# .claude/rules/agentic-permissions.md). This lint holds the existing offenders
# in a baseline while #3464 migrates them, and fails on any new one.
#
# FINDINGS
#   bare_bash          a bare `Bash` token
#   broad_shell_grant  Bash(*), or Bash(<interp> *) / Bash(<interp>:*) for
#                      interp in bash sh zsh python python3 node, however
#                      spelled: no space before * (bash*), extra spaces, a
#                      path or env prefix (/bin/bash *, env bash *), or an
#                      inline-code flag (bash -c *, node -e *)
# An anchored bundled-script grant, Bash(bash ${CLAUDE_SKILL_DIR}/scripts/x.sh *),
# is narrow and never a finding.
#
# WHAT IT SCANS
# <plugin>/skills/**/SKILL.md under every top-level `*-plugin` directory, the
# frontmatter `allowed-tools` field in the one-line form (plain, quoted, or a
# [flow, list]), either continued over indented lines, and the YAML block-list
# form. Discovery runs from INSIDE the
# project dir against relative paths (#2219), pruning `.claude/worktrees/` and
# `dist/` copies (#1492, #2214).
#
# BASELINE (scripts/bare-bash-grant-baseline.txt, override with --baseline)
#   `path<TAB>type<TAB>token`, one line per held grant. A hit held by the
#   baseline is WARN (exit 0). A hit not in it is ERROR new_hit. A baseline
#   entry with no current hit is ERROR stale_baseline, lowered with
#   --update-baseline, which drops entries and never adds one; when the baseline
#   file does not exist it seeds it from the current hits, once.
#
# MODES FOR THE MIGRATION
#   --plugin <dir>  (repeatable) scan only those plugins and IGNORE the
#                   baseline: every hit is an ERROR row and the exit is 1 if
#                   any. An editor gates its own plugins at zero without editing
#                   the shared baseline file.
#   --list          print `path<TAB>type` rows only (one per distinct pair), no
#                   structured section, exit 0.
#
# Usage:
#   bash scripts/check-bare-bash-grant.sh [--project-dir DIR] [--baseline FILE]
#       [--update-baseline] [--plugin DIR]... [--list]
#
# Exit codes:
#   0 - OK, or WARN (baseline-held hits only), or --list
#   1 - ERROR: new_hit, stale_baseline, nothing_scanned, or any hit under --plugin
#   2 - usage error (unknown argument, missing value, --plugin dir not found)
set -uo pipefail

usage() {
  sed -n '/^# Usage:/,/^#   2 - usage/p' "$0" | sed 's/^# \{0,1\}//'
}

proj_dir=""
baseline=""
update_baseline=0
list_only=0
plugins=()

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir|--baseline|--plugin)
      if [ -z "${2:-}" ]; then
        echo "check-bare-bash-grant.sh: $1 requires a value" >&2
        exit 2
      fi
      case "$1" in
        --project-dir) proj_dir="$2" ;;
        --baseline) baseline="$2" ;;
        --plugin) plugins+=("$2") ;;
      esac
      shift 2
      ;;
    --update-baseline) update_baseline=1; shift ;;
    --list) list_only=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      # An unknown argument is REJECTED, never swallowed (#2057).
      echo "check-bare-bash-grant.sh: unknown argument: $1" >&2
      echo "" >&2
      usage >&2
      exit 2
      ;;
  esac
done

script_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
if ! proj_dir="$(cd "$proj_dir" 2>/dev/null && pwd)"; then
  echo "check-bare-bash-grant.sh: --project-dir is not a directory" >&2
  exit 2
fi
[ -n "$baseline" ] || baseline="$proj_dir/scripts/bare-bash-grant-baseline.txt"
case "$baseline" in /*) ;; *) baseline="$PWD/$baseline" ;; esac

# `read -d ''` rather than a heredoc-fed `python3 -`: stdin stays free, and bash
# 3.2 misparses a heredoc inside `$(...)`.
IFS= read -r -d '' PY_SRC <<'PY' || true
import os
import sys

lib_dir, proj_dir, baseline, update, list_only = sys.argv[1:6]
plugin_args = sys.argv[6:]
sys.path.insert(0, lib_dir)
from allowed_tools import classify, read_allowed_tools  # noqa: E402
update = update == "1"
list_only = list_only == "1"
scoped = bool(plugin_args)

PRUNE = {".claude", "dist"}  # .claude/worktrees copies, the dist/ export


def one_line(text):
    return " ".join(str(text).split())


def usage_error(msg):
    print("check-bare-bash-grant.sh: %s" % msg, file=sys.stderr)
    sys.exit(2)


# --- discovery (relative to proj_dir, #2219) --------------------------------
os.chdir(proj_dir)
if scoped:
    plugin_dirs = []
    for arg in plugin_args:
        rel = os.path.normpath(os.path.relpath(os.path.abspath(arg), proj_dir)
                               if os.path.isabs(arg) else arg)
        if not os.path.isdir(rel):
            usage_error("--plugin %s: not a directory under %s" % (arg, proj_dir))
        plugin_dirs.append(rel)
else:
    plugin_dirs = sorted(d for d in os.listdir(".")
                         if d.endswith("-plugin") and d != ".claude-plugin"
                         and os.path.isdir(d))

skill_files = []
for pdir in plugin_dirs:
    # Walking from <plugin>/skills/ never reaches <plugin>/.claude/worktrees/ or
    # <plugin>/dist/; the prune covers a copy nested below skills/ itself.
    for root, dirs, files in os.walk(os.path.join(pdir, "skills")):
        dirs[:] = sorted(d for d in dirs if d not in PRUNE)
        for name in files:
            if name in ("SKILL.md", "skill.md"):
                skill_files.append(os.path.normpath(os.path.join(root, name)))
skill_files.sort()


# --- allowed-tools parsing: scripts/lib/allowed_tools.py (shared with
# scripts/skill-shell-commands.py --check, so both read grants the same way) ---
hits = {}  # (path, type, token) -> True
for sf in skill_files:
    for token in read_allowed_tools(sf):
        kind = classify(token)
        if kind:
            hits[(sf, kind, token)] = True

if list_only:
    for path, kind in sorted({(p, k) for (p, k, _) in hits}):
        print("%s\t%s" % (path, kind))
    sys.exit(0)

# --- baseline ----------------------------------------------------------------
base = set()
if not scoped:
    seeding = update and not os.path.isfile(baseline)
    if os.path.isfile(baseline):
        with open(baseline, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.rstrip("\n")
                if not line.strip() or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) != 3 or parts[1] not in ("bare_bash", "broad_shell_grant"):
                    usage_error("%s: malformed baseline line %r (want path<TAB>type<TAB>token)"
                                % (baseline, line))
                base.add(tuple(parts))
    if update and skill_files:
        base = set(hits) if seeding else (base & set(hits))
        with open(baseline, "w", encoding="utf-8") as fh:
            fh.write("# Bare-Bash grant baseline -- see scripts/check-bare-bash-grant.sh.\n"
                     "# path<TAB>type<TAB>token: full-shell allowed-tools grants that predate\n"
                     "# the lint and wait for the #3464 migration. Entries may only be removed;\n"
                     "# rewrite with --update-baseline, which never adds one.\n")
            for row in sorted(base):
                fh.write("\t".join(row) + "\n")

# --- judge -------------------------------------------------------------------
errors, warns = [], []
for key in sorted(hits):
    path, kind, token = key
    if scoped:
        errors.append((kind, path, "",
                       "grants %s; list the commands the skill runs as Bash(<command> *)" % token))
    elif key in base:
        warns.append((kind, path, "",
                      "grants %s, held by the baseline until the #3464 migration" % token))
    else:
        errors.append(("new_hit", path, kind,
                       "grants %s, not in the baseline; list the commands the skill runs "
                       "as Bash(<command> *)" % token))
for key in sorted(base - set(hits)):
    path, kind, token = key
    errors.append(("stale_baseline", path, kind,
                   "baseline holds %s but the skill no longer grants it; lower the "
                   "baseline with --update-baseline" % token))

plugin_count = len(plugin_dirs)
if not skill_files and plugin_count:
    errors.append(("nothing_scanned", "", "",
                   "%d plugin dir(s) but zero SKILL.md discovered; the discovery is broken, "
                   "not the tree clean (see #2219)" % plugin_count))

issues = [("ERROR",) + e for e in errors] + [("WARN",) + w for w in warns]
item_status = "ERROR" if errors else ("WARN" if warns else "OK")

print("=== BARE BASH GRANT ===")
print("MODE=%s" % ("plugin" if scoped else "baseline"))
print("PLUGIN_DIRS=%d" % plugin_count)
print("SKILLS_SCANNED=%d" % len(skill_files))
if not skill_files and not plugin_count:
    print("SCANNED_EMPTY=true")
print("BARE_BASH_HITS=%d" % sum(1 for k in hits if k[1] == "bare_bash"))
print("BROAD_SHELL_HITS=%d" % sum(1 for k in hits if k[1] == "broad_shell_grant"))
if not scoped:
    print("BASELINE_ENTRIES=%d" % len(base))
    print("NEW_HITS=%d" % sum(1 for e in errors if e[0] == "new_hit"))
    print("STALE_BASELINE=%d" % sum(1 for e in errors if e[0] == "stale_baseline"))
print("STATUS=%s" % item_status)
if issues:
    first = next(i for i in issues if i[0] == item_status)
    subject = (" %s" % first[2]) if first[2] else ""
    reason = one_line("%s:%s %s" % (first[1], subject, first[4]))[:180]
    if len(issues) > 1:
        reason += " (+%d more)" % (len(issues) - 1)
    print("REASON=%s" % reason)
print("ISSUE_COUNT=%d" % len(issues))
if issues:
    print("ISSUES:")
    for sev, itype, path, hit_type, msg in issues:
        row = "  - SEVERITY=%s TYPE=%s" % (sev, itype)
        if path:
            row += " SKILL=%s" % path
        if hit_type:
            row += " HIT_TYPE=%s" % hit_type
        print("%s MSG=%s" % (row, one_line(msg)))
print("=== END BARE BASH GRANT ===")
sys.exit(1 if errors else 0)
PY

python3 -c "$PY_SRC" "$script_self_dir/lib" "$proj_dir" "$baseline" "$update_baseline" "$list_only" ${plugins[@]+"${plugins[@]}"}
