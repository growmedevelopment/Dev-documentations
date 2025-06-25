
# 📡 Server Uptime Monitoring Script

## Overview

This script automates deployment of a cron-based monitoring system to a remote server. It pings a list of servers daily and emails an HTML report indicating their availability and response time.

---

## 📁 Components

- `servers.json`: JSON file containing an array of servers with `name` and `ipAddress` keys.
- `ping_report.sh`: The script deployed to the remote server for ping checks and email reporting.
- `utils.sh`: Loads environment variables (like `NOTIFY_EMAIL`).

---

## 🔧 What It Does

1. **Loads Configuration**  
   Loads the environment and server list from `servers.json`.

2. **Generates IP List**  
   Extracts all IP addresses from the JSON and writes them to `/tmp/server_ips.txt`.

3. **Uploads to Remote Server**  
   Copies the IP list to `/root/server_ips.txt` on the target server.

4. **Creates Remote Script**  
   Deploys `ping_report.sh` to `/root` on the remote server:
    - Pings each IP.
    - Creates an HTML status report.
    - Emails it to `NOTIFY_EMAIL`.

5. **Schedules Cron Job**  
   Sets up a daily cron job at 12:00 AM to run the report automatically.

---

## 💌 Output

- **Email Report**  
  Sent daily with:
    - Server IP
    - Status (`UP` / `DOWN`)
    - Ping time in milliseconds
