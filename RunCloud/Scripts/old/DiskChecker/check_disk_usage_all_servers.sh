#!/opt/homebrew/bin/bash

### ───────────────────────────────────────────────
### 🔐 Load .env and Validate Variables
### ───────────────────────────────────────────────
load_env() {
  ENV_FILE="$(dirname "$0")/../../.env"
  if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
  else
    echo "❌ .env file not found at $ENV_FILE"
    exit 1
  fi

  if [[ -z "$VULTURE_API_TOKEN" || -z "$NOTIFY_EMAIL" ]]; then
    echo "❌ Required .env variables (VULTURE_API_TOKEN, NOTIFY_EMAIL) not set"
    exit 1
  fi
}

### ───────────────────────────────────────────────
### ⏱️ Setup Timeout Utility
### ───────────────────────────────────────────────
detect_timeout_cmd() {
  if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout"
  elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout"
  else
    echo "❌ Neither 'timeout' nor 'gtimeout' found."
    exit 1
  fi
}

### ───────────────────────────────────────────────
### 🌐 Fetch All Servers from Vultr
### ───────────────────────────────────────────────
fetch_all_servers() {
  echo "📡 Fetching servers from Vultr..."
  TMPFILE=$(mktemp)
  page=1

  while true; do
    response=$(curl -s -H "Authorization: Bearer $VULTURE_API_TOKEN" \
      "https://api.vultr.com/v2/instances?page=$page&per_page=500")

    if echo "$response" | jq -e '.instances | type == "array"' >/dev/null; then
      echo "$response" | jq -c '.instances[]' >>"$TMPFILE"
    else
      echo "❌ API Error on page $page:"
      echo "$response"
      exit 1
    fi

    next=$(echo "$response" | jq -r '.meta.links.next // empty')
    [[ -z "$next" || "$next" == "null" ]] && break
    ((page++))
    sleep 0.05
  done

  mapfile -t SERVERS <"$TMPFILE"
  rm "$TMPFILE"
  TOTAL_SERVERS="${#SERVERS[@]}"
}

