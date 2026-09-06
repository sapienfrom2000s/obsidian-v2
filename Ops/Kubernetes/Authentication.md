# Kubernetes — Authentication

*How Kubernetes figures out **who you are** — before RBAC ([[Ops/Kubernetes/RBAC]]) decides what you're allowed to do.*

## The question

Everything in Kubernetes is an API request. You run `kubectl get pods`, a node reports its status, an app reads a ConfigMap — all of it is just traffic hitting one door: the **API server**.

Before anything else, that door asks one question: **who are you?**

Answering it is *authentication*. And answering it well needs three things:

1. **A credential** — something you have: a certificate or a token.
2. **A trusted authority** — the thing that made the credential. Everyone agrees: "if the authority signed it, it's real."
3. **The API server checking** — it verifies the credential against the authority, and turns it into a name.

Once the API server knows your name, a second step — authorization (RBAC) — checks what that name is allowed to do. This note is only about step one.

Now, who actually knocks on this door? Three kinds of callers:

- a **human** with kubectl
- a **machine** (a node or control-plane component)
- an **app inside a pod**

Each one is covered below, in that order — each builds on the ideas from the one before it.

## How a human authenticates

You run `kubectl get pods`. Where does your identity come from?

Your kubeconfig file holds a **client certificate** — a small ID card saying "this is alice", signed by an authority.

The flow:

1. kubectl starts a TLS connection to the API server and **presents the certificate**.
2. The API server checks the certificate's signature against a **CA** (Certificate Authority — a key pair the cluster already trusts: `ca.crt` is the public half, `ca.key` the private half that only the signing machine holds).
3. Signature valid → the API server reads the identity out of the cert: the **CN** (Common Name) field becomes your username, the **O** (Organization) fields become your groups. `CN=alice, O=dev-team` = user `alice`, member of group `dev-team`.
4. That's it — the API server now knows you as "alice" and hands off to RBAC.

Notice something strange: the cluster has **no user object**. There's no `kubectl get users`, no user database. "alice" is just a string the API server pulled out of a verified certificate. The binding in RBAC that says `User: alice` is also just a string. They match → it's you. (Corollary: if two different identity sources can both produce an "alice" — two CAs, or two login providers — the API server can't tell them apart. One alice with read-only access and another alice with admin access are, to the cluster, the same person with both.)

**The other way humans log in: OIDC.** Same flow, different credential. Instead of a cert, your company login (Okta, Google, whatever) gives kubectl a **token** after you log in. Every request carries it in an `Authorization: Bearer <token>` header. The API server checks the token's signature against the login provider's keys and reads the username and groups out of its claims. One nice detail: OIDC usernames usually get the provider's URL attached (like `https://okta.example.com#alice`) so two different providers can never produce the same "alice".

## How a machine authenticates

Machines do it the strict way: **both** sides show a certificate, **both** sides check. That's what the "m" in **mTLS** means (mutual TLS).

Every internal connection works like this — kubelet ↔ API server, API server ↔ etcd. No valid certificate, no connection, before any data moves.

Where do machine certificates come from? The CA again — the same one from the human flow, ideally. In production, that's the point of using your company's CA: your monitoring, CI/CD, and service mesh already trust it, no extra setup. With kubeadm's default, the cluster generates its own CA and the trust stays inside the cluster.

The security model is one sentence: **nodes get `ca.crt` but never `ca.key`.** They can check certificates; they cannot create them. A hacked worker node can't fake anyone else's identity.

**But how does a new node get its first certificate?** It has no cert, and the API server only trusts certs signed by the CA. Chicken and egg. The fix is a **bootstrap token** — a 24-hour password that can do exactly one thing: ask for a certificate.

1. `kubeadm init` creates the CA and prints a bootstrap token in the join command.
2. The new node runs `kubeadm join` with that token.
3. The node makes its own key pair **locally** and sends just the public half (a CSR — "please sign this").
4. The API server checks the token, signs the public key with `ca.key`, returns the certificate.
5. The node uses that cert for everything from then on.

After joining, the token is dead — it was the one-time entry ticket. If it expired unused: `kubeadm token create --print-join-command`.

## How a pod authenticates

Now the third caller. An app in a pod also needs to talk to the API server. Why not just give it a certificate like everyone else?

Because the question is different. A node proves "I'm a real member of the cluster" — that's a *network-level* fact, answered once at the connection. A pod needs to prove "I am cert-manager, in this namespace, and here's what I may touch" — a *per-workload* fact, and one certificate per pod would be a management nightmare anyway.

So pods get the lightweight version: a **name** and a **token**.

- **ServiceAccount** — the identity. Just a name in a namespace. Every namespace gets a `default` one automatically. On its own it's only a record; it needs a credential.
- **Token** — the credential. A **JWT** — a signed JSON blob holding the service account name, namespace, and expiry — signed by the API server's *own* key pair (`sa.key`/`sa.pub`, separate from the cluster CA).

How it gets into your container:

1. You submit a Pod. Before it's saved, a built-in auto-editor (the **ServiceAccount admission controller**) runs — fills in `default` if you didn't pick one, and (unless you set `automountServiceAccountToken: false`) quietly injects a volume pointing at the token. You never see this edit in your YAML.
2. The API server signs the JWT with `sa.key`.
3. The kubelet mounts three files into the container at `/var/run/secrets/kubernetes.io/serviceaccount/`: `token`, `ca.crt`, `namespace`.
4. When the app calls the API: TLS handshake first (the pod checks the API server's certificate against the mounted `ca.crt` — the pod shows no certificate of its own), then the request carries `Authorization: Bearer <token>`.
5. The API server checks the JWT signature against `sa.pub`, resolves the service account, and hands off to RBAC.

The token is only an ID card — it carries **zero permissions**. RBAC decides what the identity may do, and the default is deny: no binding, no access.

**Why this matters**: if a container is hacked, the attacker gets exactly what that service account's RBAC allows — nothing more. That's why each workload should get its own small service account, and why `automountServiceAccountToken: false` is worth setting on pods that never call the API.

## Big picture

One door, one question — "who are you?" — and three answers that all follow the same shape: **a credential, a trusted authority that signed it, and the API server checking**.

- Humans: certificate or login token → username + groups.
- Machines: certificates both ways (mTLS), minted at join time via a one-time bootstrap token.
- Pods: a named identity (ServiceAccount) plus a signed token (JWT).

After any of these answers "who", RBAC decides "what".

Related: [[Ops/Kubernetes/RBAC]] · [[Ops/Kubernetes/Foundations]]
