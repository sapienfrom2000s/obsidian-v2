# Kubernetes — Pods and Scheduling

## Pods

A _Pod_ is a group of one or more containers, with shared storage and network resources, and a specification for how to run the containers.

- **Shared network** — same IP and port space, reachable via `localhost`
- **Shared storage** — volumes defined at the Pod level, mounted into containers
- **Shared lifecycle** — scheduled together, land on the same node, die together

## Pod lifecycle

**Pod Lifecycle Phases:**

- **Pending** – Pod accepted by cluster, but containers not yet running (image pull, scheduling in progress)
- **Running** – Pod bound to node, all containers created, at least one running/starting
- **Succeeded** – All containers terminated successfully (exit 0), won't restart
- **Failed** – All containers terminated, at least one failed (non-zero exit)
- **Unknown** – State can't be determined (node communication issue)

**Container States (within Pod):**

- **Waiting** – Not running yet (pulling image, applying secrets, etc.)
- **Running** – Executing, no problems
- **Terminated** – Completed execution or failed

**Restart Policy** (controls container-level restarts):

- `Always` (default) – always restart
- `OnFailure` – restart only on non-zero exit
- `Never` – never restart

### Termination Flow

1. Pod marked `Terminating` (deletion timestamp set)
2. **In parallel:**
    - Pod removed from **Service Endpoints/EndpointSlices** (so no new traffic routed to it)
    - `preStop` hook executed (if defined)
    - `SIGTERM` sent to containers
3. Grace period (default 30s) — container should shut down gracefully
4. `SIGKILL` sent if still running after grace period

## Probes

- **Readiness** — "ready to serve traffic?" On failure: pod is pulled from the Service's endpoints, so it gets no new traffic. Container is **not restarted**. Use for: waiting on a DB connection, cache warmup, temporary overload.
- **Liveness** — "still functional?" On repeated failure: container is **restarted**. Use for deadlocks and stuck states where the process runs but does nothing useful.
- **Startup** — "finished starting up?" For slow-starting apps. While it runs, liveness and readiness are disabled; once it succeeds, they take over. Without it you'd need a huge `initialDelaySeconds` on liveness that would penalize every restart, not just the first.

