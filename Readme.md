# 📚 RunCloud Server Automation & Maintenance Documentation

## 📝 Overview

This suite of Bash scripts automates monitoring, backup, and maintenance for servers managed via RunCloud + Vultr. Scripts handle uptime checks, orphaned server detection, backups, disk extensions, and cron cleanups. 

**⚠️ Note: These scripts are prepared for iOS/Linux environment if you are Windows user read `Windows_users_documentation.md`**

---


## 📦 Script Summaries

###  Dependent scripts (run only via runner)

### ✅ Server Uptime Monitoring
**Script:** `ping_report.sh`
Automates daily pings of all Vultr servers fetched via API, generating and emailing an HTML uptime report. Includes deployment helper scripts to upload credentials, install the monitor on a remote server, and configure a daily cron job. Outputs logs to `/var/log/ping_debug.log`.
---

### ✅ Removed Servers Checker
**Script:** `check_removed_servers`
Scans Vultr Object Storage for backup folders of apps no longer existing in RunCloud, deletes outdated or orphaned backups while keeping the latest in daily/ and weekly/ folders, and generates an HTML report emailed to `NOTIFY_EMAIL`. Supports dry-run mode for safe testing before deletion.


---

### ✅ Server Metrics Collector
**Script:** `check_ram_cpu_disk_usage`
Connects to each server via SSH and collects key metrics: disk usage, unallocated space, memory, and CPU utilization. Generates color-coded HTML table rows (🟥/🟧/🟩) for easy health visualization, appends them to a report file, and sends the HTML report via email to `NOTIFY_EMAIL`.

---

### ✅ Remote Disk Extender
**Script:** `extend_space_with_unallocated`
Connects to a server via SSH, detects unallocated disk space on the root disk, and automatically extends the root partition if space is available. Handles both ext-based and XFS filesystems, resizes the filesystem, and logs each step for easy auditing.

---

### ✅ Backup Deployer
**Script:** **`make_backup.sh`  
Automates running daily backups across all RunCloud servers. Checks for key-based access (skipping servers requiring a password), runs the backup with a configurable timeout, supports a dry-run mode, and sends email alerts to `NOTIFY_EMAIL` on failures.
---


### ✅ Remove Root Cron Jobs
**Script:** `remove_cron_user`
Connects to each server via SSH and safely deletes the root user’s personal crontab (crontab -e), without touching system-wide cron files like `/etc/crontab` or `/etc/cron.d/*`
---

### ✅ Automated Backup Script & Restore Guide
**Script:** `set_making_backup`
Remotely configures servers for automated daily, weekly, monthly, and yearly WordPress backups to Vultr Object Storage. Installs required tools, sets up rclone and SMTP relay, deploys /root/full_vultr_backup.sh, configures cron schedules, and installs an interactive restore tool (restore-backup) for easy website and database recovery.
---

### ✅ SSH Accessibility Checker
**Script:** `ssh_checks`
Verifies SSH key-based root access to a specified server, timing out after 5 seconds. Returns success or failure status without making any changes on the server. Integrates seamlessly with deploy_to_servers.sh for automated multi-server checks.
---

### ✅ SSH Key Injector
**Script:** `ssh_injection`
Uses the RunCloud API to inject your SSH public key into a specified server, enabling passwordless root access. Takes server IP, ID, and name as arguments; verifies success from the API response; and provides helpful error messages if the server ID is invalid or the key label already exists.
---

### ✅ WP Temp Folder Fixer
**Script:** `create_wp_temp_folder`
Scans all WordPress apps under /home/runcloud/webapps on a server, ensures the WP_TEMP_DIR is defined in wp-config.php, and creates the /wp-content/temp/ directory if missing. Prevents the “Missing a Temporary Folder” WordPress error during uploads or updates.
---


###  Independent scripts (run directly)

### ✅ Vultr Cost Summary
**Script:** `vultr_cost_tracker`
This script fetches all active VPS instances from Vultr, calculates the total hourly cost, and estimates monthly costs assuming 30-day uptime. It then sends a clean, formatted HTML summary by email. Great for keeping track of your infrastructure expenses with minimal effort.
---

### ✅ Vultr vs RunCloud Server Sync Checker
**Script:** `check_missing_servers`
Fetches all active servers from both Vultr and RunCloud APIs, compares them by IP address, and identifies servers that exist in Vultr but not in RunCloud. If discrepancies are found, generates and sends an HTML summary email to NOTIFY_EMAIL listing the unmatched servers.
---

