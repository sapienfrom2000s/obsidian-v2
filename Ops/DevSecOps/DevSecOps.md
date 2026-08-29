# DevSecOps

Core idea: check for security problems automatically at every step of building software: while writing code, building, deploying, running. Instead of one big security review at the end.

## Mindset & Threat Modeling

### What is DevSecOps

Old way: developers build, then a security team checks everything at the end. Slow, expensive, and problems are found too late. New way: automatic security checks run on every code change. Everyone is responsible for security, not just one team. Why it matters: a problem found after release costs 10 to 100 times more to fix than one caught while coding.

### Shift Left vs Shield Right

- Shift Left: find problems early, before code ships (think about risks first, scan code and secrets before deployment).
- Shield Right: protect the running system (firewalls, monitoring, fixing problems found after release).
- Need both: early checks stop most problems from getting in; runtime protection catches whatever slips through, like a new flaw discovered in a library you shipped months ago.

### Threat Modeling

Before building, draw your system (parts and how data moves between them) and ask "what can go wrong?" Then decide what to do about each risk: fix it, accept it, or avoid it.

STRIDE, a checklist of six ways things go wrong, applied to every part and every arrow in your drawing:
- Spoofing: someone pretends to be someone else
- Tampering: someone changes data
- Repudiation: someone denies doing something, and you can't prove it
- Information Disclosure: data leaks to people who shouldn't see it
- Denial of Service: the system becomes unusable
- Elevation of Privilege: a normal user gains powers they shouldn't have

Tool: OWASP Threat Dragon. Free tool to draw your system and note risks next to each part. Alternatives: Microsoft TMT, PyTM.

### Lab: find risks in a simple web app (browser, API, database)

- Browser to API: fake identity → login with one-time codes; changed data → use HTTPS; system overload → limit request rates, autoscaling
- API to database: fake client → restricted database login, isolate network; leaks → encrypted connection, database user with minimal permissions
- Logs: denied actions → keep logs of who did what, make them unchangeable
- Stored data: leaks → encrypt the database and backups
- Deployment: gained powers → run containers without admin rights, restrict CI/CD access

## Git Security

The problem: Git remembers everything forever. A password committed by mistake stays in history even if the file is deleted later, and bots scan GitHub for leaked secrets automatically. Fixes, in order of when they act:

- `.gitignore`: list of files Git should never track: `.env`, `*.pem`, `*.key`, `id_rsa`, `terraform.tfstate` (may contain secrets in plain text). First line of defense. Does nothing about secrets already committed.
- Pre-commit hooks: Git runs a script automatically before every commit (`.git/hooks/pre-commit`). Script exit 0 means commit allowed, anything else means blocked. You can write your own checks, but every rule, and every teammate's install, is your problem.
- Gitleaks: a tool that knows hundreds of secret patterns (AWS keys, tokens, private keys). Wired as a pre-commit hook via a small config file (`.pre-commit-config.yaml`). Also supports custom rules and can scan the whole repo including old history (`gitleaks detect`).
- Gitleaks in GitHub Actions: the safety net. Local hooks can be skipped, so the same scan also runs on GitHub on every push and pull request, with full history. Defense in depth: local check plus server-side check.
- Branch protection: no direct pushes to `main`, changes only through pull requests, required checks must pass, no force pushes (which could rewrite history).
- Access control (RBAC): everyone gets only the access they need. Admins change settings, maintainers merge, developers open pull requests only, auditors read-only.
- Mandatory reviews + CODEOWNERS: changes need approval before merging. Sensitive folders get assigned owners (e.g. CI folder needs security team approval, terraform folder needs cloud team). Wrong team touching those folders means merge blocked.
- Dependabot: opens automatic pull requests when your project's libraries have known flaws and fixed versions exist.

## Infrastructure-as-Code Security

IaC in one line: describe your servers and cloud resources in code files (e.g. Terraform), run one command, they get built. Code that builds real infrastructure, so mistakes in it are security mistakes.

The problem: Terraform builds insecure things without any warning: a storage bucket open to the whole internet, a server accepting logins from anywhere, no encryption. All valid code, all deployed silently.

- Checkov: reads Terraform before anything is built and flags known bad patterns: public buckets, open ports, missing encryption. Scan with `checkov -d .`, fix, re-scan clean. Same idea as gitleaks, but for infrastructure code instead of secrets.

### Vault: temporary credentials instead of stored keys

Problem it solves: automation needs cloud credentials, and a long-lived key stored in CI settings is a standing risk. Leak once and the attacker owns the account forever.

Flow in one breath:
1. You put one master AWS key into Vault, once, and never touch it again.
2. Every time the pipeline runs, it shows GitHub's signed token to Vault.
3. Vault hands back a fresh AWS key that can only touch S3 and dies soon.
4. Terraform uses that key to build your stuff.
5. Done. No permanent keys stored in GitHub, on your laptop, or in the repo.

How the pipeline proves its identity without a password: GitHub signs a short-lived token naming the repo; Vault checks the signature and the repo name, then vends the temp keys. No secret is ever stored or sent.

