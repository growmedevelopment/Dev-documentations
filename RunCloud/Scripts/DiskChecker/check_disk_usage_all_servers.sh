#!/opt/homebrew/bin/bash

# Load API key from .env
ENV_FILE="$(dirname "$0")/../../.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "❌ .env file not found at $ENV_FILE"
  exit 1
fi

# Timeout setup
if command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout"
else
  echo "❌ Neither timeout nor gtimeout found."
  exit 1
fi

TMPFILE=$(mktemp)
FAILED_SERVERS_LOG_FILE=$(mktemp)
page=1
echo "📡 Fetching servers..."

# Fetch all servers
while true; do
  response=$(curl -s -H "Authorization: Bearer $API_KEY" \
                  "https://manage.runcloud.io/api/v3/servers?page=$page")

  echo "$response" | jq -e '.data | type == "array"' >/dev/null || break
  echo "$response" | jq -c '.data[]' >> "$TMPFILE"

  next=$(echo "$response" | jq -r '.meta.pagination.links.next // empty')
  [[ -z "$next" || "$next" == "null" ]] && break
  ((page++))
done

echo "🚀 Connecting to servers..."

TOTAL_SERVERS=$(wc -l < "$TMPFILE")
# Read servers into an array
mapfile -t SERVERS < "$TMPFILE"
MAX_JOBS=10
count=0

