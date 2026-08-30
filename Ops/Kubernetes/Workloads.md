# Kubernetes — Workloads

You almost never create Pods directly — they're too low-level. Workload resources manage Pods for you, each matched to the nature of the app:

| Workload | Use when |
|---|---|
| `Deployment` | Stateless long-running services — the default choice |
| `StatefulSet` | Stateful apps needing stable identity, storage, or ordering |
| `DaemonSet` | Exactly one pod per node — log collectors, monitoring agents, CNI |
| `Job` | Run a task once to completion |
| `CronJob` | Run a task on a schedule |

## ReplicaSet — the pod count enforcer

Ensures N identical pods are running: crash → replacement, scale down → excess deleted. But **you never create one directly** — a Deployment creates and manages ReplicaSets for you, adding rollout, rollback, and history on top.

The relationship: a Deployment owns one or more ReplicaSets. One is current (replicas > 0); ReplicaSets from previous rollouts are kept around scaled to zero — kept specifically so `rollout undo` is possible (`revisionHistoryLimit`, default 10, controls how many).

## Deployment

### What triggers a rollout?

Any change to `.spec.template` (the pod template) — image, env vars, pod labels. Changing `spec.replicas` only scales the existing ReplicaSet; no rollout.

### Strategies and the two knobs

- **RollingUpdate** (default) — old pods die as new ones become ready
- **Recreate** — kill all, then create all. Downtime, but necessary when two versions can't coexist (e.g. conflicting DB schema migrations)

RollingUpdate pace is set by two fields, respected **simultaneously**:

- **maxSurge** — extra pods allowed *above* the desired count during the update. More surge = faster rollout, more resources.
- **maxUnavailable** — pods allowed to be down during the update. Lower = safer, slower.

With `replicas=10, maxSurge=2, maxUnavailable=1`: availability never drops below 9. With `maxSurge=2, maxUnavailable=0`: new pods are fully created and Ready before any old pod dies — never below 10, but needs spare capacity. With `maxSurge=0, maxUnavailable=2`: no extra capacity needed, but availability dips to 8.

### Rollouts and rollbacks

```bash
kubectl rollout status deployment/my-app        # watch progress
kubectl rollout history deployment/my-app       # revisions
kubectl rollout undo deployment/my-app          # back to previous (--to-revision=2 for specific)
kubectl rollout pause / resume deployment/my-app
```

A rollback is just scaling the old ReplicaSet up and the current one down — which is why old ReplicaSets are kept. Pause/resume gives manual canary control: while paused, both versions run and take traffic, nothing progresses until resume.

If a rollout stalls (failing readiness probes, Pending pods, image pull failures), it doesn't auto-rollback — after `progressDeadlineSeconds` (default 600s) the Deployment is marked stalled and undo is on you.

## StatefulSet

For apps needing **stable, persistent identity**: databases, message queues, distributed systems.

| | Deployment | StatefulSet |
|---|---|---|
| Pod names | Random suffix | Stable ordinal: `mysql-0`, `mysql-1` |
| Pod DNS | None per pod | Stable DNS per pod (via headless Service) |
| Storage | Shared or none | One PVC per pod, reattached on restart |
| Startup/shutdown | Parallel | Ordered 0→1→2 / reverse |

**Stable identity**: replaced pods keep their name. Combined with a **headless Service** (`clusterIP: None`), each pod gets its own DNS entry (`mysql-0.mysql.production.svc.cluster.local`) — that's how replicas find each other and how you address the master directly. A regular Service's DNS resolves to one ClusterIP and load-balances; you can't address individual pods through it.

**Stable storage**: `volumeClaimTemplates` creates one PVC per pod (`data-mysql-0`, `data-mysql-1`, ...). Delete `mysql-1` and its replacement gets the same name *and* the same volume rebound.

**Ordering**: pods start 0→1→2 (each Ready before the next), terminate and update in reverse. Matters for databases — replicas up before master, master drained last.

Kubernetes doesn't decide which pod is the master; that's application-level (MySQL replication config). The usual pattern: a `mysql-master` Service selecting `mysql-0`, a `mysql-replica` Service selecting the rest.

Don't use StatefulSets everywhere — slower rollouts, strict ordering, more operational weight. Reach for them only when you genuinely need stable identity or per-pod storage.

## DaemonSet

Exactly one pod per node (or a labelled subset). New node joins → pod appears on it; node leaves → pod is garbage collected. Use cases: log shippers, node exporters, CNI plugins, security agents.

Note the connection to [[Ops/Kubernetes/Pods]]: control-plane nodes carry a `NoSchedule` taint, so infrastructure DaemonSets add a toleration for `node-role.kubernetes.io/control-plane` to also run there. `nodeSelector`/affinity restricts to a subset (e.g. GPU nodes only).

## Job and CronJob

**Job** — run pods to *successful completion*, no restarts:

```yaml
spec:
  completions: 5        # successes needed
  parallelism: 2        # running simultaneously
  backoffLimit: 4       # retries before Failed
  activeDeadlineSeconds: 300   # hard kill regardless of state
```

`completions=5, parallelism=2` = run 2 at a time until 5 total successes. `backoffLimit` retries with exponential backoff; `activeDeadlineSeconds` overrides everything — a job stuck past its deadline is killed even mid-retry. The pod's `restartPolicy` must be `OnFailure` or `Never`, never `Always`.

**CronJob** — creates Jobs on a cron schedule (`"0 2 * * *"` = daily 2am; `timeZone` supported since 1.27). The field that matters most is **concurrencyPolicy**:

- `Allow` (default) — fire regardless; long-running jobs pile up
- `Forbid` — skip if the previous is still running (the safe default for backups)
- `Replace` — kill the running job, start fresh

`startingDeadlineSeconds` handles missed schedules (controller down, cluster unavailable): within the deadline, the job starts late; outside it, the run is skipped. Set it generously unless you have a reason not to.

## Big picture

Deployment → ReplicaSet → Pods is the ownership chain in action (see [[Ops/Kubernetes/Foundations]]); every other workload is a variation on "what does 'done' or 'stable' mean for this app" — long-running and stateless (Deployment), stable identity (StatefulSet), one-per-node (DaemonSet), runs-to-completion (Job/CronJob).

Related: [[Ops/Kubernetes/Foundations]] · [[Ops/Kubernetes/Pods]]
