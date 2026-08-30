# Kubernetes — Pods and Scheduling

## Why Pods exist

The obvious design would be: Kubernetes schedules containers directly. So why wrap them in a Pod?

Because some workloads are naturally **multiple processes that must run together on the same machine** — a web server plus a sidecar that ships its logs, an app plus a proxy that intercepts its traffic. A Pod co-schedules such containers and gives them:

- **Shared network** — same IP and port space, reachable via `localhost`
- **Shared storage** — volumes defined at the Pod level, mounted into containers
- **Shared lifecycle** — scheduled together, land on the same node, die together

The Pod is the unit of scheduling; Kubernetes never splits one across nodes. A Pod is not a process — it's a sandbox; the containers inside it are the processes.

In practice you rarely create Pods directly — a controller (Deployment, StatefulSet, Job) creates them from a **pod template** in its spec.

## Pod lifecycle

High-level phases: `Pending` → `Running` → `Succeeded` / `Failed` (or `Unknown` if the node stops talking to the API server). Phases are coarse — they tell you roughly where the pod is, not why it's stuck.

For the "why", read **conditions** (`kubectl describe pod`):

- `PodScheduled` — a node was assigned (False = scheduling failure)
- `Initialized` — all init containers finished
- `ContainersReady` — all containers passed readiness probes
- `Ready` — pod can receive traffic

Running-but-not-Ready is usually a failing readiness probe. Pending-with-PodScheduled-False is a scheduling problem — the second half of this note.

Each container inside has its own state — `Waiting` (pulling image, waiting on init containers), `Running`, or `Terminated` (check `exitCode` and `reason`).

**Restart policy** (per pod): `Always` (default, for services), `OnFailure` (for Jobs), `Never` (one-shot).

## Probes

Health checks the kubelet runs against containers. Three types, each answering a different question:

- **Readiness** — "ready to serve traffic?" On failure: pod is pulled from the Service's endpoints, so it gets no new traffic. Container is **not restarted**. Use for: waiting on a DB connection, cache warmup, temporary overload.
- **Liveness** — "still functional?" On repeated failure: container is **restarted**. Use for deadlocks and stuck states where the process runs but does nothing useful.
- **Startup** — "finished starting up?" For slow-starting apps. While it runs, liveness and readiness are disabled; once it succeeds, they take over. Without it you'd need a huge `initialDelaySeconds` on liveness that would penalize every restart, not just the first.

The classic mistake is copy-pasting the same endpoint into both readiness and liveness. When an app is temporarily overloaded you want readiness to fail (stop traffic) but liveness to pass (don't restart it).

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

When a pod keeps restarting, the tuning knobs to check: `initialDelaySeconds` (enough time to start?), `failureThreshold` (too twitchy for transient blips?), `timeoutSeconds` (endpoint slow, not broken?), and whether a startup probe would fit better.

## Requests, limits, and QoS

Per container: **requests** = guaranteed minimum (what the scheduler uses), **limits** = ceiling. When exceeded:

- **CPU limit** → throttled (slowed, keeps running)
- **Memory limit** → OOMKilled (hard kill, no graceful shutdown)

That asymmetry matters: CPU pressure degrades, memory pressure kills.

Every pod gets a **QoS class** from its requests/limits, and that decides eviction order when a node runs short:

| QoS | Condition | Evicted |
|---|---|---|
| `Guaranteed` | requests == limits | last |
| `Burstable` | requests set, limits higher | middle |
| `BestEffort` | nothing set | first |

Stateful workloads should be `Guaranteed`; stateless services can be `Burstable`; nothing important should be `BestEffort`.

## Termination — how a pod shuts down

When a pod is deleted, in order:

1. Pod is removed from the Service's endpoints — **new traffic stops first**
2. `PreStop` hook runs (drain connections, deregister, flush)
3. `SIGTERM` is sent to the process
4. Wait up to `terminationGracePeriodSeconds` (default 30s) — this budget covers hook + SIGTERM handling combined
5. Still running? `SIGKILL`

Two consequences: if your app needs more than 30s to drain, raise the grace period; and if your app ignores SIGTERM, it gets hard-killed with no cleanup.

**Hooks**: `postStart` runs right after container creation — concurrently with the entrypoint, not after the app is ready. `preStop` runs before SIGTERM; keep it fast or it eats the whole grace budget.

## Init, sidecar, and ephemeral containers

- **Init containers** — run to completion, sequentially, before any app container starts. One failing blocks the rest. Use for: waiting on a DB, running migrations, pre-populating a shared volume. They have their own image, so your Go binary doesn't need `nc` installed — a busybox init container can do the waiting.
- **Sidecar containers** — run alongside the main container for the pod's whole life: log shipping, metrics, service-mesh proxies. Since K8s 1.29 they're native (`restartPolicy: Always` inside `initContainers`) and are guaranteed running before the main container starts.
- **Ephemeral containers** — bolted onto a *running* pod for debugging, mainly when your image is distroless and has no shell: `kubectl debug -it my-pod --image=busybox --target=my-container`.

---

# Scheduling — where a pod lands

The scheduler's one job: **for every Pod with no node assigned, pick the best node for it**. Two phases:

1. **Filter** — throw out nodes that *can't* run the pod (not enough memory, taint it doesn't tolerate, affinity rule not matched)
2. **Score** — rank the nodes that survived and pick the winner (prefer less-loaded nodes, keep pods spread out)

