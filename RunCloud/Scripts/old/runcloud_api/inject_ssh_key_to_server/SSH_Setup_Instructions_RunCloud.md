
# 📘 Instruction 1: How to Set Up SSH Access to RunCloud

## 🔧 Overview

This guide walks you through setting up SSH access to your RunCloud server. You’ll:
- Generate a new SSH key (if needed)
- Add your public key to the server
- Test your connection
- Switch to the root user for administrative tasks

---

## ✅ Step 1: Generate an SSH Key (If You Don’t Have One)

On your **local machine** (not the server), run the following:

```bash
  ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

Press `Enter` to accept the default file location. This will generate:

- **Private key**: `~/.ssh/id_rsa`
- **Public key**: `~/.ssh/id_rsa.pub`

---

## ✅ Step 2: Upload Your Public Key to the RunCloud Server

Use this command to copy your public key to the server:

```bash
  ssh-copy-id runcloud@<your-server-ip>
```

Replace `<your-server-ip>` with the actual IP address of your RunCloud server.  
You’ll be prompted to enter the password for the `runcloud` user.

> 🔐 **Alternative (Manual Method):**  
> If `ssh-copy-id` is unavailable, you can manually copy the contents of `~/.ssh/id_rsa.pub` into the file `~/.ssh/authorized_keys` on the server under the `runcloud` user.

---

## ✅ Step 3: Test the SSH Connection

Try connecting to the server to verify SSH access:

```bash
  ssh runcloud@<your-server-ip>
```

You should connect **without being prompted for a password**.

---

## ✅ Step 4: Switch to the Root User

Once connected as the `runcloud` user, switch to the root user for full administrative access:

```bash
  sudo -i
```

This will allow you to:
- Install software packages
- Set up cron jobs
- Configure system-level scripts and services
