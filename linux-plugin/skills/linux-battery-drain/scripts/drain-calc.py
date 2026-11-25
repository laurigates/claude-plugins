#!/usr/bin/env python3
"""Compute the drain between 'before' and 'after' rows of an offdrain.csv or
s3drain.csv log written by off-test.sh / s3-test.sh.

For each before/after pair it prints the period, the energy drop and the
average draw. When energy_full changed between the rows (the gauge
recalibrated), it flags the pair and also prints a state-of-charge-based
estimate, which assumes the gauge kept the percentage and rescaled the energy.
That assumption is unverified for any given gauge, so the flagged figure is an
estimate, not a measurement.

Usage: drain-calc.py LOG.csv [--overhead-wh 0.1]
  --overhead-wh  energy spent running between the readings (shutdown + boot),
                 subtracted before computing the off-state draw
"""

import argparse
import csv
import sys


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("log")
    ap.add_argument("--overhead-wh", type=float, default=0.0)
    a = ap.parse_args()
    with open(a.log, newline="") as f:
        rows = list(csv.DictReader(f))
    before = None
    pairs = 0
    for r in rows:
        if r["phase"].startswith("before"):
            before = r
            continue
        if r["phase"] != "after" or before is None:
            continue
        pairs += 1
        t0, t1 = int(before["epoch"]), int(r["epoch"])
        e0, e1 = int(before["energy_uwh"]) / 1e6, int(r["energy_uwh"]) / 1e6
        hours = (t1 - t0) / 3600
        drop = e0 - e1
        net = drop - a.overhead_wh
        print(f"=== {before['phase']} -> after ===")
        print(f"PERIOD_H={hours:.2f} ENERGY_WH={e0:.3f}->{e1:.3f} DROP_WH={drop:.3f}")
        if hours > 0:
            print(
                f"AVG_MW={1000 * drop / hours:.0f} AVG_MW_NET_OF_OVERHEAD={1000 * net / hours:.0f}"
            )
        ac = {before.get("ac_online"), r.get("ac_online")}
        if ac - {"0", "-", None}:
            print(
                "WARNING=charger was connected at one of the readings; not a drain measurement"
            )
        f0, f1 = before.get("energy_full_uwh"), r.get("energy_full_uwh")
        if f0 and f1 and f0 != f1:
            f0, f1 = int(f0) / 1e6, int(f1) / 1e6
            soc0, soc1 = e0 / f0, e1 / f1
            est = (soc0 - soc1) * (f0 + f1) / 2
            print(
                f"WARNING=energy_full changed {f0:.3f}->{f1:.3f} Wh: gauge recalibrated, DROP_WH is not comparable"
            )
            print(
                f"SOC_ESTIMATE_WH={est:.3f} SOC_ESTIMATE_MW={1000 * est / hours:.0f} (assumes the gauge kept state of charge)"
            )
        if drop < 0:
            print("WARNING=energy rose on battery: gauge correction, not a measurement")
        before = None
    print(f"PAIRS={pairs}")
    return 0 if pairs else 1


if __name__ == "__main__":
    sys.exit(main())
