#!/opt/homebrew/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/utils.sh"

SCRIPT_FOLDER="ssh_injection"

load_env
detect_timeout_cmd

#fetch_vultr_servers
# fetch_runcloud_servers
get_all_servers_from_file

FAILED=()

if [[ "$SCRIPT_FOLDER" == "ssh_injection" ]]; then
  echo "📂 Running SSH injection using server IDs"

  jq -c '.[]' "$ROOT_DIR/servers.json" | while IFS= read -r server; do
    id=$(echo "$server" | jq -r '.id')
    ip=$(echo "$server" | jq -r '.ipAddress')
    name=$(echo "$server" | jq -r '.name')

    if [[ "$id" == "0" ]]; then
      echo "❌ Skipping server: invalid ID '0' (Name: $name, IP: $ip)"
      echo "--------------------------------------------------------"
      continue
    fi

    echo "🔐 Checking server ID: $id (Name: $name, IP: $ip)"

    if run_script "$SCRIPT_FOLDER" "$id"; then
      echo "✅ Success for $id"
    else
      echo "❌ Failed for $id"
      FAILED+=("$id")
    fi

    echo "--------------------------------------------------------"
  done

else
  echo "📂 Running $SCRIPT_FOLDER using server IPs"

  if [[ "$SCRIPT_FOLDER" == "check_ram_cpu_disk_usage" ]]; then
    export REPORT_FILE="/tmp/server_usage_report_$(date +%Y%m%d_%H%M%S).html"

    cat <<EOF > "$REPORT_FILE"
<html><head>
 <style>
   body { font-family: sans-serif; }
   table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
   th, td { border: 1px solid #ccc; padding: 8px; text-align: center; }
   th { background-color: #f4f4f4; }
   td a { color: #0366d6; text-decoration: none; }
 </style>
</head><body>
<h2>📊 RAM / CPU / Disk Usage Summary</h2>
<p>Generated: $(date)</p>
<table>
 <tr>
   <th>IP Address</th>
   <th>Total Disk</th>
   <th>Used Disk</th>
   <th>Unallocated</th>
   <th>RAM Usage</th>
   <th>CPU Usage</th>
 </tr>
EOF
  fi

  for i in "${!SERVER_LIST[@]}"; do
    server_ip="${SERVER_LIST[$i]}"
    echo "[$((i + 1))/${#SERVER_LIST[@]}] → $server_ip"

    if run_script "$SCRIPT_FOLDER" "$server_ip"; then
      echo "✅ Success for $server_ip"
    else
      echo "❌ Failed for $server_ip"
      FAILED+=("$server_ip")
    fi

    echo "--------------------------------------------------------"
  done

  if [[ "$SCRIPT_FOLDER" == "check_ram_cpu_disk_usage" && -f "$REPORT_FILE" ]]; then
    echo "</table></body></html>" >> "$REPORT_FILE"

    (
      echo "To: $NOTIFY_EMAIL"
      echo "Subject: Server Usage Report - $(date)"
      echo "Content-Type: text/html; charset=UTF-8"
      echo ""
      cat "$REPORT_FILE"
    ) | msmtp "$NOTIFY_EMAIL"

    echo "📧 HTML report sent to $NOTIFY_EMAIL"
  fi
fi

# Shared summary
echo -e "\n📋 Summary:"
if [[ "${#FAILED[@]}" -eq 0 ]]; then
  echo "✅ All servers completed successfully."
else
  echo "❌ Failed on:"
  printf ' - %s\n' "${FAILED[@]}"
fi