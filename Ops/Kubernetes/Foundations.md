# Kubernetes — Foundations

*Why it exists, the object model, and the machinery that runs it.* ([[Ops/Kubernetes/Index|↑ index]])

## Why do we need it?

Docker solves "run this app anywhere". But a container by itself is a lone process on one machine, and real production systems are neither one container nor one machine. The gap between Docker and production is what Kubernetes fills:

- **One machine is a single point of failure.** If the host running your app dies, Docker gives you no story for running that app elsewhere.
- **Manual operations don't scale.** "Log into server 7, run docker run, hope it works" breaks down past a handful of services, machines, and deploys per day.
- **Traffic goes up and down.** Nothing in Docker adds or removes containers based on load.

Kubernetes' answer: give it a cluster of machines and a description of what you want ("3 copies of this image, restarted if they die, reachable on port 80"), and it continuously drives reality toward that description. You declare state; the cluster maintains it.

What that buys you: **self-healing**, **scale out**, **rolling updates & rollback**, **bin packing** (which machine runs what), **service discovery & load balancing**, **config & secrets as API objects**, and **one API for a fleet** — the same whether you run 3 machines or 3000.

In one line: **Docker packages your app; Kubernetes runs the fleet.**

### Limitations (know them up front)

- **Steep learning curve.** Pods, Services, Deployments, Ingress, RBAC — a large vocabulary before "hello world" feels comfortable.
- **Operational weight.** Even managed control planes need patching, upgrades, and someone on call. A small team may get more pain than value from self-hosting.
- **Overkill for small systems.** A couple of low-traffic services run fine with plain Docker or a PaaS.
- **Not a drop-in security solution.** Out of the box everything in the cluster can reach everything — see [[Ops/DevSecOps/Kubernetes Security]].
- **Stateful work is awkward.** Databases want stable disks and identities; Kubernetes can do it but it's clunkier, a common reason to run databases outside the cluster.
- **It runs containers, it doesn't build them.** You still need CI/CD to produce images.

## The object model — spec vs status

A Kubernetes object is a **persistent record of intent**: "I want this thing to exist, in this state." Defined in YAML, sent to the API server, stored in etcd — and then Kubernetes works continuously to make reality match it.

Every object has two halves:

- **spec** — desired state. You write it.
- **status** — current state. Kubernetes writes it.

The system runs a **reconciliation loop**: watch for drift between the two, act to close the gap, repeat forever. You set `replicas: 3`; a pod crashes and status drops to 2; the controller notices and creates a replacement. It never stops watching. This is what "declarative" means here: you declare the outcome, Kubernetes figures out the how — continuously, not once.

Objects are passive data; **controllers** are what act on them. Every core kind has a dedicated controller — and this is also how custom resources work (see [[Ops/Kubernetes/CRDs and Operators]]).

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

**Labels** are key-value identity tags — indexed, queryable — and Kubernetes itself depends on them for wiring: a Service finds its pods via label selector, a ReplicaSet finds its owned pods the same way. **Critical rule**: the `selector` on a Service or ReplicaSet is **immutable after creation** — to change which pods it targets, delete and recreate it.

**Annotations** are also key-value pairs, but for **tools, not selection** — not indexed, not queryable. They carry configuration for ingress controllers, Prometheus, Helm. One line: *labels define identity and drive selection; annotations configure behaviour.*

### Imperative vs declarative

- **Imperative** (`kubectl create deployment ...`) — fast for one-offs and debugging. Not repeatable, not Git-friendly.
- **Declarative** (`kubectl apply -f`) — the production standard. Works whether the object exists or not; computes a three-way diff (last applied, live state, new config) and changes only what differs. Idempotent, Git-friendly, CI/CD-friendly.

**`apply` vs `replace`**: `replace` swaps the whole object — can cause downtime and wipes controller-set fields. `apply` does a surgical merge. Prefer `apply`. (One trap: `apply` stores last-applied config as an annotation — mixing `apply` with `edit`/`replace` desyncs it and produces surprise diffs.)

### Namespaces

Namespaces partition a cluster logically — one per team or environment. RBAC, NetworkPolicies, and ResourceQuotas all attach per namespace. Cluster-scoped resources ignore namespaces: Nodes, PersistentVolumes, ClusterRoles. The four you get out of the box: `default`, `kube-system`, `kube-public`, `kube-node-lease`.

### Owners and finalizers

**Ownership** — objects track their parent via `ownerReferences`, forming the chain Deployment → ReplicaSet → Pods. Delete the Deployment and garbage collection cascades down the chain.

**Finalizers** — deletion blockers that give controllers time to clean up. Deleting an object with finalizers only sets a `deletionTimestamp`; each controller does its cleanup and removes its finalizer; the object disappears only when the list is empty. Practical consequence: if a controller dies while holding a finalizer, the object hangs in `Terminating` forever — the usual suspect when a namespace won't delete.

