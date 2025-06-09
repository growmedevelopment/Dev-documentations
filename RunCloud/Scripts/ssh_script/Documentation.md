# 🔐 SSH Accessibility Checker (`ssh_script`)

This script checks SSH accessibility to all servers listed in your `servers.list` file.

---

## 📂 Location

```
Scripts/ssh_script/script.sh
```

---

## ▶️ How to Run

Use the main controller script (recommended):

```bash
/bin/bash apply_to_all_servers.sh
```

Or run directly (requires `servers.list` pre-filled):

```bash
/bin/bash Scripts/ssh_script/script.sh
```

---

## 📝 Behavior

- Reads IPs from `servers.list`
- Pings and attempts SSH as `root`
- Reports status with ✅ or ❌

---

## ✅ Requirements

- `bash`, `jq`, `curl`, `timeout` or `gtimeout`
- `.env` file in project root with:
    - `VULTURE_API_TOKEN`
    - `NOTIFY_EMAIL`
    - `SSH_PUBLIC_KEY`

---

## 📌 Notes

- No changes are made to the servers
- Used only to verify key-based SSH access
  """