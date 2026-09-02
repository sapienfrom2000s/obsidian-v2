# Kubernetes — Foundations

*Why it exists, the object model, and the machinery that runs it.*

## Why do we need it?

k8s is a framework for container orchestration. It provides zero-downtime deployments, self-healing, autoscaling, built-in service discovery, declarative state system, plugins and has a massive ecosystem.

### Without K8s

- ALB + EC2 can be used but you are working at instance level and not at container level which might lead to lot of wastage of resources.
- How do you autoscale an application on container level across the nodes?
- It will lead to a lot of glue code if your application is massive and you are not using a proper container orchestration system.
- Rollout of new application will be hard.

### Limitations

- Steep learning curve
- Overkill for small scale apps
- Not suitable for AI workloads
- Requires a strong team to manage it
## The object model

Every object has two halves:

- **spec** — desired state. You write it.
- **status** — current state. Kubernetes writes it.

The system runs a **reconciliation loop**: watch for drift between the two, act to close the gap, repeat forever. 

### The four top-level fields

```yaml
apiVersion: apps/v1        # which schema version to validate against (group/version)
kind: Deployment           # the object type
metadata:                  # identity: name, namespace, labels, annotations
  name: nginx-deployment
  labels:
    app: nginx
spec:                      # desired state — you write this
  replicas: 2
```

There's a fifth you see in responses but never write: `status`, filled in by Kubernetes.

### Labels, selectors, annotations

- **Labels:** Identifying key-value pairs attached to objects (e.g., `environment: production`, `app: payment-api`). They are indexed, queryable, and define object identity.

- **Selectors:** The search queries used by Kubernetes objects (Services, Deployments, NetworkPolicies) to target specific resources based on their **Labels**.

- **Annotations:** Non-identifying, unindexed key-value metadata attached to objects for external tools, ingress controllers, or build pipelines (e.g., `prometheus.io/scrape: "true"`).

### Imperative vs declarative

- **Imperative** (`kubectl create deployment ...`) — fast for one-offs and debugging. Not repeatable, not Git-friendly.
- **Declarative** (`kubectl apply -f`) — the production standard. Works whether the object exists or not; computes a three-way diff (last applied, live state, new config) and changes only what differs. Idempotent, Git-friendly, CI/CD-friendly.

**`apply` vs `replace`**: `replace` swaps the whole object — can cause downtime and wipes controller-set fields. `apply` does a surgical merge. Prefer `apply`. (One trap: `apply` stores last-applied config as an annotation — mixing `apply` with `edit`/`replace` desyncs it and produces surprise diffs.)

### Namespaces

Namespaces partition a cluster logically — one per team or environment. RBAC, NetworkPolicies, and ResourceQuotas all attach per namespace. Cluster-scoped resources ignore namespaces: Nodes, PersistentVolumes, ClusterRoles. The four you get out of the box: `default`, `kube-system`, `kube-public`, `kube-node-lease`.

### Owners and finalizers

**Ownership** — objects track their parent via `ownerReferences`, forming the chain Deployment → ReplicaSet → Pods. Delete the Deployment and garbage collection cascades down the chain.

**Finalizers** — A **finalizer** is an array in `metadata.finalizers` listing cleanup tasks required before an object can be erased from the database (etcd). When you run `kubectl delete`, Kubernetes sees items in this array, pauses deletion, and sets a `deletionTimestamp` (status: **Terminating**). Controllers perform their cleanup, remove their entry from the array, and Kubernetes permanently deletes the object only once the array is completely empty.

## Cluster components

A cluster is two kinds of machines: the **control plane** (the brain — manages state, schedules, reconciles; never runs your workloads) and **worker nodes** (the muscle — run your pods).

### Control plane

kube-apiserver
etcd
controller-manager
scheduler

### Worker node

**kubelet — the node agent.** The bridge between the API server and the container runtime. It registers the node on startup, watches for pods assigned to *its* node, tells the runtime to start/stop containers via **CRI**, runs the probes, and reports status back. It doesn't care whether the runtime is containerd or CRI-O — anything that speaks CRI works.

**kube-proxy.** Programs iptables/IPVS rules on the node so traffic to a Service's ClusterIP reaches a backing pod.

**Container runtime.** Pulls images, creates the namespaces/cgroups, runs the processes. Docker as a runtime was removed in K8s 1.24 — but Docker-*built* images still work fine, since the OCI image format is separate from the CRI runtime interface.

### Pod creation — the full flow

`kubectl create -f pod.yaml`:

1. kubectl POSTs to the API server → auth, admission → pod object written to etcd with `nodeName: ""`
2. Scheduler sees the unbound pod, filter+scores, PATCHes `nodeName: "node-2"`
3. Kubelet on node-2 sees a pod assigned to it → starts containers via CRI
4. Kubelet PATCHes pod status to Running

### Node health and what happens when a node dies

Kubelet sends two heartbeats: a lightweight **Lease** object every 10s ("I'm alive") and a heavier full status update every 40s. Two-tier by design — full status every 10s at thousands of nodes would flood etcd.

When a node dies: **T+0** heartbeats stop → **~T+40s** Node Controller notices, marks node `Unknown` → **T+5min (default)** pods marked `Terminating`, replacements scheduled elsewhere. The 5-minute wait is deliberate: the "dead" node might just be partitioned and its containers still running — evicting immediately would risk two copies of the same pod. Practical consequence: **if a node dies, expect ~5 minutes before your pods are rescheduled.** Stateful pods with RWO volumes can take even longer.

### High availability

- **API server**: stateless, run many replicas behind a load balancer
- **etcd**: 3 or 5 nodes, Raft, odd numbers
- **controller-manager & scheduler**: only **one active instance at a time** even with multiple replicas — leader election (via a Lease object) picks the leader, others hot-standby. This prevents split-brain: two schedulers assigning the same node to different pods.


