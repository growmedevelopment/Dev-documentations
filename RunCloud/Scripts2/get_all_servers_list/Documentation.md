# 🔐 RunCloud Server List Report Script

This script fetches a list of all servers from your [RunCloud](https://runcloud.io) account using their API, outputs server information to the terminal, generates an HTML report, and emails it using `msmtp`.

---

## 📄 Features

- Loads environment variables from a `.env` file in the project root
- Paginates through all servers using the RunCloud v3 API
- Displays server details in the terminal:
  - **Server ID**
  - **Server Name**
  - **IP Address**
  - **SSH Command**
- Builds a clean, styled HTML table for report delivery
- Sends the HTML report to your specified email using `msmtp`

---

## 🛠 Setup

### 1. Environment Configuration

Create a `.env` file in your project root (same directory as `utils.sh`) with the following variables:

```env
API_KEY=your_runcloud_api_key_here
NOTIFY_EMAIL=recipient@example.com
```

### 2. `msmtp` Setup (for sending emails)

Ensure `msmtp` is installed:

```bash
sudo apt install msmtp
```

Then configure `~/.msmtprc`:

```ini
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        default
host           smtp.gmail.com
port           587
from           your-email@gmail.com
user           your-email@gmail.com
passwordeval   "gpg --quiet --for-your-eyes-only --no-tty --decrypt ~/.msmtp-password.gpg"

account default : default
```

Encrypt your password:

```bash
echo "yourpassword" | gpg --symmetric --cipher-algo AES256 -o ~/.msmtp-password.gpg
```

---

## ▶️ Usage

```bash
chmod +x runcloud_server_report.sh
./runcloud_server_report.sh
```

The script will:
- Display server data in a terminal table
- Create an HTML report at `/tmp/server_list_report_<timestamp>.html`
- Email the report to `$NOTIFY_EMAIL` using `msmtp`

---

## ✅ Output (Terminal)

```
SERVER ID  SERVER NAME              IP ADDRESS       SSH COMMAND
286146     aaron_machine_shop       149.248.58.80    ssh root@149.248.58.80
...
```

---

## ✅ Output (Email)

You will receive a fully formatted HTML email with a table listing all servers and corresponding SSH commands.

---

## 🧹 Cleanup

The report is stored in `/tmp/` and will be automatically cleaned by the OS. No manual cleanup is required.