### Prepare for HTML report generation
# HTML report file
HTML_REPORT_FILE="/tmp/server_report_$(date +%Y%m%d_%H%M%S).html"
# Start HTML report file with header and style
echo "<html><head><style>
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ddd; padding: 8px; }
tr:nth-child(even) { background-color: #f2f2f2; }
.red { background-color: #fdd; }
th:first-child, td:first-child { max-width: 50px; width: 50px; word-break: break-word; }
</style></head><body><h2>Server Storage Summary</h2><table>
<tr><th>#</th><th>Name</th><th>IP</th><th>Total (GB)</th><th>Used (GB)</th><th>Unallocated (GB)</th></tr>" > "$HTML_REPORT_FILE"

check_server() {
  local name="$1"
  local ip="$2"
  local count="$3"

  printf "\n[%3d/%3d] 🔗 %s (%s)\n" "$count" "$TOTAL_SERVERS" "$name" "$ip"

  result=$($TIMEOUT_CMD 30s ssh -o BatchMode=yes -o ConnectTimeout=10 root@"$ip" 'bash -s' <<'EOF'
    export PATH=/usr/sbin:/usr/bin:/bin:/sbin

    IP=$(hostname -I | awk '{print $1}')
    [[ -z "$IP" ]] && echo "N/A;N/A;N/A;N/A" && exit

    DF_OUT=$(df -k / | awk 'NR==2')
    DF_TOTAL_KB=$(echo "$DF_OUT" | awk '{print $2}')
    DF_USED_KB=$(echo "$DF_OUT" | awk '{print $3}')

    TOTAL_GB=$(awk -v kb="$DF_TOTAL_KB" 'BEGIN { printf "%.1f", kb/1024/1024 }')
    USED_GB=$(awk -v kb="$DF_USED_KB" 'BEGIN { printf "%.1f", kb/1024/1024 }')

    ROOT_DEV=$(echo "$DF_OUT" | awk '{print $1}')
    DEV_PATH="$ROOT_DEV"
    [[ ! "$ROOT_DEV" =~ ^/dev/ ]] && DEV_PATH="/dev/$ROOT_DEV"
    [[ ! -b "$DEV_PATH" ]] && echo "$IP;$TOTAL_GB;$USED_GB;N/A" && exit

    PART_BYTES=$(lsblk -nbdo SIZE "$DEV_PATH" 2>/dev/null)
    DISK_DEV=$(lsblk -ndo NAME,TYPE | awk '$2 == "disk" {print $1; exit}')
    [[ -z "$DISK_DEV" ]] && echo "$IP;$TOTAL_GB;$USED_GB;N/A" && exit
    DISK_BYTES=$(lsblk -nbdo SIZE "/dev/$DISK_DEV" 2>/dev/null)

    [[ -z "$DISK_BYTES" || -z "$PART_BYTES" ]] && echo "$IP;$TOTAL_GB;$USED_GB;N/A" && exit

    UNALLOC_GB=$(awk -v d="$DISK_BYTES" -v p="$PART_BYTES" 'BEGIN {
      diff=(d-p)/1024/1024/1024;
      printf "%.1f", (diff > 0) ? diff : 0;
    }')

    echo "$IP;$TOTAL_GB;$USED_GB;$UNALLOC_GB"
EOF
  )

  IFS=';' read -r internal_ip total_disk used_disk unallocated <<< "$result"

  if [[ "$internal_ip" == "N/A" || -z "$internal_ip" ]]; then
    echo "❌ $name: SSH failed or IP missing"
    # Append a row for failed connection with red background and N/A for all
    echo "<tr class=\"red\"><td>$count</td><td>$name</td><td>$ip</td><td>N/A</td><td>N/A</td><td>N/A</td></tr>" >> "$HTML_REPORT_FILE"
    echo -e "$name\t$ip\tSSH or disk info command failed" >> "$FAILED_SERVERS_LOG_FILE"
  else
    # Calculate used percent and colorize
    used_percent="N/A"
    used_color="N/A"
    if [[ "$total_disk" =~ ^[0-9.]+$ && "$used_disk" =~ ^[0-9.]+$ && $(awk "BEGIN {print ($total_disk > 0)?1:0}") -eq 1 ]]; then
      used_percent=$(awk -v used="$used_disk" -v total="$total_disk" 'BEGIN { printf "%.0f", (used/total)*100 }')
      if [[ "$used_percent" -ge 90 ]]; then
        used_color="<span style='color:red;'>$used_percent%</span>"
      elif [[ "$used_percent" -ge 60 ]]; then
        used_color="<span style='color:orange;'>$used_percent%</span>"
      else
        used_color="<span style='color:green;'>$used_percent%</span>"
      fi
    else
      used_color="N/A"
    fi
    echo "✅ $name: IP: $internal_ip, Total: $total_disk GB, Used: $used_disk GB, Unallocated: $unallocated GB"
    # Highlight row if unallocated space is present and greater than 1
    row_class=""
    if [[ "$unallocated" =~ ^[0-9]+(\.[0-9]+)?$ && $(awk "BEGIN {print ($unallocated > 1) ? 1 : 0}") -eq 1 ]]; then
      row_class=" style='background-color: #ffd6d6;'"
    fi
    echo "<tr${row_class}><td>$count</td><td>$name</td><td>$internal_ip</td><td>$total_disk</td><td>Used: $used_color</td><td>$unallocated</td></tr>" >> "$HTML_REPORT_FILE"
  fi
}

## Launch background jobs safely, append HTML rows in loop
for server in "${SERVERS[@]}"; do
  ((count++))
  name=$(echo "$server" | jq -r '.name')
  ip=$(echo "$server" | jq -r '.ipAddress // .ip_address')

  check_server "$name" "$ip" "$count" &

  while (( $(jobs -r | wc -l) >= MAX_JOBS )); do
    sleep 0.2
  done
done

wait
rm "$TMPFILE"

# Append failed servers summary to HTML report if any
if [ -s "$FAILED_SERVERS_LOG_FILE" ]; then
  {
    echo "<h3 style='color:red;'>⚠️ Failed Connections or Disk Info Retrieval</h3>"
    echo "<table><tr><th>Server</th><th>IP</th><th>Error</th></tr>"
    while IFS=$'\t' read -r fail_name fail_ip fail_msg; do
      echo "<tr><td>$fail_name</td><td>$fail_ip</td><td><pre>$fail_msg</pre></td></tr>"
    done < "$FAILED_SERVERS_LOG_FILE"
    echo "</table>"
  } >> "$HTML_REPORT_FILE"
fi

# Close the HTML
echo "</table></body></html>" >> "$HTML_REPORT_FILE"

# Send the HTML via email using sendmail (not mail -a, for better compatibility)
(
  echo "To: $NOTIFY_EMAIL"
  echo "Subject: Server Storage Summary"
  echo "Content-Type: text/html; charset=UTF-8"
  echo ""
  cat "$HTML_REPORT_FILE"
) | msmtp "$NOTIFY_EMAIL"

echo "✅ Done."