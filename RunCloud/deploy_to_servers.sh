#!/opt/homebrew/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/utils.sh"

SCRIPT_FOLDER="ssh_injection"

load_env
detect_timeout_cmd

#fetch_vultr_servers

get_all_servers_from_file


get_valid_id_by_ip() {
  local ip="$1"
  local fresh_file="$ROOT_DIR/servers_runcloud_fresh.json"
  declare -a temp_entries=()

  # Check existing cache
  if [[ -f "$fresh_file" ]]; then
    id=$(jq -r --arg ip "$ip" '.[] | select(.ipAddress==$ip).id' "$fresh_file" | head -n1 || true)
    [[ -n "$id" && "$id" != "0" ]] && { echo "$id"; return 0; }
  fi

  echo "🔄 Fetching server list from RunCloud (paginated, 40 per page)..."
  local page=1

  while true; do
    echo "📦 Requesting page $page..."
    response=$(curl -sS -X GET \
      "https://manage.runcloud.io/api/v3/servers?page=$page&perPage=40" \
      -H "Authorization: Bearer $RUNCLOUD_API_TOKEN" \
      -H "Accept: application/json")

    entries=$(echo "$response" | jq -c '.data[]' 2>/dev/null || true)
    [[ -z "$entries" ]] && break

    while IFS= read -r entry; do
      temp_entries+=("$entry")
    done <<< "$entries"

    # If fewer than 40 items, no more pages
    count=$(echo "$entries" | wc -l)
    (( count < 40 )) && break

    ((page++))
  done

  if [[ ${#temp_entries[@]} -eq 0 ]]; then
    echo "❌ No data returned from RunCloud API"
    return 1
  fi

  jq -n --argjson arr "$(printf '%s\n' "${temp_entries[@]}" | jq -s '.')" '$arr' > "$fresh_file"
  echo "📥 Cached ${#temp_entries[@]} server entries to $fresh_file"

  id=$(jq -r --arg ip "$ip" '.[] | select(.ipAddress==$ip).id' "$fresh_file" | head -n1 || true)
  [[ -n "$id" && "$id" != "0" ]] && { echo "$id"; return 0; }

  echo "❌ No match for IP $ip after fetching"
  return 1
}

FAILED=()

if [[ "$SCRIPT_FOLDER" == "ssh_injection" ]]; then
  echo "📂 Running SSH injection using server IPs to obtain IDs"
  FAILED=()

  # Fetch all servers from RunCloud and cache them
  fetch_all_runcloud_servers

  # Iterate over IPs from servers.json
  mapfile -t IP_LIST < <(jq -r '.[].ipAddress' "$ROOT_DIR/servers.json")

  for ip in "${IP_LIST[@]}"; do
    name=$(jq -r --arg ip "$ip" '.[] | select(.ipAddress==$ip) | .name' "$ROOT_DIR/servers.json")
    id=$(jq -r --arg ip "$ip" '.[] | select(.ipAddress==$ip) | .id' "$ROOT_DIR/servers.json")

    if [[ -z "$id" || "$id" == "0" ]]; then
      echo "🔍 No valid ID for $ip — resolving from fresh RunCloud cache..."
      id=$(jq -r --arg ip "$ip" '.[] | select(.ipAddress==$ip) | .id' "$ROOT_DIR/servers_runcloud_fresh.json" | head -n1 || true)

      if [[ -z "$id" || "$id" == "0" ]]; then
        echo "⚠️ Skipping $name ($ip): no valid ID found"
        echo "--------------------------------------------------------"
        continue
      fi
    else
      echo "🔐 Using cached ID: $id (Name: $name, IP: $ip)"
    fi

    echo "🔐 Injecting SSH to server ID: $id (Name: $name, IP: $ip)"

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