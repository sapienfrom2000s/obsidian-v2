## Two separate jobs, one inbound request

Every request from outside the cluster clears two gates, and it's easy to conflate them:

1. **Entry point (L3/L4)** — how does the packet reach a node at all? Needs a real, routable IP with an open port. No way around this — something must be listening.
2. **Routing (L7)** — once it arrives, which backend Service handles it? Matches hostname, path, headers.

**Ingress and Gateway API only do job 2.** Job 1 is a separate, always-necessary problem, solved independently by NodePort, hostPort, or (on bare metal) MetalLB. A common mistake is assuming MetalLB is *required* for Ingress — it isn't; Ingress routes correctly regardless of which entry-point mechanism opens the port. MetalLB only changes *where* that port lives.

## Entry point options (job 1)

| Mechanism | How | Gap |
|---|---|---|
| **NodePort** | Kubernetes opens a random high port (30000–32767) on every node | Unmemorable port, traffic must target one specific node's IP |
| **hostPort / hostNetwork** | Controller binds directly to a node's real interface on 80/443 | Ties the pod to one node, usually needs elevated privileges |
| **MetalLB** | A floating virtual IP (VIP) announced to the LAN like a real device | The only option giving both a clean address *and* failover — the other two have neither |

### MetalLB

Cloud clusters get a load balancer IP handed to them by the cloud provider the moment you create a `LoadBalancer` Service. Bare metal has no such provider — MetalLB fills exactly that gap, nothing more: it watches for `LoadBalancer` Services and assigns each one an IP from a configured pool, then announces it to the LAN.

Mechanically: the VIP is bound to a healthy node's NIC. If that node dies, MetalLB moves the same IP to another node's NIC — DNS and clients never see a change. MetalLB itself has **no HTTP awareness and does no routing** — it only gets a packet to *a* node. From there, the existing Service machinery takes over exactly as it does for a normal ClusterIP: kube-proxy's iptables/IPVS rules DNAT the VIP:port to a real pod IP (see [[Ops/Kubernetes/Networking]] for the DNAT mechanics). MetalLB changes nothing about how traffic is routed once it lands — only how it arrives.

Getting a MetalLB VIP reachable from the public internet (relevant for homelabs, irrelevant behind a cloud LB) is a second, separate problem: either a reverse tunnel (an agent inside the cluster reaches *out* to a relay, e.g. Cloudflare Tunnel — no router config, no static IP needed) or traditional port forwarding on the router (simpler, but needs a DDNS script if your WAN IP isn't static).

## Routing: Ingress vs Gateway API (job 2)

**Ingress** — one object per set of hostname/path rules; an **Ingress Controller** (NGINX, Traefik, AWS ALB) watches those objects and acts as the reverse proxy. The spec covers hostname/path routing and basic TLS, full stop. Everything else — header matching, traffic splitting, rate limiting, rewrites — has no standard field, so every controller invented its own annotation syntax:

```
nginx.ingress.kubernetes.io/rewrite-target: /$2
traefik.ingress.kubernetes.io/router.middlewares: strip-prefix
haproxy.org/path-rewrite: /(.*) /$1
```

Same feature, three incompatible strings. Switch controllers, rewrite every annotation. **The Ingress spec is frozen — this is permanent, not a gap that gets fixed.**

**Gateway API** is the official successor (same SIG built both), and moves those missing features into the spec itself as standard fields every conforming controller must implement identically:

| Feature | Ingress | Gateway API |
|---|---|---|
| Hostname/path | ✓ | ✓ |
| Header / query matching | annotations only | standard field |
| Weighted traffic split | annotations only | standard field |
| Redirects/rewrites | annotations only | standard field |
| Request mirroring | ✗ | ✓ |
| TCP/UDP/gRPC routing | ✗ | ✓ (TCPRoute, UDPRoute, GRPCRoute) |
| TLS passthrough | annotations only | standard mode |
| Portable across controllers | ✗ | ✓ |

### Three layers instead of one object

Gateway API splits routing across three resources so operators, infra teams, and app teams each own their layer without stepping on each other:

- **GatewayClass** — cluster operator picks the controller implementation (Envoy, Istio, Cilium...). One per controller type, same idea as StorageClass.
- **Gateway** — infra team opens actual listeners: ports, protocols, hostnames, TLS. Declares what traffic the infrastructure accepts.
- **HTTPRoute** (or TCPRoute/UDPRoute/GRPCRoute/TLSRoute) — app teams own these; attach to a Gateway and define which requests go to which backend Service.

Three app teams can share one Gateway, each owning only their HTTPRoute — in Ingress, they'd be editing the same object or fighting over separate ones with tangled TLS/port config.

**Cross-namespace routing is deny-by-default**: a Route can only reference a Gateway in its own namespace unless a **ReferenceGrant** in the target namespace explicitly opts in.

**Conformance profiles** (Core / Extended / Experimental) tell you what a given controller actually implements, replacing the old "which annotations does this controller support" guesswork.

Both systems coexist in the same cluster indefinitely — Gateway API is a strict superset, so migration is per-app and gradual, not a cutover.

## External HTTPS — a separate trust domain from internal mTLS

Internal cluster mTLS (kubelet ↔ API server ↔ etcd, see [[Ops/Kubernetes/Authentication]]) and external browser HTTPS are two unrelated trust chains:

| | Internal mTLS | External HTTPS |
|---|---|---|
| Who | Cluster components | Browsers, CLI tools |
| Trusts | Cluster CA (`ca.crt`) | OS/browser trust store |
| Signed by | kubeadm CA | Let's Encrypt, org CA, self-signed |

TLS terminates at the ingress/gateway edge; traffic inside the cluster runs plain HTTP — normal, not a shortcut, since the private network doesn't need its own TLS layer on top of mTLS. The kubeadm CA never signs external certs and the external CA never signs cluster component certs — keeping them separate means a self-signed homelab cert doesn't need distributing to every internal component, and a leaked internal `ca.key` doesn't compromise public-facing certs. For homelabs without public DNS (no Let's Encrypt), the practical option is running your own CA once and installing its root in your OS trust store — which is what cert-manager automates in-cluster.

## Big picture

Job 1 (entry point: NodePort/hostPort/MetalLB) and job 2 (routing: Ingress/Gateway API) are independent — solve them separately, don't conflate a floating-IP problem with a hostname-routing problem. Within job 2, Ingress is frozen at hostname/path + basic TLS; Gateway API is the same problem with the missing decade of features built into the spec instead of bolted on as controller-specific annotations.

Related: [[Ops/Kubernetes/Networking]] · [[Ops/Kubernetes/Authentication]]
