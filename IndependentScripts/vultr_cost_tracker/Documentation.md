# 💰 Vultr Cost Summary Reporter

This mini-project provides a Bash script to fetch all active Vultr VPS instances, calculate **pending charges**, and email a clean HTML summary report.  
The report now includes both a **summary** and a **per-server cost breakdown**, sorted from highest to lowest.

---

## 📦 Features

- Lists **all active VPS instances**
- Computes:
    - Total number of servers
    - Total pending charges (from Vultr API)
- Sends a **formatted HTML email** containing:
    - **Summary Table** – total servers and total pending charges
    - **Detailed Breakdown** – server name, IP address, and cost per server, sorted by highest cost first

---

## ⚙️ Setup

1. **.env file (required)**

```dotenv
VULTR_API_TOKEN=your_vultr_api_token_here
NOTIFY_EMAIL=your_email@example.com
```

2. **Dependencies**

Ensure the following are installed and configured on the system:

- `bash`
- `jq`
- `curl`
- `msmtp` (configured to send email)

---

## 🚀 Usage

```bash
bash Scripts/cost-summary/script.sh
```

---

## 📧 Email Example

- **Subject:**  
  `💰 Vultr Server Cost Summary`

- **Body includes:**
    - 📊 Summary table:
        - Total number of servers
        - Total pending charges
    - 💡 Detailed breakdown table:
        - Server Name
        - IP Address
        - Pending Charges (USD)
        - Sorted descending by cost

---

## 🧠 Notes

- Uses Vultr API v2 with pagination and `show_pending_charges=true`
- Safely handles missing/null cost values
- HTML output is lightweight and designed for email client compatibility
- Logs API errors and aborts with a clear message if the request fails

---

## 📬 Author

GrowME DevOps – Dmytro Kovalenko
