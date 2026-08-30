---
tags: [gcp, aws, kubernetes, architecture, ops]
---

# Purple — Architecture

![[Excalidraw/Purple Architecture.excalidraw.md|100%]]

## Summary

Cross-cloud setup: DNS on **DigitalOcean**, compute and data on **GCP**, object storage and secrets on **AWS**. Traffic enters via a GCP Load Balancer, hits an Ingress Controller inside a GKE cluster, and fans out to three horizontally-scaled application tiers plus supporting services. Data sits outside the cluster in a managed MySQL instance with a read replica. Object storage (S3) and secrets (AWS Secrets Manager) live in AWS, reached from the cluster over the public internet. GitOps (Argo CD) owns every deployment inside the cluster.

### Edge
- **DNS — DigitalOcean**: resolves the public domain, points at the GCP Load Balancer.
- **Load Balancer — GCP**: single entry point into the cluster's Ingress.

### GKE Cluster
- **Ingress Controller**: accepts all inbound traffic, routes by host/path to the three app services.
- **React App**: frontend, horizontally scaled (HPA).
- **Rails App**: backend API, horizontally scaled (HPA).
- **Node.js App**: backend service, horizontally scaled (HPA).
- **Redis**: shared caching layer for Rails and Node.js.
- **Metabase**: open-source BI, deployed via Helm.
- **Observability**: Prometheus (metrics) + Loki (logs) + Grafana (dashboards).
- **Argo CD**: GitOps controller — reconciles every workload above (app Deployments, Metabase Helm chart, observability stack, Redis) from Git, so cluster state always matches what's committed.

### AWS (external)
- **S3**: object storage — user uploads and static assets, written/read by Rails and Node.js.
- **Secrets Manager**: application config and credentials, consumed by workloads in the cluster.

### Data Layer
- **MySQL Primary — GCP Cloud SQL (managed)**: system of record, written to by Rails and Node.js.
- **MySQL Read Replica**: synced from primary, offloads read traffic.

### Traffic Flow
1. Client → DNS (DigitalOcean) → GCP Load Balancer
2. Load Balancer → Ingress Controller (GKE)
3. Ingress → React / Rails / Node.js depending on route
4. Rails / Node.js → Redis (cache) and MySQL Primary (writes)
5. Reads can be offloaded to the MySQL Read Replica
6. Rails / Node.js → AWS S3 (objects) and AWS Secrets Manager (credentials), cross-cloud over the public internet
7. Argo CD continuously syncs desired state (Git) into the cluster for all workloads — apps, Metabase, observability, Redis

### Open Questions / Follow-ups
- Confirm whether reads are explicitly routed to the replica (app-level split) or if it's failover-only.
- TLS termination point: at the GCP Load Balancer or at the Ingress Controller?
- Argo CD deployment target: is it in-cluster (self-managed) or a separate ops cluster?
- How do GKE pods authenticate to AWS? Static IAM access keys in-cluster, or Workload Identity federated to an AWS IAM role? Static keys are the thing to avoid here.
- Are secrets pulled at runtime (SDK call per pod) or synced into K8s Secrets via External Secrets Operator? Changes blast radius and cold-start behaviour.
- Is S3 traffic egressing over the public internet? Cross-cloud egress is billed on both sides and adds latency — worth confirming whether GCS would do the job instead.

## Drawing
Source: [[Excalidraw/Purple Architecture.excalidraw.md|Purple Architecture (Excalidraw)]]
