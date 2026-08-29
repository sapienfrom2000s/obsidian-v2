
`ufw`

Uncomplicated Firewall for quick host-level rules (built on top of `iptables`).
Common patterns:
```bash
# Check status (use verbose for rules + defaults)
sudo ufw status
sudo ufw status verbose

# Enable / disable
sudo ufw enable
sudo ufw disable

# Allow a service or port
sudo ufw allow OpenSSH
sudo ufw allow 22
sudo ufw allow 80/tcp

# Deny a port
sudo ufw deny 23

# Allow from a specific IP
sudo ufw allow from 203.0.113.10

# Allow to a specific port from an IP
sudo ufw allow from 203.0.113.10 to any port 5432 proto tcp

# Delete a rule by number (from "ufw status numbered")
sudo ufw status numbered
sudo ufw delete 2
```

Useful flags:
```txt
status verbose   show defaults + active rules
status numbered  list rules with indexes for deletion
allow/deny       add rules (default is to apply immediately)
enable/disable   toggle firewall on or off
```

> Use: open/close ports on a server — allow SSH, block the rest.

`systemd`

Default init system on most modern Linux distros.

```bash
# Service status and lifecycle
systemctl status nginx
systemctl start nginx
systemctl stop nginx
systemctl restart nginx
systemctl reload nginx

# Enable/disable on boot
systemctl enable nginx
systemctl disable nginx

# Show unit file
systemctl cat nginx
systemctl show nginx

# list systemd units
systemctl list-units
```
- `status` is the first thing you check in production; it shows logs and the last exit code.
- `reload` sends a reload signal if the service supports it (no downtime).
- `enable` creates symlinks so the service starts at boot.

Logs with journald:
```bash
# Logs for a unit
journalctl -u nginx

# Follow logs like tail -f
journalctl -u nginx -f

# Logs since a time
journalctl -u nginx --since "1 hour ago"
```
- `journalctl` is centralized logs; you rarely grep files directly on systemd systems.

> Use: `systemctl status` is the first thing to check when a service is down; `journalctl -u nginx --since "1 hour ago"` — read what nginx logged during the problem.

# check last 5 logged in users
`last -n 5

# check logged in users
`who`

# nproc and uptime

```
ubuntu@gcloud-master:~$ nproc
4
ubuntu@gcloud-master:~$ uptime
06:47:39 up 40 days, 19:03,  4 users,  load average: 2.30, 1.00, 0.30
```

Load average (2.30, 1.00, 0.30) means about 2.3, 1, and 0.3 processes using or waiting for CPU in the last 1, 5, 15 mins; on 4 cores(from `nproc`), 4 = full usage, and above 4 means the
system is overloaded and processes are waiting for CPU time.

> Use: quick check — is the server overloaded?

### 📝 vmstat

`vmstat` shows system performance stats for processes, memory, swap, disk I/O, and CPU.

---

### Sample commands
- `vmstat` → single snapshot  
- `vmstat 1` → update every 1 second  
- `vmstat 1 5` → 5 updates at 1-second interval  
- `vmstat -s` → summary stats  
- `vmstat -d` → disk stats  

> Use: server is slow — check the `wa` column. High = it's waiting on the disk, not CPU.

---

# iostat

A Linux command to monitor disk I/O and CPU usage. Part of the `sysstat` package.

```bash
iostat -x 1        # Extended stats, refresh every second
iostat -xmt 2      # Extended, MB/s, with timestamp — use when logging/sharing
```

> Use: disk shows 100% busy = disk is the problem, not the app.

---

# ss

A Linux command to monitor network connections, ports, and socket states. Modern replacement for `netstat`.

```bash
ss -tlnp      # Most common — TCP, listening, numeric, with process
ss -tunlp     # TCP + UDP, listening, numeric, with process
```

> Use: "is the service actually running?" — `ss -tlnp` before blaming the network. Leaking connections: `ss -tn | grep CLOSE-WAIT | wc -l`.

---

### iftop

Shows live bandwidth per connection, who your machine is talking to and how much data is flowing.

```
iftop                   # watch all connections on default NIC
iftop -i eth0      # specify a NIC
iftop -n             # don't resolve hostnames (faster, clearer)
iftop -P            # show ports
iftop -nP          # most useful — no DNS, show ports
```

> Use: see who the server is talking to right now, live.

### nethogs

Shows live bandwidth per process — which program on your machine is consuming bandwidth.

> Use: find which program is using the most bandwidth.

### renice

`renice 10 -p 1234 # higher the number lower the priority`

> Use: lower the priority of a background job so important work runs first.

### strace

Definition: Intercepts and records every system call (request your app makes to the Linux kernel) — files, network, everything.

Command:
```bash
strace ./myapp          # trace new process
strace -p <PID>         # attach to running process
strace -p <PID> -T      # show time spent per syscall (find hangs)
strace -c ./myapp       # summary of all syscalls
strace ./myapp 2>&1 | tail -20   # see last syscalls before crash
```

> Use: app is stuck or crashing silently — see exactly what it's asking the kernel for.

### xargs
Useful for passing output of one command to input of the next

```
find . -type f -name '*.jpg' | xargs rm

# when order is important
# -I {} makes sure that inputs are passed in order
# cp bla bla.bak for each piped output
find . -name "*.conf" -print0 | xargs -I {} cp {} {}.bak
```

> Use: run a command on many files at once (delete/move/compress in bulk).



### Is it possible to recover something even though it's deleted from the disk?
-> Yes, if it's still loaded in the memory. Check `lsof`.

### space is there but hitting inode limit

"no space left" error but disk has space = too many small files, inodes finished. Check with `df -i`. Why this happens: [[Ops/Linux/Concepts/Basics#Inode exhaustion]].


Refs:
1. https://learnxinyminutes.com/bash/
2. Hackerranks bash challenge
