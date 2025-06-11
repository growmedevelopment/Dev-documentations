# 🛠️ RunCloud SSH Key Injection Script – Developer Guide

## ✅ What It Does

This script:
- Injects your local SSH public key into each server (using root access).

---

## 📋 Prerequisites

### 0. SSH Key on Your Local Machine

Ensure that you have an SSH key pair ready:

- To check if you already have one:
  ```bash
  ls ~/.ssh/id_rsa.pub
  ```
- To generate a new SSH key:
  ```bash
  ssh-keygen
  ```

This public key will be injected into all RunCloud-managed servers.

### 1. RunCloud API Token

Create a **Bearer Token**:

- Go to **RunCloud Dashboard > Settings > API Management**
- Click **Add New Token**
- Copy the token

Place your API key and SSH key info into a `.env` file in your project root:

```
API_KEY=your_runcloud_api_token
SSH_KEY_NAME=MyDeploymentKey
SSH_PUBLIC_KEY=ssh-rsa AAAAB3NzaC1...
```

---




## 📌 Behavior

- Uses the `/servers` and `/servers/<id>/ssh/credentials` API endpoints
- Injects the key unconditionally (no deduplication)
- Sets `"temporary": false` to persist the access

---

## ⚠️ Notes

- Re-running is safe; no validation of existing keys is done.
- You may hit API rate limits with many servers — the script handles paginated fetching.
- SSH key is injected for the `root` user by default.

---

## ✏️ Optional Customization

- **Change the label**:
  ```json
  "label": "my-custom-label"
  ```
- **Change the username**:
  ```json
  "username": "runcloud"
  ```
- **Make the key temporary (expires in ~7 hours)**:
  ```json
  "temporary": true
  ```

---

## ✅ Follow-up: Use `servers.list` for Deployment

Once SSH access is injected, you can use:

```bash
./deploy_to_servers.sh ssh_script
```

To verify access or trigger other automations per server.
