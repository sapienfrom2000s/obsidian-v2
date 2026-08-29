Q: What happens when user executes ls in bash shell?
A: User input → Bash parses command → fork() creates a new process → exec() loads ls → ls makes system calls
→ Kernel accesses filesystem & terminal → Output shown
https://helloroot.medium.com/how-linux-commands-work-what-happens-when-you-run-a-command-in-linux-26253b693ac9

Q: If I am seeing a process in htop. How do I know which executable executed it?
A: There is a command column in htop. You can see the command that was executed to start the process. You can also use `sudo ls -l /proc/<PID>/exe`

Q: What are cgroups?
A: Cgroups is a linux kernel feature which allows you to put constraints on resources(cpu, memory, I/O) that a process can use.

Q: How to see more info around a process? More info than what is shown in top and htop.
A: cat /proc/<PID>/status
       cat /proc/<PID>/cmdline
       ls -l /proc/<PID>/fd

tldr; look inside `/proc`

Q: Explain mounting in linux?
A: Mount is the process of attaching a filesystem (usually on a device partition) to a directory in the system's single filesystem tree.
It makes the device's data accessible through that path without copying it.
A physical device may contain multiple filesystems via partitions, each mounted separately.
The system accesses storage via mount points, not directly via devices. FS examples are ext4, xfs, btrfs, zfs, etc.

Q: explain fstab.
A: The /etc/fstab (file systems table) is a crucial Linux configuration file that defines how disk partitions, remote file systems, and other data sources are automatically mounted at boot, ensuring persistent access

Q: Talk a bit about sudo.
A: sudo lets a normal user run one command as root, using their own password.

Why it exists: before sudo, admins had to log in as root — everyone shared the root password, and there was no way to know *which person* ran which command.

What it gives you:
- Power for one command only — you stay yourself, sudo just runs that one process as root.
- Every sudo command is logged with your name on it.
- Rules say exactly who can run what — one user may restart a service but can't touch disks.

How it checks if you're allowed: the rules are in `/etc/sudoers` — each rule says who can run which command. When you type sudo, it checks your user against those rules, asks for your password (remembers it for ~15 min), then runs the command as root. To see what you're allowed to run: `sudo -l`. Always edit the rules with `visudo`, never directly — one typo can lock everyone out of root.

tldr; power became temporary, logged, and limited per user.

Q: As a DevOps Engineer, how would you manage resource allocation for different users and processes in a Linux system?
A: I would use Linux's built-in resource management tools to control and manage resource allocation.
For instance, using the ulimit command, I can set soft and hard limits on resources per user basis, limiting how much of a system's resources a user can consume.
For more granular control, I might use cgroups to set resource usage limits per process.

Q: You're troubleshooting a service that keeps getting OOM-killed. Walk me through how you'd confirm it was the OOM killer, and how you'd find out why the kernel picked that particular process.
A: Confirm: `dmesg | grep -i "killed process"` — the kernel logs "Out of memory: Killed process 1234 (myapp)". The app itself shows no error, just exit code 137 (SIGKILL).

Why that process: the kernel kills the one with the highest oom_score (roughly proportional to memory actually used). So it kills the biggest consumer — not necessarily the one that caused the pressure. Check scores in `/proc/<PID>/oom_score`; bias with `oom_score_adj` (-1000 = protect, +1000 = sacrifice).

Then find why memory ran out: memory leak (RSS grows steadily — watch `pidstat -r`), too little RAM for the workload, or another process ballooned right before. Fix accordingly: patch the leak, raise limits (k8s pod limits if cgroup-OOM), add swap, or protect critical processes with oom_score_adj.

tldr; dmesg + exit 137 confirms OOM; kernel kills highest oom_score (biggest RSS), not the guilty one; then hunt the leak.
