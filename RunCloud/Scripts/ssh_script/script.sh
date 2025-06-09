#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/utils.sh"

detect_timeout_cmd

#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/utils.sh"

detect_timeout_cmd

#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/utils.sh"

detect_timeout_cmd

check_ssh_access_from_list() {
  local SERVER_FILE="$ROOT_DIR/servers.list"
  if [[ ! -f "$SERVER_FILE" ]]; then
    echo "❌ servers.list not found at $SERVER_FILE"
    exit 1
  fi

  echo "📥 Reading server list from $SERVER_FILE"

  local TOTAL=0
  local -a IP_LIST=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^\s*# ]] && continue
    [[ -z "$line" ]] && continue
    IP_LIST+=("$line")
    ((TOTAL++))
  done < "$SERVER_FILE"

  if [[ "$TOTAL" -eq 0 ]]; then
    echo "⚠️ No IPs loaded from servers.list — check formatting or empty file."
    exit 1
  fi

  echo "🚀 Checking SSH access to $TOTAL servers..."
  printf "\n%-10s %-16s %-10s\n" "#/Total" "IP ADDRESS" "SSH"

  local index=0
  local -a SSH_FAILED_LIST=()

  for ip in "${IP_LIST[@]}"; do
    ((index++))

    ssh_status="❌"
    if $TIMEOUT_CMD 5s ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no "root@$ip" "echo ok" &>/dev/null; then
      ssh_status="✅"
    else
      SSH_FAILED_LIST+=("$ip")
    fi

    printf "[%3d/%3d] %-16s %-10s\n" "$index" "$TOTAL" "$ip" "$ssh_status"
  done

  echo -e "\n📋 SSH Access Summary:"
  if [[ "${#SSH_FAILED_LIST[@]}" -eq 0 ]]; then
    echo "✅ SSH access succeeded on all $TOTAL servers."
  else
    echo "❌ SSH failed on ${#SSH_FAILED_LIST[@]} server(s):"
    for ip in "${SSH_FAILED_LIST[@]}"; do
      echo " - $ip"
    done
  fi
}

check_ssh_access_from_list
