# Kubernetes — Networking

## How pods get IPs

Each pod gets its own **network namespace** — an isolated copy of the network stack (own interfaces, routes, iptables). That's why containers in the same pod reach each other on `localhost`. But a fresh namespace starts dark; it needs wiring to the world:

- **veth pair** — a virtual ethernet cable. One end inside the pod's namespace (its `eth0`), the other in the host's root namespace. The pod thinks it has a real NIC.
- **bridge** (`cbr0`/`cni0`) — a virtual L2 switch on the host. All the veth host-ends plug into it; it learns which MAC lives on which veth and forwards accordingly. Pods on the same node talk through it directly, no NAT.
- **CNI plugin** — handles everything across nodes. Flannel wraps packets (VXLAN overlay), Calico routes natively via BGP, Cilium uses eBPF. Different mechanics, same guarantee: **every pod has a unique, routable IP across the cluster, no NAT between pods** — the flat network model.

When a pod is created, the CNI plugin creates the veth pair, assigns an IP from the pod CIDR, and programs routes.

## The pod IP problem → Services

Pods are ephemeral — every replacement gets a new IP. Anything referencing pod IPs directly breaks constantly.

A **Service** provides a stable virtual IP (**ClusterIP**) plus a DNS name (`my-svc.default.svc.cluster.local`) resolved by **CoreDNS**. Callers only ever talk to the Service; Kubernetes routes to a healthy backing pod.

### How it actually works — kube-proxy and DNAT

The ClusterIP is **virtual**: no interface on any node holds it, nothing listens on it. It exists only as a rule in the kernel.

- **DNAT** rewrites a packet's *destination* in flight. A packet headed for the ClusterIP gets its destination rewritten to a real pod IP, then routed normally via CNI. The sender never knows.
- **kube-proxy** (a DaemonSet, one per node) watches Services and installs those DNAT rules as iptables (or IPVS) entries. It is **not in the data path** — it writes the rules and steps aside; the kernel handles every packet. That's why Services add almost no latency.

How does kube-proxy know which pod IPs to use? **Endpoint Slices** — objects tracking the IPs and ports of pods matching a Service's selector. Pod dies or fails readiness → removed from the slice → kube-proxy updates the rules → traffic stops. (The older single `Endpoints` object rewrote entirely on any change at scale; slices shard ~100 pods each so one pod restart only touches one slice.)

## Service types — a progression

Each type exists because the previous had a gap:

- **ClusterIP** (default) — virtual IP, internal only. For anything that shouldn't be exposed: internal APIs, DBs, caches. *Gap: no external access.*
- **NodePort** — opens a port (30000–32767) on **every node**; `<node-ip>:<node-port>` reaches the service. *Gap: raw node IPs, no failover — you'd need your own LB in front.*
- **LoadBalancer** — provisions a cloud LB (ALB/NLB/...) pointing at the nodes. Stable external IP. *Gap: one cloud LB per service gets expensive, and it's L4 — can't route on HTTP host/path.* (On bare metal there's no cloud provider to hand out that IP at all — **MetalLB** fills that specific gap;)

## Ingress — one entry point, many services

One load balancer for the whole cluster, routing to many services on **HTTP host and path** (L7): `/api` → service A, `app.example.com` → service B. Plus TLS termination, auth, rate limiting.

Key mechanic: an **Ingress object is just routing rules — it does nothing alone**. An **Ingress Controller** (NGINX, Traefik, AWS ALB Controller) runs as a pod, watches Ingress objects, and implements them. The controller itself is exposed via one LoadBalancer Service.

Ingress's design flaws at scale: operators and developers share one object, advanced features (timeouts, retries) live in controller-specific annotations, and it's HTTP/HTTPS only. The official successor is **Gateway API** — separate `Gateway` (operator-owned: ports, TLS) and `HTTPRoute`/`TCPRoute` (developer-owned: routing rules) objects, with TCP/UDP support and no annotation lock-in. Full breakdown, plus how the entry-point problem (NodePort/hostPort/MetalLB) is a separate concern from this routing layer.

## NetworkPolicies

By default **every pod can reach every pod**. NetworkPolicies are pod-level firewall rules - enforced by the **CNI plugin, not kube-proxy** (Flannel doesn't support them; Calico and Cilium do - your [[Ops/DevSecOps/Kubernetes Security]] note covers the practical side).

Worth remembering: policies are **additive** (ORed, no deny rules - you deny by not allowing), and an empty `podSelector` with no rules is a default-deny for the namespace.

## Big picture

| Layer | Job |
|---|---|
| CNI + veth + bridge | give every pod a routable IP |
| CoreDNS | service names → ClusterIPs |
| kube-proxy + iptables DNAT | ClusterIP traffic → backing pods |
| Endpoint Slices | track which pods are behind a service |
| ClusterIP → NodePort → LoadBalancer | progressively wider exposure |
| Ingress / Gateway API | L7, one entry point for many services |

Same thread as the rest of Kubernetes: each abstraction exists because the previous one had a gap.