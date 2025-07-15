# 💰 Vultr Cost Summary Reporter

This mini-project provides a Bash script to fetch all active Vultr VPS instances, calculate hourly and estimated monthly cost, and email a clean HTML summary report.

---

## 📦 Features

- Lists **all active VPS instances**
- Computes:
    - Total number of servers
    - Total hourly cost
    - Estimated monthly cost (based on 30 days uptime)
- Sends a **formatted HTML email** to the provided recipient

---

## ⚙️ Setup

1. **.env file (required)**

```dotenv
VULTR_API_TOKEN=your_vultr_api_token_here
NOTIFY_EMAIL=your_email@example.com
```

2. **Dependencies**

Ensure the following are available:

- `bash`
- `jq`
- `curl`
- `bc`
- `msmtp` (configured to send email)

---

## 🚀 Usage

```bash
bash Scripts/cost-summary/script.sh
```

---

## 📧 Email Example

- Subject: `💰 Vultr Server Cost Summary`
- Body:
    - Total number of servers
    - Hourly cost
    - Estimated monthly cost

---

## 🧠 Notes

- Uses Vultr API v2 with pagination and `show_pending_charges=true`
- HTML output is minimal, designed for email compatibility

---
## 📬 Author

GrowME DevOps – Dmytro Kovalenko