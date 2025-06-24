#!/opt/homebrew/bin/bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Setup & Globals
# ────────────────────────────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/utils.sh"

SCRIPT_FOLDER="ssh_injection"
#SCRIPT_FOLDER="${1:-ssh_injection}"
#./main.sh check_ram_cpu_disk_usage

SERVER_JSON="$ROOT_DIR/servers.json"
FAILED=()
REPORT_FILE=""

# ────────────────────────────────────────────────────────────────
# Handler for RAM/CPU/Disk usage summary + email
# ────────────────────────────────────────────────────────────────

handle_check_usage() {
  echo "📂 Running $SCRIPT_FOLDER using server IPs"
  setup_html_report
  run_for_all_servers
  send_html_report
}

# ────────────────────────────────────────────────────────────────
# Handler for any other script
# ────────────────────────────────────────────────────────────────

handle_default_script() {
  echo "📂 Running $SCRIPT_FOLDER using server IPs"
  run_for_all_servers
}

#---------------------------------------
# Main Logic
#---------------------------------------
load_env
detect_timeout_cmd

if [[ "$SCRIPT_FOLDER" == "ssh_injection" ]]; then
  create_or_clear_servers_json_file
  fetch_all_runcloud_servers
else
  # Only fetch if file doesn't exist or is empty
  if [[ ! -f "$SERVER_JSON" || $(jq 'length' "$SERVER_JSON") -eq 0 ]]; then
    create_or_clear_servers_json_file
    fetch_vultr_servers
  fi
fi


get_all_servers_from_file

if [[ "$SCRIPT_FOLDER" == "check_ram_cpu_disk_usage" ]]; then
  handle_check_usage
else
  handle_default_script
fi

print_summary