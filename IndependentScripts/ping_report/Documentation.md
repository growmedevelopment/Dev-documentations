# 📡 Server Uptime Monitoring Script

## Overview

This system automates deployment of a cron-based monitoring script to a remote server. Every day, the server fetches the **latest list of Vultr instances**, pings each one, and sends HTML email reports.

It now provides **two types of reports**:
1. A **full uptime report** (all servers with UP/DOWN status).
2. A **down-only alert** (sent separately if one or more servers are unreachable).

---

## 📁 Components

- **ping_report.sh**  
  The script deployed to the remote server. It:
    - Fetches fresh servers from the Vultr API.
    - Generates a **full HTML uptime report**.
    - Generates a **separate DOWN-only alert** if any servers fail.
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
    - Fetches the current list of servers from Vultr API (handles pagination).
    - Generates an up-to-date list of IPs.
    - Pings each IP.
    - Creates two reports:
        - **Full Uptime Report (all servers)**  
          Shows IP address, status (`UP`/`DOWN`), and ping time in milliseconds.
        - **Down-Only Report**  
          Sent separately only if one or more servers fail, showing just those IPs marked `DOWN`.
    - Emails the reports to `NOTIFY_EMAIL`.

5. **Schedules Cron Job**  
   Configures `/etc/cron.d/ping_report` on the remote server to run the report **daily at 12:00 AM**.

---

## ⚠️ Important: API Whitelisting

Don’t forget to **add your remote server’s IP address** to the Vultr API IP whitelist in the [Vultr customer portal](https://my.vultr.com/settings/#apiaccess).  
If you skip this, the API requests from your server will fail with 403 Forbidden errors.

---

## 💌 Output

- **Email Report (always sent)**
    - Table of all servers with:
        - IP address
        - Status (`UP`/`DOWN`)
        - Ping times (ms)

- **Down-Only Alert (conditionally sent)**
    - Sent **only if at least one server is unreachable**.
    - Contains a simplified table of only `DOWN` servers.
    - Subject line starts with:
      ```
      🚨 ALERT: Servers Down - YYYY-MM-DD HH:MM
      ```

- **Log File**  
  Remote server logs each run to `/var/log/ping_debug.log` for troubleshooting.

---

## ✅ Key Advantages

- **Automated discovery** — No need to manually update IP lists; the script always uses the latest servers from Vultr.
- **Dual reporting** — Always get the full daily snapshot **plus** a separate urgent alert if something breaks.
- **Error handling** — Failures trigger immediate error notifications with line numbers.
- **Easy redeployment** — Just re-run `deploy_ping_report.sh` when updating configs.

---

## 📬 Author

GrowME DevOps – Dmytro Kovalenko