Do not copy the same endpoint into both readiness and liveness. When an app is temporarily overloaded you want readiness to fail (stop traffic) but liveness to pass (don't restart it).

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 1
  failureThreshold: 3
```

Three handler types: `httpGet` (success = 2xx/3xx), `exec` (success = exit 0), `tcpSocket` (success = connection opens).

## Init, sidecar, and ephemeral containers

- **Init containers** — run to completion, sequentially, before any app container starts.
- **Sidecar containers** — run alongside the main container for the pod's whole life: log shipping, metrics, service-mesh proxies.
- **Ephemeral containers** — for debugging, mainly when your image is distroless and has no shell: `kubectl debug -it my-pod --image=busybox --target=my-container`.

## Requests, limits, and QoS

Per container: **requests** = guaranteed minimum, **limits** = ceiling. When exceeded cpu is throttled and OOMkilled respectively.

Instead of setting QoS directly, Kubernetes assigns a QoS class to your Pod based on how you configure its `requests` (minimum guaranteed resources) and `limits` (maximum allowed resources). QoS comes into picture when deciding which pod to be evicted under node pressure.

| QoS          | Condition                     | Evicted |
| ------------ | ----------------------------- | ------- |
| `Guaranteed` | requests == limits            | last    |
| `Burstable`  | requests < limit              | middle  |
| `BestEffort` | requests == 0 and limits == 0 | first   |

Stateful workloads should be `Guaranteed`; stateless services can be `Burstable`; nothing important should be `BestEffort`.

## PriorityClass — who goes first

When the cluster is full, priority decides who schedules first and who gets **preempted** (evicted to make room). Higher value = higher priority.

```yaml
spec:
  priorityClassName: high-priority
```

System components use built-in classes (`system-cluster-critical`, `system-node-critical`) with values around 2 billion — never set app priorities above those.

Q. **Which Pod gets evicted to free up capacity for scheduling?**
A. **PriorityClass** decides (handled by `kube-scheduler`).

Q. **When pod is already running and node runs out of memory?**
A. **QoS Class** decides (handled by `kubelet` / Linux kernel).

# Scheduling — where a pod lands

The scheduler picks a node for every Pod that doesn't have one yet. First it **filters out** nodes that can't work — not enough memory, a taint the pod doesn't tolerate, etc. Then it **scores** the remaining nodes and picks the best one — usually the least busy or one that keeps pods spread out. If no node passes the filter, the Pod stays stuck in `Pending`, and `kubectl describe pod` (Events section) will tell you why.

## Resource requests

The scheduler uses **requests, not limits**, to decide if a pod fits on a node. A node "fits" a pod if its allocatable resources minus all existing requests still cover the pod's request.

- **Capacity vs allocatable**: a 4-CPU node doesn't offer 4 CPUs to pods — the OS and kubelet reserve a cut. The scheduler works with *allocatable* (`kubectl describe node` shows both).
- **No requests set** = pod looks like it needs zero resources, gets placed anywhere (usually an already-busy node), then gets throttled or OOMKilled. Always set requests.
- **Requests are a promise, limits are a cap**: if you request 100m but limit at 4000m, the scheduler packs many such pods on one node and they all try to burst at once. Keep requests realistic.

## Taints and tolerations — nodes repel pods

Taint node and tolerate in pods to make it schedulable to tainted node.

```yaml
# pod that is allowed on the tainted node
spec:
  tolerations:
  - key: "gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
```

Three effects:

| Effect             | Behaviour                                                   |
| ------------------ | ----------------------------------------------------------- |
| `NoSchedule`       | Don't place new pods here without a toleration              |
| `PreferNoSchedule` | Try to avoid, but use if nothing else                       |
| `NoExecute`        | Don't place new pods **and evict** existing intolerant pods |

Where you've already seen this: control-plane nodes carry a built-in taint so app pods never land on them, and when a node goes `NotReady`, Kubernetes adds a `NoExecute` taint that evicts pods after a grace period.

## Node affinity — pods pick nodes

Node affinity is configured on pods to control which **nodes** they can run on. relies on **labels** attached to nodes

- `requiredDuringSchedulingIgnoredDuringExecution` — hard: no matching node, pod stays Pending
- `preferredDuringSchedulingIgnoredDuringExecution` — soft: weighted preference, scheduling never blocks

```yaml
spec:
  nodeSelector:          # simple version: exact label match
    node-type: gpu
```


`nodeSelector` is the shorthand for simple cases; full `nodeAffinity` buys you operators (`In`, `NotIn`, `Exists`) and soft preferences. "IgnoredDuringExecution" means it only matters at scheduling time — label changes later don't evict running pods.

**Taints vs affinity**: for dedicated nodes you typically need *both* — taint keeps everyone else off, affinity makes sure your workload actively goes there. Taint alone doesn't guarantee your pod lands on that node.

## Pod affinity / anti-affinity — pods relative to pods

Places pods based on where **other pods** are, matched on pod labels.

- **Affinity**: co-locate. "Run my app pods on the same node as the cache pod" — when they talk constantly.
- **Anti-affinity**: spread. "No two replicas of my app on the same node" — so one node failure can't kill the whole service.

```yaml
spec:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app: my-app
          topologyKey: kubernetes.io/hostname
```


### Pod vs Node affinity

- **Node Affinity** binds a Pod to a **Node** based on node characteristics (e.g., _"Put this Pod on a node with an SSD"_).

- **Pod Affinity** binds a Pod to **other Pods** based on workload proximity (e.g., _"Put this Pod on the same machine/zone as the Cache Pod"_).

## Topology spread constraints

Anti-affinity only says "not together"; it doesn't balance. Spread constraints do: `maxSkew: 1` across nodes with 6 pods gives 2-2-2, with 7 gives 3-2-2.

```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway   # soft; DoNotSchedule = hard
    labelSelector:
      matchLabels:
        app: my-app
```

For "spread my replicas evenly" this replaces anti-affinity — it's the better tool for that job.

## PodDisruptionBudget — survive drains

The point of a **Pod Disruption Budget (PDB)** is to prevent voluntary cluster actions like node drains, upgrades, or cluster autoscaling from taking down so many Pods at once that your application goes offline.

A PDB says how many pods of a service must stay up during **voluntary** disruptions node drains, upgrades, admin evictions. (Involuntary ones crashes, OOM kills are not its business.)

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 2        # or maxUnavailable: 25%
  selector:
    matchLabels:
      app: my-app
```

During `kubectl drain`, Kubernetes evicts pods one at a time, waiting for replacements to become Ready so the budget is never violated. If `minAvailable` equals your replica count, no eviction can ever proceed and the drain hangs — always leave at least one pod of slack.




