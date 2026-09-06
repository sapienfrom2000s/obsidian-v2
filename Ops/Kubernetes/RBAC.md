# Kubernetes — RBAC

## Short Overview

RBAC (Role-Based Access Control) decides **who can do what** in a cluster. Every action in Kubernetes (creating a pod, reading a Secret, deleting a deployment) is an API request — RBAC is the gatekeeper that says "allowed" or "denied" for each one.

## Why is it needed

- Without it, anyone with cluster access could do anything — delete production, read secrets, take over nodes.
- It enforces **least privilege**: people and apps only get the permissions they actually need.
- It replaced the old ABAC method (a static JSON file on the server). RBAC permissions are normal Kubernetes objects — you can manage them with `kubectl`, store them in Git, and change them without restarting the API server.

## Users and Groups

- **Users** are humans. Kubernetes has no "user" object — the name comes from outside (a certificate or login token). You can't `kubectl get users`.
- **Groups** are also external (from the certificate/token) and let you grant a whole team at once — e.g. "dev-team" gets read access.

## Role

A **Role** is a list of permissions **inside one namespace**. It says what actions (verbs) can be done on which resources.

```yaml
kind: Role
metadata:
  name: pod-reader
  namespace: dev
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
```

This Role allows *reading* pods — only in the `dev` namespace.

## RoleBinding

A **RoleBinding** connects a Role to a person, group, or ServiceAccount — within that same namespace. It's the glue: Role = *what* is allowed, Binding = *who* gets it.

```yaml
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

Now alice can read pods in `dev`.

## ClusterRole

Same idea as a Role, but **cluster-wide**. Used for:

- Resources that aren't in any namespace (nodes, persistent volumes)
- Reusable permission sets you can bind in many namespaces

## ClusterRoleBinding

Grants a ClusterRole across the **entire cluster** — the subject gets those permissions everywhere. Powerful; use sparingly.

> Handy trick: a ClusterRole bound with a normal **RoleBinding** applies only in that one namespace — a great way to reuse one permission set per namespace without giving cluster-wide access.

## ServiceAccounts

- ServiceAccounts are identities for **apps/pods**, not humans.
- Every namespace gets a `default` ServiceAccount, and every pod uses it unless told otherwise.
- When your app talks to the Kubernetes API, it's acting as its ServiceAccount.
- Tip: pods that don't need API access should set `automountServiceAccountToken: false` — the default token is a freebie for attackers if the app is compromised.

## Summary

- RBAC = who (User / Group / ServiceAccount) + what (Role / ClusterRole) + glue (Binding).
- Role + RoleBinding → namespaced. ClusterRole + ClusterRoleBinding → cluster-wide. ClusterRole + RoleBinding → reusable, namespaced.
- Permissions are **additive only** — there is no "deny" rule; you only list allows.
- Subresources like `pods/log` need their own explicit rules.
- Check anything fast with `kubectl auth can-i <verb> <resource> -n <ns> --as <user>`.

