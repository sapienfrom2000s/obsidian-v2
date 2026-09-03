# Kubernetes — ConfigMaps and Secrets

## ConfigMap

Stores configuration as key-value pairs, separate from the container image. A value can be a single setting or an entire file like `nginx.conf`. The point: the same image runs in dev, staging and prod unchanged — you just point the pod at a different ConfigMap.

The pod consumes it in one of three ways. `configMapKeyRef` injects specific keys as env vars. `envFrom` turns every key into an env var, which is convenient but means new keys silently appear in the pod. Or you mount it as a volume, where each key becomes a file — this is what apps that read config files (nginx, prometheus) need.

Values are always strings. `8080` arrives as `"8080"`.

## Secret

Same mechanism, same three consumption options, but for sensitive data. The differences are in how it's handled, not how it works:

Base64 is not encryption. It exists so binary data (certs, keys) fits in YAML — anyone who can read the Secret decodes it in one command. etcd also stores Secrets as plaintext unless you explicitly enable encryption at rest, so an etcd backup leak exposes every Secret in the cluster. Keep RBAC tight on `get` and `list`; `list` dumps a whole namespace at once. And mount Secrets as files rather than env vars — env var values are visible in `kubectl describe pod`, files aren't.

## External Secrets Operator

Native Secrets don't rotate and have no audit trail, and putting values in Git means committing secrets to Git. ESO moves the source of truth outside the cluster: real values stay in Vault or AWS Secrets Manager, and you create an `ExternalSecret` that holds only a reference. ESO fetches the value from the manager and writes it into a normal Kubernetes Secret, which pods consume like any other. When the value changes in the manager, ESO re-syncs on its `refreshInterval`.

So Git only ever holds the reference, rotation is automatic, and auditing happens in a system built for it. In practice: ConfigMaps for config, native Secrets for internal values, ESO for anything that would be a real incident if it leaked.
