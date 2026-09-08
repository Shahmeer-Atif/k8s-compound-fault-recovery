#!/usr/bin/env python3
"""Summarise one experimental run into the metrics defined in the methodology.

Reads the CSVs written by harness/run-experiment.sh and reports:
  - recovery outcome (did the cluster return to desired state unaided?)
  - autonomy-loss window
  - the divergence between reported and observed state (RQ3 signal)

Usage: python3 analysis/summarise.py results/<run_dir>
"""
import sys
import csv
from pathlib import Path


def read(path):
    if not path.exists():
        return []
    with path.open() as fh:
        return list(csv.DictReader(fh))


def as_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def main(run_dir):
    run = Path(run_dir)
    baseline = read(run / "baseline.csv")
    fault = read(run / "fault_window.csv")
    recovery = read(run / "recovery.csv")

    if not baseline or not fault:
        sys.exit(f"missing baseline or fault_window CSV in {run}")

    desired = max(as_int(r["pods_total"]) for r in baseline)

    print(f"run:                  {run.name}")
    print(f"desired replicas:     {desired}")

    # Locate the first sample that dropped below desired state. Samples before this
    # point predate the data-plane fault landing and must not count as recovery.
    counts = [as_int(r["pods_total"]) for r in fault]
    times = [as_int(r["t_offset_s"]) for r in fault]
    first_drop = next((i for i, c in enumerate(counts) if c < desired), None)

    if first_drop is None:
        print("degradation observed:  NO (pod count never fell below desired)")
        print("autonomy-loss window:  0s")
    else:
        after = counts[first_drop:]
        recovered = any(c >= desired for c in after)
        print(f"degradation observed:  YES, from t+{times[first_drop]}s")
        print(f"recovered unaided:     {'YES' if recovered else 'NO'}")
        print(f"minimum pods in fault: {min(after)}")

        if recovered:
            idx = first_drop + next(i for i, c in enumerate(after) if c >= desired)
            print(f"autonomy-loss window:  {times[idx] - times[first_drop]}s")
        else:
            span = times[-1] - times[first_drop]
            print(f"autonomy-loss window:  >= {span}s (right-censored at window end)")

    # RQ3 signal: reported state versus observed reality.
    divergent = [
        r for r in fault
        if r["deploy_available"] not in ("NA", "")
        and as_int(r["deploy_available"], -1) != as_int(r["pods_total"], -2)
    ]
    if divergent:
        first = divergent[0]
        print(f"status divergence:     YES, from t+{first['t_offset_s']}s "
              f"(reported {first['deploy_available']}, actual {first['pods_total']})")
        print(f"divergent samples:     {len(divergent)} of {len(fault)}")
    else:
        print("status divergence:     none observed")

    # Recovery latency after the fault is cleared.
    if recovery:
        for row in recovery:
            if as_int(row["pods_total"]) >= desired:
                print(f"recovery after clear:  {row['t_offset_s']}s")
                break
        else:
            print("recovery after clear:  not within observation window")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
