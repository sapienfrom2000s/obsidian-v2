# Kubernetes — Kustomize and Helm

Both exist for the same root problem: **YAML sprawl**. Copy `deployment.yaml` into `-dev`, `-staging`, `-prod` variants and within six months nobody knows what's canonical — a fix lands in two of three files and drift accumulates. The two tools answer different halves:

- **Kustomize** — "how do I customize existing manifests per environment *without duplicating YAML*?"
- **Helm** — "how do I *package, version, and distribute* a Kubernetes application?"

## Kustomize — base/overlays

Built into kubectl (`kubectl apply -k`), no templating language, your YAML stays plain YAML throughout.

- **Base** — the common manifests: the app in its default form, environment-agnostic.
- **Overlay** — one per environment, containing *only what differs*, layered on top of the base.

```
k8s/
├── base/                 # deployment.yaml, service.yaml, kustomization.yaml
└── overlays/
    ├── dev/
    └── prod/             # kustomization.yaml + small patches
```

An overlay's `kustomization.yaml` references the base and declares its differences:

```yaml
resources:
  - ../../base
namespace: production
images:
  - name: my-app
    newTag: v1.4.2        # override the tag without touching base
replicas:
  - name: my-app
    count: 5
```

Beyond patches, built-in transformers handle the common cases: `namePrefix`, `namespace`, `commonLabels`, image tag overrides, replica counts. Two patch formats: **strategic merge** (a partial manifest merged intelligently — the readable default) and **JSON 6902** (explicit `add`/`replace`/`remove` ops — surgical, for removing fields or targeting one list item).

```bash
kubectl apply -k overlays/prod/
kustomize build overlays/prod/   # print rendered YAML without applying
```

One trap: a patch whose target doesn't match a base resource **silently does nothing** — always verify rendered output.

This is why Kustomize fits GitOps (ArgoCD/Flux) so well: base is stable and reviewed, overlay changes are small PR diffs, output is deterministic, and the CD tools support it natively.

## Helm — packaging and releases

A package manager: an app becomes a **versioned, installable chart**. Where Kustomize patches YAML, Helm *generates* YAML from Go templates and manages the release lifecycle (install, upgrade, rollback, uninstall).

A chart is a directory: `Chart.yaml` (name, `version` = chart version, `appVersion` = app version), `values.yaml` (defaults), `templates/` (Go-templated manifests), `charts/` (dependencies).

```yaml
# templates/deployment.yaml — the templating essentials
metadata:
  name: {{ .Release.Name }}-my-app
spec:
  replicas: {{ .Values.replicaCount }}
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
  {{- if .Values.ingress.enabled }}
  ...
  {{- end }}
```

Key objects: `.Values` (values.yaml + overrides), `.Release.Name/.Namespace`, `.Chart.*`. Functions you'll see constantly: `toYaml | nindent`, `default`, `quote`, `if`/`range`.

```bash
helm upgrade --install my-release ./chart -f prod-values.yaml   # idempotent, CI/CD-friendly
helm rollback my-release 2                                      # to a specific revision
helm template my-release ./chart                                # render locally, no cluster
helm install my-release ./chart --dry-run                       # validate against the API server
```

**How rollback works**: each `helm upgrade` stores the fully-rendered manifest for that revision as a **Secret** in the release's namespace. Those secrets *are* the release state — deleting them orphans everything Helm deployed; never hand-edit Helm-managed resources, since the next upgrade re-applies its rendered manifest and silently overwrites your `kubectl edit`.

**Values precedence** (later wins): chart `values.yaml` → `-f` files left to right → `--set`. Passing `-f prod-values.yaml -f base-values.yaml` in that order means base wins — order matters.

**Hooks** run Jobs at lifecycle points (`pre-install`, `pre-upgrade`, `post-rollback`, ...). The classic use: a `pre-upgrade` migration Job that must succeed before the new version goes live.

## Which when

| | Kustomize | Helm |
|---|---|---|
| Approach | patch plain YAML | template + generate |
| Distribution | not its job | core use case (chart repos, OCI) |
| Lifecycle | none | install/upgrade/rollback |
| Customizing third-party apps | awkward | natural — override `values.yaml` |

The common combined pattern: **Helm for infra** (Prometheus, cert-manager, ingress-nginx — installed as charts with a values file each) + **Kustomize for your own apps** (base + env overlays), with ArgoCD/Flux syncing both from Git.

Related: [[Ops/Kubernetes/Foundations]] · [[Ops/Kubernetes/Workloads]]
