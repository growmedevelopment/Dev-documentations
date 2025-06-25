# 🧹 remove_cron_user

This script is used to **remotely remove the root user's personal crontab** (`crontab -e`) from one or multiple servers via SSH. It ensures that **only the user's crontab** is deleted — system cron jobs in `/etc/cron.d`, `/etc/crontab`, etc., are untouched.

---

## 📂 Folder Structure

```
remove_cron_user/
├── deploy_payload.sh   # Script to be executed on the remote server
├── runner.sh           # Local script that connects via SSH and runs deploy_payload.sh remotely
```

---

## ⚙️ What It Does

- Connects to a remote server using SSH
- Checks if the root user has a crontab
- If present, deletes the root crontab (`crontab -r`)
- Prints clear output for success/failure
- Skips servers with no crontab or failed SSH connection

---

## 📌 Notes

- This only removes `crontab -e` entries for the `root` user.
- It **does not affect** `/etc/crontab` or `/etc/cron.d/*` files.
- Ideal for cleanup or deprecation of obsolete cron tasks like `check_alive.sh`.

---

