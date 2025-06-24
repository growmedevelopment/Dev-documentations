#!/bin/bash

# Get project root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

### 🔐 Load .env
load_env() {
  ENV_FILE="$ROOT_DIR/.env"
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
  else
    echo "❌ .env file not found at $ENV_FILE"
    exit 1
  fi

  if [[ -z "${VULTR_API_TOKEN:-}" || -z "${NOTIFY_EMAIL:-}" ]]; then
    echo "❌ Required vars (VULTR_API_TOKEN, NOTIFY_EMAIL) not set"
    exit 1
  fi
}

### ⏱️ Detect Timeout Command
detect_timeout_cmd() {
  if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout"
  elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout"
  else
    echo "❌ timeout/gtimeout not found"
    exit 1
  fi
}

fetch_vultr_servers() {
  echo "📡 Fetching from Vultr API..."
  local JSON_FILE="$ROOT_DIR/servers.json"
  local page=1
  > "$JSON_FILE"
  echo "[" > "$JSON_FILE"
  local first=true

  while true; do
    response=$(curl -s -H "Authorization: Bearer $VULTR_API_TOKEN" \
      "https://api.vultr.com/v2/instances?page=$page&per_page=500")

    if echo "$response" | jq -e '.instances | type == "array"' >/dev/null; then
      local count
      count=$(echo "$response" | jq '.instances | length')
      echo "📦 Page $page: $count instances"

      entries=$(echo "$response" | jq -c '.instances[] | {id: 0, name: .label, ipAddress: .main_ip}')
      while read -r entry; do
        if [[ "$first" == true ]]; then
          echo "$entry" >> "$JSON_FILE"
          first=false
        else
          echo ",$entry" >> "$JSON_FILE"
        fi
      done <<< "$entries"
    else
      echo "❌ API error on page $page"
      echo "$response"
      echo "]" >> "$JSON_FILE"
      return 1
    fi

    next=$(echo "$response" | jq -r '.meta.links.next // empty')
    [[ -z "$next" || "$next" == "null" ]] && break
    ((page++))
    sleep 0.05
  done

  echo "]" >> "$JSON_FILE"
  echo "📄 Server data saved to $JSON_FILE"
}

### 📡 Fetch minimal server info from RunCloud and save to servers.json
fetch_all_runcloud_servers() {
  local output_file="$ROOT_DIR/servers.json"
  declare -a temp_entries=()
  local page=1

  echo "🔄 Fetching server list from RunCloud (paginated, 40 per page)..."

  while true; do
    echo "📦 Requesting page $page..."

    response=$(curl -sS -X GET \
      "https://manage.runcloud.io/api/v3/servers?page=$page&perPage=40" \
      -H "Authorization: Bearer $RUNCLOUD_API_TOKEN" \
      -H "Accept: application/json")

    entries=$(echo "$response" | jq -c '.data[] | {id, name, ipAddress}' 2>/dev/null || true)
    [[ -z "$entries" ]] && break

    while IFS= read -r entry; do
      temp_entries+=("$entry")
    done <<< "$entries"

    count=$(echo "$entries" | wc -l)
    (( count < 40 )) && break

    ((page++))
  done

  if [[ ${#temp_entries[@]} -eq 0 ]]; then
    echo "❌ No simplified server data returned from RunCloud API"
    return 1
  fi

  jq -n --argjson arr "$(printf '%s\n' "${temp_entries[@]}" | jq -s '.')" '$arr' > "$output_file"
  echo "📥 Wrote ${#temp_entries[@]} simplified server entries to $output_file"
}

### 🧠 Load Static IPs
get_all_servers_from_file() {
  local JSON_FILE="$ROOT_DIR/servers.json"
  SERVER_LIST=()

  if [[ ! -f "$JSON_FILE" ]]; then
    echo "📁 Creating missing $JSON_FILE..."
    mkdir -p "$(dirname "$JSON_FILE")"
    echo "[]" > "$JSON_FILE"
  fi

  echo "📄 Loading server IPs from $JSON_FILE..."
  mapfile -t SERVER_LIST < <(jq -r '.[].ipAddress' "$JSON_FILE")

  echo "📦 Loaded ${#SERVER_LIST[@]} servers from file"
}

run_script() {
  local SCRIPT_NAME="$1"
  shift
  local SCRIPT_PATH="$ROOT_DIR/Scripts/$SCRIPT_NAME/script.sh"

  if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "❌ Script '$SCRIPT_NAME' not found at $SCRIPT_PATH"
    return 1
  fi

  # Log the call (optional)
  echo "▶️ Running: $SCRIPT_PATH $*"

  # Forward all remaining arguments
  "$SCRIPT_PATH" "$@"
}


# ────────────────────────────────────────────────────────────────
# Generates the beginning of an HTML report for server usage.
# This sets the global variable REPORT_FILE to a new temp file.
# Output includes basic table headers for disk, RAM, and CPU usage.
# ────────────────────────────────────────────────────────────────
setup_html_report() {
  REPORT_FILE="/tmp/server_usage_report_$(date +%Y%m%d_%H%M%S).html"
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
}


# ────────────────────────────────────────────────────────────────
# Appends closing HTML tags to REPORT_FILE and sends it via email
# using msmtp. Assumes $NOTIFY_EMAIL and $REPORT_FILE are set.
# ────────────────────────────────────────────────────────────────
send_html_report() {
  echo "</table></body></html>" >> "$REPORT_FILE"

  (
    echo "To: $NOTIFY_EMAIL"
    echo "Subject: Server Usage Report - $(date)"
    echo "Content-Type: text/html; charset=UTF-8"
    echo ""
    cat "$REPORT_FILE"
  ) | msmtp "$NOTIFY_EMAIL"

  echo "📧 HTML report sent to $NOTIFY_EMAIL"
}


# ────────────────────────────────────────────────────────────────
# Iterates over SERVER_LIST and runs the designated script
# (stored in SCRIPT_FOLDER) on each server IP.
# If a server fails, it's added to the FAILED array.
# ────────────────────────────────────────────────────────────────
run_for_all_servers() {
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
}

# ────────────────────────────────────────────────────────────────
# Prints a summary at the end of the run.
# Shows whether all servers succeeded or lists failed ones.
# ────────────────────────────────────────────────────────────────
print_summary() {
  echo -e "\n📋 Summary:"
  if [[ "${#FAILED[@]}" -eq 0 ]]; then
    echo "✅ All servers completed successfully."
  else
    echo "❌ Failed on:"
    printf ' - %s\n' "${FAILED[@]}"
  fi
}