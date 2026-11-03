#!/usr/bin/env python3
"""Split a taskwarrior queue into clusters, validate agent verdicts, apply them by UUID.

usage:
  triage.py split    --dir D --map MAP.json [--partial]  # writes D/pending.json, D/clusters/<C>.json
  triage.py validate --dir D                     # checks D/verdicts/<C>.jsonl against the clusters
  triage.py apply    --dir D --verdicts done,update [--only UUIDFILE] [--dry-run]

MAP.json maps a cluster name to the project slugs it owns, e.g.
  {"A": ["comfyui-nodes"], "B": ["infrastructure", "gitops"]}
Every pending task's project must appear in exactly one cluster; `split` fails
otherwise, unless --partial (then unmapped projects are skipped and listed). A task with no project is matched by the slug "(none)".

Verdict lines (one per task, keyed by full uuid):
  {"uuid": "...", "verdict": "done|obsolete|update|keep", "evidence": "...",
   "annotation": "... or null", "new_description": "... or null", "duplicate_of": "... or null"}

apply: done -> annotate + `task done`; obsolete -> annotate + `task delete`;
update -> annotate (+ modify description when new_description is set); keep -> nothing.
Every change is addressed by UUID, so numeric-ID renumbering mid-run cannot hit
the wrong task. Tasks no longer pending at apply time are skipped.
"""

import argparse
import datetime
import json
import pathlib
import subprocess
import sys

VERDICTS = {"done", "obsolete", "update", "keep"}
NO_PROJECT = "(none)"


def export_pending():
    out = subprocess.run(
        ["task", "status:pending", "export"], capture_output=True, text=True, check=True
    ).stdout
    return json.loads(out)


def slim(t):
    return {
        "uuid": t["uuid"],
        "project": t.get("project"),
        "description": t["description"],
        "tags": t.get("tags"),
        "entry": t["entry"][:8],
        "modified": t.get("modified", t["entry"])[:8],
        "due": t.get("due"),
        "priority": t.get("priority"),
        "depends": t.get("depends"),
        "annotations": [
            {"d": a["entry"][:8], "t": a["description"]}
            for a in t.get("annotations", [])
        ],
    }


def cmd_split(d, map_path, partial):
    mapping = json.loads(pathlib.Path(map_path).read_text())
    owner = {}
    for cluster, slugs in mapping.items():
        for s in slugs:
            if s in owner:
                sys.exit(f"ERROR project {s!r} is in clusters {owner[s]} and {cluster}")
            owner[s] = cluster
    pending = export_pending()
    unmapped = sorted({t.get("project") or NO_PROJECT for t in pending} - owner.keys())
    if unmapped and not partial:
        sys.exit(f"ERROR unmapped projects (pass --partial to skip them): {unmapped}")
    if unmapped:
        print(f"SKIPPED_PROJECTS={','.join(unmapped)}")
        pending = [t for t in pending if (t.get("project") or NO_PROJECT) in owner]
    (d / "clusters").mkdir(parents=True, exist_ok=True)
    (d / "verdicts").mkdir(exist_ok=True)
    (d / "pending.json").write_text(json.dumps(pending))
    for cluster in mapping:
        tasks = [
            slim(t) for t in pending if owner[t.get("project") or NO_PROJECT] == cluster
        ]
        (d / "clusters" / f"{cluster}.json").write_text(json.dumps(tasks, indent=1))
        print(f"CLUSTER={cluster} TASKS={len(tasks)}")
    print(f"PENDING={len(pending)}")


