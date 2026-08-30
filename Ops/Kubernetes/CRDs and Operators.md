# Kubernetes — CRDs and Operators

## Why CRDs exist

Kubernetes ships a fixed set of resource types. But you want it to manage things it doesn't know about — a database cluster, a TLS certificate, a queue-based scaler. A **CRD (CustomResourceDefinition)** teaches the Kubernetes API a new resource type. Once registered, `kubectl get certificates` or `kubectl get scaledobjects` works exactly like built-in resources — stored in etcd, validated, RBAC-able, watchable.

> CRDs are what turn Kubernetes from a container scheduler into a platform.

**CRD vs CR** — the terms get confused: the CRD is the *schema definition* (registered once, cluster-wide); a custom resource (CR) is an *instance* of it. Class vs object.

You've been using CRDs throughout these notes without the label: HPA, NetworkPolicy, PodDisruptionBudget, and everything from cert-manager, KEDA, ESO, ArgoCD. Not exotic — it's how Kubernetes is extended in practice.

## Operators — CRDs with a brain

A CRD alone is just a schema. Create a `Certificate` CR and... nothing happens — it sits in etcd as data. An **Operator** is a controller that watches CRs of its type and runs the reconciliation loop for them: you declare what you want in the spec, the Operator makes it happen, the Operator writes results back to the CR's status.

Same watch-compare-act loop as built-in controllers (see [[Ops/Kubernetes/Foundations]]) — just for a custom type, running as a regular pod in the cluster.

The loop is **level-triggered, not edge-triggered**: it re-reconciles periodically even without events, so manually deleting a resource the Operator manages just gets recreated on the next pass.

**Controller vs Operator** — every Operator is a controller; the difference is domain knowledge. The Deployment controller knows how to roll out pods. An Operator knows how to do a zero-downtime Postgres major-version upgrade, take a backup before scaling down, or fail over primary to replica. That operational knowledge encoded in software is what makes it an Operator.

**Operator vs Helm**: Helm is a one-time action (install/upgrade/uninstall); an Operator is a continuous process that keeps correcting. Helm can install a database but can't detect a lagging replica or promote a failover. For stateless apps Helm is often enough; for stateful systems, Operators.

## Working with CRs day to day

```bash
kubectl get crds                       # what's installed
kubectl describe crd certificates.cert-manager.io
kubectl get certificates -n production
kubectl describe certificate my-tls-cert   # → Status.Conditions
```

The **status conditions** are the Operator's language: `Type: Ready, Status: True/False, Reason, Message`. When a CR isn't working, `kubectl describe` on it is always the first stop — then the Operator pod's logs, which is where reconciliation errors actually appear.

Debugging order for a misbehaving CR:
1. `kubectl describe` the CR — status conditions
2. Operator pod running? `kubectl logs -n cert-manager deploy/cert-manager`
3. RBAC — an Operator whose ServiceAccount lacks permissions fails quietly
4. `kubectl get crds` — "the server doesn't have a resource type" means the CRD isn't installed at all

Two safety notes: **deleting a CRD deletes every CR of that type, no warning** — which is why uninstalling charts that own CRDs needs care. And Operators add **finalizers** to CRs for cleanup — if the Operator is gone, the CR hangs in `Terminating` (same finalizer mechanics as [[Ops/Kubernetes/Foundations]]).

## A concrete example — Prometheus Operator

Configuring Prometheus to scrape services in a dynamic cluster (services appearing and disappearing constantly) is unmanageable by hand. The Prometheus Operator:

1. You create a `ServiceMonitor` CR: "scrape services labelled `app=my-app`, port `metrics`, every 30s"
2. The Operator watches for ServiceMonitors, generates the corresponding Prometheus scrape config, and reloads Prometheus
3. New service gets scraped when its ServiceMonitor appears; stops when it's deleted

You never touch Prometheus config files. That's the pattern at its best — domain knowledge (how to configure Prometheus) encoded as declarative intent.

## When to build your own

At mid-level: you *use* Operators, you don't build them (check OperatorHub.io first — well-maintained ones exist for Postgres, Redis, Kafka, Elasticsearch). Building one is for when you have internal platforms that need Kubernetes-native management or runbooks you want to automate — and it's a senior task. Understanding the pattern is what lets you debug, configure, and trust the ones you run.

## Big picture

CRD = new API type (schema). CR = instance. Operator = the controller that reconciles those instances. Together they're the extension mechanism behind every "Kubernetes-native" tool you install — and the reason the ecosystem could grow without changing Kubernetes core.

Related: [[Ops/Kubernetes/Foundations]] · [[Ops/Kubernetes/ConfigMaps and Secrets]] (ESO is an Operator)