Vault vs. a scoped permanent key in GitHub settings:
- Scoped key fixes blast radius only: a stolen key touches just S3. Simple, no extra servers. Fine for hobby projects.
- What it doesn't fix: never expires, leaks are invisible (can't tell which run leaked it), rotation is manual and disruptive, scope creeps over time.
- Vault gives temporary, narrow, per-job credentials, at the cost of running and securing a Vault server itself.
- Rule of thumb: hobby project → scoped key. Real users or data → temporary credentials.

Caveat: the tutorial's Vault setup is a learning demo (dev mode, weak token, open port), not production-grade.

### CI vs CD: who actually creates the infrastructure

- CI (continuous integration): checks code (tests, scans, linting). Changes nothing.
- CD (continuous delivery/deployment): releases (`terraform apply`, deploying containers). Changes real infrastructure.
- In this repo: the gitleaks workflow is pure CI; `infra-create.yml` is really CD (it runs `terraform apply`) but looks like CI. The step that truly needs AWS keys is `terraform apply`: it's the one creating resources, so it's the one AWS must trust.
- In production, apply is never run automatically on every push. Typical setup: a pull request triggers a plan (dry run showing what would change), a human reviews and approves exactly what they saw, and only then does a protected environment run apply, often with a manual click and credentials scoped to just that environment. `apply -auto-approve` on every push (this repo's demo) is fine for learning, wrong for production.

## Container Security

A container is a packaged app with just enough operating system to run. The repo demos a tiny app that prints its user ID, hardened step by step, each fix visible in the output.

Starting point (the Dockerfile everyone writes first): full Node image, copies the whole folder, runs as root. The app prints "User ID: 0", which is root, the admin account. If an attacker breaks the app, they have full control inside the container. As root: install tools, read any file (secrets), replace the app, maybe escape to the host. As a normal user: all denied. Root was never needed, just the default.

Five fixes, in order of impact:
1. Run as a normal user: create an unprivileged user, switch to it before the app starts. Same exploit now lands in an account that can't do much (prints user ID 1000). Smallest change, biggest single win.
2. `.dockerignore`: without it, `COPY . .` bakes git history, `.env` files, and junk into the image: secrets shipped inside the package, and a bigger image means more things that can have flaws. Same idea as `.gitignore`.
3. Multi-stage builds: build the app in one fat image, copy only the finished pieces into a slim image that runs. Compilers and build tools never ship, so attackers who get in find nothing to use.
4. Distroless images: strip almost the entire OS. No shell, no package manager, no utilities. An attacker breaks in and lands in an empty room. Non-root by default (user 65532).
5. Runtime limits: even a clean image gets restrained while running. Read-only filesystem (can't plant files), all special privileges dropped, no gaining new ones, caps on processes, memory and CPU (can't drag the host down). Flags on the `docker run` command.

Scanning tools (the "check" side; the five steps are the "fix" side):
- Trivy: scans built images for known flaws in their libraries. Like Dependabot, but on the finished image instead of the source files, so it also catches flaws in the base image and things Dependabot can't see.
- Hadolint: points out bad instructions in Dockerfiles.

One-line summary: secure container = secure image + hardened runtime. Who runs it, what goes in, what stays in, what tools exist, what it can do.

## Application Security (SAST, SCA, DAST)

Core insight: no single scanner sees everything, because each looks at a different thing.

- SAST (Static Application Security Testing): reads your source code without running it, flagging known bad patterns: hardcoded passwords, SQL queries built by gluing strings, dangerous functions like eval, debug mode left on. Runs early (on every pull request), so it's the shift-left scanner. Blind spots: can't confirm a flaw is actually exploitable, knows nothing about your libraries. Tool: SonarQube.
- SCA (Software Composition Analysis): reads your dependency list and matches versions against known flaw databases ("flask 1.0 has known vulnerabilities"). Same idea as Dependabot and Trivy, at the source level. Even perfect code can be insecure because of vulnerable libraries. Tool: pip-audit.
- DAST (Dynamic Application Security Testing): attacks the running app like a real hacker. No source code, just the website: it crawls pages, fires real attacks, reports what actually worked. Blind spots: only finds what's reachable from outside, can't point to the guilty line of code. Tool: OWASP ZAP.

The repo's demo app (a small Flask API) has real, classic flaws, each found by a different scanner:
- SQL injection: user input glued straight into a database query, letting attackers make the database leak or delete data (found by SAST, confirmed by DAST)
- eval on user input: the calculator endpoint turns typed text into live code, giving the attacker a keyboard to your server (SAST + DAST)
- random.random() for tokens: predictable "random" numbers make guessable security tokens (SAST)
- Debug mode on: gives attackers detailed error pages full of hints (SAST)
- Ancient dependency versions (SCA)

The fix loop, which is DevSecOps in miniature: scan, see findings, fix (parameterized queries, no eval, secrets in environment variables, upgrade dependencies, debug off), re-scan, watch findings disappear. Automated, that loop is the whole point of the course.

## The Full Pipeline (capstone project)

Jerney, a three-tier blog platform, puts all topics together in one GitHub Actions workflow. Details and diagram: [[Jerney]].
