# 🛡️ RunCloud Backup & Monitoring Automation

This folder contains a complete automation script that deploys daily and weekly backup tasks, along with health monitoring, across **all servers managed through RunCloud**.

## 🔧 What It Does

- ✅ Authenticates to the RunCloud API to retrieve all server IPs
- ✅ Pings each server to verify it's online
- ✅ Sends an email to `development@growme.ca` if a server is offline
- ✅ Connects via SSH to:
  - Install and configure the AWS CLI for Vultr Object Storage
  - Deploy the `full_vultr_backup.sh` script:
    - Archives each WordPress app’s files + MySQL DB
    - Uploads the archive to Vultr Object Storage
    - Sends a failure email to `development@growme.ca` if DB dump fails
  - Deploy the `check_alive.sh` script:
    - Runs every 5 minutes via cron
    - Pings 8.8.8.8 and notifies `development@growme.ca` if unreachable
  - Replaces all existing cron jobs with:
    - `30 2 * * *` – Daily backup
    - `0 3 * * 0` – Weekly backup
    - `*/5 * * * *` – Server uptime check

## 📨 Notification Emails

- **Server unreachable during deploy:** `development@growme.ca`
- **Database backup failure:** `development@growme.ca`
- **Health check ping failure:** `development@growme.ca`

## 🚀 How to Use

1. Set your RunCloud API key in `deploy_to_all_servers.sh`
2. Make the script executable:

   ```bash
   chmod +x deploy_to_all_servers.sh
   ```

3. Run it:

   ```bash
   ./deploy_to_all_servers.sh
   ```

All servers will be updated in-place with the backup and monitoring logic above.
