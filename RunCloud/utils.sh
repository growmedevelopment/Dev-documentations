#!/bin/bash

# Get project root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

### 🔐 load_env
# Loads environment variables from .env file at project root.
# Exits with error if required vars are missing (VULTR_API_TOKEN, NOTIFY_EMAIL).
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

### ⏱️ detect_timeout_cmd
# Detects whether 'timeout' or 'gtimeout' is available for command timeouts.
# Exits with error if neither is found.
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

### 📡 fetch_all_vultr_servers
# Fetches all Vultr servers with paginated API requests.
# Outputs a JSON array to stdout; does not write to file.
fetch_all_vultr_servers() {
  echo "🔄 Fetching servers from Vultr (paginated)..." >&2

  local page=1
  local -a entries=()

  while true; do
    response=$(curl -sS -H "Authorization: Bearer $VULTR_API_TOKEN" \
      "https://api.vultr.com/v2/instances?page=$page&per_page=500")

    # Check for API errors
    if ! echo "$response" | jq -e '.instances | type == "array"' >/dev/null 2>&1; then
      echo "❌ Vultr API error on page $page" >&2
      echo "$response" >&2
      return 1
    fi

    local count
    count=$(echo "$response" | jq '.instances | length')
    echo "📦 Page $page: $count instances" >&2

    # Extract relevant fields into an array
    mapfile -t page_entries < <(echo "$response" | jq -c '.instances[] | {id: .id, name: .label, main_ip: .main_ip}')

    entries+=("${page_entries[@]}")

    # Check if more pages exist
    next=$(echo "$response" | jq -r '.meta.links.next // empty')
    [[ -z "$next" || "$next" == "null" ]] && break
    ((page++))
    sleep 0.05
  done

  if [[ ${#entries[@]} -eq 0 ]]; then
    echo "❌ No servers found from Vultr API." >&2
    return 1
  fi

  # Emit JSON array
  jq -n --argjson arr "$(printf '%s\n' "${entries[@]}" | jq -s '.')" '$arr'
}

### 📡 fetch_all_runcloud_servers
# Fetches all servers from RunCloud API (paginated).
# Outputs a JSON array of servers directly to stdout; does not save.
fetch_all_runcloud_servers() {

  declare -a temp_entries=()
  local page=1

  echo "🔄 Fetching all servers from RunCloud (paginated, 40 per page)..." >&2

  while true; do
    echo "📦 Requesting page $page..." >&2

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
    echo "❌ No server data returned from RunCloud API" >&2
    return 1
  fi

  jq -n --argjson arr "$(printf '%s\n' "${temp_entries[@]}" | jq -s '.')" '$arr'
}

### 💾 save_servers_to_file
# Saves provided JSON data to $ROOT_DIR/servers.json.
fetch_all_vultr_servers() {
  local json_data="$1"
  local output_file="$ROOT_DIR/servers.json"

  echo "💾 Saving server data to $output_file" >&2
  echo "$json_data" > "$output_file"
  echo "📥 Wrote $(jq length <<< "$json_data") server entries to $output_file" >&2
}

### 📡 fetch_all_runcloud_apps
# Fetches all servers from RunCloud, then retrieves all web apps
# across those servers, assembling them into a JSON array.
fetch_all_runcloud_apps() {
   echo "🌐 Fetching all servers from RunCloud..."

   local all_servers_json
   if ! all_servers_json=$(fetch_all_runcloud_servers); then
     echo "❌ Failed to fetch servers."
     return 1
   fi

   mapfile -t server_ids < <(echo "$all_servers_json" | jq -r '.[].id')
   mapfile -t server_names < <(echo "$all_servers_json" | jq -r '.[].name')

   if [[ ${#server_ids[@]} -eq 0 ]]; then
     echo "❌ No servers found."
     return 1
   fi

   declare -a all_apps_local=()

   for idx in "${!server_ids[@]}"; do
     server_id="${server_ids[$idx]}"
     server_name="${server_names[$idx]}"
     echo "📡 Processing server: $server_name (ID: $server_id)"

     local page=1
     local more=true
     while $more; do
       echo "   🔎 Fetching apps page $page from server: $server_name (ID: $server_id)"
       local response
       response=$(curl -s --location --request GET "https://manage.runcloud.io/api/v3/servers/$server_id/webapps?sortColumn=name&sortDirection=asc&page=$page" \
         --header "$AUTH_HEADER" --header "Accept: application/json")
       if ! echo "$response" | jq -e '.data' >/dev/null 2>&1; then
         echo "⚠️ Failed to fetch apps for server $server_id on page $page. Skipping."
         break
       fi
       local page_apps
       page_apps=$(echo "$response" | jq -r '.data[]?.name')
       if [[ -n "$page_apps" ]]; then
         while IFS= read -r app_name; do
           all_apps_local+=("$app_name")
         done <<< "$page_apps"
       fi
       local total_pages
       total_pages=$(echo "$response" | jq '.meta.pagination.total_pages // 1')
       (( page >= total_pages )) && more=false || ((page++))
     done
   done

   if [[ ${#all_apps_local[@]} -eq 0 ]]; then
     echo "❌ No apps found across servers."
     return 1
   fi

   jq -n --argjson arr "$(printf '%s\n' "${all_apps_local[@]}" | jq -R . | jq -s .)" '$arr'
 }

### ☁️ fetch_all_vultr_backups_folders
# Lists top-level folders in Vultr object storage bucket for backups.
# Populates 'folders' array variable with folder names.
fetch_all_vultr_backups_folders() {
  echo "☁️ Listing top-level folders in bucket: runcloud-app-backups"
  folders=()
  while IFS= read -r line; do
    folders+=("$line")
  done < <(aws s3 ls "s3://runcloud-app-backups/" --endpoint-url "https://sjc1.vultrobjects.com" | awk '/PRE/ {print $2}' | sed 's#/##')
}

### 📁 create_or_clear_servers_json_file
# Creates or overwrites servers.json file with empty JSON array.
create_or_clear_servers_json_file(){
  local JSON_FILE="$ROOT_DIR/servers.json"

  echo "📁 Creating missing $JSON_FILE..."
  mkdir -p "$(dirname "$JSON_FILE")"
  echo "[]" > "$JSON_FILE"
}

### 📄 get_all_servers_from_file
# Loads server details from servers.json into SERVER_IDS, SERVER_IPS, SERVER_NAMES arrays.
get_all_servers_from_file() {
  local JSON_FILE="$ROOT_DIR/servers.json"

  SERVER_IDS=()
  SERVER_IPS=()
  SERVER_NAMES=()

  echo "📄 Loading server details from $JSON_FILE..."

  while IFS=$'\t' read -r id ip name; do
    SERVER_IDS+=("$id")
    SERVER_IPS+=("$ip")
    SERVER_NAMES+=("$name")
  done < <(jq -r '.[] | [.id, .ipAddress, .name] | @tsv' "$JSON_FILE")

  echo "📦 Loaded ${#SERVER_IDS[@]} servers from file"
}

### ▶️ run_script
# Executes a script located in Scripts/<SCRIPT_NAME>/script.sh with arguments.
# Exits with error if script does not exist.
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

### 📊 setup_html_report
# Initializes an HTML report file with table headers for server usage summary.
# Sets REPORT_FILE global variable.
setup_html_report() {
  REPORT_FILE="/tmp/server_heals_report.html"
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

### 📧 send_html_report
# Appends closing tags to REPORT_FILE and emails the report to $NOTIFY_EMAIL using msmtp.
send_html_report() {
  {
    echo "</table>"

    echo "<hr><h3>⚠️ Summary of Critical Issues</h3>"
    if (( ${#ERROR_SUMMARY[@]} > 0 )); then
      echo "<ul>"
      for err in "${ERROR_SUMMARY[@]}"; do
        echo "<li>$err</li>"
      done
      echo "</ul>"
    else
      echo "<p>✅ No critical issues detected.</p>"
    fi

    echo "</body></html>"
  } >> "$REPORT_FILE"

  (
    echo "To: $NOTIFY_EMAIL"
    echo "Subject: Server Usage Report - $(date)"
    echo "Content-Type: text/html; charset=UTF-8"
    echo ""
    cat "$REPORT_FILE"
  ) | msmtp "$NOTIFY_EMAIL"

  echo "📧 HTML report sent to $NOTIFY_EMAIL"
}

### 🚀 run_for_all_servers
# Iterates through all loaded servers and runs the designated script on each server.
# Appends failures to ERROR_SUMMARY.
run_for_all_servers() {
  echo "📋 Running for ${#SERVER_IPS[@]} servers..."

  for i in "${!SERVER_IPS[@]}"; do
    server_id="${SERVER_IDS[$i]}"
    server_ip="${SERVER_IPS[$i]}"
    server_name="${SERVER_NAMES[$i]}"

    echo "[$((i + 1))/${#SERVER_IPS[@]}] → $server_ip ($server_name)"

    if run_script "$SCRIPT_FOLDER" "$server_ip" "$server_id" "$server_name"; then
      echo "✅ Success for $server_name ($server_ip)"
    else
      error_msg="❌ Failed for $server_name ($server_ip)"
      echo "$error_msg"
      ERROR_SUMMARY+=("$error_msg")
    fi

    echo "--------------------------------------------------------"
  done
}

### 📋 print_summary
# Prints a summary of the script run, showing success or failed servers.
print_summary() {
  echo -e "\n📋 Summary:"
  if [[ "${#FAILED[@]}" -eq 0 ]]; then
    echo "✅ All servers completed successfully."
  else
    echo "❌ Failed on:"
    printf ' - %s\n' "${FAILED[@]}"
  fi
}