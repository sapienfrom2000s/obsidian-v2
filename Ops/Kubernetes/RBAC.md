# Kubernetes — RBAC

Every action — create a pod, read a Secret, scale a Deployment — is an API request to the API server. Authorization answers one question: *is this authenticated identity allowed to do this action on this resource?* (Two separate steps: authentication = who you are, authorization = what you may do; RBAC is evaluated only after auth succeeds — see [[Ops/Kubernetes/Authentication]] for how identity gets proven in the first place, via mTLS for nodes and tokens for pods.)

## Why RBAC won (and ABAC didn't)

Kubernetes' older authorization mode, **ABAC**, defined rules in a static JSON policy file on the API server node. Every change required an API server restart; there was no API for managing policies (no kubectl, no GitOps); auditing meant reading scattered JSON on disk. Dead legacy.

**RBAC** makes permissions Kubernetes API objects themselves — `kubectl apply`-able, versionable in Git, live-updating, auditable. Same "everything is an object" move as the rest of the system.

## Subjects — who gets permissions

- **Users** — humans. Kubernetes has *no user object*: identities come from outside (client certificates, OIDC tokens from Okta/Google). You can't `kubectl get users`; the username is just a string extracted by the auth layer.
- **Groups** — also external, membership comes from the cert/token. Useful for granting a whole team at once.
- **ServiceAccounts** — the Kubernetes-native identity for **processes in pods**, not humans. Actual objects you create and manage. When your app pod calls the API, it authenticates as its ServiceAccount. Every namespace gets a `default` one, and every pod that doesn't specify one gets it. (See [[Ops/Kubernetes/Authentication]] for how the token behind that identity actually gets minted and mounted.)

## The four objects

Permissions are built from three ingredients: **apiGroups** (`""` = core: pods/services/secrets; `apps` = deployments; `batch` = jobs; `networking.k8s.io` = ingresses), **resources**, and **verbs** (`get/list/watch` = read, `create/update/patch/delete` = write).

| Object | Scope |
|---|---|
| **Role** | permissions within one namespace |
| **RoleBinding** | attaches a Role to subjects in that namespace |
| **ClusterRole** | cluster-scoped permissions — for non-namespaced resources (nodes, PVs) or reusable permission sets |
| **ClusterRoleBinding** | grants a ClusterRole across the whole cluster |

```yaml
kind: Role
metadata:
  name: pod-reader
  namespace: dev
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: dev
subjects:
- kind: User
  name: alice
roleRef:
  kind: Role
  name: pod-reader
```

**The combination people skip**: a **ClusterRole bound by a RoleBinding** applies only within that RoleBinding's namespace. That's the reuse pattern — define "can read pods and logs" once at cluster level, bind it per namespace, never granting cluster-wide access. (The fourth combo, Role + ClusterRoleBinding, is invalid — ClusterRoleBindings can only reference ClusterRoles.)

## Rules of the game

- **RBAC is additive — there is no deny rule.** Multiple bindings OR together; access is denied only by the absence of an allow. You can't say "everything except X" — you enumerate allows. (Same shape as NetworkPolicies.)
- **Subresources need explicit rules**: permission on `pods` does *not* cover `pods/log`, `pods/exec`, `pods/portforward`. Granting `pods` and then wondering why CI can't stream logs is a classic.
- **`system:masters` bypasses RBAC entirely** — the bootstrap admin certificate's group. Treat it like a root key.
- **The default ServiceAccount isn't harmless**: no permissions, but every pod still gets its token mounted at a well-known path. An compromised app hands that token to an attacker. Set `automountServiceAccountToken: false` on pods that don't need API access.

## Debugging permissions

```bash
kubectl auth can-i list pods -n dev --as alice
kubectl auth can-i --list -n monitoring --as system:serviceaccount:monitoring:prometheus
```

`kubectl auth can-i` is the fastest answer to any "can they do X?" question — including "can I?" when your own command fails with a forbidden.

## Big picture

Role (what) + Subject (who) + Binding (glue), namespaced or cluster-scoped, additive-only. This is the mechanism behind the one-liner in [[Ops/DevSecOps/Kubernetes Security]] — least privilege, cluster edition — and the reason RBAC shows up in every one of those controls (Kyverno, ESO, Operators all run as ServiceAccounts with scoped Roles).

Related: [[Ops/Kubernetes/Foundations]] · [[Ops/Kubernetes/Authentication]] · [[Ops/DevSecOps/Kubernetes Security]]