### ───────────────────────────────────────────────
### 🧾 Prepare HTML Report
### ───────────────────────────────────────────────
start_html_report() {
  HTML_REPORT_FILE="/tmp/server_report_$(date +%Y%m%d_%H%M%S).html"
  FAILED_SERVERS_LOG_FILE=$(mktemp)
  cat <<EOF >"$HTML_REPORT_FILE"
<html><head><style>
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ddd; padding: 8px; }
tr:nth-child(even) { background-color: #f2f2f2; }
.red { background-color: #fdd; }
th:first-child, td:first-child { max-width: 50px; width: 50px; word-break: break-word; }
</style></head><body><h2>Server Resource Summary</h2><table>
<tr><th>#</th><th>Name</th><th>IP</th><th>Total Disk</th><th>Used Disk</th><th>Unallocated</th><th>RAM Used</th><th>CPU (%)</th></tr>
EOF
}

### ───────────────────────────────────────────────
### 📡 Server SSH Check
### ───────────────────────────────────────────────
check_server() {
  local name="$1" ip="$2" count="$3"

  printf "\n[%3d/%3d] 🔗 %s (%s)\n" "$count" "$TOTAL_SERVERS" "$name" "$ip"

  result=$($TIMEOUT_CMD 30s ssh -o BatchMode=yes -o ConnectTimeout=10 root@"$ip" 'bash -s' <<'EOF'
    export PATH=/usr/sbin:/usr/bin:/bin:/sbin
    IP=$(hostname -I | awk '{print $1}')
    [[ -z "$IP" ]] && echo "N/A;N/A;N/A;N/A;N/A;N/A" && exit

    # Disk
    DF_OUT=$(df -k / | awk 'NR==2')
    DF_TOTAL_KB=$(echo "$DF_OUT" | awk '{print $2}')
    DF_USED_KB=$(echo "$DF_OUT" | awk '{print $3}')
    TOTAL_GB=$(awk -v kb="$DF_TOTAL_KB" 'BEGIN { printf "%.1f", kb/1024/1024 }')
    USED_GB=$(awk -v kb="$DF_USED_KB" 'BEGIN { printf "%.1f", kb/1024/1024 }')

    # Unallocated
    ROOT_DEV=$(echo "$DF_OUT" | awk '{print $1}')
    DEV_PATH="$ROOT_DEV"
    [[ ! "$ROOT_DEV" =~ ^/dev/ ]] && DEV_PATH="/dev/$ROOT_DEV"
    PART_BYTES=$(lsblk -nbdo SIZE "$DEV_PATH" 2>/dev/null)
    DISK_DEV=$(lsblk -ndo NAME,TYPE | awk '$2 == "disk" {print $1; exit}')
    DISK_BYTES=$(lsblk -nbdo SIZE "/dev/$DISK_DEV" 2>/dev/null)
    UNALLOC_GB=$(awk -v d="$DISK_BYTES" -v p="$PART_BYTES" 'BEGIN { printf "%.1f", (d-p)/1024/1024/1024 }')

    # RAM
    MEM_USED=$(free -m | awk '/Mem:/ { print $3 }')
    MEM_TOTAL=$(free -m | awk '/Mem:/ { print $2 }')
    MEM_PERCENT=$(awk -v u="$MEM_USED" -v t="$MEM_TOTAL" 'BEGIN { printf "%.0f", (u/t)*100 }')

    # CPU
    CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | awk -F. '{print $1}')

    echo "$IP;$TOTAL_GB;$USED_GB;$UNALLOC_GB;$MEM_PERCENT;$CPU_LOAD"
EOF
  )

  IFS=';' read -r internal_ip total_disk used_disk unallocated mem_percent cpu_percent <<<"$result"

  if [[ "$internal_ip" == "N/A" || -z "$internal_ip" ]]; then
    echo "❌ $name: SSH failed or info missing"
    echo "<tr class=\"red\"><td>$count</td><td>$name</td><td>$ip</td><td colspan=5>SSH failed</td></tr>" >>"$HTML_REPORT_FILE"
    echo -e "$name\t$ip\tSSH failed" >>"$FAILED_SERVERS_LOG_FILE"
  else

    # Disk usage percent
    used_percent=$(awk -v u="$used_disk" -v t="$total_disk" 'BEGIN { if (t > 0) printf "%.0f", (u/t)*100 }')

    # Disk color
    if [[ "$used_percent" -ge 90 ]]; then
      disk_color="<span style='color:red;'>${used_disk} GB (${used_percent}%)</span>"
    elif [[ "$used_percent" -ge 60 ]]; then
      disk_color="<span style='color:orange;'>${used_disk} GB (${used_percent}%)</span>"
    else
      disk_color="<span style='color:green;'>${used_disk} GB (${used_percent}%)</span>"
    fi

    # RAM color
    if [[ "$mem_percent" -ge 90 ]]; then
      mem_color="<span style='color:red;'>${mem_percent}%</span>"
    elif [[ "$mem_percent" -ge 60 ]]; then
      mem_color="<span style='color:orange;'>${mem_percent}%</span>"
    else
      mem_color="<span style='color:green;'>${mem_percent}%</span>"
    fi

    # CPU color
    if [[ "$cpu_percent" -ge 90 ]]; then
      cpu_color="<span style='color:red;'>${cpu_percent}%</span>"
    elif [[ "$cpu_percent" -ge 60 ]]; then
      cpu_color="<span style='color:orange;'>${cpu_percent}%</span>"
    else
      cpu_color="<span style='color:green;'>${cpu_percent}%</span>"
    fi

    echo "<tr><td>$count</td><td>$name</td><td>$internal_ip</td><td>${total_disk} GB</td><td>$disk_color</td><td>${unallocated} GB</td><td>$mem_color</td><td>$cpu_color</td></tr>" >>"$HTML_REPORT_FILE"
  fi
}

### ───────────────────────────────────────────────
### 📧 Send HTML Report
### ───────────────────────────────────────────────
send_report() {
  echo "</table>" >>"$HTML_REPORT_FILE"

  if [ -s "$FAILED_SERVERS_LOG_FILE" ]; then
    echo "<h3>❗ Failed Servers</h3><table><tr><th>Server</th><th>IP</th><th>Error</th></tr>" >>"$HTML_REPORT_FILE"
    while IFS=$'\t' read -r fail_name fail_ip fail_msg; do
      echo "<tr><td>$fail_name</td><td>$fail_ip</td><td>$fail_msg</td></tr>" >>"$HTML_REPORT_FILE"
    done <"$FAILED_SERVERS_LOG_FILE"
    echo "</table>" >>"$HTML_REPORT_FILE"
  fi

  echo "</body></html>" >>"$HTML_REPORT_FILE"

  (
    echo "To: $NOTIFY_EMAIL"
    echo "Subject: Server Resource Summary"
    echo "Content-Type: text/html; charset=UTF-8"
    echo ""
    cat "$HTML_REPORT_FILE"
  ) | msmtp "$NOTIFY_EMAIL"
}

### ───────────────────────────────────────────────
### 🚀 Main Script Logic
### ───────────────────────────────────────────────
main() {
  load_env
  detect_timeout_cmd
  fetch_all_servers
  start_html_report

  MAX_JOBS=10
  count=0
  for server in "${SERVERS[@]}"; do
    ((count++))
    name=$(echo "$server" | jq -r '.label')
    ip=$(echo "$server" | jq -r '.main_ip')
    check_server "$name" "$ip" "$count" &

    while (( $(jobs -r | wc -l) >= MAX_JOBS )); do
      sleep 0.2
    done
  done

  wait
  send_report
  echo "✅ Done."
}

main