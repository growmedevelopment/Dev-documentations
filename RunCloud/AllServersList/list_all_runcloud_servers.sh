#!/bin/bash

# Load API Key from environment
ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "❌ .env file not found at $ENV_FILE"
  exit 1
fi

# Check msmtp
if ! command -v msmtp >/dev/null 2>&1; then
  echo "❌ msmtp is not installed. Please install msmtp to send mail."
  exit 1
fi

# Create HTML report
HTML_REPORT_FILE="/tmp/server_list_report_$(date +%Y%m%d_%H%M%S).html"
{
  echo "<html><head><style>"
  echo "table { border-collapse: collapse; width: 100%; }"
  echo "th, td { border: 1px solid #ddd; padding: 8px; }"
  echo "th { background-color: #f2f2f2; }"
  echo "</style></head><body><h2>RunCloud Server List</h2><table>"
  echo "<tr><th>Server ID</th><th>Server Name</th><th>IP Address</th><th>SSH Command</th></tr>"
} > "$HTML_REPORT_FILE"

# Print header to terminal
echo -e "SERVER ID	SERVER NAME			IP ADDRESS		SSH COMMAND"

page=1
while :; do
  response=$(curl -s --location --request GET "https://manage.runcloud.io/api/v3/servers?page=$page" \
    --header "Authorization: Bearer $API_KEY" \
    --header "Accept: application/json" \
    --header "Content-Type: application/json")

  if ! echo "$response" | jq empty > /dev/null 2>&1; then
    echo "❌ Invalid response from RunCloud API (page $page)"
    exit 1
  fi

  echo "$response" | jq -c '.data[]' | while read -r server; do
    id=$(echo "$server" | jq -r '.id')
    name=$(echo "$server" | jq -r '.name')
    ip=$(echo "$server" | jq -r '.ipAddress')
    ssh_cmd="ssh root@$ip"

    # Output to terminal
    echo -e "$id	$name	$ip	$ssh_cmd"

    # Append to HTML
    echo "<tr><td>$id</td><td>$name</td><td>$ip</td><td><code>$ssh_cmd</code></td></tr>" >> "$HTML_REPORT_FILE"
  done

  next=$(echo "$response" | jq -r '.meta.pagination.links.next')
  if [[ "$next" == "null" || -z "$next" ]]; then
    break
  fi
  ((page++))
done

# Close HTML
echo "</table></body></html>" >> "$HTML_REPORT_FILE"

# Send HTML report via email
(
  echo "To: $NOTIFY_EMAIL"
  echo "Subject: RunCloud Server List"
  echo "Content-Type: text/html; charset=UTF-8"
  echo ""
  cat "$HTML_REPORT_FILE"
) | msmtp "$NOTIFY_EMAIL"

echo "✅ Report emailed to $NOTIFY_EMAIL"
