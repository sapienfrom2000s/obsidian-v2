# Kubernetes — Autoscaling

Static sizing is wrong in both directions: sized for peak you overpay 23 hours a day; sized for average you fall over during spikes. Three autoscalers fix this at different levels:

| Scaler | Scales | Trigger |
|---|---|---|
| **HPA** | pod replicas | CPU, memory, custom metrics |
| **VPA** | CPU/memory requests per pod | historical usage |
| **Cluster Autoscaler** | number of nodes | pods stuck Pending |

In practice: HPA + Cluster Autoscaler together constantly; VPA selectively.

## HPA — Horizontal Pod Autoscaler

A control loop (~every 15s) that fetches metrics, computes the desired replica count, and writes it to the Deployment:

```
desiredReplicas = ceil(currentReplicas × currentMetric / targetMetric)
```

3 replicas at 90% CPU with a 60% target → ceil(3 × 1.5) = 5. It rounds up — over-provisioning beats under-provisioning.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef:
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
```

The details that matter:

- **Utilization is measured against the pod's *request*, not node capacity.** A pod requesting 500m and using 300m is at 60%. Wrong requests → HPA scales at the wrong thresholds — which is why accurate requests ([[Ops/Kubernetes/Pods]]) are a prerequisite for HPA working at all. It also needs **metrics-server** installed (pre-installed on most managed clusters; without it HPA shows `<unknown>/60%`).
- **Multiple metrics**: HPA evaluates all of them and uses the one demanding the *most* replicas. CPU says 6, memory says 4 → scale to 6.
- **Scale-up fast, scale-down slow** — deliberate, to prevent oscillation. The key knob is the down stabilization window (default 5 min of sustained low load before removing pods); shrink it aggressively and you get flapping.

## Custom metrics and KEDA

CPU/memory covers stateless request-serving apps. Product-shaped signals — queue depth, Kafka consumer lag, WebSocket connections — need more:

- **Custom metrics** via Prometheus + prometheus-adapter: HPA scales on e.g. `http_requests_per_second` per pod.
- **KEDA** is the modern standard for this: 50+ built-in scalers (SQS, Kafka, cron, ...) without running your own adapter, and one feature plain HPA can't offer — **scale to zero** (`minReplicaCount: 0`), so idle batch workers cost nothing and wake when work arrives. Trade-off: cold start (schedule + image pull + startup), so keep `minReplicaCount: 1` for latency-sensitive services.

## VPA — Vertical Pod Autoscaler

Scales pods *up* instead of out: adjusts CPU/memory **requests** based on observed usage. Use when you don't know the right requests, or the workload can't scale horizontally (single-instance stateful apps). Modes: `Off` (recommendations only — start here to audit right-sizing), `Initial`, `Recreate`/`Auto` (evicts and recreates pods with new requests).

**The conflict rule**: never run VPA together with HPA on CPU/memory — VPA changes requests, which changes HPA's utilization math, which changes replicas, which changes VPA's recommendation. Unstable loop. Safe combos: HPA alone, VPA alone, or HPA on **custom** metrics + VPA.

## Cluster Autoscaler — scaling the nodes

HPA can create replicas, but if there's no node capacity the pods sit `Pending`. CA watches for exactly that:

- **Scale up**: pods Pending due to resources → simulate which node group fits → provision → 2–5 minutes end to end, dominated by node boot.
- **Scale down**: nodes underutilized for ~10 min (default) and whose pods can be drained elsewhere — respecting PDBs and `safe-to-evict: "false"` annotations — get cordoned, drained, terminated. Conservative by design.

Works across node groups (standard / high-mem / GPU), picking the cheapest group that fits the pending pod, guided by the pod's affinity/selector constraints (ties back to [[Ops/Kubernetes/Pods]]).

## The full flow

Traffic spike → HPA raises replicas → new pods Pending (no capacity) → CA provisions nodes → pods schedule → traffic normalizes → HPA scales down → CA drains and removes nodes after the underutilization window.

**Scaling has a lag — plan for it**: HPA reaction ~15–30s, pod startup 10–60s, node provisioning 2–5 min. Traffic that spikes faster than that needs headroom: higher `minReplicas` at known peaks, pre-warming, faster container startup.

Rules of thumb for production: `minReplicas >= 2` with anti-affinity (one pod = one restart away from an outage), HPA + CA for stateless services, KEDA + CA for queue consumers, VPA in `Off` mode to right-size everything else.

## Big picture

Three levels, one system: **HPA** matches pods to load, **CA** matches nodes to pods, **VPA** matches requests to reality. Each feeds the next — and all of them are only as good as the resource requests underneath.

Related: [[Ops/Kubernetes/Workloads]] · [[Ops/Kubernetes/Pods]]
