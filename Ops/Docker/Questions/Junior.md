

Definitional / "have you used Docker at all" level.

<details>
<summary>1. Docker default networking</summary>
By default, Docker uses the `bridge` driver on a single host. Containers get a private IP on a virtual bridge, and outbound traffic is NATed. The default bridge is legacy and lacks built-in DNS by container name, which is why user-defined bridges are preferred for real apps.
</details>

<details>
<summary>2. Explain docker architecture.</summary>
Docker uses a client–server architecture.
The Docker Client (CLI) sends commands like build and run to the Docker Daemon.
The Docker Daemon builds images, runs containers, and manages networks & volumes.
Docker Images are read-only templates used to create containers.
Containers are lightweight, isolated runtime instances sharing the host OS kernel.
</details>

<details>
<summary>3. What is docker swarm</summary>
Docker Swarm is a way to run and manage Docker containers on multiple machines together as one system. Instead of manually starting containers on each machine, you tell Swarm what you want to run and how many copies you need. Swarm then spreads the containers across machines, keeps them running, and shifts them if a machine fails. This makes running apps at scale easier and more reliable.
</details>

<details>
<summary>4. Explain docker compose</summary>
Docker Compose is a tool used to run multiple containers together on a single machine using one configuration file. You describe your app's services, networks, and volumes in a simple YAML file, and then start everything with a single command. It's mainly used for local development and testing because it's easy to set up and understand. Compose makes sure all containers start in the right order and can talk to each other.
</details>

<details>
<summary>5. Explain lifecycle of docker</summary>
The Docker lifecycle starts with building an image from a Dockerfile, which defines how the app and its dependencies are packaged. That image is stored locally or pushed to a registry like Docker Hub. Next, the image is used to create and run a container, which is the live, running instance of the app. The container can be started, stopped, restarted, or scaled, and Docker monitors it while running. Finally, containers and images can be stopped, removed, or updated when no longer needed.
</details>

<details>
<summary>6. Can a container restart itself?</summary>
Yes, a container can restart itself if it crashes or stops unexpectedly. This is controlled by the restart policy set when the container is created. The default policy is "no", which means the container will not restart automatically. Other policies include "always", "on-failure", and "unless-stopped".
</details>

<details>
<summary>7. Various states of docker container at any given point in time?</summary>
running, paused, restarting, exited
</details>

<details>
<summary>8. Docker volume vs Bind mounts</summary>
Docker volumes are managed by Docker and are isolated from the host filesystem, while bind mounts are directly mapped to the host filesystem. Docker volumes are more secure and easier to manage, but bind mounts are more flexible and can be used to share data between containers.
Isolation means Docker controls where and how the data is stored, and containers can access it only through the mounted volume—not the host filesystem directly.
</details>
