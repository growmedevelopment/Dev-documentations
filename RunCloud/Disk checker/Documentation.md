# 📊 RunCloud Server Disk Monitoring – Setup & Usage Guide

This script monitors disk usage across all RunCloud-managed servers. It connects via SSH, collects disk statistics (total, used, unallocated), and emails a styled HTML report.

---

## 📁 Script Information

- **Script Name:** `check_disk_usage_all_servers.sh`
- **Location:**  
  `/Users/dmytrokovalenko/Documents/Projects/Growme/Dev-documentations/check_disk_usage_all_servers.sh`

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

Create a `.env` file in the **same directory** as the script:

```env
API_KEY=your_runcloud_api_key
NOTIFY_EMAIL=your_email@example.com
```

## ✉️ SMTP Configuration for Email (Gmail Example)
Create a file at ~/.msmtprc:

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

Then secure it:

```bash 
    chmod 600 ~/.msmtprc
```
---
## 🧪 Manual Execution

Run the script using:

```bash 
    /opt/homebrew/bin/bash /Users/dmytrokovalenko/Documents/Projects/Growme/Dev-documentations/check_disk_usage_all_servers.sh
```
---
## ⏱️ Cron Setup for Daily Execution (at 9 AM)
```bash
  0 9 * * * /opt/homebrew/bin/bash /Users/dmytrokovalenko/Documents/Projects/Growme/Dev-documentations/check_disk_usage_all_servers.sh > /dev/null 2>&1
```
---
## 📧 HTML Report Includes
•	Server name and IP address
•	Total storage space
•	Used space (highlighted by severity):
•	🟥 Red: ≥ 90%
•	🟧 Orange: 60–89%
•	🟩 Green: < 60%
•	Unallocated space (any value > 0 is flagged red)
•	Connection or disk command errors (shown in a separate section)

## 📂 Output Files
•	HTML Report:
RunCloud_Full_Disk_Report_<YYYY-MM-DD>.html
•	Email Log:
~/.msmtp.log

---

## 🧰 Troubleshooting
•	Email not received? Check:
•	.env and ~/.msmtprc exist and are correct
•	Gmail users must use an App Password
•	Review ~/.msmtp.log for delivery errors
•	SMTP TLS errors? Update your trust file path to match your OS certs.