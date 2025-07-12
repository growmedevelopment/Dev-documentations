# RunCloud Backup Cleanup Script

This tool helps you automatically manage backups stored in Vultr Object Storage (S3-compatible) for web applications deployed on RunCloud:

✅ Deletes old backups for apps that have been removed from RunCloud  
✅ Keeps only the latest backup in each orphaned app’s `daily/` and `weekly/` folders  
✅ Detects apps that exist in RunCloud but have no corresponding backup folders  
✅ Supports **dry-run mode** so you can test safely before actually deleting

---

## 📦 Features

- Fetches all applications across your RunCloud servers
- Lists top-level folders (apps) in your Vultr bucket
- Compares RunCloud apps and backup folders to identify:
    - Orphaned backups (folders for apps that no longer exist)
    - Apps missing backups (apps with no folder in Vultr bucket)
- Cleans up old backups inside `daily/` and `weekly/` folders, keeping the most recent
- Modular, well-documented Bash script with clear logs

---

## 🛠 Requirements

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (configured for Vultr Object Storage)
- [jq](https://stedolan.github.io/jq/)
- curl
- Bash 4+

---

## ⚙️ Environment Variables

You must provide these in a `.env` file two directories above your script (or adjust the script path):

```dotenv
AWS_ACCESS_KEY_ID=YOUR_VULTR_KEY
AWS_SECRET_ACCESS_KEY=YOUR_VULTR_SECRET
API_KEY=YOUR_RUNCLOUD_API_KEY
```

---

## 📬 Author

GrowME DevOps – Dmytro Kovalenko