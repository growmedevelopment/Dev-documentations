#!/bin/bash
set -euo pipefail

REMOTE_IP="155.138.130.98"
REMOTE_USER="root"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/../../utils.sh"
load_env

IP_LIST_FILE="/tmp/server_ips.txt"
JSON_FILE="/tmp/fresh_servers.json"
page=1
first=true

# Start JSON array
echo "[" > "$JSON_FILE"

while true; do
  response=$(curl -s -H "Authorization: Bearer $VULTR_API_TOKEN" \
    "https://api.vultr.com/v2/instances?page=$page&per_page=500")

  if echo "$response" | jq -e '.instances | type == "array"' >/dev/null; then
    count=$(echo "$response" | jq '.instances | length')
    echo "📦 Page $page: $count instances"

    entries=$(echo "$response" | jq -c '.instances[] | {id: .id, name: .label, ipAddress: .main_ip}')
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
    exit 1
  fi

  next=$(echo "$response" | jq -r '.meta.links.next // empty')
  [[ -z "$next" || "$next" == "null" ]] && break
  ((page++))
  sleep 0.05
done

# Close JSON array
echo "]" >> "$JSON_FILE"

# Generate IP list from that JSON
jq -r '.[].ipAddress' "$JSON_FILE" > "$IP_LIST_FILE"

if [[ ! -s "$IP_LIST_FILE" ]]; then
  echo "❌ No IP addresses found. Aborting."
  exit 1
fi

# 2. Upload IP list to server
scp "$IP_LIST_FILE" "$REMOTE_USER@$REMOTE_IP:/root/server_ips.txt"

NOTIFY_EMAIL_ESCAPED="${NOTIFY_EMAIL//\"/\\\"}"

# 3. Create ping_report.sh on the remote server
ssh "$REMOTE_USER@$REMOTE_IP" "cat > /root/ping_report.sh" <<EOF
#!/bin/bash
set -euo pipefail

trap 'ERR_LINE=\$LINENO; echo "❌ ping_report.sh FAILED on \$(hostname) at \$(date)\nLine: \$ERR_LINE" | mail -s "Ping Report FAILED" "$NOTIFY_EMAIL_ESCAPED"' ERR

IP_LIST_FILE="/root/server_ips.txt"
HTML_REPORT="/tmp/server_ping_report.html"
LOG_FILE="/var/log/ping_debug.log"
NOTIFY_EMAIL="$NOTIFY_EMAIL_ESCAPED"

# Ensure sendmail is installed
if ! command -v sendmail &>/dev/null; then
  echo "📦 Installing sendmail..."
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y sendmail
fi

# Start fresh log
echo "=== Ping Report Log - \$(date) ===" > "\$LOG_FILE"

cat > "\$HTML_REPORT" <<EOT
Subject: 📡 Server Uptime Report - \$(date '+%Y-%m-%d %H:%M')
MIME-Version: 1.0
Content-Type: text/html
To: \$NOTIFY_EMAIL
From: uptime-monitor@\$(hostname -f)

<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; font-size: 14px; }
    table { border-collapse: collapse; width: 100%; }
    th, td { padding: 8px 12px; border: 1px solid #ddd; text-align: left; }
    th { background-color: #f4f4f4; }
    tr.up { background-color: #e8ffe8; }
    tr.down { background-color: #ffe8e8; }
  </style>
</head>
<body>
  <h2>📡 Server Uptime Report</h2>
  <p><strong>Date:</strong> \$(date)</p>
  <table>
    <thead>
      <tr>
        <th>IP Address</th>
        <th>Status</th>
        <th>Ping (ms)</th>
      </tr>
    </thead>
    <tbody>
EOT

while IFS= read -r IP; do
  [[ -z "\$IP" ]] && continue
  echo "Pinging \$IP..." >> "\$LOG_FILE"
  if PING_RESULT=\$(ping -c 1 -W 2 "\$IP" 2>/dev/null); then
    TIME=\$(echo "\$PING_RESULT" | grep 'time=' | sed -E 's/.*time=([0-9.]+).*/\1 ms/')
    echo "<tr class='up'><td>\$IP</td><td>UP</td><td>\$TIME</td></tr>" >> "\$HTML_REPORT"
  else
    echo "<tr class='down'><td>\$IP</td><td>DOWN</td><td>N/A</td></tr>" >> "\$HTML_REPORT"
    echo "Failed to ping \$IP" >> "\$LOG_FILE"
  fi
done < "\$IP_LIST_FILE"

cat >> "\$HTML_REPORT" <<EOT
    </tbody>
  </table>
</body>
</html>
EOT

sendmail -t < "\$HTML_REPORT"
EOF

# 4. Set permissions
ssh "$REMOTE_USER@$REMOTE_IP" "chmod +x /root/ping_report.sh"

# 5. Schedule cron job
ssh "$REMOTE_USER@$REMOTE_IP" 'echo "0 0 * * * root /root/ping_report.sh" > /etc/cron.d/ping_report && chmod 644 /etc/cron.d/ping_report'

# 6. Clean up temporary files
rm -f "$JSON_FILE" "$IP_LIST_FILE"

echo "✅ ping_report.sh deployed and scheduled via cron on $REMOTE_IP"