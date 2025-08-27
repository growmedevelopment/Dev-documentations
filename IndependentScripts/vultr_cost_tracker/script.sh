#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/utils.sh"
load_env

trap 'echo "❌ Billing report FAILED on $(hostname) at $(date) (line $LINENO)" | mail -s "Vultr Billing Report FAILED" "$NOTIFY_EMAIL"' ERR

echo "📦 Fetching Vultr server billing data..."

cursor=""
all_json="[]"

while :; do
  url="https://api.vultr.com/v2/instances?per_page=500&show_pending_charges=true"
  [[ -n "$cursor" ]] && url+="&cursor=$cursor"

  response=$(curl -sS -H "Authorization: Bearer $VULTR_API_TOKEN" "$url")

  # Detect Vultr error response
  if echo "$response" | jq -e '.error' >/dev/null; then
    echo "❌ API Error: $(echo "$response" | jq -r '.error.message // .error')"
    exit 1
  fi

  page_instances=$(echo "$response" | jq '.instances')
  all_json=$(jq -s '.[0] + .[1]' <(echo "$all_json") <(echo "$page_instances"))

  cursor=$(echo "$response" | jq -r '.meta.next_cursor // empty')
  [[ -z "$cursor" ]] && break
done

server_count=$(echo "$all_json" | jq 'length')

total_pending=$(echo "$all_json" \
  | jq '[.[] | .pending_charges? | select(. != null) | tonumber] | add // 0')

rounded_pending=$(printf "%.2f" "$total_pending")

# Build detailed server breakdown (sorted by cost desc)
detailed_rows=$(echo "$all_json" \
  | jq -r 'sort_by(-(.pending_charges // 0 | tonumber))[]
           | "<tr><td>\(.label)</td><td>\(.main_ip)</td><td>$\(.pending_charges // "0.00")</td></tr>"')

# Compose HTML report
REPORT_FILE="/tmp/vultr_cost_summary.html"
cat <<EOF > "$REPORT_FILE"
<html>
<head><style>
  body { font-family: Arial, sans-serif; font-size: 14px; }
  table { border-collapse: collapse; margin-bottom: 20px; width: 100%; }
  th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; }
  th { background: #f4f4f4; }
</style></head>
<body>
  <h2>📊 Vultr Server Cost Summary</h2>
  <p>Generated: $(date)</p>

  <table>
    <tr><th>Metric</th><th>Value</th></tr>
    <tr><td>Total Servers</td><td>$server_count</td></tr>
    <tr><td>Total Pending Charges</td><td>\$$rounded_pending</td></tr>
  </table>

  <h3>💡 Cost Breakdown by Server</h3>
  <table>
    <tr><th>Server Name</th><th>IP Address</th><th>Pending Charges (USD)</th></tr>
    $detailed_rows
  </table>
</body></html>
EOF

# Send email via msmtp
(
  echo "To: $NOTIFY_EMAIL"
  echo "From: vultr-monitor@$(hostname -f)"
  echo "Subject: 💰 Vultr Server Cost Summary"
  echo "MIME-Version: 1.0"
  echo "Content-Type: text/html; charset=UTF-8"
  echo ""
  cat "$REPORT_FILE"
) | msmtp "$NOTIFY_EMAIL"

echo "📧 Email report sent to $NOTIFY_EMAIL"