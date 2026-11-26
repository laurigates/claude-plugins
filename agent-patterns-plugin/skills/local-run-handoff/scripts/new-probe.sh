#!/usr/bin/env bash
# Scaffold a local-run probe (or repro) bundle under the probe root.
#
#   new-probe.sh --slug <slug> [--question <text>] [--ref <owner/repo#N>]
#                [--os any|darwin|linux] [--codes 'CODE=meaning;CODE=meaning']
#                [--repro] [--notify-pr <owner/repo#N>] [--notify-session <name>]
#                [--requester <text>] [--root <dir>] [--date YYYYMMDD] [--update-lib]
#
# Root: --root, else $LOCAL_PROBES_DIR, else $HOME/claude-probes. The root's
# justfile and lib/ are written on first use and refreshed only with --update-lib.
# Output: === NEW PROBE === block with PROBE_DIR=, RUN=, STATUS=.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tpl="$here/../templates"

np_root="${LOCAL_PROBES_DIR:-$HOME/claude-probes}"
np_slug="" np_question="" np_ref="" np_os="any" np_codes="" np_repro=0
np_pr="" np_session="" np_requester="" np_date="" np_update_lib=0

fail() {
  echo "=== NEW PROBE ==="
  echo "STATUS=ERROR"
  echo "REASON=$1"
  echo "ISSUE_COUNT=1"
  echo "=== END NEW PROBE ==="
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root) np_root="${2:-}"; shift 2 ;;
    --slug) np_slug="${2:-}"; shift 2 ;;
    --question) np_question="${2:-}"; shift 2 ;;
    --ref) np_ref="${2:-}"; shift 2 ;;
    --os) np_os="${2:-}"; shift 2 ;;
    --codes) np_codes="${2:-}"; shift 2 ;;
    --repro) np_repro=1; shift ;;
    --notify-pr) np_pr="${2:-}"; shift 2 ;;
    --notify-session) np_session="${2:-}"; shift 2 ;;
    --requester) np_requester="${2:-}"; shift 2 ;;
    --date) np_date="${2:-}"; shift 2 ;;
    --update-lib) np_update_lib=1; shift ;;
    *) fail "unknown_arg: $1" ;;
  esac
done

[ -n "$np_slug" ] || fail "missing_slug: --slug is required"
[[ "$np_slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || fail "bad_slug: use lowercase letters, digits and hyphens"
case "$np_os" in any | darwin | linux) ;; *) fail "bad_os: --os must be any, darwin or linux" ;; esac
command -v python3 >/dev/null 2>&1 || fail "missing_tool: python3"
[ -d "$tpl/probe" ] || fail "missing_templates: $tpl"

if [ -z "$np_codes" ]; then
  if [ "$np_repro" = 1 ]; then
    np_codes="REPRODUCED=the bug reproduces on this host;NOT_REPRODUCED=the steps ran and the bug did not appear"
  else
    np_codes="YES=the behaviour in question holds;NO=the behaviour in question does not hold"
  fi
fi
[ -n "$np_question" ] || np_question="TODO: the one question this probe answers"
np_date="${np_date:-$(date +%Y%m%d)}"
np_name="${np_date}-${np_slug}"
np_dir="$np_root/$np_name"

[ -e "$np_dir" ] && fail "exists: $np_dir"

mkdir -p "$np_root/lib" || fail "mkdir_failed: $np_root"
for f in justfile lib/report.sh lib/probes.sh; do
  if [ ! -f "$np_root/$f" ] || [ "$np_update_lib" = 1 ]; then
    cp "$tpl/$f" "$np_root/$f" || fail "copy_failed: $f"
  fi
done

mkdir -p "$np_dir/fixtures" "$np_dir/results" || fail "mkdir_failed: $np_dir"

python3 -I - "$tpl/probe" "$np_dir" "$np_name" "$np_slug" "$np_question" "$np_ref" "$np_os" "$np_codes" <<'PY' || fail "render_failed"
import pathlib, sys
src, dst, name, slug, question, ref, os_, codes = sys.argv[1:]
pairs = []
for item in codes.split(";"):
    item = item.strip()
    if not item:
        continue
    code, _, meaning = item.partition("=")
    pairs.append((code.strip(), meaning.strip()))
def sh(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")
case = "\n".join(f'  {c}) verdict {c} "{sh(m)}. Next: TODO." ;;' for c, m in pairs).lstrip()
table = "\n".join(f"| {c} | {m} | TODO |" for c, m in pairs)
subs = {"__NAME__": name, "__SLUG__": slug, "__QUESTION__": question,
        "__REF__": ref or "-", "__OS__": os_, "__CODES_CASE__": case, "__CODES_TABLE__": table}
for f in ("run.sh", "README.md"):
    text = (pathlib.Path(src) / f).read_text()
    for k, v in subs.items():
        text = text.replace(k, v)
    (pathlib.Path(dst) / f).write_text(text)
PY
chmod +x "$np_dir/run.sh"

python3 -I - "$np_dir/.handoff.json" "$np_name" "$np_ref" "$np_requester" "$np_os" "$np_pr" "$np_session" "$np_repro" <<'PY' || fail "handoff_failed"
import datetime, json, sys
out, name, ref, requester, os_, pr, session, repro = sys.argv[1:]
notify = {k: v for k, v in (("pr", pr), ("session", session)) if v}
doc = {"name": name, "kind": "repro" if repro == "1" else "probe", "ref": ref,
       "requester": requester, "requires_os": os_, "notify": notify,
       "created": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
open(out, "w").write(json.dumps(doc, indent=2) + "\n")
PY

echo "=== NEW PROBE ==="
echo "PROBE_DIR=$np_dir"
echo "ROOT=$np_root"
echo "RUN=just -f $np_root/justfile run $np_slug"
echo "STATUS=OK"
echo "ISSUE_COUNT=0"
echo "=== END NEW PROBE ==="
