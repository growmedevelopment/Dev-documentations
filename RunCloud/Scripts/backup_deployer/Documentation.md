# RunCloud Backup Deployer

This script automates backups for **all RunCloud servers** by:
- Fetching server details using the RunCloud API
- Pinging each server to check availability
- Running a backup script remotely over SSH on each server

---

## 📁 File: `backup-deployer.sh`

### 🔧 Features

- Loads environment variables from a `.env` file
- Handles both raw SSH public key strings and file paths
- Uses the RunCloud API to fetch server information with pagination
- Checks if each server is online using `ping`
- Runs the `/root/full_vultr_backup.sh daily` script via SSH on each online server
- Skips offline servers and optionally sends email alerts

---

## 🔐 Environment Setup

Create a `.env` file in the parent directory with the following variables:

```env
API_KEY=your_runcloud_api_key
SSH_PUBLIC_KEY=your_ssh_key_or_path
NOTIFY_EMAIL=admin@example.com
```

---

## 🚀 Usage

From the `Scripts` directory:

```bash
chmod +x backup-deployer.sh
./backup-deployer.sh
```

Or run with bash explicitly:

```bash
/bin/bash ./backup-deployer.sh
```

---

## 🛠️ Notes

- Make sure the SSH key has access to all target servers.
- Your `full_vultr_backup.sh` must exist on each server under `/root/`.
- Ensure `jq` and `curl` are installed locally.
- Output includes logs of each server’s status and whether backups were triggered.

---

## ✅ Example Output

```bash
✅ Using raw SSH public key string
🔍 [1/192] Checking availability of server1 (IP)...
✅ server1 is online. Running backup script...
✅ Backup executed on server1
...
```

---

