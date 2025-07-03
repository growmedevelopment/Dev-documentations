# 📡 Server Uptime Monitoring Script (Refactored)

## Overview

This system automates deployment of a cron-based monitoring script to a remote server. Every day, the server fetches the **latest list of Vultr instances**, pings each one, and sends an HTML email report showing their availability and response times.

---

## 📁 Components

- **ping_report.sh**  
  The script deployed to the remote server. It:
    - Fetches fresh servers from Vultr API.
    - Generates the ping report.
    - Emails results.

- **utils.sh**  
  Loads environment variables locally (e.g., `VULTR_API_TOKEN`, `NOTIFY_EMAIL`) for the deployment script.

- **deploy_ping_report.sh**  
  The local script you run to:
    - Upload your Vultr API token to the remote server.
    - Deploy `ping_report.sh`.
    - Schedule it in cron.

---

## 🔧 What It Does

1. **Loads Configuration**  
   Your local `deploy_ping_report.sh` loads `VULTR_API_TOKEN` and `NOTIFY_EMAIL` from your environment.

2. **Uploads API Token**  
   Pushes your `VULTR_API_TOKEN` securely to the remote server’s `/root/.vultr_token`.

3. **Deploys Remote Script**  
   Uploads `ping_report.sh` to `/root/ping_report.sh` on the remote server.

4. **Remote Script Behavior**  
   Every time `/root/ping_report.sh` runs (manually or via cron):
    - Fetches the current list of servers from Vultr API.
    - Generates an up-to-date list of IPs.
    - Pings each IP.
    - Creates an HTML report with:
        - IP address
        - Status (`UP` / `DOWN`)
        - Ping time in milliseconds.
    - Emails the report to `NOTIFY_EMAIL`.

5. **Schedules Cron Job**  
   Configures `/etc/cron.d/ping_report` on the remote server to run the report **daily at 12:00 AM**.

---

## ⚠️ Important: API Whitelisting

Don’t forget to **add your remote server’s IP address** to the Vultr API IP whitelist in the [Vultr customer portal](https://my.vultr.com/settings/#apiaccess).  
If you skip this, the API requests from your server will fail with 403 Forbidden errors.

---

## 💌 Output

- **Email Report**  
  Sent daily with:
    - Server IP addresses.
    - Status (`UP`/`DOWN`).
    - Ping times.

- **Log File**  
  Remote server logs each run to `/var/log/ping_debug.log` for troubleshooting.

---

## ✅ Key Advantages

- No need to manually maintain or upload `servers.json` or IP lists.
- The remote server always uses the **latest servers in your Vultr account**.
- Local script only needs to run when you update deployment settings (e.g., change `NOTIFY_EMAIL` or redeploy).

---