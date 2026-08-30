# Contents

1. Motivation
2. CI vs CD vs CD
3. The Pipeline
4. Build Stage
5. Test Stage
6. Artifacts and Registries
7. Deployment Strategies
8. Environments and Promotion
9. Secrets in Pipelines
10. Rollback
11. Metrics (DORA)
12. Anti-patterns

## Motivation

tldr; integration pain grows non-linearly with how long branches live.

Before CI, teams merged in "integration weeks" — everyone's month-old branch met for the first time and the merge conflicts, broken tests and environment drift all surfaced at once, right before a release date. CI's bet is simple: if merging hurts, do it more often, and let a machine prove each merge is still good. CD extends the same bet to shipping — if releasing hurts, release more often, in smaller pieces, with an automated path.

The real product of a pipeline is not automation, it's **confidence**. A pipeline you don't trust is worse than none, because people learn to ignore red builds.

## CI vs CD vs CD

- **Continuous Integration** — every push merges to trunk (or a short-lived branch off it) and is automatically built + tested. Goal: trunk is always green.
- **Continuous Delivery** — every green commit produces a deployable artifact and is *ready* to ship. The final push to prod is a human clicking a button.
- **Continuous Deployment** — no button. Green commit goes to prod automatically.

Most regulated shops (payments, healthcare) stop at Delivery deliberately — the button is where change-approval / audit evidence lives. That's a compliance choice, not a maturity failure.

## The Pipeline

A pipeline is a DAG of stages. Canonical shape:

```
commit -> lint -> build -> unit tests -> package -> integration tests -> deploy staging -> e2e -> approval -> deploy prod -> smoke
```

Two rules that matter more than the stage list:

1. **Fail fast, cheap first.** Lint and unit tests run in seconds; put them ahead of the 20-minute e2e suite. Ordering stages by cost is the single biggest feedback-time win.
2. **Build once, promote the same artifact.** Never rebuild per environment. If staging tested image `sha-abc123`, prod runs `sha-abc123`. Rebuilding means you shipped something you never tested.

## Build Stage

- Builds must be **reproducible**: pinned dependency lockfiles, pinned base images (digest, not `:latest`), no network fetches of mutable things.
- Builds must be **hermetic-ish**: same input commit -> same output artifact. If your build reads the wall clock or a mutable remote, it isn't.
- Cache aggressively but key the cache on the lockfile hash, not the branch. Stale caches produce phantom green builds.

## Test Stage

Test pyramid, cheapest and most numerous at the bottom:

- **Unit** — no I/O, milliseconds, thousands of them. The bulk.
- **Integration** — real DB / real queue via ephemeral containers. Hundreds.
- **Contract** — verify service A's assumptions about B's API without booting B. Cheap insurance in a microservice estate.
- **E2E / smoke** — full stack, browser or API-level. Dozens at most. Slow, flaky, expensive; keep them for critical user journeys (login, checkout, payout).

**Flaky tests are a production incident.** A suite that fails 5% of the time randomly trains everyone to hit "re-run", which means real failures get re-run too. Quarantine flakes into a separate non-blocking job and fix or delete them, don't retry-loop them in place.

## Artifacts and Registries

The pipeline's output is an immutable artifact: a container image, a jar, a wheel, a tarball.

- Tag by immutable identity (git SHA), not by moving names. `:latest` in a deploy manifest is how you get an un-reproducible prod.
- Store in a registry (ECR/GCR/Artifactory) with retention policies, else storage cost grows unbounded.
- Sign artifacts (cosign/sigstore) and record a **SBOM** if you have supply-chain requirements. Generate provenance attestations (SLSA) if you're being audited.

## Deployment Strategies

| Strategy     | How                                | Cost     | Rollback                 |
| ------------ | ---------------------------------- | -------- | ------------------------ |
| Recreate     | stop old, start new                | downtime | redeploy old             |
| Rolling      | replace N pods at a time           | none     | roll forward/back slowly |
| Blue/Green   | full parallel stack, flip LB       | 2x infra | instant flip back        |
| Canary       | 1% -> 5% -> 50% -> 100% by metrics | small    | shift traffic back       |
| Feature flag | ship code dark, enable per-cohort  | ~none    | toggle off               |

Canary + feature flags is the strongest combo: deployment and release become separate events. You deploy code continuously and *release* behaviour when the business is ready. It also makes rollback a config change instead of a deploy.

Any strategy that runs old and new code simultaneously (rolling, canary, blue/green) requires **backwards-compatible schema changes**. Expand-migrate-contract: add the new nullable column, dual-write, backfill, switch reads, then drop the old column in a later release. Never in one deploy.

## Environments and Promotion

`dev -> staging -> prod`, with the same artifact promoted through each. Differences between environments should be *config only* (env vars, secrets, scale), never code or build flags.

Ephemeral preview environments per PR are the highest-leverage upgrade for most teams — reviewers get a real URL instead of reading a diff and imagining it.

## Secrets in Pipelines

- Never commit secrets; never echo them into logs. CI providers mask known secret values but only ones they know about — a secret derived or base64'd in a script is not masked.
- Prefer **short-lived, federated credentials** (OIDC to AWS/GCP) over long-lived static keys stored in the CI provider. The trust is then "this repo, this branch, this workflow" rather than "whoever has the key".
- Scope by environment: prod credentials should only be reachable from a protected prod job with required reviewers.
- Never expose secrets to jobs triggered by forked-PR events. That's the classic exfiltration path.

## Rollback

Design the rollback before the deploy. Practical rules:

- Keep the previous artifact deployable and warm.
- Migrations must be reversible or forward-only-safe; a deploy you cannot revert because of a destructive migration is a one-way door — treat it as a separate, deliberate change.
- Automate rollback on smoke-test failure. MTTR is dominated by decision latency, not by mechanics.

## Metrics (DORA)

- **Deployment frequency** — how often you ship.
- **Lead time for change** — commit to prod.
- **Change failure rate** — % of deploys causing incidents.
- **MTTR** — time to recover.

The first two measure throughput, the last two stability. The DORA finding is that they correlate positively — teams that ship more often break things *less*, because batch size is small. If someone argues for slower releases to be safer, this is the counterargument.

## Anti-patterns

- Long-lived feature branches — reintroduces the exact integration pain CI was built to remove.
- Manual steps in the middle of an automated pipeline ("then ping Ravi to run the migration").
- Different build for staging vs prod.
- Snowflake CI runners with hand-installed tooling; runners should be disposable and defined as code.
- Tests that hit real third-party APIs — you inherit their downtime as your build failures.
- Pipeline logic living in a 900-line bash script that only one person understands.

