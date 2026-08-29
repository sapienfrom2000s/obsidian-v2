# /proc — the kernel's live window

`/proc` (procfs) is a **pseudo-filesystem managed by the kernel**:
- **Storage**: uses 0 bytes of disk. Exists entirely in RAM.
- **Interface**: instead of inventing custom system calls for every metric, the kernel exposes its data through standard file operations (open(), read(), close()).
- **Philosophy**: "everything is a file" — so cat, grep, less all just work on live system data.

### On-demand generation ("on the fly")

The text inside a /proc file **does not exist until you ask for it**.

The kernel constantly maintains *raw binary* state in RAM (total RAM, CPU cycles, open connections — stored inside C structures). It never wastes cycles formatting text like `MemTotal: 16384000 kB` in the background.

What happens when you run `cat /proc/meminfo`:

1. **System call** — your program issues open()/read() on the /proc path.
2. **Interception** — the disk is completely bypassed; the VFS routes the call to the procfs driver.
3. **Execution** — the kernel runs the internal function attached to that file path.
4. **Formatting** — that function reads current binary values from kernel RAM, translates them into ASCII text, dumps it into a temporary buffer.
5. **Delivery & cleanup** — the buffer goes to your output; when the FD closes, the generated text is discarded.

Unread /proc file → the formatted text is never created.

### PIDs and process lifecycle (/proc/[PID])

Every running process is represented in kernel memory by a structure called `task_struct`.

- While PID 23 runs: its state, memory maps, environment variables, and open FDs live continuously in kernel RAM inside its task_struct. `/proc/23/` is a valid access route to it — reading a file there converts the binary values to ASCII on the spot.
- The instant PID 23 dies: the kernel frees its task_struct, and `/proc/23/` immediately stops responding and vanishes from directory listings.

Key files: `status` (state/memory/threads), `cmdline` (exact launch command), `fd/` (all open file descriptors — including deleted-but-open files), `exe` (link to the running binary).

### Tools are just /proc parsers

Standard utilities have no special access to kernel memory — they open /proc files, parse the ASCII, and pretty-print it:

| Tool | What it actually reads |
|------|----------------------|
| ps / top | scans /proc/ for numeric folders, reads each `[PID]/stat`, `status`, `cmdline` |
| free | `/proc/meminfo` (MemTotal, MemAvailable) |
| uptime | `/proc/uptime` (raw seconds since boot + idle time) |
| lscpu | `/proc/cpuinfo` |

```
+----------------+      System Call       +------------------------+
| Linux Utility  | ---------------------> |      Linux Kernel      |
|  (e.g., free)  |                        |  (Reads C Structures)  |
+----------------+                        +------------------------+
        ^                                             |
        |                                             |
        |          Formats into ASCII Text            |
        +---------------------------------------------+
```

---

# Inodes & links

An **inode** is a data structure holding a file's metadata. When you open a file, the location of its content is fetched from the inode. Filenames are just directory entries pointing to inodes.

**Hard link** (`ln f dup-hard`): a new name pointing to the *same inode*. Deleting one name doesn't affect the other — the inode survives as long as something references it.

**Soft/sym link** (`ln -s f dup-soft`): a new inode containing a *path* to the original. If the original is deleted, the link breaks.

Memory aid:
1. Hard: name → inode → data
2. Soft: name → inode → path → inode → data

An inode is only deleted when the hard-link count hits 0 AND no process has it open. That's why deleted-but-open files still work — and why you can recover them via `/proc/<PID>/fd`.

### Inode exhaustion

Inodes are pre-allocated at filesystem creation — a fixed pool, separate from data blocks. You can have 500GB free but zero inodes left, and the system refuses to create files:

```
touch newfile
# touch: cannot touch 'newfile': No space left on device
# But df -h shows 60% free — confusing!
```

Check with `df -i`.

# Storage: loop devices & LVM

**Loop device** — lets you treat a regular file as if it were a block device. Needed because the OS expects to mount filesystems from block devices (/dev/sda1), but disk images are just files — loop devices bridge that gap. (This is why snap apps show up as loop mounts.)

**LVM (Logical Volume Manager)** — manages storage flexibly instead of fixed partitions. Combines multiple disks into a single pool (Volume Group); from that pool you create Logical Volumes like /home or /var. Example: 100GB + 200GB disks = one 300GB pool. Add another disk later and extend /home without downtime.

# Permissions

For files: `r` = read, `w` = write, `x` = execute.
For directories: `r` = list names, `w` = create/delete/rename inside (needs `x` too), `x` = enter/traverse (`cd`).

Numeric: `r`=4, `w`=2, `x`=1.

Every file has one user owner (UID) and one group owner (GID); checks apply in order — user → group → others, first match wins.

### umask

Masks out permission bits for newly created files, set per user. Not subtraction — a bit mask: `final = base & ~umask` (dirs base 777, files base 666).

```
umask 022
# 022 = --- -w- -w-  (turns off write for group + others)
# dirs:  777 & ~022 = 755 → rwxr-xr-x
# files: 666 & ~022 = 644 → rw-r--r--
```

### SUID and SGID

Enable with `chmod u+s file` / `chmod g+s file`.

- SUID: process runs with the *file owner's* privileges instead of the invoking user's (shows as `s` in owner execute position, e.g. `-rwsr-xr-x`).
- SGID: process runs with the *file's group* privileges; on directories, new files inherit the directory's group.

Classic example — how `passwd` works:

```
-rw------- 1 root root /etc/shadow         (only root can write)
-rwsr-xr-x 1 root root /usr/bin/passwd     (SUID bit set)
```

