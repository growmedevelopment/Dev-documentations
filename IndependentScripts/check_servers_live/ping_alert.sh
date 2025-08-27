#!/bin/bash
set -euo pipefail

IP_LIST_FILE="/root/server_ips.txt"
DOWN_STATE_FILE="/tmp/server_down_times.json"
NOTIFY_EMAIL="-----------"
TELEGRAM_BOT_TOKEN="-----------"
TELEGRAM_CHAT_ID="-------------"

[[ -f "$DOWN_STATE_FILE" ]] || echo '{}' > "$DOWN_STATE_FILE"

declare -A down_servers

send_telegram() {
  local MESSAGE="$1"
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=${MESSAGE}" \
    -d "parse_mode=HTML" >/dev/null
}

# Load saved state
while IFS="=" read -r ip ts; do
  [[ -n "$ip" && -n "$ts" ]] && down_servers["$ip"]=$ts
done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$DOWN_STATE_FILE")

new_state="{}"
alert_rows=""

while IFS= read -r IP; do
  [[ -z "$IP" ]] && continue
  if ping -c 1 -W 2 "$IP" &>/dev/null; then
    unset down_servers["$IP"]   # server is UP → clear record
  else
    now=$(date +%s)
    if [[ -n "${down_servers[$IP]:-}" ]]; then
      first_down=${down_servers[$IP]}
      if (( now - first_down >= 3600 )); then
        alert_rows+="<tr><td>$IP</td><td>DOWN > 1h</td></tr>"
      fi
    else
      down_servers["$IP"]=$now   # first time DOWN → store timestamp
    fi
  fi
done < "$IP_LIST_FILE"

# Save updated state
for ip in "${!down_servers[@]}"; do
  new_state=$(echo "$new_state" | jq --arg ip "$ip" --arg ts "${down_servers[$ip]}" '. + {($ip): $ts|tonumber}')
done
echo "$new_state" > "$DOWN_STATE_FILE"

# Send alert if needed
if [[ -n "$alert_rows" ]]; then
  down_list=$(echo "$alert_rows" | sed -E 's/<[^>]+>//g')  # strip HTML tags
  send_telegram "🚨 ALERT: Some servers are still DOWN >1h on <b>$(hostname)</b> at <b>$(date)</b>\n\n<pre>$down_list</pre>"

  (
    echo "To: $NOTIFY_EMAIL"
    echo "From: uptime-monitor@$(hostname -f)"
    echo "Subject: 🚨 Servers Still Down After 1 Hour"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html; charset=UTF-8"
    echo ""
    echo "<html><body>"
    echo "<h2>🚨 The following servers have been DOWN for over 1 hour</h2>"
    echo "<table border=1><tr><th>IP</th><th>Status</th></tr>"
    echo "$alert_rows"
    echo "</table></body></html>"
  ) | sendmail -t
fi