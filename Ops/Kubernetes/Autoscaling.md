# Kubernetes

| Scaler | Scales | Trigger |
|---|---|---|
| **HPA** | pod replicas | CPU, memory, custom metrics |
| **VPA** | requests per pod | historical usage |
| **Cluster Autoscaler** | number of nodes | pods stuck Pending |
| **KEDA** | pod replicas (incl. 0) | events: queue depth, Kafka lag, cron, ... |

In practice: HPA + CA together constantly; VPA selectively.

## HPA

Control loop (~15s): `desiredReplicas = ceil(currentReplicas × currentMetric / targetMetric)`. 3 replicas at 90% CPU, 60% target → 5. Rounds up on purpose.

- **Utilization is measured against the pod's *request*** ([[Ops/Kubernetes/Pods]]), not node capacity — wrong requests break HPA's math. Needs **metrics-server** (else shows `<unknown>/60%`).
- **Multiple metrics**: uses whichever demands the *most* replicas.
- **Scale-up fast, scale-down slow** (default 5-min stabilization window) — shrink it aggressively and you get flapping.

## KEDA — event-driven autoscaling

**HPA is metric-driven, KEDA is event-driven.** Two gaps motivate this:

- **CPU/memory are lagging indicators** — by the time CPU hits 90% from 50k queued messages, you're already dropping requests. Queue depth predicts; CPU reflects.
- **HPA can't scale to zero** — it needs ≥1 pod alive just to have metrics, so idle workers still cost money.

KEDA: 50+ built-in scalers (SQS, Kafka, cron, ...) on the *source* event. It's an HPA operator underneath — at 0 replicas it feeds metrics itself, then hands off to a normal HPA. **Scale to zero** (`minReplicaCount: 0`) makes idle workers free; cold-start trade-off means keep `minReplicaCount: 1` for latency-sensitive services. (Alternative for custom signals: Prometheus + prometheus-adapter with plain HPA — still needs a pod alive.)

## VPA

Adjusts CPU/memory **requests** from observed usage, for workloads that can't scale horizontally. Modes: `Off` (recommendations only — start here), `Initial`, `Recreate`/`Auto`.

**Never combine VPA with HPA on CPU/memory** — VPA changes requests → changes HPA's utilization → changes replicas → changes VPA's recommendation. Unstable loop. Safe: HPA alone, VPA alone, or HPA on *custom* metrics + VPA.

## Cluster Autoscaler

Pods stuck `Pending` (no node capacity) → CA provisions a node, 2–5 min end to end (node boot dominates). Scales down after ~10 min underutilization if pods are drainable (respects PDBs, `safe-to-evict: "false"`). Picks the cheapest node group that fits, guided by affinity/selector constraints.

## Full flow

**HPA path**: spike → CPU rises → HPA adds replicas → pods Pending → CA adds nodes → traffic normalizes → HPA scales down → CA drains nodes.

**KEDA path**: messages arrive at the queue → KEDA sees queue depth rise → activates from 0 and creates the HPA → replicas scale with the backlog → queue drains → KEDA scales back to 0 → idle workers cost nothing (CA reclaims node capacity after the underutilization window).

**Scaling lags — plan for it**: HPA ~15–30s, pod startup 10–60s, node provisioning 2–5 min. Faster spikes need headroom (`minReplicas` at known peaks, pre-warming, fast startup).

Rules of thumb: `minReplicas >= 2` with anti-affinity, HPA + CA for stateless, KEDA + CA for queue consumers, VPA `Off` to right-size the rest.