- Samantha runs passwd → process gets effective UID 0 (root), real UID stays hers.
- Kernel allows the write to /etc/shadow because effective UID = root.
- passwd's internal logic checks the *real* UID ("who started me?") and only modifies her line.

Why the alternatives fail:

- World-writable /etc/shadow, no SUID → write works, but Samantha can now edit /etc/shadow directly (change root's password, delete users). No isolation.
- No SUID, shadow stays root-only → process runs as Samantha; kernel blocks the write at the syscall level (execute ≠ write permission).

tldr; SUID/SGID elevate privilege for one specific program, keeping the file itself locked down.

### Sticky bit

- Directories (the modern use): in shared writable dirs like /tmp (`drwxrwxrwt`), only the file owner, directory owner, or root can delete/rename entries — even though everyone can write.
- Executables: historical/obsolete — code used to "stick" in swap for faster startup.
- Shown as `t` in others-execute position; capital `T` if set without others-execute.

---

# systemd

Systemd is the init system — the first process the kernel starts (PID 1). Every process in the OS descends from it. It starts all other system and user services.

Why it replaced SysV:
1. Parallel daemon startup → faster boot (SysV was sequential).
2. Unit files are cleaner than messy SysV daemon scripts.
3. Every process runs in its own cgroup → easier control.

### Boot process

1. Firmware (BIOS/UEFI) runs POST to verify hardware.
2. BIOS: loads bootloader from the first 512 bytes (MBR). UEFI: loads it from the EFI System Partition (ESP).
3. Bootloader (GRUB) loads the kernel.
4. Kernel initializes hardware, mounts root fs, starts PID 1 = systemd.
5. systemd reads `default.target` (usually a symlink to `graphical.target` or `multi-user.target`), builds a dependency graph from units, and starts units in order — in parallel where possible.

### Unit files

A unit = anything systemd can manage (service, mount, timer, socket):

```
[Unit]
Description=usbguard
[Service]
ExecStart=/usr/sbin/usb-daemon
[Install]
WantedBy=multi-user.target
```

- `[Unit]` — metadata + relationships
- `[Service]` — the behavior (ExecStart etc.)
- `[Install]` — only matters when enabling at boot

Common types: `.service` (apps), `.timer` (cron-like, triggers a matching service), `.target` (a system state / group of units), `.mount` / `.automount`.

### Dependencies vs order

- Dependencies — "must run together?"
  - `Wants=`: try to start; continue even if it fails.
  - `Requires=`: must succeed, or this unit stops.
- Order — "who starts first?"
  - `After=` / `Before=`: sequencing only, says nothing about success.

### Targets

- `multi-user.target` — server/text login state
- `graphical.target` — desktop
- `default.target` — boot default (symlink to one of the above)
- `rescue.target` — emergency shell

### User services

- Unit files in `$HOME/.config/systemd/user/`, managed via `systemctl --user`.
- Stop on logout unless lingering is on: `loginctl enable-linger USERNAME`

### systemctl / journalctl

```bash
systemctl status|start|stop|restart|reload|enable|disable SERVICE
journalctl -u nginx -f --since "1 hour ago"
```

`status` is the first thing to check in production (logs + last exit code). `reload` = no downtime. `enable` creates boot symlinks.

Refs:
1. https://documentation.suse.com/smart/systems-management/pdf/systemd-basics_en.pdf
2. https://bytebytego.com/guides/linux-boot-process-explained/

---

# logrotate

Unmanaged logs grow forever → disk fills up, apps crash or stop logging. Logrotate automates rotation, compression, retention, and keeps apps logging correctly.

### How it works

Runs daily via cron or a systemd timer:
1. Renames the current log
2. Creates a fresh log file
3. Compresses older logs
4. Runs scripts to tell apps to reopen log files

Key point: **apps always write to the same filename** — logrotate only renames old logs. With `daily` + `rotate 7`:

```
app.log        # active log (always same name)
app.log.1      # most recent rotated
app.log.2
app.log.3.gz
...
app.log.7.gz   # oldest kept; deleted beyond limit
```

### Sample config

```conf
/var/log/myapp/*.log {
    daily              # rotate every day
    rotate 7           # keep last 7, delete older
    compress           # compress rotated logs
    delaycompress      # delay compression by one rotation
                       # (apps may still access recent logs)
    missingok          # no error if file doesn't exist
    notifempty         # skip empty files
    create 0640 myapp myapp   # new log with given perms/owner
    sharedscripts      # postrotate runs only once, even for many logs
    postrotate
        systemctl reload myapp >/dev/null 2>&1 || true
                       # reload app so it reopens logs; ignore errors
    endscript
}
```

### First-time setup

1. Enable the scheduler: `sudo systemctl enable --now logrotate.timer`
2. Create config: `sudo nano /etc/logrotate.d/myapp` (paste block above)
3. Dry test: `sudo logrotate -d /etc/logrotate.conf`
4. Force one rotation: `sudo logrotate -f /etc/logrotate.conf`
5. Verify: new `app.log` exists, rotated files appear, app keeps logging.

### postrotate / endscript / sharedscripts

- `postrotate ... endscript` — commands to run after rotation; usually reload the app so it reopens the new log file.
- `sharedscripts` — by default postrotate runs once *per matched file* (3 matching logs = 3 reloads); with it, runs once total.

Takeaways: same log filename always; rotated logs get `.1`, `.2`, ...; `sharedscripts` matters when reloading; postrotate defines what runs, endscript marks its end.
