# 🛡️ RunCloud Backup & Monitoring Automation

This folder contains a complete automation toolkit to deploy backup tasks and health monitoring scripts to **RunCloud-managed servers** or to a **manually defined list of servers**.

---

## 🔧 What It Does

- ✅ Authenticates to the RunCloud API (optional mode) or loads a manual list of IPs
- ✅ Pings each server to verify it's online
- ✅ Sends an email to `development@growme.ca` (or your configured `$ADMIN_EMAIL`) if a server is offline
- ✅ Connects via SSH to:
    - Install and configure the AWS CLI for Vultr Object Storage
    - **Verifies AWS CLI connectivity** with `sts get-caller-identity`
    - Deploy the `full_vultr_backup.sh` script:
        - Archives each WordPress app’s files + MySQL DB
        - Uploads the archive to Vultr Object Storage using `aws s3api put-object`
        - Automatically downgrades AWS CLI to **v2.15.0** if a newer (incompatible) version is detected
        - Sends a failure email to `$ADMIN_EMAIL` if DB dump or upload fails
    - Deploy the `check_alive.sh` script:
        - Runs every 5 minutes via cron
        - Pings 8.8.8.8 and notifies `$ADMIN_EMAIL` if unreachable
    - Replaces all existing cron jobs with:
        - `30 2 * * *` – Daily backup
        - `0 3 * * 0` – Weekly backup
        - `*/5 * * * *` – Server uptime check

---

## ⚠️ AWS CLI Compatibility

Vultr Object Storage has known issues with AWS CLI v2.27+ that cause `NoneType` crashes during uploads. This toolkit:
- Detects the AWS CLI version
- Automatically **downgrades to v2.15.0** if necessary
- Ensures long-term compatibility with Vultr’s S3 API

---

## 📨 Notification Emails

All failure and monitoring notifications are sent to the address configured via the `ADMIN_EMAIL` variable (typically `development@growme.ca`).

---

## 🗂 Folder Structure

```
Runcloud backup deploy/
├── deploy_payload.sh           # The core script sent to each server
├── deploy_to_all_servers.sh    # Deployment using RunCloud API
├── deploy_to_servers.sh        # Deployment using manual server IP list
├── servers.list                # Editable list of IPs (used by deploy_to_servers.sh)
└── ../../.env                  # Environment config (used by both modes)
```

---

## 🔐 .env Setup

Create a `.env` file two levels above the scripts with the following structure:

```env
API_KEY="your-runcloud-api-key"
ADMIN_EMAIL="development@growme.ca"
AWS_ACCESS_KEY_ID="your-vultr-access-key"
AWS_SECRET_ACCESS_KEY="your-vultr-secret-key"
SMTP_RELAY_USER="your-gmail-user@gmail.com"
SMTP_RELAY_PASS="your-app-password"
```

---

## 🚀 How to Deploy

### 🔁 Option 1: Deploy to All RunCloud Servers (via API)

> Fetches server IPs from RunCloud automatically.

1. Set your API key and email in the `.env` file
2. Make the script executable:
   ```bash
   chmod +x deploy_to_all_servers.sh
   ```
3. Run it:
   ```bash
   ./deploy_to_all_servers.sh
   ```

---

### 🧾 Option 2: Deploy to Manual List of Servers

> Reads IPs from `servers.list`

1. Open `servers.list` and list IPs line by line:
   ```txt
   192.168.1.10
   192.168.1.11
   216.128.176.32
   ```
   > **Note:** Ensure there's a newline at the end of the file.
2. Make the script executable:
   ```bash
   chmod +x deploy_to_servers.sh
   ```
3. Run it:
   ```bash
   ./deploy_to_servers.sh
   ```

---

## ✅ Requirements

| Tool       | Purpose                         |
|------------|----------------------------------|
| `bash`     | Script runtime                  |
| `jq`       | JSON parsing (for API mode)     |
| `mail`     | Sends alert notifications       |
| `ping`     | Verifies server availability    |
| `ssh`      | Remote command execution        |
| SSH Key    | `~/.ssh/id_ed25519.pub` required|
