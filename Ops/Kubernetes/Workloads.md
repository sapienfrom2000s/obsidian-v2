# Kubernetes — Workloads

You almost never create Pods directly — they're too low-level. Workload resources manage Pods for you, each matched to the nature of the app:

| Workload      | Use when                                                                                    |
| ------------- | ------------------------------------------------------------------------------------------- |
| `Deployment`  | Stateless long-running services — the default choice                                        |
| `StatefulSet` | Stateful apps needing stable identity, storage, or ordering                                 |
| `DaemonSet`   | Exactly one pod per node — log collectors, monitoring agents, CNI. Multiple can be present. |
| `Job`         | Run a task once to completion                                                               |
| `CronJob`     | Run a task on a schedule                                                                    |
## Deployment

A **Deployment** is the Kubernetes API resource you use to declare the desired state for a stateless app. Under the hood, the **Deployment Controller** watches this spec in `etcd` and drives the cluster toward that state by managing ReplicaSets to deliver rolling updates, self-healing, and scaling.

### Max Surge and Max unavailable

- **maxSurge** — extra pods allowed *above* the desired count during the update. More surge = faster rollout, more resources.
- **maxUnavailable** — pods allowed to be down during the update. Lower = safer, slower.

## ReplicaSet — the pod count enforcer

A **ReplicaSet** sits between a Deployment and a Pod in the abstraction hierarchy. While a Deployment handles the high-level orchestration of _how_ applications roll out or update, the **ReplicaSet Controller** handles the low-level execution of keeping the actual count of identical Pods stable.
## StatefulSet

Unlike a Deployment, which relies on a ReplicaSet to manage identical pods in parallel, a **StatefulSet** interacts with the control plane to manage Pods **directly**. The **StatefulSet Controller** enforces a strict sequential ordering during creation and deletion, and uses a _VolumeClaimTemplate_ to automatically provision and bind a specific PersistentVolumeClaim (PVC) to each individual Pod ordinal.

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

Unlike a Deployment, where you request a specific _replica count_ (e.g., 3 pods) and the scheduler places them anywhere, a **DaemonSet** ignores total count and binds pod topology directly to **node membership**. The **DaemonSet Controller** watches the node pool and automatically appends node affinity and tolerations to place exactly one instance on every matching node, including control plane nodes if tolerations permit.

One daemonset exactly spawns 1 pod.

## Job and CronJob

A **Job** runs one or more Pods to complete a specific task and then stops. The **Job Controller** tracks when the task is done, can run multiple Pods in sequence or at the same time, and automatically retries any Pods that fail.

A **CronJob** runs a **Job** on a set schedule. The **CronJob Controller** checks the timer (like _"every night at midnight"_), starts a new Job when the time comes, and ensures old runs don't overlap with new ones.



