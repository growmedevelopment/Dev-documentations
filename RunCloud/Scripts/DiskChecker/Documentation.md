# 📊 RunCloud Server Resource Monitoring – Setup & Usage Guide

This Bash script monitors **disk usage**, **RAM**, and **CPU** across all Vultr-based servers managed via RunCloud. It connects to each server using SSH, gathers system resource information, and sends a visually formatted HTML report via email.

---

## 📁 Script Information

- **Script Name:** `check_disk_usage_all_servers.sh`
- **Location:**  
  `/Users/user/pathToProject/check_disk_usage_all_servers.sh`

---

## ✅ Requirements

### Supported OS

- **macOS** (with Homebrew)
- **Ubuntu/Debian Linux**

### Required Tools

| Tool      | macOS install                        | Linux install                          |
|-----------|--------------------------------------|----------------------------------------|
| `jq`      | `brew install jq`                    | `sudo apt install jq`                  |
| `msmtp`   | `brew install msmtp`                 | `sudo apt install msmtp`               |
| `coreutils` (for `gtimeout`) | `brew install coreutils` | _Not required on Linux_               |

---

## 🔐 Environment Configuration

Create a `.env` file **in the project root**:

```env
VULTURE_API_TOKEN=your_vultr_api_key
NOTIFY_EMAIL=your_email@example.com
```

---

## ✉️ SMTP Configuration for Email (Gmail Example)

Create a file at `~/.msmtprc`:

```ini
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile ~/.msmtp.log

account gmail
host smtp.gmail.com
port 587
from your_email@gmail.com
user your_email@gmail.com
password your_app_password

account default : gmail
```

Secure the file:

```bash
chmod 600 ~/.msmtprc
```

---

## 🧪 Manual Execution

```bash
/opt/homebrew/bin/bash /Users/user/pathToProject/check_disk_usage_all_servers.sh
```

---

## ⏱️ Cron Setup for Daily Execution (at 9 AM)

```bash
0 9 * * * /opt/homebrew/bin/bash /Users/user/pathToProject/check_disk_usage_all_servers.sh > /dev/null 2>&1
```

---

## 📧 HTML Report Includes

- Server name and IP address
- **Disk Space**:
  - Total GB
  - Used GB (color-coded):
    - 🟥 Red: ≥ 90%
    - 🟧 Orange: 60–89%
    - 🟩 Green: < 60%
  - Unallocated GB (flagged if > 0)
- **RAM Usage %** (color-coded)
- **CPU Usage %** (color-coded)
- Error summary for failed servers

---

## 📂 Output Files

- HTML Report:
  `/tmp/server_report_YYYYMMDD_HHMMSS.html`
- Email Log:
  `~/.msmtp.log`

---

## 🧰 Troubleshooting

- Email not received?
  - Ensure `.env` and `~/.msmtprc` are configured correctly
  - Use an App Password for Gmail
  - Check `~/.msmtp.log` for errors
- TLS Errors?
  - Update your trust file path in `.msmtprc`

---

_Last updated: 2025-06-09 20:03:42_
