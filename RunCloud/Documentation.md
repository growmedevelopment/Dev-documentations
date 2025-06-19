# 🌐 Global Script Usage Guide

Before running any script, ensure you have **root access** to the server.

---

## 🔐 Gaining Access

1. **Generate SSH Key:**  
   → See `Create SSH Key.md` in the `ssh_injection/` folder.

2. **Inject SSH Key:**  
   → Run the injection script in the same folder to enable root access.

---

## 🚀 Running Scripts

Use the **Universal Runner**:
```bash
deploy_to_servers.sh
```

Just set:
```bash
SCRIPT_FOLDER=<your-target-folder>
```
…to run any script from that directory on all listed servers.

---

## 📦 Main Scripts

1. `ssh_injection` – Injects SSH key for root access
2. `check_ram_cpu_disk_usage` – Checks server health (RAM, CPU, disk)
3. `extend_space_with_unallocated` – Expands unallocated disk space
4. `set_making_backup` – Sets up automated daily backups and restore config

---

## 🛠️ Helper Scripts

- `make_backup` – Manually runs `full_vultr_backup.sh` for daily backup
- `ssh_script` – Verifies SSH access and provides SSH key instructions
