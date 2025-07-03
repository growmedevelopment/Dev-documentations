#!/opt/homebrew/bin/bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Setup & Globals
# ────────────────────────────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/utils.sh"

# ────────────────────────────────────────────────────────────────
# CLI Argument Parser
# ────────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
  echo "❗ Usage: $0 <script_folder>"
  echo "   Example: $0 set_making_backup"
  echo "   Run '$0 --help' for more information."
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo "📖 Usage: $0 <script_folder>"
  echo ""
  echo "Run any script folder across all servers defined in servers.json."
  echo ""
  echo "Examples:"
  echo "  $0 set_making_backup"
  echo "  $0 check_ram_cpu_disk_usage"
  echo "  $0 ssh_injection"
  echo "  $0 ssh_checks"
  echo "  $0 remove_old_backups"
  echo "  $0 remove_cron_user"
  exit 0
fi

SCRIPT_FOLDER="$1"

SERVER_JSON="$ROOT_DIR/servers.json"
FAILED=()
REPORT_FILE=""

# ────────────────────────────────────────────────────────────────
# Handler for RAM/CPU/Disk usage summary + email
# ────────────────────────────────────────────────────────────────
ERROR_SUMMARY=()
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
  runcloud_data=$(fetch_all_runcloud_servers)
  save_servers_to_file "$runcloud_data"
else
  # Only fetch if file doesn't exist or is empty
  if [[ ! -f "$SERVER_JSON" || $(jq 'length' "$SERVER_JSON") -eq 0 ]]; then
    create_or_clear_servers_json_file
    vultr_data=$(fetch_all_vultr_servers)
    save_servers_to_file "$vultr_data"
  fi
fi

get_all_servers_from_file

if [[ "$SCRIPT_FOLDER" == "check_ram_cpu_disk_usage" ]]; then
  handle_check_usage
else
  handle_default_script
fi

print_summary