If no node passes filtering, the pod sits in `Pending`. When a pod is `Pending`, the answer is almost always in `kubectl describe pod` → Events section.

## Resource requests — the foundation

The scheduler uses **requests, not limits**, to decide if a pod fits on a node. A node "fits" a pod if its allocatable resources minus all existing requests still cover the pod's request.

- **Capacity vs allocatable**: a 4-CPU node doesn't offer 4 CPUs to pods — the OS and kubelet reserve a cut. The scheduler works with *allocatable* (`kubectl describe node` shows both).
- **No requests set** = pod looks like it needs zero resources, gets placed anywhere (usually an already-busy node), then gets throttled or OOMKilled. Always set requests.
- **Requests are a promise, limits are a cap**: if you request 100m but limit at 4000m, the scheduler packs many such pods on one node and they all try to burst at once. Keep requests realistic.

## Taints and tolerations — nodes repel pods

A **taint** on a node says "stay away unless you're okay with this". A **toleration** on a pod says "I'm okay with that".

```bash
# taint a node (dedicate it to GPU work)
kubectl taint nodes gpu-node-1 gpu=true:NoSchedule

# remove it (trailing -)
kubectl taint nodes gpu-node-1 gpu=true:NoSchedule-
```

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

| Effect | Behaviour |
|---|---|
| `NoSchedule` | Don't place new pods here without a toleration |
| `PreferNoSchedule` | Try to avoid, but use if nothing else |
| `NoExecute` | Don't place new pods **and evict** existing intolerant pods |

Where you've already seen this: control-plane nodes carry a built-in taint so app pods never land on them, and when a node goes `NotReady`, Kubernetes adds a `NoExecute` taint that evicts pods after a grace period.

## Node affinity — pods pick nodes

Taints are the node pushing pods away; node affinity is the pod pulling toward nodes, matched on **node labels**.

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

Places pods based on where **other pods** are, matched on pod labels. `topologyKey` defines "near": `kubernetes.io/hostname` = same node, `topology.kubernetes.io/zone` = same AZ.

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

Gotcha worth remembering: `required` anti-affinity with 5 replicas and 4 nodes means the 5th pod is Pending forever. Use `preferred` for best-effort spreading.

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

A PDB says how many pods of a service must stay up during **voluntary** disruptions — node drains, upgrades, admin evictions. (Involuntary ones — crashes, OOM kills — are not its business.)

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

## PriorityClass — who goes first

When the cluster is full, priority decides who schedules first and who gets **preempted** (evicted to make room). Higher value = higher priority.

```yaml
spec:
  priorityClassName: high-priority
```

System components use built-in classes (`system-cluster-critical`, `system-node-critical`) with values around 2 billion — never set app priorities above those.

## ResourceQuota and LimitRange — namespace guardrails

For shared clusters, per namespace:

- **ResourceQuota** caps the totals — sum of CPU/memory requests, pod count, etc. Side effect: once a quota exists, pods *must* set requests/limits or they're rejected.
- **LimitRange** fills in defaults (so pods without explicit requests get sane ones) and sets per-container min/max so one pod can't request 100 CPUs.

Together: quota keeps teams from starving each other, LimitRange makes the quota's requirement painless.

## Big picture

Scheduling is just constraints: **requests** say what a pod needs, **taints/affinity** say where it may go, **spread constraints** say how it should be distributed, **PDBs** protect it during drains, **priority** breaks ties when there isn't room. Debugging almost always starts at `kubectl describe pod` → Events.

Related: [[Ops/Kubernetes/Foundations]] · [[Ops/Kubernetes/Workloads]] · [[Ops/Kubernetes/Autoscaling]]
