# Jerney — DevSecOps Project

A three-tier blog platform (React frontend, Node.js backend, PostgreSQL database) used as the capstone of the DevSecOps-Zero-to-Hero course: the same app exists twice, once deployed the naive way, once with a full DevSecOps pipeline.

Repo: https://github.com/iam-veeramalla/Jerney
Related notes: [[DevSecOps]], [[Kubernetes Security]], [[Terraform]]

## The App

Classic three tiers:

- Frontend: React (Vite) served by Nginx on port 80
- Backend: Node.js Express API on port 5000 (posts and comments endpoints)
- Database: PostgreSQL on port 5432

Two branches tell the story:

- `main`: the "before". Plain source code deployed manually on a single EC2 server via a setup script (install Node, PostgreSQL, Nginx, PM2 by hand).
- `devops`: the "after". Same app, full DevSecOps: Docker, Kubernetes on AWS (EKS), Terraform, GitHub Actions pipelines, security scanning at every stage.

## The Three Pipelines

The `devops` branch runs three separate pipelines. All stages run in the CI pipeline, on GitHub's servers, not on your machine: GitHub spins up a fresh VM, checks out the code, and runs every check there. Local checks (IDE linting, running audit yourself) are optional and skippable; the pipeline checks are enforced on every push, no exceptions.

### App pipeline

Runs on every push and pull request. Stages, cheapest checks first:

1. Lint: ESLint on frontend and backend
2. SCA: npm audit flags known flaws in dependencies
3. Dockerfile lint: Hadolint on both Dockerfiles (static check, so it runs before anything is built)
4. Build: Docker images for both components, tagged with the commit ID, SBOM generated (ingredients list of each image)
5. Image scan: Trivy scans the built images, fails the pipeline on critical or high flaws
6. Push: only clean images are pushed to GitHub Container Registry (scan before push, so flawed images never reach the registry)

### Terraform pipeline

Manages cloud infrastructure: it builds the EKS cluster itself. Changes are rare and dangerous, so this pipeline is the most heavily gated. Stages:

1. Checkov scan on the Terraform code
2. terraform plan (dry run showing what would change)
3. Manual approval: a human reviews and approves exactly what the plan showed
4. terraform apply, with credentials scoped to just this stage

### K8s manifest pipeline

Manages workload configuration: what runs inside the cluster (images, ports, limits). Changes are frequent and routine, updated on every deploy. Stages:

1. Checkov scan on the Kubernetes manifests
2. On merge to main: rewrite the manifest to point at the new image tags (by commit ID) and commit it. GitOps style: the config in Git always says exactly which version should run, and the cluster pulls that exact version.

### Security details

- Pipeline permissions are read-only by default; write access is granted per stage only where needed
- `.dockerignore` in both components
- Terraform split into main.tf, variables.tf, outputs.tf, provider.tf, tfvars
- Least privilege carried through from commit to cluster

### How it maps to the course

Every stage is a topic from the notes. Lint and SCA are the shift-left checks from Application Security, Trivy and Hadolint are from Container Security, Checkov is from IaC Security, the manual approval on Terraform is CI vs CD done right (the dangerous apply step never runs automatically), and the permission model is the Git Security mindset.

## How Secrets Are Pulled

No secret is ever stored in Git or hardcoded. Every pipeline that needs credentials gets them at the moment it needs them, and only for as long as it needs them.

### GitHub Actions authenticating to AWS (Terraform pipeline)

The pipeline needs AWS credentials to run plan and apply. It does not store an AWS key anywhere:

1. When the workflow starts, GitHub generates a token describing this exact run: which repo, which branch, which commit, which job. The token lives for a few minutes. GitHub then signs it with its private key, like a wax seal that only GitHub can make and anyone can verify with GitHub's public key. This whole scheme is called OIDC
2. The pipeline shows the token to AWS
3. AWS verifies the signature and checks the repo and role restrictions configured in the IAM role's trust policy
4. AWS hands back temporary credentials (access key, secret key, session token) that expire after minutes to hours, scoped to what the role allows
5. terraform plan and apply use those credentials; then they die

Same pattern as Vault on Day 3, but the "front desk" is AWS itself and the signed token comes from GitHub. Nothing to leak, nothing to rotate, no keys in repo settings.

### The GITHUB_TOKEN (pipeline's own identity)

Each workflow run automatically gets a built-in token (`GITHUB_TOKEN`) representing itself. Jerney grants it only what each stage needs: read-only everywhere by default, write to packages for the push stage, write to contents for the manifest update. The token expires when the run ends, so a leaked token from one run is useless later.

### Application secrets (database password)

The app's database password never passes through the pipeline at all:

1. The password lives in a secret store on the cluster side (Kubernetes Secret synced from an external store like Vault, via the External Secrets Operator pattern from the Kubernetes notes)
2. The K8s manifest in Git contains only a reference to the secret name, never the value
3. When a pod starts, Kubernetes injects the password into the container as an environment variable
4. The container reads it like any other environment variable; the code never changes

So the pipeline builds and deploys images without ever seeing a single secret: images are generic, secrets arrive at runtime, where they're used.

The rule the whole section follows: secrets are delivered to the place that needs them, at the moment they're needed, and nothing upstream ever holds them.

## Diagram

![[Excalidraw/Jerney Pipeline.excalidraw.md|100%]]

Source: [[Excalidraw/Jerney Pipeline.excalidraw.md|Jerney Pipeline (Excalidraw)]]
