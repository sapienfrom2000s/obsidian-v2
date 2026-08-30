# Kubernetes — Authentication

*How identity gets proven, before RBAC ([[Ops/Kubernetes/RBAC]]) decides what that identity may do.*

Two different questions get answered by two different mechanisms, at two different layers:

| | Nodes / control-plane components | Pods |
|---|---|---|
| **Question** | "Are you a legitimate member of this cluster?" | "Are you cert-manager in namespace X, allowed to do Y?" |
| **Layer** | Transport (TLS handshake, before any HTTP) | Application (`Authorization: Bearer <token>`, after the handshake) |
| **Credential** | Client certificate | JWT (service account token) |
| **Verified against** | `ca.crt` | `sa.pub` |

A cert proves cluster membership. A token proves scoped, per-workload identity. Using a cert for the pod case would answer the wrong question — the node already proved the network is trusted; the pod needs to prove *which* workload it is.

## mTLS — how components trust each other

Every internal connection (kubelet ↔ API server, API server ↔ etcd) is **mutual TLS**: both sides present a cert, both verify it against a shared CA. No valid cert, no connection — enforced before any application data moves.

The CA is a key pair: `ca.crt` (public, distributed everywhere) and `ca.key` (secret, held only by whoever issues certs).

- **Self-signed (kubeadm default)** — `kubeadm init` generates its own CA. Trust exists only inside the cluster.
- **Proper org CA (production)** — Kubernetes certs are signed by the same CA as the rest of your infra. External systems (monitoring, CI/CD, service mesh) already trust the chain without distributing `ca.crt` by hand, and revocation goes through your org's normal CRL/OCSP process instead of being the cluster's own problem.

**Only the control plane ever holds `ca.key`.** Nodes and pods only get `ca.crt`, which is enough to *verify* a presented cert but not to *sign* one. That asymmetry is the whole security model: a compromised worker can impersonate nothing, because it has no way to mint a cert for another identity.

### How a worker node joins

The chicken-and-egg problem: a new worker has no cert, and the API server only trusts certs signed by the CA. The bootstrap token solves it:

1. `kubeadm init` generates the CA and a **bootstrap token** — short-lived (24h), scoped to nothing but "request a cert" — printed in the join command.
2. `kubeadm join` on the worker uses that token.
3. The worker generates its own key pair locally and sends a **CSR** (just the public key) to the API server, authenticated with the bootstrap token.
4. The API server validates the token, signs the CSR with `ca.key`, and returns the signed cert.
5. The worker uses that cert for every connection from then on.

The token is the one-time proof of identity — used immediately, then irrelevant. If it expires before you use it: `kubeadm token create --print-join-command`.

Neither side uses `ca.key` *during* a connection — only when issuing a new cert. Day to day, mTLS is just "check the presented cert against `ca.crt`," in both directions.

## Service account tokens — how pods authenticate

Pods can't use client certs the way nodes do, because the question being asked is different. The node's network access is already trusted (it already went through mTLS); the pod needs to prove a scoped identity *within* that trusted network — an application-layer fact, not a transport-layer one.

**ServiceAccount** — an identity: a name in a namespace. Every namespace gets a `default` one automatically. On its own it's just a database record; it needs a credential to be usable.

**Token** — the credential. A JWT containing the service account name, namespace, UID, and expiry, signed by the API server's own `sa.key`/`sa.pub` keypair (separate from the cluster CA).

How it actually gets into a container:

1. You submit a Pod. Before it's written to etcd, the **`ServiceAccount` admission controller** runs — fills in `default` if you didn't specify one, and (unless `automountServiceAccountToken: false`) injects a projected volume pointing at the token endpoint. You never see this edit in your YAML.
2. The API server signs the JWT with `sa.key`.
3. Kubelet mounts three files into the container at `/var/run/secrets/kubernetes.io/serviceaccount/`: `token`, `ca.crt`, `namespace`.
4. At request time: TLS handshake first (the pod verifies the API server's cert against the mounted `ca.crt` — one-sided, the pod doesn't present a cert of its own), then the HTTP request carries the token in `Authorization: Bearer <token>`.
5. API server verifies the JWT signature against `sa.pub`, resolves the service account, and hands off to RBAC.

The token is only an identity card — it carries no permissions itself. RBAC decides what that identity may do (see [[Ops/Kubernetes/RBAC]]), and the default is deny: no binding, no access.

**Why this matters**: if a container is compromised, the attacker inherits exactly what that service account's RBAC bindings allow — nothing more. This is why dedicated, minimally-scoped service accounts per workload matter, and why `automountServiceAccountToken: false` is worth setting on pods that never call the API server (RBAC.md's point about the `default` ServiceAccount not being harmless is the same finding from the other side).

## Big picture

Two trust problems, two mechanisms: mTLS settles "is this a real cluster member" once, at the transport layer, for nodes and control-plane components; service account tokens settle "which workload is this, and what can it do" per-request, at the application layer, for pods. RBAC only ever runs after one of these has already answered "who are you."

Related: [[Ops/Kubernetes/RBAC]] · [[Ops/Kubernetes/Foundations]]
