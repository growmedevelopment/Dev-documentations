# 🌐 Global Script Usage Guide

This guide explains how to run **any per-server automation script** located in the `Scripts/` directory using the unified `deploy_to_servers.sh` and `run_script()` setup.

---

## 🗂 Folder Structure Convention

Each task lives in its own subfolder under `Scripts/`, containing a single entry point named `script.sh`:

```
Scripts/
├── ssh_script/
│   └── script.sh
├── check_disk/
│   └── script.sh
├── update_packages/
│   └── script.sh
```

- ✅ Every folder must contain a `script.sh` file.
- ✅ Each `script.sh` must accept **1 argument**: the server IP.

---

## 🧠 Usage Pattern

Scripts are executed **once per server** using:

```bash
run_script "<folder_name>" "$server"
```

This will execute:

```bash
Scripts/<folder_name>/script.sh "$server"
```

---

## 🚀 Universal Runner

Use the main runner to loop through all servers and execute your script:

```bash
./deploy_to_servers.sh ssh_script
```

This will:
- Load all IPs from `servers.list`
- For each IP, call `Scripts/ssh_script/script.sh <ip>`

---

## 📄 Example Integration

Inside `deploy_to_servers.sh`:

```bash
SCRIPT_NAME="ssh_script"

for server in "${SERVER_LIST[@]}"; do
  run_script "$SCRIPT_NAME" "$server"
done
```

---

## 🔐 Requirements

- `.env` file in project root with:
  - `VULTURE_API_TOKEN`
  - `NOTIFY_EMAIL`
  - `SSH_PUBLIC_KEY`
- `servers.list` file in project root:
  - One IP per line
  - No trailing comments or empty lines
- Each `script.sh`:
  - Must be executable (`chmod +x script.sh`)
  - Must use `$1` as the target server IP
  - Should include `set -euo pipefail`

---

## 🧩 Optional Enhancements

- Combine multiple tasks:
  ```bash
  run_script "check_disk" "$server"
  run_script "update_packages" "$server"
  ```
- Use `timeout` and SSH options like:
  ```bash
  ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no ...
  ```
- Track success/failure per server
- Log outputs for audit/debugging

---

## ✅ Best Practices

- Keep each script focused on a single concern
- Handle unreachable servers gracefully
- Validate arguments before use
- Exit with `0` on success, `1` on failure
