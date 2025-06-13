#!/opt/homebrew/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/utils.sh"

HTML_REPORT_FILE="/tmp/server_list_report_$(date +%Y%m%d_%H%M%S).html"

load_env

print_table_header() {
  {
    echo "<html><head><style>"
    echo "table { border-collapse: collapse; width: 100%; }"
    echo "th, td { border: 1px solid #ddd; padding: 8px; }"
    echo "th { background-color: #f2f2f2; }"
    echo "</style></head><body><h2>RunCloud Server List</h2><table>"
    echo "<tr><th>Server ID</th><th>Server Name</th><th>IP Address</th><th>SSH Command</th></tr>"
  } > "$HTML_REPORT_FILE"

  printf "\n%-10s %-25s %-16s %-30s\n" "SERVER ID" "SERVER NAME" "IP ADDRESS" "SSH COMMAND"
  printf -- "-------------------------------------------------------------------------------\n"
}

append_server_row() {
  local id="$1"
  local name="$2"
  local ip="$3"
  local ssh_cmd="$4"

  printf "%-10s %-25s %-16s %-30s\n" "$id" "$name" "$ip" "$ssh_cmd"
  echo "<tr><td>$id</td><td>$name</td><td>$ip</td><td><code>$ssh_cmd</code></td></tr>" >> "$HTML_REPORT_FILE"
}

fetch_servers_and_build_report() {
  local page=1
  while :; do
    local response
    response=$(curl -s --location --request GET "https://manage.runcloud.io/api/v3/servers?perPage=40&page=$page" \
      --header "Authorization: Bearer $API_KEY" \
      --header "Accept: application/json" \
      --header "Content-Type: application/json")

    if ! echo "$response" | jq empty > /dev/null 2>&1; then
      echo "❌ Invalid response from RunCloud API (page $page)"
      exit 1
    fi

    echo "$response" | jq -c '.data[]' | while read -r server; do
      local id name ip ssh_cmd
      id=$(echo "$server" | jq -r '.id')
      name=$(echo "$server" | jq -r '.name')
      ip=$(echo "$server" | jq -r '.ipAddress')
      ssh_cmd="ssh root@$ip"

      append_server_row "$id" "$name" "$ip" "$ssh_cmd"
    done

    local next
    next=$(echo "$response" | jq -r '.meta.pagination.links.next')
    if [[ "$next" == "null" || -z "$next" ]]; then
      break
    fi
    ((page++))
  done
}

send_email_report() {
  {
    echo "</table></body></html>"
  } >> "$HTML_REPORT_FILE"

  {
    echo "To: $NOTIFY_EMAIL"
    echo "Subject: RunCloud Server List"
    echo "Content-Type: text/html; charset=UTF-8"
    echo ""
    cat "$HTML_REPORT_FILE"
  } | msmtp "$NOTIFY_EMAIL"

  echo "✅ Report emailed to $NOTIFY_EMAIL"
}

main() {
  print_table_header
  fetch_servers_and_build_report
  send_email_report
}

main
