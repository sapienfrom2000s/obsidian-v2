# Kubernetes — ConfigMaps and Secrets

## Why both exist

Same image, every environment: DB URLs differ per env, feature flags change, credentials must never be baked in. If config lives inside the image, every config change means a rebuild — and credentials risk leaking into source control. ConfigMaps and Secrets decouple code from configuration: **one image runs everywhere, config is injected at runtime.**

- **ConfigMap** — non-sensitive config, key-value, plain text.
- **Secret** — sensitive data, same mechanics, different handling.

## ConfigMap — three ways to consume

Create declaratively (or `kubectl create configmap --from-literal/--from-file` for quick tests). Values are always strings; a key can also hold a whole file (e.g. `nginx.conf: |`). Then consume one of three ways:

1. **Individual env vars** — `env[].valueFrom.configMapKeyRef`. Explicit, verbose.
2. **All keys as env vars** — `envFrom[].configMapRef`. Convenient, but new keys silently appear as env vars.
3. **Mounted as files** — a `configMap` volume where each key becomes a file. For apps that read config from files (nginx, prometheus).

Same three patterns apply to Secrets (`secretKeyRef` / `secretRef` / `secret` volume). For Secrets, **file mounts are the production preference**: the value never shows in `kubectl describe pod` (env vars do), you can set file permissions (`defaultMode: 0400`, `readOnly: true`), and updates propagate.

## Secrets — the honest security picture

Your [[Ops/DevSecOps/Kubernetes Security]] note covers the operational side; the essentials:

- **Base64 is encoding, not encryption.** Anyone who can read the Secret object decodes it in one command. The base64 exists because Secrets can hold arbitrary binary (TLS certs, SSH keys) that YAML can't represent safely — a transport encoding, not a security mechanism.
- **Secrets are not encrypted in etcd by default** — stored as base64 plaintext; an etcd backup leak exposes every secret in the cluster. Encryption at rest exists but must be explicitly enabled (`EncryptionConfiguration` on the API server); on managed clusters, check whether it's on.
- **Defense in depth**: encryption at rest → RBAC restricting `get`/`list` on Secrets → file mounts over env vars → external secret manager for the crown jewels.

**`stringData` vs `data`**: `data` requires base64-encoded values, `stringData` takes plaintext and K8s encodes on save (write-only — `get -o yaml` always returns `data`).

**Types**: most you create are `Opaque`; the built-ins you'll meet are `kubernetes.io/tls` (Ingress certs), `kubernetes.io/dockerconfigjson` (private registry pulls — `imagePullSecrets`), and service-account tokens.

## External Secrets Operator

Native Secrets don't rotate, audit, or cross clusters. ESO keeps the real values in Vault/AWS Secrets Manager/GCP and syncs them into ordinary Kubernetes Secrets via an `ExternalSecret` object — pods consume them normally, rotation syncs automatically on `refreshInterval`. Git holds only the reference. (Details in [[Ops/DevSecOps/Kubernetes Security]].)

## The update gotcha — env vars freeze, files don't

Update a ConfigMap/Secret a pod is already using:

- **Mounted as files** → kubelet re-syncs the volume automatically (~1–2 min delay). The app must watch and reload — but no restart.
- **Env vars** → **frozen at container start.** The pod keeps the old value until restarted.

So 12-factor env-var apps need `kubectl rollout restart deployment/my-app` after config changes — or the Helm trick of a checksum annotation on the pod template that changes whenever the config changes, forcing a rolling restart on every `apply`.

## Immutable ConfigMaps/Secrets

`immutable: true` (K8s 1.21+) — can't be updated, only deleted and recreated. Buys performance (kubelet stops watching the object; matters at thousands of pods) and safety (no accidental silent updates). Changing means a deliberate delete-recreate-rollout.

## Big picture

ConfigMaps and Secrets are the same mechanism with different sensitivity: keys become env vars or files, injected at runtime. Remember the two asymmetries — **Secrets aren't encrypted by default**, and **env vars don't update without a restart** — and most of the real-world pain disappears.

Related: [[Ops/Kubernetes/Foundations]] · [[Ops/Kubernetes/Pods]] · [[Ops/DevSecOps/Kubernetes Security]]
