
# 🧰 RunCloud & Vultr Backup Folder Verification Script

This script verifies whether all existing RunCloud applications have corresponding backup folders in your Vultr Object Storage bucket.

---

## 📦 Purpose

- Fetch all web applications from all RunCloud servers.
- List all top-level folders in the Vultr bucket (`runcloud-app-backups`).
- Compare folder names to app names.
- Print any unmatched folders to the terminal.

---

## 🔧 Requirements

- Bash
- `jq`
- AWS CLI (configured for Vultr)
- `.env` file with the following:
    - `API_KEY` (RunCloud API)
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

- Uses pagination to loop through all servers and apps.
- Collects all app names into an array.
- Lists all folders in Vultr bucket via:

```bash
aws s3 ls s3://runcloud-app-backups/ --endpoint-url https://sjc1.vultrobjects.com
```

- Compares **lowercased** folder and app names to avoid mismatches due to casing.

---

## 🛠 Matching Logic

To ensure robustness, both folder and app names are normalized before comparison:

```bash
norm_folder=$(echo "$folder" | xargs | tr '[:upper:]' '[:lower:]')
norm_app=$(echo "$app" | xargs | tr '[:upper:]' '[:lower:]')
if [[ "$norm_folder" == "$norm_app" ]]; then
  matched=true
fi
```

This solves the issue where `Google_Merchant_Center_API` was flagged as unmatched when the app was saved as `google_merchant_center_api`.

---

## 📤 Output

- `✅ Found XX apps on RunCloud`
- `☁️ Scanning folders in Vultr bucket`
- `❌ Unmatched backup folder: folder_name`
- `📊 Total backup folders: X, Unmatched: Y`

---

## 🧼 Cleanup Suggestion

If a folder is unmatched, consider:
- Verifying the app was deleted
- Archiving or deleting the backup
