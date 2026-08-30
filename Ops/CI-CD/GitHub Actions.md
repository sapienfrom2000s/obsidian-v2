# Contents

1. Mental Model
2. Workflow Anatomy
3. Events and Triggers
4. Runners
5. Jobs, Steps, Matrix
6. Contexts and Expressions
7. Passing Data (outputs, artifacts, cache)
8. Secrets, Environments, OIDC
9. Reusable Workflows vs Composite Actions
10. Concurrency and Cost Control
11. Security Model
12. Debugging
13. Cheatsheet

## Mental Model

A **workflow** is a YAML file in `.github/workflows/` that reacts to an **event**. It contains **jobs**, which run in parallel by default on separate **runners** (fresh VMs/containers). A job contains **steps**, which run sequentially in the same filesystem and can be either a shell command (`run`) or a packaged **action** (`uses`).

Key consequence of "separate runners": jobs share nothing by default — not files, not env vars, not the checkout. Anything crossing a job boundary must go through outputs, artifacts, or cache.

## Workflow Anatomy

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read          # deny-by-default; grant per job what's needed

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npm test
```

## Events and Triggers

- `push`, `pull_request` — the common two. Filter with `branches`, `paths`, `tags`.
- `pull_request_target` — runs in the *base* repo context with secrets, on the base ref. Dangerous: never check out and execute PR head code in this trigger. This is the #1 GH Actions CVE pattern.
- `workflow_dispatch` — manual button, supports typed `inputs`. Your "deploy to prod" trigger.
- `schedule` — cron, **UTC only**. For a 09:00 IST job use `30 3 * * *`. Scheduled runs are also deprioritised and can be delayed or skipped on busy repos; don't depend on precise timing.
- `workflow_run` — chain a workflow off another's completion.
- `repository_dispatch` — triggered by external API call.
- `issues`, `release`, `deployment` — automation hooks.

`paths` filters are how you stop a monorepo from running everything on every commit. Note: a `paths`-skipped required check shows as pending forever unless you add a dummy "always green" job with the same name.

## Runners

- **GitHub-hosted** — `ubuntu-latest`, `windows-latest`, `macos-latest`. Clean VM per job, preinstalled toolchains, billed per-minute (Linux 1x, Windows 2x, macOS 10x). Free for public repos.
- **Self-hosted** — your infra, your network. Use when you need VPC access, large caches, GPUs, or cheap compute at volume. **Never attach self-hosted runners to a public repo** — a forked PR can execute arbitrary code on your machine.
- **Larger runners** — paid bigger GitHub-hosted machines; usually cheaper than the engineering time spent optimising a build to fit 2 cores.
- Runners are ephemeral: nothing persists between jobs except what you explicitly cache or upload.

## Jobs, Steps, Matrix

```yaml
jobs:
  build:
    strategy:
      fail-fast: false
      max-parallel: 4
      matrix:
        python: ["3.10", "3.11", "3.12"]
        os: [ubuntu-latest, macos-latest]
        exclude:
          - os: macos-latest
            python: "3.10"
    runs-on: ${{ matrix.os }}
```

- `needs: [build]` creates the dependency DAG. Without `needs`, jobs are parallel.
- `if:` controls conditional execution. Note that `if` on a job with `needs` implies "only if needs succeeded" — to run on failure you need `if: ${{ always() }}` or `failure()`.
- `continue-on-error: true` marks a step non-blocking (good for flaky-quarantine jobs).
- Steps in a job share the working directory and the `$GITHUB_ENV` file, so `echo "K=v" >> $GITHUB_ENV` exports to later steps.

## Contexts and Expressions

`${{ }}` expressions read from contexts: `github`, `env`, `vars`, `secrets`, `job`, `steps`, `needs`, `matrix`, `runner`, `inputs`.

Useful ones:

- `github.sha`, `github.ref`, `github.ref_name`, `github.event_name`
- `github.event.pull_request.number`, `.head_ref`, `.draft`
- `github.repository`, `github.actor`, `github.run_id`
- `needs.build.outputs.image_tag`
- `steps.<id>.outcome` / `.conclusion`

Functions: `contains()`, `startsWith()`, `format()`, `toJSON()`, `fromJSON()`, `hashFiles()`, and the status checks `success()`, `failure()`, `cancelled()`, `always()`.

`fromJSON` is the trick for a dynamic matrix — one job emits a JSON list, the next consumes it as `matrix: ${{ fromJSON(needs.plan.outputs.list) }}`.

## Passing Data

**Step outputs** (same job):
```yaml
- id: meta
  run: echo "tag=sha-${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
- run: echo ${{ steps.meta.outputs.tag }}
```

**Job outputs** (across jobs):
```yaml
jobs:
  build:
    outputs:
      tag: ${{ steps.meta.outputs.tag }}
  deploy:
    needs: build
    steps:
      - run: deploy --tag ${{ needs.build.outputs.tag }}
