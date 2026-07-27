#!/usr/bin/env python3
"""synthesize.py — unblind the judgments into synthesis.json.

Median of the two judges per (unit, dimension). Where the two judges differ by
2 or more points the pair is recorded as CONTESTED and the report must say so:
with n=2 a median cannot distinguish "the judges agree" from "the judges are
correlated", so a wide split is published, never smoothed.

Reads judgments/*.json, writes synthesis.json. No timestamps — the output is a
pure function of its inputs so a re-run over unchanged judgments is
byte-identical.

    python3 synthesize.py [--judgments DIR] [--out FILE]
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import statistics
import sys

DIMS = ["C1", "C2", "C3", "C4", "C5", "C6"]
CONTESTED_GAP = 2


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--judgments", default=os.path.join(here, "judgments"))
    ap.add_argument("--out", default=os.path.join(here, "synthesis.json"))
    args = ap.parse_args()

    by_unit: dict[str, list[dict]] = {}
    for path in sorted(glob.glob(os.path.join(args.judgments, "*.json"))):
        data = json.load(open(path, encoding="utf-8"))
        by_unit.setdefault(data["unit"], []).append(data)

    units = {}
    dim_totals: dict[str, list[float]] = {d: [] for d in DIMS}
    contested = []
    leakage_rows = []

    for unit in sorted(by_unit):
        judgments = sorted(by_unit[unit], key=lambda j: j["judge_id"])
        dims = {}
        for dim in DIMS:
            scores = [
                j["dimensions"][dim]["score"]
                for j in judgments
                if dim in j.get("dimensions", {})
            ]
            numeric = [s for s in scores if isinstance(s, int)]
            if not numeric:
                dims[dim] = {"median": "n/a", "scores": scores, "contested": False}
                continue
            median = statistics.median(numeric)
            gap = max(numeric) - min(numeric) if len(numeric) > 1 else 0
            is_contested = gap >= CONTESTED_GAP
            dims[dim] = {
                "median": median,
                "scores": scores,
                "gap": gap,
                "contested": is_contested,
            }
            dim_totals[dim].append(median)
            if is_contested:
                contested.append({"unit": unit, "dim": dim, "scores": numeric, "gap": gap})

        numeric_medians = [d["median"] for d in dims.values() if isinstance(d["median"], (int, float))]
        units[unit] = {
            "kind": judgments[0].get("unit_kind", "skill"),
            "judges": [j["judge_id"] for j in judgments],
            "dimensions": dims,
            "mean_median": round(sum(numeric_medians) / len(numeric_medians), 2)
            if numeric_medians
            else None,
            "top_findings": [j.get("top_finding", "") for j in judgments],
            "counter_findings": [j.get("counter_finding", "") for j in judgments],
        }

        for j in judgments:
            leak = j.get("leakage") or {}
            leakage_rows.append(
                {
                    "unit": unit,
                    "judge": j["judge_id"],
                    "influenced_scoring": bool(leak.get("influenced_scoring")),
                    "house_standards_seen": sorted(leak.get("house_standards_seen") or []),
                }
            )

    out = {
        "schema_version": 1,
        "units": units,
        "dimension_means": {
            d: round(sum(v) / len(v), 2) if v else None for d, v in sorted(dim_totals.items())
        },
        "contested": sorted(contested, key=lambda c: (-c["gap"], c["unit"], c["dim"])),
        "coverage": {
            "units_judged": len(units),
            "judgments": sum(len(v) for v in by_unit.values()),
            "units_with_two_judges": sum(1 for v in by_unit.values() if len(v) >= 2),
        },
        "leakage": sorted(leakage_rows, key=lambda r: (r["unit"], r["judge"])),
        "leakage_summary": {
            "judgments_reporting_influence": sum(1 for r in leakage_rows if r["influenced_scoring"]),
            "judgments_total": len(leakage_rows),
        },
    }

    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2, sort_keys=True)
        fh.write("\n")

    print("=== SYNTHESIS ===")
    print(f"UNITS_JUDGED={out['coverage']['units_judged']}")
    print(f"JUDGMENTS={out['coverage']['judgments']}")
    print(f"UNITS_WITH_TWO_JUDGES={out['coverage']['units_with_two_judges']}")
    for dim in DIMS:
        print(f"MEAN_MEDIAN_{dim}={out['dimension_means'][dim]}")
    print(f"CONTESTED_PAIRS={len(out['contested'])}")
    print(f"LEAKAGE_INFLUENCED={out['leakage_summary']['judgments_reporting_influence']}")
    print(f"STATUS={'OK' if out['coverage']['units_with_two_judges'] == len(units) else 'WARN'}")
    print("=== END SYNTHESIS ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
