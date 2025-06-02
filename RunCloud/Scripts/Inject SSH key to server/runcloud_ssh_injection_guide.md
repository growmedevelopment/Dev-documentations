
# 🛠️ RunCloud SSH Key Injection Script – Developer Guide

## ✅ What It Does
This script:
- Fetches all servers from your RunCloud account.
- Loops through every server (197+).
- Automatically injects your local SSH public key to each server.
- Logs the result for each server.

---

## 📋 Prerequisites


### 0. SSH Key on Your Local Machine

Ensure that you have an SSH key pair generated on your local machine.

- To check for an existing key:
  ```bash
  ls ~/.ssh/id_rsa.pub
  ```
- To generate a new one (if needed):
  ```bash
  ssh-keygen
  ```
This public key will be injected into all your RunCloud servers.

### 1. RunCloud API Token
Create a **Bearer Token**:

- Go to **RunCloud Dashboard > Settings > API Management**
- Click **Add New Token**
- Copy the token and replace this line in the script:

```bash
  API_KEY="your_actual_api_token"
```

---

## 📂 Setup & Execution

1. Save the script as `inject_ssh_key.sh`

2. Make it executable:
```bash
  chmod +x inject_ssh_key.sh
```

3. Run the script:
```bash
  ./inject_ssh_key.sh
```

The script will:
- Loop through all pages of servers
- Change label and publicKey for your
- Use `"temporary": false` to make it permanent

---

## ⚠️ Notes

- The script injects your key even if it's already there.
- If needed, you can modify it to check existing keys before injecting.
- Rate limiting might occur with hundreds of servers — it’s safe to re-run.

---

## ✏️ Optional Customization

- **Change the label**:
  ```json
  "label": "custom-label"
  ```
- **Change the user** (e.g., to `runcloud`):
  ```json
  "username": "runcloud"
  ```
- **Enable temporary access (auto-expires in 7 hours)**:
  ```json
  "temporary": true
  ```
- **Change the label**:
  ```json
  "publicKey": "your ssh public key"
  ```
  
---