```

**Artifacts** — files across jobs and downloadable from the UI. `actions/upload-artifact@v4` / `download-artifact@v4`. Retention is billed; set `retention-days` low for build junk. v4 artifacts are immutable — you cannot append to the same name from a matrix, use `name: report-${{ matrix.os }}` and `merge-multiple: true` on download.

**Cache** — `actions/cache@v4`, keyed on lockfile hash:
```yaml
- uses: actions/cache@v4
  with:
    path: ~/.npm
    key: npm-${{ runner.os }}-${{ hashFiles('**/package-lock.json') }}
    restore-keys: npm-${{ runner.os }}-
```
Cache is a speed optimisation, never a correctness dependency — a cold cache must still produce a correct build. Caches are scoped: a branch can read main's cache, but not a sibling branch's.

Rule of thumb: **cache = reconstructible, artifact = the thing you built.**

## Secrets, Environments, OIDC

- Repo/org secrets: `${{ secrets.FOO }}`. Masked in logs, but only exact-match — don't transform them before printing.
- Secrets are **not** passed to workflows triggered by `pull_request` from a fork. That's deliberate.
- **Environments** (`environment: production`) add required reviewers, wait timers, branch restrictions and environment-scoped secrets. This is where a Continuous Delivery approval gate lives, and it's the audit trail an auditor will ask for.
- **OIDC** is the right way to reach a cloud. No stored keys:
```yaml
permissions:
  id-token: write
  contents: read
steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::123456789012:role/gha-deploy
      aws-region: ap-south-1
```
Constrain the IAM trust policy on `sub` (repo + ref + environment), otherwise any repo in the org can assume the role.

## Reusable Workflows vs Composite Actions

- **Reusable workflow** (`on: workflow_call`, invoked as `uses: org/repo/.github/workflows/x.yml@v1`) — packages whole *jobs*, can specify its own runners, secrets, environments. Use for "our standard deploy pipeline".
- **Composite action** (`action.yml` with `runs: using: composite`) — packages a group of *steps* inside someone else's job. Use for "our standard setup: checkout, auth, install toolchain".

Version both by tag and consume by tag, not by `@main`. For third-party actions, pin to a **commit SHA** — tags are mutable and a compromised action runs with your secrets.

## Concurrency and Cost Control

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```
Cancels superseded runs on the same branch — the single biggest CI bill reduction for most repos. For deploy jobs use `cancel-in-progress: false` with a fixed group name so deploys queue instead of racing.

Other levers: `paths` filters, `timeout-minutes` on every job (default is 6 hours of burn on a hung job), matrix pruning on PRs (full matrix only on main), and skipping drafts with `if: github.event.pull_request.draft == false`.

## Security Model

- Set `permissions: contents: read` at workflow level, escalate per job. The default token is broad.
- `GITHUB_TOKEN` is scoped to the repo and expires with the job.
- Untrusted input (`github.event.pull_request.title`, issue bodies, branch names) interpolated into a `run:` block is a **script injection** — the value is substituted into the shell before execution. Pass via `env:` and reference `"$TITLE"` instead of `${{ ... }}` inline.
- Never `pull_request_target` + checkout of `head.sha` + build. That gives fork authors your secrets.
- Enable Dependabot for action versions; audit third-party actions before adoption.
- Branch protection: required status checks, required reviews, and no bypass for admins if you're being audited.

## Debugging

- Re-run with debug logging: set repo secrets `ACTIONS_STEP_DEBUG=true`, `ACTIONS_RUNNER_DEBUG=true`, or use "Re-run with debug logging" in the UI.
- `act` runs workflows locally against Docker — imperfect fidelity but fine for YAML/syntax loops.
- A tmate step (`mxschmitt/action-tmate`) gives an SSH shell into a live runner. Never leave it in a workflow on a repo with secrets.
- `echo "::group::name"` / `::endgroup::` to fold log sections; `$GITHUB_STEP_SUMMARY` to write markdown into the run summary page — good place to dump test results or a terraform plan diff.

## Cheatsheet

```yaml
# conditionals
if: github.ref == 'refs/heads/main'
if: ${{ always() }}
if: ${{ failure() }}
if: contains(github.event.pull_request.labels.*.name, 'deploy')

# manual trigger with inputs
on:
  workflow_dispatch:
    inputs:
      env:
        type: choice
        options: [staging, production]

# service container for integration tests
services:
  postgres:
    image: postgres:16
    env: { POSTGRES_PASSWORD: postgres }
    options: >-
      --health-cmd pg_isready --health-interval 10s --health-retries 5
    ports: ['5432:5432']

# env / output / summary files
echo "KEY=value" >> "$GITHUB_ENV"
echo "key=value" >> "$GITHUB_OUTPUT"
echo "### Results" >> "$GITHUB_STEP_SUMMARY"
echo "::add-mask::$COMPUTED_SECRET"
```
