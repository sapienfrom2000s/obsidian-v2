Q: What is bash?
A: bash is a unix shell and scripting language generally used in linux based OS to interact with kernel.

Q: What is shell?
A: It is an optional user-level program that provides an interface to interact with the OS. A shell is not enforced by the operating system.

Q: What is kernel?
A: The kernel is the core component of an operating system that manages CPU scheduling, memory management, process management, context switching, and communication with hardware.

Q: What is linux?
A: Linux is a free and open-source kernel that forms the core of many Unix-like operating systems, such as Ubuntu, Fedora, and Android.

Q: How to list files in sorted order of modified time?
A: ls -ltr

Q: Why use bash over modern programming languages?
A: BTW, bash is a shell program. Shell programs provide interface to talk to kernel. Shell programs are readily available and can be executed
directly without importing libraries or compiling the code. It's good when you want to quickly mess around to get the system info and write some glue
code consisting of multiple shell programs(e.g.- cat bla | grep -v jkl | less)

Q: What is filesystem?
A: A filesystem defines how data is organized, stored, and retrieved on a storage device. Common filesystem formats include ext4, XFS, and Btrfs.

Q: How to check the open ports in local machine?
A: netstat -tulpn

Q: What are /procs in linux?
A: /proc is a virtual filesystem (does not store data on disk; files are generated dynamically by the kernel and show live system and process data).
It is used to inspect running processes (/proc/<PID>/status, cmdline).
Helps monitor system resources like CPU and memory (/proc/cpuinfo, /proc/meminfo).
Used by commands like ps, top, and free

Q: Talk a bit about files in linux. "In Linux, everything is treated as a file", What is meant by this?
A: When people said "everything is file", they mean that everything can be opened, read and written to as if it's a file, which is true to some extent, but in recent years is becoming less so. Eg.- open harddisk by cat /dev/sda, check process info in /proc/<PID>/status and so on.

Q: How to see processes with open ports?
A: ss -tulnp or netstat -tulnp

Q: What is a zombie process?
A: A zombie process is a process that has finished execution but still has an entry in the process table.
You can identify it in system tools as a Z (defunct) process.

Q: What is a process?
A: A process is an instance of a running program. Chrome uses a separate process for each tab, which allows for better security (sandboxing tabs so a malicious page can't access other tabs or system memory), crash isolation (if one tab crashes, the rest of the browser keeps running), and smoothness (slow or heavy tabs don't freeze other tabs).

Q: Process vs Thread
A: A process is a container of memory and OS resources, while a thread is a unit of execution that exists inside a process and cannot live on its own. Every process has at least one thread, and multiple threads in the same process share the same address space and resources but each has its own stack and execution state. True parallel execution is limited by the number of CPU cores (sometimes doubled with hyper-threading), and when there are more threads than cores the OS schedules them over time, giving concurrency rather than real parallelism.

Q: What is lsof command?
A: lsof = List Open Files. On Unix/Linux, everything is a file (files, sockets, pipes, devices), so lsof shows which processes have which files or network connections open.
       `lsof -i :5432`

lsof -i :5432
-> shows which process is using port 5432 (for example, Postgres)

lsof -p 1234
-> lists all files and sockets opened by process with PID 1234

lsof /var/log/app.log
-> shows which process is reading or writing /var/log/app.log

lsof -u shivam
-> lists all files opened by user shivam

lsof -i TCP -sTCP:LISTEN
-> shows all processes listening on TCP ports

Q: Talk a bit about file permissions in linux.
A:

Q: Explain signals in linux.
A: Signals are lightweight, asynchronous notifications sent by the kernel or processes to a process (or thread) to indicate an event. Common signals include SIGINT (Ctrl+C), SIGTERM (polite termination), SIGKILL (force kill, cannot be caught), SIGSTOP (pause, cannot be caught), and SIGHUP (hangup/reload). Processes can handle most signals via signal handlers to clean up, reload config, or change behavior, but some (SIGKILL, SIGSTOP) are always enforced by the kernel. You can send signals with `kill -<SIGNAL> <pid>` or `killall`.

Q: How might you use the nice and renice commands in managing process priorities in Linux?
A: In Linux, the nice command is used to start a process with a specific priority, and renice is used to change the priority of an existing process. These tools help manage system performance by ensuring critical tasks receive the necessary CPU time over less critical ones.

Q: Talk a bit about `2>&1`
A:

Basics of file descriptors:
- `0` is stdin
- `1` is stdout
- `2` is stderr

Redirect stdout to a file:

```sh
echo test > file.txt
# same as:
echo test 1> file.txt
```

Redirect stderr to a file:

```sh
echo test 2> file.txt
```

`>&` means "redirect this stream to another file descriptor":

Redirect stdout to stderr:

```sh
echo test 1>&2
# same as:
echo test >&2
```

Redirect stderr to stdout:

```sh
echo test 2>&1
```

So in `2>&1`:
- `2>` means "redirect stderr"
- `&1` means "to wherever stdout is currently going"

Why `2>1` doesn't work:
`2>1` redirects stderr into a file literally named `1`. Without `&`, the shell treats `1` as a filename, not a file descriptor.

Q: Sort process by cpu `ps -aux`
A: a - all users, u -> show which user owns the process, x -> extended
  ps -aux --sort=-%cpu
  ps -aux --sort=-%mem

Note - A zombie is a process that has finished executing but still has an entry in the process table because its parent hasn't read its exit status yet via wait().