### ✅ Remote Ping Monitor Deployer
**Script:** `ping_report.sh`

Installs a daily uptime monitor on your remote server.
- **Full Report (daily):** All Vultr servers with status + ping times.
- **Down-Only Alert:** Sent only if servers are unreachable.
- Runs nightly via cron, auto-fetches server list from Vultr API, and logs to `/var/log/ping_debug.log`.

### ✅ Old Backup Cleaner
**Script:** `remove_old_backups`
This script helps keep your backup storage tidy. It checks which websites still exist and compares them to the folders in your Vultr backup storage. If it finds backups for websites that no longer exist, it marks them as “orphaned” and removes them. It also clears out old daily and weekly backups for active sites, keeping only the latest ones. You can run it in safe “dry run” mode to preview what it would delete — no surprises.
⚠️ Note: Use this script no more than once per week to avoid hitting API rate limits.
---

### ✅ Timezone Enforcer for Remote Servers
**Script:** `set_time_zone`  
This script ensures all remote servers use the correct timezone (`America/Edmonton`) and are time-synced via NTP. When run, it connects over SSH to each server, checks the current timezone, and only updates it if necessary. It also enables NTP time synchronization to prevent drift. Designed to be used with `deploy_to_servers.sh`, this automation scales across dozens or hundreds of servers and ensures consistent time-based behavior for backups, cron jobs, and logs.
---


## 🚀 Quick Start

1. **Environment Setup**
- Create a `.env` file with credentials:
  ```env
  NOTIFY_EMAIL=...
  SUMMARY_FILE=$(mktemp)
  SMTP_RELAY_USER=...
  SMTP_RELAY_PASS=...
  SSH_KEY_NAME=...
  SSH_PUBLIC_KEY=...
  DRY_RUN="true"
  VULTR_API_TOKEN=...
  RUNCLOUD_API_TOKEN=...
  AWS_ACCESS_KEY_ID=...
  AWS_SECRET_ACCESS_KEY=...
  ```
- Install prerequisites:
  ```bash
  sudo apt install jq curl bash msmtp awscli
  ```
  Also install `timeout` (Linux) or `gtimeout` (macOS with coreutils).

2. **SSH Key**
- Create and use an SSH key **without a passphrase**, for automated root access.

3. **SSH Access**
- Use `ssh_injection` scripts to inject your public key onto all servers for passwordless root login.

4. **Edit `servers.json`**
- This file is the main data source listing your servers.
- Each object must include `id`, `name`, and `ipAddress`. **Do not leave fields empty**.

5. **Configure Local msmtp**
   all info you can get from your Gmail account. You have to create Gmail APP and get password
- Update your `~/.msmtprc` to send emails with your SMTP relay credentials:
  ```
  defaults
  auth           on
  tls            on
  tls_trust_file /etc/ssl/certs/ca-certificates.crt
  logfile        ~/.msmtp.log

  account        default
  host           smtp.yourrelay.com
  port           587
  user           $SMTP_RELAY_USER
  password       $SMTP_RELAY_PASS
  from           $NOTIFY_EMAIL
  ```
- Test with:
  ```bash
  echo "Test email body" | msmtp recipient@example.com
  ```

6. **Deploy Scripts**
- Use the universal runner:  deploy_to_servers.sh
- Or run individual scripts as documented below.

---

## 🛠 Running Scripts

You can easily run any script from `Script` folder across all your servers using the universal runner. From your project root, just call:

```bash
./deploy_to_servers.sh <script_folder>
```
Replace `<script_folder>` with the folder name of the script you want to run. For example:


```bash
./deploy_to_servers.sh ssh_injection
./deploy_to_servers.sh check_ram_cpu_disk_usage
./deploy_to_servers.sh ssh_checks
./deploy_to_servers.sh set_making_backup
./deploy_to_servers.sh remove_old_backups
./deploy_to_servers.sh remove_cron_user
./deploy_to_servers.sh create_wp_temp_folder
./deploy_to_servers.sh set_time_zone
```

✅ Need help?

Run:
```bash
./deploy_to_servers.sh --help
```



---

## 📬 Author

GrowME DevOps – Dmytro Kovalenko