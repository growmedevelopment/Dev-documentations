# ⏰ Server Timezone Sync Script

This script ensures that all remote servers are configured to use the **America/Edmonton** time zone and have **NTP (Network Time Protocol)** enabled for accurate timekeeping.

---

## 🧾 Usage

Run the script for a specific server:

```bash
  ./deploy_to_servers.sh set_time_zone
```

The `deploy_to_servers.sh` wrapper will:
1. Load server details from `servers.json`
2. Call `script.sh` with IP, ID, and name for each server
3. SSH into the server and:
    - Check current timezone
    - If not `America/Edmonton`, change it
    - Enable and confirm NTP

---

## 🛠 What It Does

Inside `script.sh`:

- Connects to the server via SSH
- Checks current timezone:
  ```bash
  timedatectl show --value --property=Timezone
  ```
- If incorrect, runs:
  ```bash
  timedatectl set-timezone America/Edmonton
  timedatectl set-ntp true
  ```

---

## ✅ Output Example

```
🌐 Connecting to 149.248.58.80 to update timezone...
🕒 Ensuring timezone is set to America/Edmonton on vultr...
🌎 Updating timezone from Etc/UTC to America/Edmonton...
✅ Timezone update complete for vultr (149.248.58.80)
```

---

## 📁 Requirements

- SSH key-based access to each server
- Bash installed locally
- Each server must support `timedatectl`

---

## 📌 Notes

- Best practice: keep RTC in UTC (`RTC in local TZ: no`)
- Works for any number of servers using `servers.json`

---

## 📬 Author

GrowME DevOps – Dmytro Kovalenko
