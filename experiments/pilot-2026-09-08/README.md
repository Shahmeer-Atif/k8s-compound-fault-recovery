# Pilot experiment, 8 September 2026

Purpose: validate the central premise before committing to the study.

**Hypothesis.** A pod deleted while `kube-controller-manager` is unavailable will not be
replaced, and will remain absent for the duration of the outage.

## Environment

| | |
|---|---|
| Host | Apple MacBook Air M4, 10 cores, 16 GB unified memory |
| OS | macOS (Darwin 25.5.0) |
| Docker | 29.5.3 |
| kind | 0.33.0 |
| Kubernetes | v1.37.0 |
| Cluster | single control-plane node |
| Workload | nginx Deployment, 10 replicas |

## Method

1. Create a `kind` cluster and deploy nginx with 10 replicas.
2. Relocate `/etc/kubernetes/manifests/kube-controller-manager.yaml`, removing the component.
3. Confirm via `crictl` that the container is gone.
4. Delete one nginx pod.
5. Poll pod count every 30 seconds for five minutes.
6. Restore the manifest and measure time to recovery.

## Results

```
T+30s   pods=9  running=9
T+60s   pods=9  running=9
T+90s   pods=9  running=9
T+120s  pods=9  running=9
T+150s  pods=9  running=9
T+180s  pods=9  running=9
T+210s  pods=9  running=9
T+240s  pods=9  running=9
T+270s  pods=9  running=9
T+300s  pods=9  running=9
```

| Observation | Result |
|---|---|
| Pods after deletion | 9 of 10 |
| Duration held at 9 | full 300 s observation window |
| Recovery without intervention | none |
| Recovery after manifest restored | 22 s |

### Reported state during the fault

```
$ kubectl get deployment nginx
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
nginx   10/10   10           10          6m47s

$ kubectl get pods -l app=nginx --no-headers | wc -l
9
```

## Findings

**1. Premise confirmed.** The pod was not replaced and did not return until the
controller-manager was restored. Recovery then took 22 seconds.

**2. Unplanned: differential observability.** The Deployment object continued reporting
`10/10 ready, 10 available` while only nine pods existed. The controller-manager owns
Deployment status reconciliation; with it unavailable, the status object freezes at its last
known value and is never corrected.

Operationally this means **every dashboard, health check and status query would have reported
the cluster as healthy throughout the degradation**. This is an instance of gray failure as
defined by Huang et al. (HotOS 2017): a partial failure with differential observability, where
some components see the system as healthy while others see it as failed.

This was not a planned measurement. It provides direct empirical support for RQ3 and will be
measured systematically in the main study, which is why `harness/observe.sh` records both
`pods_total` (observed) and `deploy_available` (reported) in every sample.

## Resource measurement

Taken during the same session, with unrelated containers also running on the host.

| Node | Memory |
|---|---|
| control-plane 1 | 725 MiB |
| control-plane 2 | 543 MiB |
| control-plane 3 | 574 MiB |
| worker 1 | 139 MiB |
| worker 2 | 115 MiB |
| haproxy load balancer | 19 MiB |
| **Total, 5 nodes + 10 pods** | **2.44 GiB** |

Cluster creation times: single-node 2 m 15 s (including image pull), five-node HA 1 m 23 s.

Note that `kind` automatically provisions an haproxy load balancer in front of the three API
servers in an HA configuration. The "HA API servers behind a load balancer" mitigation
relevant to RQ4 is therefore present in the testbed at no additional cost.

## Threats

Single run, single-node cluster, one workload type. This was a go/no-go check on the premise,
not a measurement. All figures here are indicative and are superseded by the main study.
