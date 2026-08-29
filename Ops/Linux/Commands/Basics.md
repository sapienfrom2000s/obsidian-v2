`tree`

To see the hierarchy of a directory.

`less`

To open a scrollable pager of a file.

`head`

To see the first n lines of a file.

```
# first n lines
head -n 10 file.txt

# first c chars
head -c 10 file.txt

# offset
head -n 22 | tail -n 11
```

`tail`

To see the last -n lines of a file. `tail -f file` is also very useful when
streaming is being done on that file.

> Use: watch new log lines as they come (`tail -f app.log`); `head` to peek at the first lines of a file (CSV headers).

`ln` — hard and soft links

```bash
ln f dup-hard     # hard link: same inode
ln -s f dup-soft  # soft link: points to the path
```

How inodes/links work under the hood: see [[Ops/Linux/Concepts/Basics#Inodes & links]].

> Use: soft link — point to a file/folder that gets replaced, e.g., `latest -> v2.3` (deploy swaps the target, `latest` always works; can also cross filesystems). Hard link — protect a file from deletion: `cp` + `rm` by a script won't destroy the data as long as your link exists; also, backup tools like rsnapshot/time-machine use them to snapshot unchanged files for free.

`file`

Tells the content type that a file contains. Eg.:
```zsh
Downloads % file Wireshark\ 4.6.0.dmg
Wireshark 4.6.0.dmg: zlib compressed data
```

> Use: check what a file really is before opening it (is this really a PDF?).

`stat`

Shows detailed metadata about file like: permissions, owner, size, timestamps.

> Use: see exactly when a file was last changed and its permissions.

`du` vs `df`

`du` - disk usage (works on directories)  
`df` - disk free (only for partition)

> Use: `df -h` — check how much space is left on the disk; `du -sh * | sort -hr` — find the biggest folders when disk is full.

`lsof`

List Open Files — since everything is a file (files, sockets, pipes, devices), lsof shows which processes have which files or network connections open.

```bash
lsof -i :5432              # which process is using port 5432 (e.g., Postgres)
lsof -p 1234               # all files/sockets opened by PID 1234
lsof /var/log/app.log      # who is reading/writing this file
lsof -u shivam             # all files opened by user shivam
lsof -i TCP -sTCP:LISTEN   # all processes listening on TCP ports
```

Bonus: `lsof` (or `ls /proc/<PID>/fd`) can also recover deleted-but-open files — the inode lives on until the last FD closes.

> Use: "port already in use" error — `lsof -i :5432` finds which process is using it.

`/proc`

A virtual filesystem — nothing on disk, the kernel generates files on the fly. ps, top, and free all read from here.

```bash
cat /proc/cpuinfo              # CPU info
cat /proc/meminfo              # memory usage (free reads this)
cat /proc/<PID>/status         # state, memory, threads (richer than top)
cat /proc/<PID>/cmdline        # exact command + args (NUL-separated: tr '\0' ' ')
ls -l /proc/<PID>/exe          # symlink to the actual binary
ls -l /proc/<PID>/fd           # all open file descriptors
```

FD = file descriptor: a small integer the kernel gives a process for each open file/socket/pipe — its handle to that file (0=stdin, 1=stdout, 2=stderr). Deleted-but-open files show as `(deleted)` in fd but the data is still there: `cp /proc/<PID>/fd/N backup`.

> Use: a weird process is running — `cat /proc/<PID>/cmdline` shows what command started it.

`lsblk`

List block devices (disks, partitions, LVM, loop devices) in a tree.

What loop devices and LVM are: see [[Ops/Linux/Concepts/Basics#Storage: loop devices & LVM]].

Examples:
```bash
# 1) Basic view (name, size, type, mountpoint)
lsblk

# 2) Show filesystem details
lsblk -f

# 3) Show sizes in bytes (no rounding)
lsblk -b

# 4) Custom columns
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
```

Useful flags:
```txt
-f show filesystem info (FSTYPE, UUID, LABEL, etc.)
-b sizes in bytes
-o pick columns to display
-p show full device paths (e.g., /dev/sda1)
```

> Use: a new disk was attached — `lsblk -f` to find its name before mounting it.

`sort`

Examples:
```bash
# 1) Alphabetical sort (default)
sort names.txt

# 2) Numeric sort
sort -n numbers.txt

# 3) Human-readable size sort (largest first)
du -sh * | sort -hr

# 4) Unique sorted values (deduplicate)
sort -u words.txt

# 5) Sort by 2nd column, comma-separated (e.g., CSV)
sort -t ',' -k2,2 data.csv
```

Useful flags:
```txt
-n numeric sort (treat lines as numbers)
-h human-numeric sort (understands sizes like 10K, 2M, 1G)
-r reverse order
-u unique (remove duplicates after sorting)
-k sort by a specific key/column
-t set field delimiter (default: whitespace)
```

> Use: `sort | uniq -c | sort -rn` — count the most repeated lines in a file (top IPs, top errors).

`uniq`

Filter out repeated adjacent lines (usually after `sort`).

Examples:
```bash
# 1) Remove duplicates (needs sorted input)
sort names.txt | uniq

# 2) Count duplicates
sort names.txt | uniq -c

# 3) Print only lines that occur exactly once in a consecutive run
sort names.txt | uniq -u
```

Useful flags:
```txt
-c prefix lines by the number of occurrences
-d show only duplicate lines
```

> Use: count how many times each IP or error appears in a log (after sort).

`paste`

Merge lines from files side by side.

Examples:
```bash
# 1) Combine two files column-wise (tab-separated)
paste names.txt ages.txt

# 2) Use a custom delimiter
paste -d ',' names.txt ages.txt

# 3) Paste 3 columns side by side (tab-separated)
paste -d $'\t' - - -
```

Useful flags:
```txt
-d set delimiter (default: tab)
```

> Use: join two files side by side into one (make a quick CSV).

`cut`

Extract specific columns from each line of a file.

Examples:
```bash
# 1) Get 2nd column from a CSV
cut -d ',' -f2 data.csv

# 2) Get characters 1-10 from each line
cut -c 1-10 file.txt
```

Useful flags:
```txt
-d field delimiter (default: tab)
-f select fields (comma-separated or ranges)
-c select character positions (e.g., 1-5)
```

> Use: grab one column from a CSV.

`tr`

Translate or delete characters (works on stdin).

Examples:
```bash
# 1) Lowercase to uppercase
echo "hello" | tr 'a-z' 'A-Z'

# 2) Remove digits
echo "a1b2c3" | tr -d '0-9'

# 3) Squeeze repeated spaces into one
echo "a   b     c" | tr -s ' '
```

Useful flags:
```txt
-d delete characters
-s squeeze repeats
```

> Use: clean up text in a pipe (remove digits, squeeze extra spaces).

## Permissions

Theory (rwx meaning, umask, SUID/SGID, sticky bit): see [[Ops/Linux/Concepts/Basics#Permissions]].

```bash
chmod +x something      # add execute
chmod 755 something     # rwxr-xr-x
chmod g+rwx something   # group gets rwx
chown user:group file   # change owner (or use chgrp for group only)
```

> Use: fix permissions or ownership of files — e.g., files created by root but needed by the app user.

`umask` — default permissions for new files

```bash
umask 022    # new dirs: 755 (rwxr-xr-x), new files: 644 (rw-r--r--)
```

> Use: control what permissions new files get automatically. See [[Ops/Linux/Concepts/Basics#umask]] for how the mask works.

`SUID` and `SGID`

```bash
chmod u+s filename   # SUID
chmod g+s filename   # SGID
```

> Use: understand why `passwd` works for normal users; `find / -perm -4000` lists SUID programs (check for security risk). How it works: [[Ops/Linux/Concepts/Basics#SUID and SGID]].

`Sticky bit`

> Use: understand why users can't delete each other's files in /tmp. Details: [[Ops/Linux/Concepts/Basics#Sticky bit]].

`grep`

Common patterns:
```bash
# Basic match
grep "POST" app.log

# Case-insensitive match
grep -i "POST" app.log

# Invert match (lines that do NOT match)
grep -v "POST" app.log

# Context around matches
grep -C5 "POST" app.log    # before + after
grep -A5 "POST" app.log    # after
grep -B5 "POST" app.log    # before

# Recursive search
grep -r "POST" directory

# Line numbers + filenames
grep -n "POST" app.log
grep -l "POST" app.log     # list filenames with matches

# Match-only output + counting
grep -o "POST" app.log
grep -o "POST" app.log | wc -l

# Extended regex examples
grep -E '^ERROR' app.log
grep -E 'ERROR$' app.log
grep -E 'ERROR|WARNING' app.log
grep -E '^4..$' app.log
grep -E '^[234]00$' app.log
grep -E 'app/api/v2/.*ui/user' app.log

# Exit status (0 = found, 1 = not found)
grep -q 'POST' app.log; echo $?
```

> Use: count matches in a log (`grep -c`), or hide lines you don't care about (`grep -v`).

`find`

Common patterns:
```bash
# Find by name (case-sensitive)
find . -name "app.log"

# Case-insensitive name
find . -iname "readme.md"

# Only files or only directories
find -max-depth 1 /var/log -type f
find /etc -type d

# Find by extension
find . -type f -name "*.log"

# Modified in last N days
find /var/log -type f -mtime -7

# Larger than 100MB
find /var -type f -size +100M

# Combine conditions (AND is default)
find . -type f -name "*.log" -mtime -s
```

Useful flags:
```txt
-name / -iname  match filename (case-sensitive / insensitive)
-type           f = file, d = directory, l = symlink
-mtime          modified time in days (-7 = last 7 days)
-size           file size (+100M, -10k, +1G)
-maxdepth       limit recursion depth
```

> Use: find files changed in the last 7 days (`-mtime -7`) — "what changed before it broke?"

`sed`

Stream editor for fast, non-interactive text edits. 

- `sed` processes input line by line.
- You give it commands like substitute (`s///`), delete (`d`), print (`p`).
- By default, it prints every line after applying commands. Use `-n` to suppress auto-print and print only what you choose. Also, p can be used with g.

```bash
# Replace first match per line
sed 's/error/ERROR/' app.log

# Replace all matches per line (global)
sed 's/POST/HTTP_POST/g' app.log

# Use a different delimiter when slashes exist in the pattern
sed 's|/api/v1|/api/v2|g' access.log
```
- `s/old/new/` replaces the first `old` per line.
- Add `g` to replace all matches in the line.
- Any delimiter works (`s|a|b|` is often easier for paths).

Print only matching lines (like `grep`, but with transformations if needed):
```bash
sed -n '/ERROR/p' app.log
```
- `-n` turns off default printing.
- `/ERROR/` selects matching lines; `p` prints them.

Delete lines (filtering):
```bash
# Delete lines that match a pattern
sed '/DEBUG/d' app.log

# Delete a line range (inclusive)
sed '5,12d' app.log
```
- `/pattern/d` removes matching lines from output.
- `start,endd` drops a numeric line range.

Targeted edits by line range:
```bash
# Only change lines 10 to 20
sed '10,20s/timeout=30/timeout=60/' config.ini
```
- Line ranges let you be precise without touching the rest of the file.

```bash
# GNU sed (Linux): in-place edit(i flag), or it will print the changes to only stdout
sed -i 's/ENV=dev/ENV=prod/' .env
```

> Use: find and replace text in a file without opening an editor.

`awk`

Programming language for text processing. `awk` reads input line by line, splits each line into fields, and lets you write small programs to print, filter, and transform data.

Basics and fields (field separator, whole line, and column access):

```bash
awk -F ',' '{print $0}' file.csv
```
- `-F ','` sets the field separator to a comma (default is whitespace).
- `$0` means "the entire current line".

```bash
awk -F ',' '{print $1}' file.csv
```
- `$1` is the first field/column, `$2` is the second, etc.

```bash
awk -F ',' '{print $NF}' file.csv
```
- `NF` is the number of fields in the current line.
- `$NF` is the last field in the line, no matter how many columns there are.

```bash
awk -F ',' '{print NR ":", $0}' file.csv
```
- `NR` is the current record (line) number.
- Output looks like `1: <line contents>` for each each line

Substring by character position:
```bash
# From 2nd char, length 6
awk '{print substr($0,2,6)}' file

# From 2nd char to end of line (no length needed)
awk '{print substr($0,2)}' file
```
- `substr(s, start, len)` and `len` is optional; omit it to go to end of line.

Filters and matches (pattern matching and numeric comparisons):
```bash
awk '/ERROR/ {print}' app.log
```
- `/ERROR/` is a regex pattern.
- For any line that matches the pattern, the action `{print}` runs.
- `{print}` with no arguments prints the whole line (same as `print $0`).

```bash
awk '$4 > 200' app.log
awk '$2 == 234 && $3 == 233' app.log
awk '$9 ~ /^5/' access.log
```

> Use: pull specific columns or filter lines by value — e.g., only requests that took > 1 sec.
