#!/usr/bin/env python3
"""probe-delta — report only the findings a probe has not reported before.

Reads a probe's `--format=json` document on stdin (or from a file) and compares
it against a stored baseline, so a recurring report says "one new thing" rather
than repeating a corpus-sized list that a reader learns to skip.

    python3 probe-delta.py --findings - --baseline <path> --probe config-drift \\
        --root <abs> [--record] [--section "CONFIG DRIFT DELTA"]

Behaviour:

* No baseline — or one recorded at a different root, or under a different
  schema — records fresh and reports `STATUS=OK FIRST_RUN=true`. A baseline
  from another root would compare two disjoint fingerprint sets and call every
  finding new AND every stored one resolved, so refusing to compare is the only
  honest answer.
* Nothing new: `STATUS=OK NEW=0 ISSUE_COUNT=0`.
* New findings: `STATUS=WARN`/`ERROR`, rendering ONLY the new ones, counted by
  `NEW_ERRORS=`/`NEW_WARNINGS=` — deliberately not the `ERRORS=`/`WARNINGS=`
  that `config-drift.py --format=status` writes over the FULL finding set.
* Empty or unparseable input: `STATUS=ERROR TYPE=analyzer_failed`, never a
  clean sweep. An analyzer that died and one that found nothing produce the
  same empty stdout; reporting the latter would launder a broken probe into a
  green report.

This is the second consumer of `lib.probe`, and it touches no `check_*` code —
that is the claim the extraction makes: the finding/waiver/delta contract is
separable from the similarity computation that produced the findings.

Stdlib only, invoked with a bare `python3`.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

# See lib/probe.py's module docstring for why this is the dotted namespace form.
from lib.probe import Baseline, Finding, exit_code, render_status


def _now() -> str:
    """The module never calls now() itself — timestamps come from the caller."""
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def _analyzer_failed(section: str, probe: str, root: str, msg: str) -> str:
    return "\n".join(
        [
            f"=== {section} ===",
            f"PROBE={probe}",
            f"ROOT={root}",
            "FIRST_RUN=false",
            "STATUS=ERROR",
            "TYPE=analyzer_failed",
            "ISSUE_COUNT=1",
            f"MSG={msg}",
            f"=== END {section} ===",
        ]
    )


def _parse(raw: str) -> list:
    """Turn a probe's JSON document into Findings, or raise.

    Accepts the full `{"counts": ..., "findings": [...]}` document and a bare
    findings array, because a caller piping `jq .findings` is the obvious thing
    to do and failing on it would be a papercut with no upside.
    """
    payload = json.loads(raw)
    items = payload.get("findings") if isinstance(payload, dict) else payload
    if not isinstance(items, list):
        raise ValueError("no findings array in input")
    out = []
    for d in items:
        extra = {k: v for k, v in d.items() if k not in ("severity", "kind", "summary")}
        out.append(Finding(d["severity"], d["kind"], d["summary"], **extra))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--findings",
        default="-",
        help="path to a probe's --format=json output, or - for stdin",
    )
    ap.add_argument("--baseline", required=True, help="path to the baseline file")
    ap.add_argument(
        "--probe", required=True, help="probe name recorded in the baseline"
    )
    ap.add_argument(
        "--root", required=True, help="absolute root the findings were collected at"
    )
    ap.add_argument(
        "--record",
        action="store_true",
        help="update the baseline after reporting (a first run always records)",
    )
    ap.add_argument("--section", default=None, help="section header for the report")
    # argparse rejects an unknown argument with usage on stderr and exit 2,
    # which is the contract here -- a swallowed flag is how a bounded run turns
    # into an unbounded one.
    args = ap.parse_args()

    section = args.section or f"{args.probe.upper()} DELTA"
    root = str(Path(args.root).expanduser().resolve())

    if args.findings == "-":
        raw = sys.stdin.read()
    else:
        try:
            raw = Path(args.findings).read_text(encoding="utf-8")
        except OSError as exc:
            print(
                _analyzer_failed(section, args.probe, root, f"unreadable input: {exc}")
            )
            return 1

    if not raw.strip():
        print(_analyzer_failed(section, args.probe, root, "empty analyzer output"))
        return 1
    try:
        findings = _parse(raw)
    except (ValueError, TypeError, AttributeError, KeyError) as exc:
        print(
            _analyzer_failed(section, args.probe, root, f"{type(exc).__name__}: {exc}")
        )
        return 1

    baseline = Baseline.load(args.baseline, root=root, probe=args.probe)
    if baseline is None:
        baseline = Baseline(args.probe, root, _now())
    delta = baseline.delta(findings)

    # On a first run every finding is trivially "new", which is noise rather
    # than news -- record it and stay silent.
    reported = [] if delta.first_run else delta.new

    counts = {
        "probe": args.probe,
        "root": root,
        "first_run": "true" if delta.first_run else "false",
        "total_findings": len(findings),
        "new": len(reported),
        "resolved": len(delta.resolved),
        "carried": len(delta.carried),
    }

    if delta.first_run or args.record:
        try:
            Baseline(args.probe, root, _now()).record(findings).save(args.baseline)
            counts["baseline_written"] = "true"
        except OSError as exc:
            counts["baseline_written"] = "failed"
            counts["baseline_error"] = type(exc).__name__

    # No STATUS override: `render_status` derives OK/WARN/ERROR, and OK over an
    # empty `reported` list IS "nothing new". The distinction a reader wants —
    # nothing new vs. nothing at all vs. never run before — is carried by
    # `NEW=`, `TOTAL_FINDINGS=` and `FIRST_RUN=` above, which add a key rather
    # than putting a fourth word where a rollup greps for three.
    print(render_status(section, reported, counts))
    return exit_code(reported)


if __name__ == "__main__":
    sys.exit(main())
