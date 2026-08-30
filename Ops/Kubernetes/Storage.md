# Kubernetes — Storage

## The ladder

Container writes die with the container. Kubernetes climbs the same ladder it always does — each layer exists because the previous one had a gap:

| Type | Survives pod? | Provisioned by | Use case |
|---|---|---|---|
| `emptyDir` | no | Kubernetes | scratch space, sidecar sharing |
| PV / PVC | yes | infra team (manual) | persistence |
| StorageClass | yes | Kubernetes (dynamic) | persistence, automated |

## emptyDir — scratch space

An empty directory on the node, created when the pod starts, mounted into containers. Containers in the same pod can share it (sidecar writes logs, app reads them). `medium: Memory` backs it with RAM — fast, but counts against the memory limit and dies on node restart.

The catch: it lives and dies with the **pod**. Rescheduled pod = fresh empty directory. Scratch, not persistence.

## PV and PVC — supply and demand

Data that must survive pods (databases, queues, uploads) needs storage independent of any pod. Kubernetes splits this into two objects on purpose:

- **PersistentVolume (PV)** — the actual storage (an EBS volume, NFS share). Cluster-scoped, created by the infra team. Supply.
- **PersistentVolumeClaim (PVC)** — a request for storage ("10Gi, read-write"), written by the developer. Demand.

Kubernetes binds a PVC to a PV when **capacity, accessModes, and storageClassName all match**. Nothing matches → PVC stays `Pending` — the first thing to check when a pod is stuck on `ContainerCreating` with unbound volumes.

**Access modes**:

| Mode | Meaning |
|---|---|
| RWO | one node mounts read-write — standard for databases |
| ROX | many nodes, read-only — shared config |
| RWX | many nodes, read-write — needs special backends (NFS, EFS) |

**Reclaim policies** — what happens to the disk when the PVC is deleted:
- `Retain` — disk kept, human cleans up. Safe for production databases.
- `Delete` — disk destroyed automatically. Default for dynamic provisioning.

Production rule: `Retain` on anything stateful. Losing a database because someone deleted a PVC is a bad day.

## StorageClass — dynamic provisioning

Manual PVs bottleneck: infra team pre-provisions pools, devs wait on tickets, a 7Gi request consumes a whole 20Gi PV, and a PV created in zone `us-east-1a` can't serve a pod scheduled in `us-east-1b`.

A **StorageClass** is a blueprint for *creating* storage automatically when a PVC arrives:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com          # which driver creates the volume
parameters:
  type: gp3
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer   # don't create the disk until the pod is scheduled
```

`WaitForFirstConsumer` fixes the zone problem: the disk is created in whatever zone the pod actually lands in. The PVC just references the StorageClass by name — no pre-provisioned pool, no tickets.

**CSI** is the interface underneath: storage drivers used to be baked into Kubernetes core (every vendor update required a K8s release). The Container Storage Interface moved them out into vendor-maintained plugins behind a standard contract — `CreateVolume`, `AttachVolume`, `MountVolume`. That's why the provisioner is `ebs.csi.aws.com`: AWS's driver, not Kubernetes.

## Projected volumes

When a pod needs a ConfigMap, a Secret, and pod metadata all mounted, a **projected volume** collapses them into one directory at one mount point — instead of three volumes and three `volumeMounts`.

## StatefulSets — where it comes together

A Deployment treats replicas as interchangeable; that breaks for databases, where each replica needs its own stable storage. StatefulSets + `volumeClaimTemplates` create **one PVC per pod** (`data-postgres-0`, `data-postgres-1`, ...) and rebind the same PVC when a pod is rescheduled — same name, same volume, same data. See [[Ops/Kubernetes/Workloads]].

## RWO and node failures — the practical gotcha

RWO means one node mounts at a time. When that node dies, Kubernetes reschedules the pod elsewhere — but the volume is still attached to the dead node, and it must detach before the new node can mount. Expect the pod stuck in `ContainerCreating` for minutes while Kubernetes waits out a timeout before force-detaching.

Not a bug — a split-brain guard (two nodes writing one disk). RWX volumes (NFS, EFS) avoid it at the cost of performance and consistency tradeoffs.

## Big picture

Supply (PV) and demand (PVC) separated so developers don't touch infrastructure; StorageClass automates the supply; CSI keeps the drivers out of core; StatefulSets glue it to workloads. Debugging order for stuck pods: PVC `Pending`? → check accessModes/capacity/storageClass. `ContainerCreating`? → RWO detach delay or unbound volume.

Related: [[Ops/Kubernetes/Workloads]] · [[Ops/Kubernetes/Foundations]] · [[Ops/Docker/Basics]] (volumes in Docker)
