#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT_DIR/utils.sh"
load_env

echo "📦 Fetching Vultr server billing data..."

cursor=""
instances=()

while :; do
  url="https://api.vultr.com/v2/instances?per_page=500&show_pending_charges=true"
  [[ -n "$cursor" ]] && url+="&cursor=$cursor"

  response=$(curl -sS -H "Authorization: Bearer $VULTR_API_TOKEN" "$url")

  new_instances=$(echo "$response" | jq -c '.instances[]')
  while IFS= read -r inst; do
    instances+=("$inst")
  done <<< "$new_instances"

  cursor=$(echo "$response" | jq -r '.meta.next_cursor // empty')
  [[ -z "$cursor" ]] && break
done

server_count="${#instances[@]}"
total_hourly=$(printf '%s\n' "${instances[@]}" | jq -s '[.[] | .billing_hourly_rate | select(. != null) | tonumber] | add')
total_hourly="${total_hourly:-0}"
total_monthly=$(echo "$total_hourly * 24 * 30" | bc)

# Compose HTML report
REPORT_FILE="/tmp/vultr_cost_summary.html"
cat <<EOF > "$REPORT_FILE"
<html><body>
  <h2>📊 Vultr Server Cost Summary</h2>
  <p>Generated: $(date)</p>
  <table border="1" cellpadding="8" cellspacing="0" style="border-collapse: collapse;">
    <tr><th>Metric</th><th>Value</th></tr>
    <tr><td>Total Servers</td><td>$server_count</td></tr>
    <tr><td>Hourly Cost</td><td>\$$total_hourly</td></tr>
    <tr><td>Estimated Monthly Cost</td><td>\$$total_monthly</td></tr>
  </table>
</body></html>
EOF

# Send email
(
  echo "To: $NOTIFY_EMAIL"
  echo "Subject: 💰 Vultr Server Cost Summary"
  echo "Content-Type: text/html"
  echo ""
  cat "$REPORT_FILE"
) | msmtp "$NOTIFY_EMAIL"

echo "📧 Email report sent to $NOTIFY_EMAIL"