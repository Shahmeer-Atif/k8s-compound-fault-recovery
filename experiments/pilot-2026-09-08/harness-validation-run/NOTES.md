# Harness validation run

Output from the first end-to-end execution of `harness/run-experiment.sh`, retained so the
repository contains real harness output rather than only documentation.

```
./harness/run-experiment.sh kube-controller-manager 60 pod smoketest
```

Single control-plane node, nginx with 10 replicas, 60 second fault window, compound condition
`pod` (one pod deleted five seconds after the controller-manager was removed).

`analysis/summarise.py` reports:

```
desired replicas:      10
degradation observed:  YES, from t+5s
recovered unaided:     NO
minimum pods in fault: 9
autonomy-loss window:  >= 52s (right-censored at window end)
status divergence:     YES, from t+5s (reported 10, actual 9)
divergent samples:     11 of 12
recovery after clear:  19s
```

Note the `fault_window.csv` columns `deploy_available` and `pods_total`. The Deployment reports
10 available for eleven of twelve samples while only nine pods exist. This is the differential
observability signal for RQ3, captured automatically by the harness.

This is a single short run for tooling validation, not a measurement. Superseded by the main study.
