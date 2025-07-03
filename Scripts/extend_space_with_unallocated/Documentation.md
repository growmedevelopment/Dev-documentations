# 🛠 Remote Disk Extension Script - Instruction

## 📘 What This Script Does

This script connects to a remote Linux server over SSH and performs automated disk space extension on the root partition **only if unallocated space is available**.

---

## ✅ Main Steps Performed by the Script

1. **Connects via SSH** to the specified server using a secure, non-interactive method with timeouts to prevent hangs.
2. **Identifies the root partition and physical disk** using `df` and `lsblk`.
3. **Calculates unallocated disk space** by subtracting the total used partition size from the disk size.
4. If **more than 10MB** of unallocated space is detected:
    - **Extends the root partition** using `growpart`.
    - **Resizes the filesystem**:
        - Uses `resize2fs` for ext2/3/4 filesystems.
        - Uses `xfs_growfs` for XFS filesystems.
5. **Logs each step with clear, human-readable output** to track success or failure.

---

## 🧰 Requirements

- Remote server must have:
    - `growpart` (from `cloud-guest-utils`)
    - `lsblk` (from `util-linux`)
    - `resize2fs` or `xfs_growfs`
- SSH access with root privileges and no password prompt (key-based auth recommended).

---
