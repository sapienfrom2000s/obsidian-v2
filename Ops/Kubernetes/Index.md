# Kubernetes — Index

Reading order roughly top to bottom; later notes assume earlier ones.

## Core
- [[Ops/Kubernetes/Foundations]] — why K8s exists, the object model (spec vs status), cluster components (control plane + node)
- [[Ops/Kubernetes/Pods]] — pods, containers, probes, lifecycle; scheduling, taints/affinity, PDBs, priority

## Running workloads
- [[Ops/Kubernetes/Workloads]] — Deployment, StatefulSet, DaemonSet, Job, CronJob — which one for which app shape
- [[Ops/Kubernetes/Autoscaling]] — HPA, VPA, Cluster Autoscaler — scaling pods, requests, and nodes
- [[Ops/Kubernetes/ConfigMaps and Secrets]] — injecting config/credentials at runtime, three consumption patterns

## Networking & storage
- [[Ops/Kubernetes/Networking]] — pod IPs, veth/bridge/CNI, Services, kube-proxy/DNAT
- [[Ops/Kubernetes/Ingress and Gateway API]] — entry point (NodePort/hostPort/MetalLB) vs L7 routing (Ingress/Gateway API), external HTTPS
- [[Ops/Kubernetes/Storage]] — emptyDir, PV/PVC, StorageClass

## Security
- [[Ops/Kubernetes/Authentication]] — mTLS bootstrap for nodes, service account tokens for pods
- [[Ops/Kubernetes/RBAC]] — subjects, Roles/ClusterRoles, bindings
- Related but outside this folder: [[Ops/DevSecOps/Kubernetes Security]]

## Extending & packaging
- [[Ops/Kubernetes/CRDs and Operators]] — teaching the API new resource types, controllers with a brain
- [[Ops/Kubernetes/Kustomize and Helm]] — base/overlays vs packaging/templating, avoiding YAML sprawl
