
# 🔐 RunCloud Server List Report Script

This script fetches a list of all servers from your [RunCloud](https://runcloud.io) account using their API, outputs the server information to the terminal, generates an HTML report, and sends it via email using `msmtp`.

---

## 📄 Features

- Loads your RunCloud API key securely from a `.env` file
- Paginates through all available servers using the RunCloud v3 API
- Displays server details in the terminal:
    - **Server ID**
    - **Server Name**
    - **IP Address**
    - **Region**
    - **Tags**
- Generates a clean, responsive HTML table of all server data
- Emails the report to a specified address using `msmtp`

---

## 🛠 Setup

### 1. Environment Configuration

Create a `.env` file in the parent directory of the script with the following variables:

```env
API_KEY=your_runcloud_api_key_here
NOTIFY_EMAIL=recipient@example.com
```

### 2. `msmtp` Setup (for sending emails)

Make sure `msmtp` is installed:

```bash
sudo apt install msmtp
```

Create a `~/.msmtprc` file:

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

Then encrypt your password:

```bash
echo "yourpassword" | gpg --symmetric --cipher-algo AES256 -o ~/.msmtp-password.gpg
```

---

## 🧪 Usage

```bash
chmod +x list_servers.sh
./list_servers.sh
```

This will:

- Print server data in the terminal
- Create an HTML file at `/tmp/server_list_report_<timestamp>.html`
- Email the report to `$NOTIFY_EMAIL` using `msmtp`

---

## ✅ Output Example (Terminal)

```
SERVER ID       SERVER NAME               IP ADDRESS       REGION       TAGS
286146          aaron_machine_shop        149.248.58.80     N/A         production,web
...
```

---

## ✅ Output Example (Email)

You will receive an HTML-formatted email listing all servers in a table, ready to view in a browser or forward to other teams.

---

## 🧹 Cleanup

The HTML report is saved to `/tmp/` and will be cleaned up by the OS automatically.
