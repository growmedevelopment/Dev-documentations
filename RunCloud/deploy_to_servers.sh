#!/opt/homebrew/bin/bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Setup & Globals
# ────────────────────────────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/utils.sh"

SCRIPT_FOLDER="check_ram_cpu_disk_usage"
#SCRIPT_FOLDER="${1:-ssh_injection}"
#./main.sh check_ram_cpu_disk_usage

SERVER_JSON="$ROOT_DIR/servers.json"
FAILED=()
REPORT_FILE=""


# ────────────────────────────────────────────────────────────────
# Handler for RAM/CPU/Disk usage summary + email
# ────────────────────────────────────────────────────────────────

handle_ssh_injection() {
  echo "📂 Running SSH injection using server IPs to obtain IDs"

  if [[ ! -f "$SERVER_JSON" ]]; then
    echo "⚠️  $SERVER_JSON not found. Running fetch_all_runcloud_servers..."
    fetch_all_runcloud_servers

    if [[ ! -f "$SERVER_JSON" ]]; then
      echo "❌ Failed to generate $SERVER_JSON. Aborting."
      exit 1
    fi
  fi
}

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

# Ensure servers.json file exists
if [[ ! -f "$SERVER_JSON" ]]; then
  create_servers_json_file
fi

# Check if it's empty (valid but has no servers)
if [[ $(jq 'length' "$SERVER_JSON") -eq 0 ]]; then
  fetch_vultr_servers
fi

get_all_servers_from_file

#if [[ "$SCRIPT_FOLDER" == "ssh_injection" ]]; then
#  handle_ssh_injection
#fi
#
if [[ "$SCRIPT_FOLDER" == "check_ram_cpu_disk_usage" ]]; then
  handle_check_usage
fi
handle_default_script
print_summary