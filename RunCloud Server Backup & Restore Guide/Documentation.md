
# 🛡️ RunCloud Server Backup & Restore Guide

## 📘 INSTRUCTION 1: How to Set Up Automated Backups

### 🔧 Overview

This guide shows you how to:
- Create full **daily and weekly backups** for all WordPress apps on a RunCloud server
- Upload them to **Vultr Object Storage**
- Set up automated scheduling with **cron**

---

### ✅ Prerequisites

- Ubuntu server managed by RunCloud
- AWS CLI installed: `sudo apt install awscli`
- Access to Vultr Object Storage (bucket, access key, secret key, endpoint)

---

### 🛠️ Step-by-Step Setup

### 🔐 SSH Access Setup (Required for Backup Script Setup)

To configure your backup script on a RunCloud server, you must first connect via SSH.

#### ✅ 1. Generate an SSH Key (if you don’t have one)

Run this on your local machine (not the server):

```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

Press `Enter` to accept the default file location. This creates:

- A private key: `~/.ssh/id_rsa`
- A public key: `~/.ssh/id_rsa.pub`

#### ✅ 2. Copy your public key to the server

Use the following command to upload your public key to the RunCloud server:

```bash
ssh-copy-id runcloud@155.138.130.98
```

If prompted, enter the password for the `runcloud` user.

> 🔐 Alternatively, manually paste your `id_rsa.pub` content into the server’s `~/.ssh/authorized_keys` file.

#### ✅ 3. Test the connection
#### ✅ 4. Switch to Root User

Once connected to the server as the `runcloud` user, switch to the `root` user to complete the backup setup:

```bash
sudo -i
```

This gives you full administrative privileges to install packages, configure cron jobs, and manage system-level scripts.


Run:

```bash
ssh runcloud@155.138.130.98
```

You should be connected without entering a password.


#### 1. Configure AWS CLI for Vultr

```bash
aws configure
```

Then:

```bash
nano ~/.aws/config
```

Paste:

```ini
[default]
region = us-east-1
output = json

s3 =
    endpoint_url = https://your-region.vultrobjects.com
```

---

#### 2. Create the Backup Script

Save this as `~/full_vultr_backup.sh`:


Make it executable:

```bash
chmod +x ~/full_vultr_backup.sh
```

---

#### 3. Automate with Cron

```bash
crontab -e
```

Add:

```bash
30 2 * * * /bin/bash ~/full_vultr_backup.sh daily >> ~/backup_daily.log 2>&1
0 3 1 * * /bin/bash ~/full_vultr_backup.sh weekly >> ~/backup_weekly.log 2>&1
```
---

### 📄 Viewing Backup Logs

To check the output of automated backups:

#### ✅ Daily Backup Log

```bash
tail -n 50 ~/backup_daily.log
```

#### ✅ Weekly Backup Log

```bash
tail -n 50 ~/backup_weekly.log
```

Use `less`, `cat`, or `grep` to search through full logs:

```bash
less ~/backup_daily.log
```
---

## 📘 INSTRUCTION 2: How to Restore a Backup

### 🔄 Overview

Restore:
- Any backup made by the backup script
- From local disk or Vultr Object Storage
- Files + database

---

### 🛠️ Step-by-Step Restore

#### 1. Create the Restore Script

Save as `~/restore-backup.sh`:


Make it executable:

```bash
chmod +x ~/restore-backup.sh
```

---

### ✅ How to Use

```bash
./restore-backup.sh
```

Then follow prompts to restore any app from a given date.
