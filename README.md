# Compound Fault Recovery in Kubernetes

**Quantifying the Autonomy-Loss Window When Control-Plane and Data-Plane Failures Coincide**

Reproducibility materials for an empirical study of Kubernetes behaviour under control-plane
faults, and under control-plane faults that coincide with data-plane faults.

| | |
|---|---|
| **Institution** | FAST NUCES Islamabad |
| **Course** | Cloud Computing, 100-Day Research Assignment |
| **Research area** | Autonomous / Self-Adaptive Cloud Computing |
| **Authors** | Shahmeer Atif (23i-0711, Section A), Taaha Zaman Khan (22i-1377, Section B) |
| **Status** | Active. Cutoff 1 submitted September 2026. |

---

## What this studies

Kubernetes separates the **control plane** (API server, scheduler, controller-manager, etcd),
which decides what should happen, from the **data plane** (worker nodes and kubelets), which
executes those decisions.

When control-plane components become unavailable, running workloads keep serving traffic,
because kubelets do not need the API server to maintain existing containers. The cluster
therefore looks healthy from outside. What is silently lost is every adaptive behaviour:

- Self-healing stops. A crashed pod is not replaced.
- Autoscaling stops. A traffic surge receives no capacity.
- Scheduling stops. New pods stay `Pending`.
- Rollouts freeze mid-deployment.
- Service endpoints stop updating.

We call the interval during which a cluster is **operational but incapable of self-adaptation**
the **autonomy-loss window**. This repository contains the harness that measures it.

## Why it matters

Control-plane failures are less common than pod failures, but they are real and they hit
organisations with substantial engineering maturity.

| Incident | Duration | What happened |
|---|---|---|
| Shopify, Feb 2024 | 45 min | An etcd compaction bug caused API server unavailability. Workloads kept running, but the team could not schedule pods, roll back deployments, or respond to scale events. |
| OpenAI, Dec 2024 | 4h 22m | A telemetry deployment overwhelmed the control plane. Remediation required control-plane access, which had been lost. |
| Google Cloud, 2026 | 2h 22m | GKE autoscaling could not absorb load spikes because node provisioning failed **at the same time** as network congestion on existing nodes. |

That last one is a **compound fault**: a control-plane function failing concurrently with a
data-plane problem. Existing fault-injection studies inject one fault at a time. Production
outages are rarely so orderly.

## Research questions

| ID | Question |
|---|---|
| **RQ1** | How does loss of each control-plane component affect self-adaptive capability, decomposed into detection, reaction and recovery latency? |
| **RQ2** | What is the recovery outcome when data-plane faults occur concurrently with control-plane unavailability, and does it differ between stateless and stateful workloads? |
| **RQ3** | Does gray failure (degraded but not down) produce worse outcomes than clean failure? |
| **RQ4** | Do control-plane redundancy and tuned leader-election timeouts reduce the autonomy-loss window under compound faults? |

---

## Preliminary result

A pilot experiment on 8 September 2026 validated the central premise.

**Method.** Single-node `kind` cluster, nginx Deployment with 10 replicas. The
controller-manager manifest was relocated, removing the component. One pod was then deleted
and the cluster observed for five minutes.

```
T+30s   pods=9  running=9
T+60s   pods=9  running=9
T+120s  pods=9  running=9
T+300s  pods=9  running=9     <- never recovered
```

| Observation | Result |
|---|---|
| Pods after deletion | 9 of 10, for the full five-minute window |
| Recovery without intervention | none |
| Recovery after manifest restored | 22 seconds |
| **Deployment reported** | **`10/10 ready, 10 available`** |
| **Pods actually present** | **9** |

Two findings. First, the premise holds: a pod deleted while the controller-manager is
unavailable is not replaced. Second, and unplanned, the Deployment object continued reporting
ten of ten replicas available while only nine pods existed, because the controller-manager
owns status reconciliation. **Any dashboard or health check would have shown green throughout
the degradation.** That is differential observability, and it is direct empirical support
for RQ3.

Full record: [`experiments/pilot-2026-09-08/`](experiments/pilot-2026-09-08/)

---

## Reproducing

### Requirements

