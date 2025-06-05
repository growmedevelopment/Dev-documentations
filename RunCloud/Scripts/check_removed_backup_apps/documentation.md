
# 🧰 RunCloud & Vultr Backup Folder Verification Script

This script verifies whether all existing **RunCloud applications** have corresponding **backup folders** in your **Vultr Object Storage** bucket, and vice versa.

---

## 📦 Purpose

- Retrieve all web applications from all RunCloud servers (with pagination support).
- List all top-level folders from the Vultr bucket (`runcloud-app-backups`).
- Compare the list of app names with the list of folders.
- Identify:
  - Orphaned folders (no corresponding app)
  - Apps missing backups (no corresponding folder)
  - Clean up old backup files from `daily` and `weekly` subfolders of orphaned folders, keeping only the latest one.

---

## 🔧 Requirements

- Bash
- `jq`
- AWS CLI (configured for Vultr)
- `.env` file containing:
  - `API_KEY` (RunCloud API token)
  - AWS credentials if not globally configured

---

## 📁 .env Format

```dotenv
API_KEY=your_runcloud_api_key
AWS_ACCESS_KEY_ID=your_aws_key
AWS_SECRET_ACCESS_KEY=your_aws_secret
```

---

## 🧪 How to Use

```bash
chmod +x script.sh
./script.sh
```

---

## ✅ Script Behavior

- Loads environment variables from `.env`.
- Uses the RunCloud API to:
  - Paginate through all servers.
  - Paginate through all web applications on each server.
- Lists folders in the specified Vultr bucket via:

```bash
aws s3 ls s3://runcloud-app-backups/ --endpoint-url https://sjc1.vultrobjects.com
```

- Normalizes all names (lowercase, trimmed) before comparing.

---

## 🔍 Matching Logic

To ensure accuracy, app and folder names are **normalized** before comparison:

```bash
norm_folder=$(echo "$folder" | xargs | tr '[:upper:]' '[:lower:]')
norm_app=$(echo "$app" | xargs | tr '[:upper:]' '[:lower:]')
```

This prevents mismatches from minor formatting differences (like underscores vs. hyphens or case sensitivity).

---

## 📤 Output

- `✅ Total apps found: XX`
- `☁️ Listing top-level folders in bucket: runcloud-app-backups`
- `🗑️ Folders with no corresponding RunCloud app (likely deleted):`
  - Lists unmatched folders
- `❗ Apps without corresponding S3 backup folders:`
  - Lists unmatched apps

---

## 🧼 Cleanup Suggestions

For unmatched folders:
- Confirm if the related app was intentionally deleted.
- Archive or remove stale backup folders as needed.
- The script now **automatically cleans up** `daily` and `weekly` subfolders in unmatched folders by deleting all but the latest backup file.

For unmatched apps:
- Review backup automation.
- Manually create a backup folder if necessary.
