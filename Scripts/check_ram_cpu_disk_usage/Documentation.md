# 📄 Server Metrics Collection Script Documentation

## Overview

This Bash script is designed to remotely connect to a Linux server via SSH and gather critical system metrics. It supports both macOS and Linux by detecting the appropriate `timeout` command (`timeout` or `gtimeout`). The collected data is appended as an HTML table row, ideal for inclusion in a larger dashboard or health report.

## 🔧 Features

- Remote system health monitoring over SSH.
- Disk usage and unallocated space reporting.
- Memory and CPU usage statistics.
- Color-coded health indicators (🟥, 🟧, 🟩).
- Output formatted as an HTML `<tr>` row.
- Graceful handling of connection issues with timeout.

## 🧰 Requirements

- `bash`
- `ssh` client
- `timeout` (Linux) or `gtimeout` (macOS with coreutils)
- SSH access to the target server (as `root`)
- Target server must have standard Linux utilities: `df`, `lsblk`, `awk`, `free`, `top`, `hostname`


## 📥 Input

- `SERVER_IP` (Required): The public or private IP address of the server to connect to.

## 📤 Output

Appends the following HTML row to the specified `REPORT_FILE` (or `/tmp/fallback_report.html` by default):

```html
<tr>
  <td><a href="http://<ip>"><ip></a></td>
  <td><total_disk> GB</td>
  <td><used_disk> GB (%)</td>
  <td><unallocated_disk> GB</td>
  <td><memory_usage>%</td>
  <td><cpu_usage>%</td>
</tr>
```

Color indicators:
- 🟥 Red: Critical (> 90%)
- 🟧 Orange: Warning (60–89%)
- 🟩 Green: Healthy (< 60%)

## 🔍 What It Collects

| Metric             | Description                                           |
|--------------------|-------------------------------------------------------|
| IP Address         | Server’s primary IP address (`hostname -I`)           |
| Disk Total (GB)    | Total size of `/` partition                           |
| Disk Used (GB/%)   | Used space and % usage of root partition              |
| Unallocated (GB)   | Space not yet assigned to any partition               |
| Memory Usage (%)   | % of RAM used (`free -m`)                             |
| CPU Usage (%)      | % of CPU in use (via `top`)                           |

## 📂 Variables

| Variable      | Description                                              |
|---------------|----------------------------------------------------------|
| `SERVER_IP`   | Server IP to SSH into                                    |
| `TIMEOUT_CMD` | Resolved `timeout` or `gtimeout` command                 |
| `REPORT_FILE` | Optional output file path (defaults to `/tmp/fallback_report.html`) |

## 🔄 Flow Summary

1. **Argument Parsing**:
   Ensures a server IP is passed, otherwise exits with usage info.

2. **Timeout Detection**:
   Checks system for `timeout` or `gtimeout` command.

3. **Metric Collection**:
   SSHes into the server, executes a Bash block, and extracts:
    - Disk usage via `df` and `lsblk`
    - RAM via `free`
    - CPU via `top`

4. **HTML Row Construction**:
   Formats the values with emoji indicators and appends them to the output file.

## ⚠️ Notes

- Root SSH access must be available and passwordless (`BatchMode=yes` is used).
- The script times out SSH connections after 30 seconds to avoid hanging.