- Docker (tested with 29.5.3)
- [kind](https://kind.sigs.k8s.io/) 0.33.0 or later
- kubectl
- macOS or Linux. Tested on Apple Silicon (M4, 16 GB).

```bash
brew install kind kubectl        # macOS
```

### Resource footprint

Measured on an M4 MacBook Air, 16 GB:

| Configuration | Memory |
|---|---|
| 5 nodes (3 control-plane + 2 workers) + 10 pods | **2.44 GiB** |
| Single control-plane node + 10 pods | 0.72 GiB |

A 5-node cluster fits comfortably in a Docker Desktop allocation of 4 GiB or more.

### Run the pilot

```bash
git clone https://github.com/Shahmeer-Atif/k8s-compound-fault-recovery.git
cd k8s-compound-fault-recovery

kind create cluster --name cfr --config clusters/ha-3cp-2w.yaml
kubectl apply -f workloads/stateless-nginx.yaml
kubectl wait --for=condition=available --timeout=180s deployment/nginx

./harness/run-experiment.sh kube-controller-manager 300 pod pilot-repro
```

Results are written to `results/<component>_<duration>_<compound>_<run_id>/`:

| File | Contents |
|---|---|
| `baseline.csv` | 30 s of pre-fault state |
| `fault_window.csv` | State during the fault |
| `recovery.csv` | 180 s after the fault is cleared |
| `events.log` | Timestamped injection and clearing events |
| `thermal_before/after.txt` | Thermal pressure, for flagging throttled runs |

### Tear down

```bash
kind delete cluster --name cfr
```

---

## Fault injection technique

Control-plane components run as **static pods**, managed by the kubelet directly from manifest
files on the node filesystem rather than through the API server. `kubectl delete pod` is
ineffective, because the kubelet immediately recreates the pod from the manifest.

The correct technique is to relocate the manifest file:

```bash
docker exec <node> mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/
```

The kubelet stops the component and does not recreate it. Moving the file back reverses the
fault. This is deterministic, scriptable in one command, and requires **no chaos-engineering
framework**, which keeps both the dependency surface and the memory footprint small.

`harness/inject.sh` wraps this for all four components.

---

## Repository layout

```
clusters/      kind cluster definitions (HA and single control-plane)
workloads/     stateless (nginx) and stateful (PostgreSQL StatefulSet) workloads
harness/       fault injection, observation, and experiment orchestration
experiments/   dated experimental records with raw output
analysis/      data processing and figure generation
results/       run output (gitignored except for archived experiments)
docs/          methodology notes and threats to validity
```

---

## Related work

This study deliberately avoids two well-covered areas and targets what lies between them.

- **Barletta et al., DSN 2024.** *Mutiny! How does Kubernetes fail, and what can we do about
  it?* Bit-level corruption injected into the etcd datastore. 3% of injections caused
  cluster-wide failures, 24% caused service under/over-provisioning. **Datastore corruption is
  covered; we do not enter that territory.**
- **ACM ACSW 2026** (arXiv:2507.16109). Approximately 12,000 fault injections, 30 GB of data.
  Faults are container termination, pod elimination, network delay, packet loss and bandwidth
  throttling: **all data plane**. The authors identify control-plane testing as a gap in
  existing tooling and do not fill it.

Chaos Mesh, LitmusChaos, Gremlin and krkn are mature and free, and all are oriented toward
pod-level and network-level faults.

To the best of our knowledge, based on a systematic search of IEEE Xplore, ACM DL, Scopus and
arXiv in September 2026, no published study systematically injects **concurrent** control-plane
and data-plane faults and characterises the resulting recovery outcomes.

---

## Threats to validity

Stated in advance, and reported in the manuscript.

| Threat | Handling |
|---|---|
| Testbed is smaller than the production systems cited | Claims are tiered. Binary outcomes and relative comparisons are asserted as generalisable; **absolute timings are descriptive only** and explicitly disclaimed. |
| Faults are injected by stopping processes, not by reproducing production defects | Standard fault-injection practice. The effect under study, component unavailability, is reproduced faithfully. |
| Containers run inside a VM layer on macOS, adding timing variance | Minimum ten repetitions per configuration; medians and full distributions reported. |
| Passively cooled hardware may throttle during long runs | Thermal pressure logged per run; throttled runs flagged and excluded from timing analysis. |
| Managed Kubernetes users cannot apply findings directly | Target audience is self-managed, on-premise, telecommunications and edge operators who own their control plane. |

---

## Licence

MIT. See [LICENSE](LICENSE).

## Citing

See [CITATION.cff](CITATION.cff).
