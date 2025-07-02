## 🚦 Removed Servers Checker

![Removed Servers Checker](https://img.shields.io/badge/Removed%20Servers%20Checker-Active-brightgreen?style=for-the-badge&logo=linux)

This script automatically detects **servers that still exist in Vultr but no longer exist in RunCloud**, helping you identify orphaned servers you might still be paying for. It:

✅ Fetches active servers from **Vultr** and **RunCloud**  
✅ Validates the API responses for correct JSON  
✅ Compares IPs to find servers present in Vultr but missing in RunCloud  
✅ Generates a detailed **HTML report** listing these servers  
✅ Emails the report to your configured recipient

### 📥 Inputs

- **Environment variables**:
    - `VULTR_API_TOKEN` — Vultr API token
    - `RUNCLOUD_API_TOKEN` — RunCloud API token
    - `NOTIFY_EMAIL` — recipient email for the report

### 📤 Outputs

- HTML report saved at `/tmp/servers_removed_report.html`
- Report emailed to `$NOTIFY_EMAIL`

> **Why use it?**  
> Keep your infrastructure clean and costs under control by identifying servers running in Vultr that are no longer managed in RunCloud.