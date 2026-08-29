<details>
<summary>1. How do you secure and maintain Docker images/containers in production?</summary>
<ul>
<li>Use minimal, trusted base images (alpine/distroless) and multi-stage builds — smaller attack surface.</li>
<li>Scan images for vulnerabilities (Trivy, Grype).</li>
<li>Pin image versions, never use <code>latest</code>.</li>
<li>Run containers as non-root users, least privilege, limited resources.</li>
<li>Sign and verify images (Docker Content Trust / Cosign).</li>
<li>Clean up unused images, containers, and volumes regularly (<code>docker system prune</code>); monitor/log containers in production.</li>
</ul>
</details>

<details>
<summary>2. Talk a bit about namespaces.</summary>
Namespaces are a Linux feature which ensure that a process never sees the host — it gets its own networking, processes, hosts, among other things.
</details>

<details>
<summary>3. Multi-stage Dockerfile for a Go app, but the final image is still 800MB. How would you debug and reduce it?</summary>
<p>A proper Go multi-stage build ends up at ~5–20MB, so 800MB means something is structurally wrong.</p>
<ul>
<li><b>Debug first:</b> <code>docker history &lt;image&gt;</code> (or <code>dive</code>) to see which layer carries the weight — a huge layer right after your <code>COPY --from</code> is the leak.</li>
<li><b>Build stage:</b>
<ul>
<li><code>COPY --from=build</code> must grab <b>only the compiled binary</b> (<code>COPY --from=build /app/server .</code>) — copying the source tree, <code>/go</code>, or the module cache into the final stage is the classic cause.</li>
<li>Cache mounts (<code>RUN --mount=type=cache,target=/go/pkg/mod</code> + GOCACHE) → build speed only, not final size.</li>
<li>Build-stage base (<code>golang:1.x</code> vs <code>-alpine</code>) doesn't affect final size either — that stage gets discarded.</li>
</ul>
</li>
<li><b>Final stage:</b>
<ul>
<li>Static binary check: build with <code>CGO_ENABLED=0</code>, verify with <code>file ./server</code> ("statically linked"). Static → base on <code>scratch</code> or <code>distroless/static</code>; CGO unavoidable → <code>distroless/cc</code> or alpine (musl).</li>
<li>Strip symbols: <code>go build -ldflags="-s -w"</code> → ~30% smaller binary.</li>
<li>Minimal but functional: from <code>scratch</code> copy in CA certs + tzdata yourself; <code>distroless/static</code> ships them. Non-root user either way.</li>
<li>Nothing after the COPY — every RUN/ADD in the final stage becomes a permanent layer.</li>
</ul>
</li>
<li><b>Also:</b> <code>.dockerignore</code> (.git, test data, docs) — bloats build context / busts cache more than final size, but fix it anyway.</li>
</ul>
</details>

<details>
<summary>4. A container can't reach another container by name on the same custom bridge network, but reaching it by IP works. What's going on, and how do you fix it?</summary>
<p>IP works → routing/connectivity is fine. This is a <b>DNS resolution</b> problem, not a networking one.</p>
<ul>
<li><b>Key fact:</b> on a user-defined bridge, Docker runs an embedded DNS server at <code>127.0.0.11</code> inside every container and auto-registers container names. On the default bridge this doesn't exist at all (only legacy <code>--link</code>). So first: are both containers actually attached to the same custom network?
<ul>
<li><code>docker network inspect &lt;network&gt;</code> — classic root cause is one container accidentally left on the default bridge or a different network.</li>
</ul>
</li>
<li><b>Check <code>/etc/resolv.conf</code></b> inside the container: it must show <code>nameserver 127.0.0.11</code>. If DNS was overridden (<code>--dns</code> flag elsewhere) or the base image ships its own resolv.conf, embedded DNS gets bypassed.</li>
<li><b>Check <code>--network-alias</code>:</b> the container may be registered under an alias rather than resolving by its container name — common trip-up.</li>
<li><b>Isolate resolution itself:</b> run <code>nslookup &lt;other_container&gt;</code> or <code>getent hosts &lt;other_container&gt;</code> from inside.
<ul>
<li>No answer → name isn't registered / embedded DNS not in path → back to network + resolv.conf checks.</li>
<li>Wrong/stale IP → target was recreated and got a new IP while something cached the old answer (container IPs change across restarts).</li>
</ul>
</li>
<li><b>Reality check:</b> embedded DNS essentially never "goes down" — misconfiguration or wrong-network attachment is the real-world failure mode, so lead with those.</li>
</ul>
</details>

<details>
<summary>5. Explain the difference between a Docker volume and a bind mount. Then describe a production scenario where using a bind mount would actually be the wrong choice, and why.</summary>
<p><b>Volume:</b> storage managed by Docker itself — lives under Docker's own area (<code>/var/lib/docker/volumes</code>), created/removed via <code>docker volume</code>, and can be backed by volume drivers/plugins. <b>Bind mount:</b> an arbitrary host directory mapped straight into the container at a fixed host path — Docker just passes it through, and the data's lifecycle belongs to the host machine.</p>
<ul>
<li><b>Portability:</b> bind mounts tie you to the exact host filesystem layout. With orchestrators (Swarm, ECS, Kubernetes-style scheduling), containers get placed on different nodes — a bind-mount path that exists on Node A may not exist or may hold different content on Node B. Named volumes (especially driver-backed) are the portable, orchestration-friendly choice.</li>
<li><b>Permissions/security:</b> bind mounts expose host permissions and UID/GID mapping directly into the container. Classic example: mounting <code>/var/run/docker.sock</code> or another sensitive host path — a well-known privilege-escalation / container-escape vector.</li>
<li><b>Performance/isolation:</b> on Docker Desktop (macOS/Windows), bind mounts cross a filesystem translation layer (osxfs / gRPC-FUSE) that's significantly slower than native volumes for I/O-heavy workloads — matters for dev-vs-prod parity discussions.</li>
<li><b>Ecosystem features:</b> volumes support drivers/plugins (cloud block storage, NFS), enabling backups, replication, multi-host storage. Bind mounts get none of that — they're just a raw path.</li>
</ul>
<p><b>The wrong-choice scenario:</b> bind-mounting an app's config or data from a specific host path across a multi-node Swarm/ECS cluster — works fine on a single dev box, then breaks the moment the scheduler lands the container on a different node (path missing or stale content). Same family of mistake as bind-mounting the Docker socket for convenience: convenient locally, dangerous at production scale.</p>
</details>