def load(d):
    verdicts, errors = {}, []
    for cf in sorted((d / "clusters").glob("*.json")):
        c = cf.stem
        cluster = {t["uuid"] for t in json.loads(cf.read_text())}
        vf = d / "verdicts" / f"{c}.jsonl"
        if not vf.exists():
            errors.append(f"{c}: missing {vf.name}")
            continue
        seen = set()
        for n, line in enumerate(vf.read_text().splitlines(), 1):
            if not line.strip():
                continue
            try:
                v = json.loads(line)
            except json.JSONDecodeError as e:
                errors.append(f"{c}:{n}: bad json ({e})")
                continue
            u = v.get("uuid")
            if u not in cluster:
                errors.append(f"{c}:{n}: uuid {u} not in cluster")
            elif v.get("verdict") not in VERDICTS:
                errors.append(f"{c}:{n}: bad verdict {v.get('verdict')!r}")
            elif u in seen:
                errors.append(f"{c}:{n}: duplicate uuid {u}")
            else:
                seen.add(u)
                verdicts[u] = v
        missing = cluster - seen
        if missing:
            errors.append(
                f"{c}: {len(missing)} tasks without a verdict: {sorted(m[:8] for m in missing)}"
            )
    return verdicts, errors


def summarize(verdicts, errors):
    for e in errors:
        print(f"ERROR {e}")
    counts = {k: 0 for k in sorted(VERDICTS)}
    for v in verdicts.values():
        counts[v["verdict"]] += 1
    print(
        " ".join(f"{k.upper()}={n}" for k, n in counts.items()),
        f"TOTAL={len(verdicts)}",
    )


def task(args, dry):
    cmd = ["task", "rc.confirmation=off", "rc.verbose=nothing", "rc.bulk=0", *args]
    if dry:
        print("DRY", *args[:2])
        return 0
    r = subprocess.run(cmd, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if r.returncode:
        print(f"FAIL {args[0][:8]} {args[1]}: {r.stderr.strip()[:200]}")
    return r.returncode


def cmd_apply(d, want, only_file, dry):
    verdicts, errors = load(d)
    summarize(verdicts, errors)
    if errors:
        sys.exit("refusing to apply with validation errors")
    only = set(pathlib.Path(only_file).read_text().split()) if only_file else None
    live = {t["uuid"] for t in export_pending()}
    today = datetime.date.today().isoformat()
    applied = failed = skipped = 0
    for u, v in verdicts.items():
        if v["verdict"] not in want:
            continue
        if only is not None and u not in only and u[:8] not in only:
            continue
        if u not in live:
            print(f"SKIP {u[:8]} no longer pending")
            skipped += 1
            continue
        note = (
            v.get("annotation")
            or f"triage {today}: {v['verdict']} — {v.get('evidence', '')}"
        )
        rc = task([u, "annotate", "--", note], dry)
        if v["verdict"] == "update" and v.get("new_description"):
            rc |= task([u, "modify", f"description:{v['new_description']}"], dry)
        elif v["verdict"] == "done":
            rc |= task([u, "done"], dry)
        elif v["verdict"] == "obsolete":
            rc |= task([u, "delete"], dry)
        applied += rc == 0
        failed += rc != 0
    print(
        f"APPLIED={applied} FAILED={failed} SKIPPED={skipped} DRY_RUN={str(dry).lower()}"
    )
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("mode", choices=["split", "validate", "apply"])
    ap.add_argument(
        "--dir",
        required=True,
        type=pathlib.Path,
        help="scratch directory for this triage run",
    )
    ap.add_argument("--map", help="split: JSON mapping cluster -> project slugs")
    ap.add_argument(
        "--partial",
        action="store_true",
        help="split: skip projects not in the map instead of failing",
    )
    ap.add_argument(
        "--verdicts",
        default="done,update",
        help="apply: comma-separated verdicts to apply",
    )
    ap.add_argument(
        "--only", help="apply: file of uuids (full or 8-char) to restrict to"
    )
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if a.mode == "split":
        if not a.map:
            ap.error("split needs --map")
        cmd_split(a.dir, a.map, a.partial)
    elif a.mode == "validate":
        verdicts, errors = load(a.dir)
        summarize(verdicts, errors)
        sys.exit(1 if errors else 0)
    else:
        want = set(a.verdicts.split(","))
        bad = want - VERDICTS
        if bad:
            ap.error(f"unknown verdicts {sorted(bad)}")
        cmd_apply(a.dir, want, a.only, a.dry_run)


if __name__ == "__main__":
    main()