## Cluster components — the machinery

A cluster is two kinds of machines: the **control plane** (the brain — manages state, schedules, reconciles; never runs your workloads) and **worker nodes** (the muscle — run your pods).

### Control plane

**kube-apiserver — the single entry point.** The API server is the **only component that talks to etcd**. Everything else — controllers, scheduler, kubelet, kubectl — goes through it. This is a hard architectural rule, not a convention. It's what authenticates and authorizes every request (mechanics in [[Ops/Kubernetes/Authentication]] and [[Ops/Kubernetes/RBAC]]), runs admission webhooks, and serializes concurrent writes safely. When you `kubectl apply`, the scheduler assigning a node, and the kubelet reporting status are all just HTTP requests to the same API. **The API server is the cluster.** It's also the only control plane component that's stateless — which is why you can run several replicas behind a load balancer for HA.

**etcd — the source of truth.** A distributed key-value store holding the entire cluster state. If etcd is lost without a backup, the cluster is gone — workloads keep running (kubelets don't need etcd), but you've lost the ability to manage anything. Consistency comes from **Raft consensus**: one leader takes all writes, replicates to a quorum before acknowledging. This is why etcd runs an **odd number of nodes** — 4 nodes need quorum 3 (survive 1 loss), same as 3 nodes; the 4th buys nothing. **Losing quorum freezes the cluster**: read-only, no new pods, no changes. On EKS/GKE/AKS the provider handles etcd and its backups; self-managed means `etcdctl snapshot save` is your job.

**controller-manager — the reconciliation engine.** One binary running many independent controllers (node, deployment, replicaset, job, namespace...). Each is the same loop: watch the API server for its object type, compare spec to status, act via the API server to close the gap, repeat. This watch-compare-act loop is the core idea of Kubernetes — everything above the API server is just controllers reconciling.

**scheduler.** Watches for **unbound pods** (no `nodeName` set), runs filter + score (details in [[Ops/Kubernetes/Pods]]), and writes `nodeName` to the pod object via the API server. That's all it does — it never starts a container.

### Worker node

**kubelet — the node agent.** The bridge between the API server and the container runtime. It registers the node on startup, watches for pods assigned to *its* node, tells the runtime to start/stop containers via **CRI**, runs the probes, and reports status back. It doesn't care whether the runtime is containerd or CRI-O — anything that speaks CRI works.

**kube-proxy.** Programs iptables/IPVS rules on the node so traffic to a Service's ClusterIP reaches a backing pod. (Details in [[Ops/Kubernetes/Networking]].)

**Container runtime.** Pulls images, creates the namespaces/cgroups, runs the processes. Docker as a runtime was removed in K8s 1.24 — but Docker-*built* images still work fine, since the OCI image format is separate from the CRI runtime interface.

### Pod creation — the full flow

`kubectl create -f pod.yaml`:

1. kubectl POSTs to the API server → auth, admission → pod object written to etcd with `nodeName: ""`
2. Scheduler sees the unbound pod, filter+scores, PATCHes `nodeName: "node-2"`
3. Kubelet on node-2 sees a pod assigned to it → starts containers via CRI
4. Kubelet PATCHes pod status to Running

Key insight: the pod object exists in etcd **before any container runs**. The object is desired state; the running container is actual state; reconciliation connects them.

### Node health and what happens when a node dies

Kubelet sends two heartbeats: a lightweight **Lease** object every 10s ("I'm alive") and a heavier full status update every 40s. Two-tier by design — full status every 10s at thousands of nodes would flood etcd.

When a node dies: **T+0** heartbeats stop → **~T+40s** Node Controller notices, marks node `Unknown` → **T+5min (default)** pods marked `Terminating`, replacements scheduled elsewhere. The 5-minute wait is deliberate: the "dead" node might just be partitioned and its containers still running — evicting immediately would risk two copies of the same pod. Practical consequence: **if a node dies, expect ~5 minutes before your pods are rescheduled.** Stateful pods with RWO volumes can take even longer.

### High availability

- **API server**: stateless, run many replicas behind a load balancer
- **etcd**: 3 or 5 nodes, Raft, odd numbers
- **controller-manager & scheduler**: only **one active instance at a time** even with multiple replicas — leader election (via a Lease object) picks the leader, others hot-standby. This prevents split-brain: two schedulers assigning the same node to different pods.

## Big picture

Kubernetes is the operating system of a datacenter: it schedules work, restarts what dies, and exposes one API over many machines. Every interaction is the same move: write a spec, let controllers reconcile reality toward it, read status to see how it's going. When something's wrong, `kubectl get <thing> -o yaml` (spec + status + conditions) is the first stop.

Continue: [[Ops/Kubernetes/Pods]] · [[Ops/Kubernetes/Workloads]] · [[Ops/Kubernetes/Networking]]
