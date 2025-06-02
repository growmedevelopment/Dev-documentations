
# 🔐 SSH Key Access Checker for RunCloud Servers

This utility fetches all your servers from the RunCloud API and checks whether your local SSH key is authorized on each one.

---

## 📂 Folder Structure

```
SSHChecker/
└── check_ssh_access.sh      # Main script to list servers and test SSH access                   # Environment file holding your RunCloud API key
└── Documentation.md                    # This documentation
```

---


## 🚀 Usage

Run the script from the `ssh-checker` root directory:

```bash
   /opt/homebrew/bin/bash "/Users/user/----path-to-project/RunCloud/SSHChecker/check_ssh_access.sh
```

You will see a list of all servers with the following columns:

- **Server Name**
- **IP Address**
- **Region**
- **Tags**
- **SSH Status** (`✅` = key access OK, `❌` = key missing or unreachable)

---

## ✅ Requirements

- `bash`
- `curl`
- `jq`
- `timeout`
- Valid SSH key loaded in your agent (`ssh-add -l` to verify)

---

## 🔐 SSH Behavior

- Assumes SSH login as `root`. You can modify this in the script.
- Uses `BatchMode=yes` to fail fast if password auth is required.
- Uses `StrictHostKeyChecking=no` to avoid manual fingerprint confirmations.
- Times out after 5 seconds if no response from server.

---

## 📌 Notes

- This script **does not make any changes** to the servers.
- It only checks whether you have SSH access to the server with your current key.

---

## ✍️ Example Output

```
SERVER NAME                   IP ADDRESS       REGION       TAGS                 SSH
example-server-1             123.123.123.123  us-west-1    web,prod             ✅
example-server-2             123.123.123.124  sg-1         staging              ❌
```

---

## 📬 Support

If your server shows ❌ and you're expecting SSH access, make sure:
- The correct public key is added to `/root/.ssh/authorized_keys`
- The server is online and reachable
- The correct user is used (default is `root`, but you may need `ubuntu`, `admin`, etc.)
```