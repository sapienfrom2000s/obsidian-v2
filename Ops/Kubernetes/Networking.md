# Kubernetes — Networking

## How pods get IPs

Each pod gets its own **network namespace** — an isolated copy of the network stack (own interfaces, routes, iptables). That's why containers in the same pod reach each other on `localhost`. But a fresh namespace starts dark; it needs wiring to the world:

- **veth pair** — a virtual ethernet cable. One end inside the pod's namespace (its `eth0`), the other in the host's root namespace. The pod thinks it has a real NIC.
- **bridge** (`cbr0`/`cni0`) — a virtual L2 switch on the host. All the veth host-ends plug into it; it learns which MAC lives on which veth and forwards accordingly. Pods on the same node talk through it directly, no NAT.
- **CNI plugin** — handles everything across nodes. Flannel wraps packets (VXLAN overlay), Calico routes natively via BGP, Cilium uses eBPF. Different mechanics, same guarantee: **every pod has a unique, routable IP across the cluster, no NAT between pods** — the flat network model.

When a pod is created, the CNI plugin creates the veth pair, assigns an IP from the pod CIDR, and programs routes.

## The pod IP problem → Services

Pods are ephemeral — every replacement gets a new IP. Anything referencing pod IPs directly breaks constantly.

A **Service** provides a stable virtual IP (**ClusterIP**) plus a DNS name (`my-svc.default.svc.cluster.local`) resolved by **CoreDNS**(hosted in `kube-dns`). Callers only ever talk to the Service; Kubernetes routes to a healthy backing pod.

### How it actually works — kube-proxy and DNAT

The ClusterIP is **virtual**: no interface on any node holds it, nothing listens on it. It exists only as a rule in the kernel.

- **DNAT** rewrites a packet's *destination* in flight. A packet headed for the ClusterIP gets its destination rewritten to a real pod IP, then routed normally via CNI. The sender never knows.
- **kube-proxy** (a DaemonSet, one per node) watches Services and installs those DNAT rules as iptables (or IPVS) entries. It is **not in the data path** — it writes the rules and steps aside; the kernel handles every packet. That's why Services add almost no latency.

How does kube-proxy know which pod IPs to use? **Endpoint Slices** — objects tracking the IPs and ports of pods matching a Service's selector. Pod dies or fails readiness → removed from the slice → kube-proxy updates the rules → traffic stops. (The older single `Endpoints` object rewrote entirely on any change at scale; slices shard ~100 pods each so one pod restart only touches one slice.)

## CNI — who actually gives pods their network

Every pod needs the same three things when it starts: a network cable, an IP address, and a route to the rest of the cluster. Someone has to do that work — Kubernetes itself doesn't. **CNI** ("Container Network Interface") is the agreed recipe for that job, and the tool that follows it is called a **CNI plugin**.

Think of it like electrical standards: any plug that matches the standard fits any socket. Kubernetes says "when I start a pod, I'll hand you this info" and the plugin does the wiring. That's why you can swap plugins — Flannel, Calico, Cilium — without changing anything else in the cluster.

- **The flow**: a pod gets scheduled → kubelet runs the plugin before starting the container → the plugin does the three things above (cable = the veth pair from earlier, IP, route) → only then does the container start, already connected.
- **The plugins differ mainly in how pods on different nodes reach each other:**
    - **Flannel** — the simple one. Wraps each packet inside another packet and mails it across (like putting a letter in an envelope). Easy, works everywhere, but can't enforce NetworkPolicies.
    - **Calico** — makes every node act like a router and teaches them each other's addresses, so packets travel directly (no envelope). Fast, and supports NetworkPolicies.
    - **Cilium** — the newest approach: instead of piling up rules in the kernel the old way, it loads small custom programs into the kernel itself. Fastest and most flexible — it can even take over kube-proxy's job.
- Whichever you pick, the promise is the same: **every pod can reach every other pod by IP, from any node, with no address translation in between.**

Rule of thumb: need NetworkPolicies or speed → Calico/Cilium; just need it to work → Flannel.

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