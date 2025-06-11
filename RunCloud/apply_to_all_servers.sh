#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/utils.sh"

SCRIPT_NAME="ssh_script"  # Change as needed

[[ -z "$SCRIPT_NAME" ]] && {
  echo -e "❌ Script name missing.\nUsage: ./deploy_to_servers.sh ssh_script"
  exit 1
}

load_env
detect_timeout_cmd
fetch_all_servers
#get_all_servers_from_file

#FAILED=()
#for i in "${!SERVER_LIST[@]}"; do
#  server="${SERVER_LIST[$i]}"
#  echo "[$((i + 1))/${#SERVER_LIST[@]}] → $server"
#
#  if run_script "$SCRIPT_NAME" "$server"; then
#    echo "✅ Success for $server"
#  else
#    echo "❌ Failed for $server"
#    FAILED+=("$server")
#  fi
#done
#
#echo -e "\n📋 Summary:"
#((${#FAILED[@]} == 0)) && echo "✅ All servers completed successfully." || {
#  echo "❌ Failed on:"
#  printf ' - %s\n' "${FAILED[@]}"
#}