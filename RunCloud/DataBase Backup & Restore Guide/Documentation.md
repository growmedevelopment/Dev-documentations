# 🛡️ RunCloud Server Backup & Restore Guide

## 📘 INSTRUCTION 1: How to Set Up Automated Backups

### 🔧 Overview

This guide shows you how to:
- Create full **daily, weekly, monthly, and yearly backups** for all WordPress apps on a RunCloud server
- Upload them to **Vultr Object Storage**
- Set up automated scheduling with **cron**

---

This script already includes checks for low disk space, automatic installation of mail utilities, and email notifications for errors

### ✅ Prerequisites

- Ubuntu server managed by RunCloud
- AWS CLI installed: `sudo apt install awscli`
- Access to Vultr Object Storage (bucket, access key, secret key, endpoint)

---

### 🛠️ Step-by-Step Setup

### 🔐 SSH Access Setup (Required for Backup Script Setup)

To configure your backup script on a RunCloud server, you must first connect via SSH.


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
Create file   `nano ~/full_vultr_backup.sh`:
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
    # Run daily backup at 2:30 AM every day
    30 2 * * * /bin/bash ~/full_vultr_backup.sh daily >> ~/backup_daily.log 2>&1
    
    # Run weekly backup at 3:00 AM every Sunday
    0 3 * * 0 /bin/bash ~/full_vultr_backup.sh weekly >> ~/backup_weekly.log 2>&1
    
    # Run monthly backup at 3:00 AM on the 1st of each month
    0 3 1 * * /bin/bash ~/full_vultr_backup.sh monthly >> ~/backup_monthly.log 2>&1
    
    # Run yearly backup at 3:00 AM on January 1st
    0 3 1 1 * /bin/bash ~/full_vultr_backup.sh yearly >> ~/backup_yearly.log 2>&1
```
---


---

### ✅ How to Use

```bash
  ./full_vultr_backup.sh [mode]
```

Where [mode] can be one of:
•	daily
•	weekly
•	monthly
•	yearly


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

#### ✅ Monthly Backup Log

```bash
  tail -n 50 ~/backup_monthly.log
```

#### ✅ Yearly Backup Log

```bash
  tail -n 50 ~/backup_yearly.log
```

Use `less`, `cat`, or `grep` to search through full logs:

```bash
  less ~/backup_daily.log
```
---

## 📘 INSTRUCTION 2: How to Restore a Backup

### 🔄 Overview

This guide walks you through restoring a backup created by the automated backup script. You can restore:
- Website files
- Databases
- From either **local disk** or **Vultr Object Storage**

--- 

### 🛠️ Step-by-Step Restore

#### 1. Create the Restore Script

Create a script file to manage the restore process:

```bash
  nano ~/restore-backup.sh
```

Add your restore logic inside this script.

Then make it executable:

```bash
  chmod +x ~/restore-backup.sh
```

---

### ✅ How to Use

To start the restoration process, run:

```bash
  ./restore-backup.sh
```

Follow the on-screen prompts to:
- Select a backup date
- Choose the app to restore
- Complete file and database restoration
