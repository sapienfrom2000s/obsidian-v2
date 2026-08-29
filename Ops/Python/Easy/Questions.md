## 1. HTTP Health Check  ✔
Write a script that takes a web URL as input and checks if the site is up and healthy (returns an HTTP status code 200).

## 2. Log Parser (Error Counter) ✔
Write a script that opens a log file (e.g., app.log), reads it line by line, and counts the total number of times the word "ERROR" appears.

## 3. Execute Shell Command ✔
Write a script that uses Python to safely execute a system shell command (like `uptime` or `df -h`) and captures its output into a variable.

## 4. Parse API JSON Response ✔
Write a script that fetches data from a REST API endpoint returning JSON, parses the response, and extracts a specific key value.

## 5. Find Duplicate Lines in a File ✔
Write a script that reads a text file line by line and identifies all duplicate lines using an efficient data structure.

## 6. Extract IP Addresses with Regex ✔
Write a script that reads through a log file, extracts all IPv4 addresses using regular expressions, and returns a set of unique IPs.

-----------x------------------------x--------------------x----------------
## 7. Backup File with Timestamp
Write a script that takes a file path, creates a backup copy of it in the same directory, and appends a timestamp (e.g., `app.log.2026-08-24_1030`) to the backup's name.

## 8. Check Disk Space Usage
Write a script that checks the free disk space on the root (or a given) partition using `shutil.disk_usage()` and prints a warning if usage exceeds 80%.

## 9. Port Availability Checker
Write a script that takes a hostname and port number, then checks whether the port is open (i.e., a TCP connection can be established) using the `socket` module.

## 10. Read Configuration from Environment Variables
Write a script that reads configuration values (like `DB_HOST`, `DB_PORT`, `DB_USER`) from environment variables and prints them, providing sensible defaults for any that are missing.

## 11. Cleanup Old Files in a Directory
Write a script that deletes all files in a given directory that haven't been modified in the last N days, and prints the name of each file it deletes.

## 12. Generate a Secure Random Password
Write a script that generates a random password of a given length containing uppercase, lowercase, digits, and special characters, using the `secrets` module.

## 13. Append-Only Event Logger
Write a script that logs messages with a timestamp and severity level (INFO/WARN/ERROR) to a file using the `logging` module, and ensures old logs are appended rather than overwritten.

## 14. DNS Resolution Checker
Write a script that takes a list of hostnames and prints whether each one resolves to an IP address (use `socket.gethostbyname()`), reporting failures gracefully.
