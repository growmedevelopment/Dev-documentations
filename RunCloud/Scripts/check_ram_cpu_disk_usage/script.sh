#!/opt/homebrew/bin/bash
set -euo pipefail

parse_args() {
  if [[ $# -lt 1 ]]; then
    echo "❌ Usage: $0 <SERVER_IP>"
    exit 1
  fi
  SERVER_IP="$1"
}

detect_timeout_cmd() {
  if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout"
  elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout"
  else
    echo "❌ 'timeout' or 'gtimeout' is required but not installed."
    exit 1
  fi
}

fetch_metrics() {
  echo "🔍 Checking server: $SERVER_IP..."
  result=$($TIMEOUT_CMD 30s ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$SERVER_IP" 'bash -s' <<'EOF'
    export PATH=/usr/sbin:/usr/bin:/bin:/sbin
    IP=$(hostname -I | awk '{print $1}')

    DF_OUT=$(df -k / | awk 'NR==2')
    DF_TOTAL_KB=$(echo "$DF_OUT" | awk '{print $2}')
    DF_USED_KB=$(echo "$DF_OUT" | awk '{print $3}')
    TOTAL_GB=$(awk -v kb="$DF_TOTAL_KB" 'BEGIN { printf "%.1f", kb/1024/1024 }')
    USED_GB=$(awk -v kb="$DF_USED_KB" 'BEGIN { printf "%.1f", kb/1024/1024 }')

    ROOT_DEV=$(echo "$DF_OUT" | awk '{print $1}')
    DEV_PATH="$ROOT_DEV"
    [[ ! "$ROOT_DEV" =~ ^/dev/ ]] && DEV_PATH="/dev/$ROOT_DEV"
    PART_BYTES=$(lsblk -nbdo SIZE "$DEV_PATH" 2>/dev/null)
    DISK_DEV=$(lsblk -ndo NAME,TYPE | awk '$2 == "disk" {print $1; exit}')
    DISK_BYTES=$(lsblk -nbdo SIZE "/dev/$DISK_DEV" 2>/dev/null)
    UNALLOC_GB=$(awk -v d="$DISK_BYTES" -v p="$PART_BYTES" 'BEGIN { printf "%.1f", (d-p)/1024/1024/1024 }')

    MEM_USED=$(free -m | awk '/Mem:/ { print $3 }')
    MEM_TOTAL=$(free -m | awk '/Mem:/ { print $2 }')
    MEM_PERCENT=$(awk -v u="$MEM_USED" -v t="$MEM_TOTAL" 'BEGIN { printf "%.0f", (u/t)*100 }')

    CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | awk -F. '{print $1}')

    echo "$IP;$TOTAL_GB;$USED_GB;$UNALLOC_GB;$MEM_PERCENT;$CPU_LOAD"
EOF
  )
}

append_summary() {
  IFS=';' read -r ip total used unalloc ram cpu <<<"$result"

  used_pct=$(awk -v u="$used" -v t="$total" 'BEGIN { printf "%.0f", (u/t)*100 }')
  [[ $used_pct -ge 90 ]] && used_colored="🟥 ${used} GB (${used_pct}%)" ||
  [[ $used_pct -ge 60 ]] && used_colored="🟧 ${used} GB (${used_pct}%)" ||
  used_colored="🟩 ${used} GB (${used_pct}%)"

  [[ $ram -ge 90 ]] && ram_colored="🟥 ${ram}%" ||
  [[ $ram -ge 60 ]] && ram_colored="🟧 ${ram}%" ||
  ram_colored="🟩 ${ram}%"

  [[ $cpu -ge 90 ]] && cpu_colored="🟥 ${cpu}%" ||
  [[ $cpu -ge 60 ]] && cpu_colored="🟧 ${cpu}%" ||
  cpu_colored="🟩 ${cpu}%"

  echo "<tr>
    <td><a href=\"http://$ip\">$ip</a></td>
    <td>${total} GB</td>
    <td>$used_colored</td>
    <td>${unalloc} GB</td>
    <td>$ram_colored</td>
    <td>$cpu_colored</td>
  </tr>" >> "${REPORT_FILE:-/tmp/server_heals_report.html}"

  # Check for critical issues
    error_message="❗ $ip -"
    has_error=false

    if [[ $used_pct -ge 90 ]]; then
      error_message+=" High Disk: ${used_pct}%"
      has_error=true
    fi
    if [[ $ram -ge 90 ]]; then
      error_message+=" High RAM: ${ram}%"
      has_error=true
    fi
    if [[ $cpu -ge 90 ]]; then
      error_message+=" High CPU: ${cpu}%"
      has_error=true
    fi

    if [[ "$has_error" == true ]]; then
      ERROR_SUMMARY+=("$error_message")
    fi
}

main() {
  parse_args "$@"
  detect_timeout_cmd
  fetch_metrics
  append_summary
}

main "$@"