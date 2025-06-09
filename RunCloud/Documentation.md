# 🌐 Global Script Usage Guide

This guide describes how to run **any script** in the `Scripts/` directory using the unified `run_script()` utility.

---

## 🗂 Structure Convention

Each script lives in a subfolder:

```
Scripts/
├── ssh_script/
│   └── script.sh
├── check_disk/
│   └── script.sh
├── update_packages/
│   └── script.sh
```

Each subfolder must include a file named `script.sh`.

---

## 🧠 Usage Convention

Scripts are run using the utility function:

```bash
run_script "<folder_name>"
```

This executes:

```
Scripts/<folder_name>/script.sh
```

---

## 🏁 Example

```bash
run_script "ssh_script"
```

Executes:

```
Scripts/ssh_script/script.sh
```

---

## 🚀 Integrate in Wrapper Scripts

In `apply_to_all_servers.sh`, for example:

```bash
main() {
  load_env
  detect_timeout_cmd
  fetch_all_servers
  run_script "ssh_script"
}
```

---

## 🔐 Requirements

- `.env` file in project root with:
    - `VULTURE_API_TOKEN`
    - `NOTIFY_EMAIL`
    - `SSH_PUBLIC_KEY`

- Valid script folder with `script.sh` inside

---

## 📌 Notes

- You can combine multiple `run_script` calls in one wrapper
- `servers.list` is typically populated by `fetch_all_servers()`
  """