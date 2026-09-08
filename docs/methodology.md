# Methodology notes

## Claims tiering

Testbed scale is smaller than the production systems cited in the motivation. Claims are
therefore tiered explicitly, and this tiering is stated in the manuscript before results are
presented.

| Tier | Example | Asserted as generalisable? |
|---|---|---|
| Architectural / binary | "Pods deleted during a controller-manager outage are not replaced" | Yes |
| Ordinal / relative | "Three control-plane nodes recover faster than one" | Yes |
| Trend | "Recovery time grows with node count" | Yes, where a scale sweep supports it |
| Absolute timing | "Recovery took 47 seconds" | **No. Descriptive only.** |

Absolute timings will not transfer to production: object counts, API load and thundering-herd
dynamics all differ at scale, and containers on macOS run inside a VM layer that adds variance.

## Experimental design

A full factorial design across all faults, durations, configurations and workloads requires
approximately 960 runs, which exceeds the compute budget. A fractional design is used instead.

| Condition | Fault coverage | Runs |
|---|---|---|
| Primary: 3 control-plane nodes, stateless | Full matrix | 160 |
| Stateful workload | Core subset | 60 |
| Single control-plane node | Core subset | 60 |
| Tuned leader-election timeouts | Core subset | 60 |
| **Total** | | **~340** |

Minimum ten repetitions per configuration. Medians and full distributions reported, never
single values.

At approximately eight minutes per complete run cycle, the budget is roughly 45 hours,
executed in overnight batches.

## Staging

Each stage from Stage 2 onward yields a self-contained result set, so a delay in a later stage
narrows the contribution without eliminating it.

| Stage | Dates | Activity |
|---|---|---|
| 0 | Sep 9 to Sep 15 | Environment, premise validation, repository setup |
| 1 | Sep 16 to Oct 3 | Literature review and gap consolidation (Cutoff 2) |
| 2 | Oct 4 to Oct 20 | Harness, metrics pipeline, primary condition runs |
| 3 | Oct 21 to Nov 2 | Compound and stateful experiments (Cutoff 3) |
| 4 | Nov 3 to Nov 17 | Gray failure, mitigations, complete draft (Day 80) |
| 5 | Nov 18 to Dec 7 | Revision, poster, submission, defence |

## Excluded from scope

Deliberately not attempted, with reasons.

- **etcd data corruption.** Covered authoritatively by Barletta et al. (DSN 2024).
- **Machine-learning failure prediction.** Training a detector on faults we inject ourselves is
  circular; the non-circular alternative requires production telemetry over months.
- **Externally triggered failover infrastructure.** Building a health-checking load balancer
  with failover logic is a systems engineering project, not a treatment arm.

## Search protocol for the gap claim

Databases: IEEE Xplore, ACM Digital Library, Scopus, arXiv (cs.DC, cs.SE).

Query terms: kubernetes AND (fault injection OR chaos engineering) AND (control plane OR
resilience OR recovery).

The claim is stated as bounded and dated, never as an absolute absence. Standing alerts are
configured on arXiv cs.DC and cs.SE, and Google Scholar citation alerts track the Mutiny and
ACSW papers. The search is repeated within one week of submission and the date recorded.
