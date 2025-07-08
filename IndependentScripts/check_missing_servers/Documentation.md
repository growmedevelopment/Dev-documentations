# 🔍 Vultr vs RunCloud Server Audit

## Overview

This script compares active servers between **Vultr** and **RunCloud** by IP address. It identifies any servers that are live in Vultr but missing from RunCloud — potentially indicating orphaned resources. If such servers are found, it generates an HTML report and emails the findings to a designated recipient.

---

## Features

- ✅ Fetches server lists from Vultr and RunCloud via API
- 🔍 Compares servers based on IP address
- 📋 Identifies Vultr servers missing in RunCloud
- 📧 Sends an HTML email report listing discrepancies

---

## Prerequisites

- Bash environment (Unix/Linux/macOS)
- `jq` for JSON parsing
- Valid `utils.sh` file that exports:
    - `NOTIFY_EMAIL`
    - Required API keys or environment variables
- `sendmail` installed and configured

---

## Usage

```bash
  ./check_missing_servers/script.sh
```

No arguments are needed — the script automatically:
1. Loads your environment variables from `utils.sh`
2. Fetches servers from Vultr and RunCloud
3. Compares their IPs
4. Sends an alert email if mismatches are found

---

## Email Example

The script sends a formatted HTML email like the one below:

| IP Address    | Server Name      | Vultr ID |
|---------------|------------------|----------|
| 192.0.2.123   | orphaned-server1 | 654321   |
| 198.51.100.10 | orphaned-server2 | 987654   |

---

