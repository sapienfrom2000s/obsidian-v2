# Contents

1. Motivation
2. Namespaces and Cgroups
3. Container Runtime
4. Container vs VM
5. Docker
6. Docker Networking
7. OverlayFS(and Docker)
8. Image Layering and caching
9. Persisting data with docker
10. Multistage Builds
11. Docker Swarm and Docker Compose
12. Cheatsheet

## Motivation

tldr; It solves the problem of 'it works on my system'

Before docker, in order to setup a dev environment, a dev had to go through a lot of hassle - google the error, find answers in blogs, stackoverflow and run it. Two different devs who tried to setup the same environment might have different results due to various reasons like different OS versions, package managers, etc. Docker came up and said, I don't care what is the underlying dependencies, I will give you sort of an isolated system where you can replicate the same environment across different machines and OS's w/o any conflicts.

## Namespaces, Cgroups and chroot

All of the above are features of linux.

From arch wiki:

A chroot is an operation that changes the apparent root directory for the current running process and their children. A program that is run in such a modified environment cannot access files and commands outside that environmental directory tree. This modified environment is called a chroot jail.

E.g.- Let's say you opened vim by running `vim` in terminal, linux went through the PATH and found it in `/usr/bin/vim`. Now, you went ahead and made some `/dir` the new root using `chroot`. When you try to open `vim` now, it's possible that this time the program will not be able to find the vim binary because it is not in the new root directory.

A namespace makes a group of processes see its own private slice of the system, instead of the whole machine. Two processes can run on the same host but each thinks it has its own processes, network, filesystem, or users — they just can't see each other's. Linux gives you a namespace per resource type: Process (own PID tree), Network (own IPs/ports/routes), Filesystem (own mount view), and User (own UID/GID mapping).

cgroups are a Linux kernel feature that allow you to put limits on resource usage (CPU, memory, disk I/O, network, etc.) on processes.

### How this becomes a container

A container is just a normal Linux process wearing three pieces of gear: chroot gives it its own filesystem, namespaces give it its own view of the world (processes, network, users), and cgroups cap how much of the machine it's allowed to use. Docker doesn't invent isolation — it just bundles these three existing Linux features together and gives you a friendly CLI on top.

## Container Runtime

A container runtime manages a container's lifecycle. Two layers, split by job:

- **containerd / CRI-O** (high-level) — the "manager". Pulls images, manages storage and networking, tracks running containers, exposes an API for something else to drive it. containerd is Docker's manager; CRI-O is the same job built for Kubernetes. Neither actually creates the isolated process itself.
- **runc** (low-level) — the "worker". Does one thing: take a filesystem + config, wrap it in namespaces and cgroups, start the process, then step back. No images, no networking, no API — just this one process.
- **OCI** (Open Container Initiative) — not software, a spec. It's the agreed contract for what an image looks like and what a low-level runtime must accept/do. runc is just one implementation of that spec, which is why it's swappable with others (crun, gVisor) without containerd caring.

Chain: Docker CLI -> dockerd -> containerd (manager) -> runc (worker, OCI spec) -> kernel.
Docker uses containerd as its runtime by default.

## Container vs VM

Container is a collection of processes running in isolation on an OS. VM can run multiple OS in a machine. So you can run multiple containers on multiple VM's. Container's are a higher layer abstraction than VM's. In real world we use the power of both. We buy VMs from cloud providers and run containers on them.

## Docker

![[Pasted image 20260820074419.png]]

Docker CLI/UI -> Docker Engine (dockerd) -> containerd -> runc -> Linux kernel (namespaces, cgroups)

Docker is a platform that helps in the management of containers. It's a higher level abstraction than container runtime. As you can see that
docker cli and docker engine(dockerd) is an additional layer provided by docker.

Dockerfile is a file that contains instructions to build a docker image.

Docker image is a collection of files which contains all the dependencies required to run an application.
From docker - "A container image is a standardized package that includes all of the files, binaries, libraries, and configurations to run a container"

## Docker Networking

1. https://www.youtube.com/watch?v=j_UUnlVC2Ss(Also, check what is a switch device)
2. https://docs.docker.com/engine/network/(Just focus on bridge, host, overlay and none)

## OverlayFS(Image Layering)

https://www.youtube.com/watch?v=R5UzWd833bg

Q: If Docker uses OverlayFS (union FS), why can’t it just rebuild the changed layer and reuse the rest?

A: Because each Docker layer is a diff computed against its exact parent layer; if a parent changes, the filesystem state changes, so all subsequent layer diffs become invalid and must be rebuilt — union FS only merges layers at runtime, it doesn’t make them independent during build.

## Persisting data with docker

Docker offers the following options for persisting data:

- Bind mounts: Mount local path to container path
- Volumes: Docker feature, manages storage for user, abstracts away path
- tmpfs: data is stored in memory

## Multi-stage builds

Multi stage builds can heavily decrease the size of the final image size. The idea is that you throw out the dependencies that were only needed to build the image. For e.g.- In case of go, you just need the final binary in order to serve the applications, you can
throw out other dependencies but those dependencies were needed to create the binary image.

## Docker Swarm and Docker Compose

Docker compose is used to connect multiple containers running locally using a single configuration file on a single node.
Docker Swarm is used in production to manage multiple containers running on multiple machines.

# Docker cheatsheet

### Build and images

- Build: `docker build -t myapp:1.0 .`
- List: `docker images`
- Remove: `docker rmi myapp:1.0`
- Tag (for pushing to a registry): `docker tag myapp:1.0 myrepo/myapp:1.0`
- History (see each layer and its size): `docker history myapp:1.0`

### Containers — running and inspecting

- Run: `docker run --name web -p 8080:80 myapp:1.0`
- Run interactive shell: `docker run -it --rm ubuntu:24.04 bash`
- List running / all: `docker ps` / `docker ps -a`
- Logs: `docker logs -f web`
- Exec into a running container: `docker exec -it web sh`
- Copy files in/out: `docker cp web:/app/log.txt .`
- Live resource usage: `docker stats`

### Containers — lifecycle

- Stop / kill: `docker stop web` / `docker kill web`
- Remove: `docker rm web`
- Restart: `docker restart web`

### Volumes (persistence)

- List / create: `docker volume ls` / `docker volume create app-data`
- Use a named volume: `docker run -v app-data:/var/lib/app myapp:1.0`
- Bind mount (host path): `docker run -v $(pwd):/app myapp:1.0`

### Networking

- List / create: `docker network ls` / `docker network create app-net`
- Run on a network: `docker run --network app-net --name api myapp:1.0`

### Cleanup

- Full cleanup (containers, images, networks — asks for confirmation): `docker system prune`
- Same, including unused (not just dangling) images: `docker system prune -a`

### Compose (local multi-container)

- Start / stop: `docker compose up -d` / `docker compose down`
- Rebuild after Dockerfile changes: `docker compose up -d --build`
- Logs: `docker compose logs -f`


# Advanced Commands

1. `docker network`
2. `docker history`
3. `dive image`
4. `docker stats`
5. `docker inspect`
6. `docker ps -a`