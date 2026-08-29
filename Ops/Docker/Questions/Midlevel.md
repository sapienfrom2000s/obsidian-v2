## Mid-level Docker Questions

Practical — separates people who've actually written Dockerfiles and debugged
real images from people who've only run `docker run hello-world`.

<details>
<summary>1. How to reduce container image size?</summary>
Use multi-stage builds to throw out build-only dependencies, start from a minimal or distroless base image, combine RUN steps and clean up caches in the same layer, and avoid adding tools you don't need at runtime. Smaller image also means smaller attack surface.
</details>

<details>
<summary>2. What's the difference between CMD and ENTRYPOINT in a Dockerfile?</summary>
`ENTRYPOINT` sets the fixed executable for the container. `CMD` provides default arguments or a default command that can be overridden at runtime. When both are set, `CMD` usually supplies arguments to `ENTRYPOINT`.
</details>

<details>
<summary>3. What are dangling images?</summary>
Dangling images are images with no tag or name (shown as `&lt;none&gt;:&lt;none&gt;`). They're mainly created when you rebuild an image using a tag that already points to an older image — Docker moves the tag to the new image, and the old one is left behind untagged. They still take up disk space and should be cleaned up with `docker image prune`.
</details>

<details>
<summary>4. COPY vs ADD. Which one to use?</summary>
COPY just supports copying local files. ADD supports copying local files, remote files, and archives. Docker's official documentation recommends using COPY for most cases. Reserve ADD only for scenarios where you specifically need its unique, automatic tar extraction capability for a local file.
</details>

<details>
<summary>5. How do you stop, remove, and recreate a container (e.g. to update it or reattach with fresh state)?</summary>
docker stop my_container
docker rm my_container
docker run -d --name my_container -v my_volume:/app/data my_image

As long as the data lives in a named volume (not the container's writable layer), removing and recreating the container is safe — the volume persists independently and gets remounted into the new container.
</details>

<details>
<summary>6. A container keeps restarting in a crash loop. What commands do you use to figure out why?</summary>
<ul>
<li><code>docker ps -a</code> — status like <code>Restarting (137) 5s ago</code>; the number in parentheses is the last exit code and already hints at the cause.</li>
<li><b>Decode the exit code:</b> 137 → killed (OOM or SIGKILL), 139 → segfault, 126/127 → can't execute / command not found (bad ENTRYPOINT path), 1 → generic app error.</li>
<li><code>docker logs --tail 100 &lt;container&gt;</code> — the actual error message; logs persist across restarts so you see the repeated crash output.</li>
<li><code>docker inspect &lt;container&gt;</code> — check <code>.State.ExitCode</code>, <code>.State.OOMKilled</code>, <code>.State.Error</code>, <code>RestartCount</code>, and whether an aggressive <code>RestartPolicy</code> is just masking a persistent failure.</li>
<li><code>docker events</code> — watch <code>die</code>/<code>restart</code> events live while it loops.</li>
<li>If it exits too fast to inspect: rerun overriding the entrypoint (<code>docker run --rm -it --entrypoint sh &lt;image&gt;</code>) and poke at config, env vars, paths, and permissions interactively.</li>
<li>If OOM-killed: compare memory limit (<code>--memory</code>) against real usage (<code>docker stats</code>) — raise the limit or fix the leak.</li>
</ul>
</details>

<details>
<summary>7. Explain the difference between the default bridge network and a user-defined bridge network.</summary>
<p>Both let containers on the same host talk to each other through a software bridge — but user-defined bridges are what you use for anything real.</p>
<ul>
<li><b>DNS:</b> user-defined networks run Docker's embedded DNS (<code>127.0.0.11</code>) — containers resolve each other automatically by name and network alias. The default bridge has no automatic name resolution at all (only the legacy, deprecated <code>--link</code>).</li>
<li><b>Isolation:</b> each user-defined bridge is its own isolated network — containers on network A can't reach network B unless attached to both. The default bridge is one flat shared network where every container can reach every other.</li>
<li><b>Dynamic attach/detach:</b> you can <code>docker network connect/disconnect</code> a user-defined network on a running container without restarting it; changing default-bridge connectivity means recreating the container.</li>
<li><b>Configurability:</b> user-defined bridges get their own subnet, gateway, and IP range (<code>docker network create --subnet ...</code>). The default <code>docker0</code> is effectively fixed (daemon-wide config only).</li>
<li><b>Takeaway:</b> default bridge is fine for throwaway single-container experiments; any multi-container setup gets its own user-defined network.</li>
</ul>
</details>
