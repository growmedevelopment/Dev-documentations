# 🔐 SSH Accessibility Checker (`ssh_script`)

This script checks SSH accessibility to a **single server**, passed as an argument. It is meant to be run once per server by the main automation runner.

---

## 📂 Location

```
Scripts/ssh_script/script.sh
```

---

## ▶️ How It's Used

It is called automatically by the universal runner:

```bash
./deploy_to_servers.sh ssh_script
```

Or manually for a single server:

```bash
./Scripts/ssh_script/script.sh 192.168.1.10
```

---

## 📝 Behavior

- Accepts a single argument: the server IP
- Attempts SSH login as `root` using key-based auth
- Times out after 5 seconds
- Returns:
  - `0` on success ✅
  - `1` on failure ❌

---

## ✅ Requirements

- `bash`, `ssh`, `timeout` (or `gtimeout` on macOS)
- SSH key already added to the server
- No password prompts

---

## 📌 Notes

- No changes are made to the server
- Safe to run repeatedly
- Designed for integration with `deploy_to_servers.sh`
