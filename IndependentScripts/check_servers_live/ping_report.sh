#!/bin/bash
set -euo pipefail

trap 'echo -e "❌ ping_report.sh FAILED on $(hostname) at $(date)\nLine: $LINENO" | mail -s "Ping Report FAILED" "dmytro@growme.ca"' ERR

IP_LIST_FILE="/root/server_ips.txt"
HTML_REPORT="/tmp/server_ping_report.html"
DOWN_REPORT="/tmp/servers_down.html"
LOG_FILE="/var/log/ping_debug.log"

for cmd in jq ping sendmail; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ Required command '$cmd' not found. Installing..."
    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y "$cmd"
  fi
done

if [[ ! -s "$IP_LIST_FILE" ]]; then
  echo "❌ No IPs found in $IP_LIST_FILE."
  exit 1
fi

echo "=== Ping Report Log - $(date) ===" > "$LOG_FILE"

# FULL REPORT
cat > "$HTML_REPORT" <<EOT
Subject: 📡 Server Uptime Report - $(date '+%Y-%m-%d %H:%M')
MIME-Version: 1.0
Content-Type: text/html
To: dmytro@growme.ca
From: uptime-monitor@$(hostname -f)

<html><head><style>
body { font-family: Arial, sans-serif; font-size: 14px; }
table { border-collapse: collapse; width: 100%; }
th, td { padding: 8px 12px; border: 1px solid #ddd; text-align: left; }
th { background-color: #f4f4f4; }
tr.up { background-color: #e8ffe8; }
tr.down { background-color: #ffe8e8; }
</style></head><body>
<h2>📡 Server Uptime Report</h2>
<p><strong>Date:</strong> $(date)</p>
<table><thead><tr><th>IP Address</th><th>Status</th><th>Ping (ms)</th></tr></thead><tbody>
EOT

# DOWN REPORT
cat > "$DOWN_REPORT" <<EOT
Subject: 🚨 ALERT: Servers Down - $(date '+%Y-%m-%d %H:%M')
MIME-Version: 1.0
Content-Type: text/html
To: dmytro@growme.ca
From: uptime-monitor@$(hostname -f)

<html><head><style>
body { font-family: Arial, sans-serif; font-size: 14px; }
table { border-collapse: collapse; width: 100%; }
th, td { padding: 8px 12px; border: 1px solid #ddd; text-align: left; }
th { background-color: #f4f4f4; }
tr.down { background-color: #ffe8e8; }
</style></head><body>
<h2>🚨 The following servers are DOWN</h2>
<p><strong>Date:</strong> $(date)</p>
<table><thead><tr><th>IP Address</th><th>Status</th></tr></thead><tbody>
EOT

DOWN_COUNT=0

while IFS= read -r IP; do
  [[ -z "$IP" ]] && continue
  echo "Pinging $IP..." >> "$LOG_FILE"
  if PING_RESULT=$(ping -c 1 -W 2 "$IP" 2>/dev/null); then
    TIME=$(echo "$PING_RESULT" | grep 'time=' | sed -E 's/.*time=([0-9.]+).*/\1 ms/')
    echo "<tr class='up'><td>$IP</td><td>UP</td><td>$TIME</td></tr>" >> "$HTML_REPORT"
  else
    echo "<tr class='down'><td>$IP</td><td>DOWN</td><td>N/A</td></tr>" >> "$HTML_REPORT"
    echo "<tr class='down'><td>$IP</td><td>DOWN</td></tr>" >> "$DOWN_REPORT"
    ((DOWN_COUNT++))
    echo "Failed to ping $IP" >> "$LOG_FILE"
  fi
done < "$IP_LIST_FILE"

# Close both reports
cat >> "$HTML_REPORT" <<EOT
</tbody></table></body></html>
EOT

cat >> "$DOWN_REPORT" <<EOT
</tbody></table><p>Please investigate immediately.</p></body></html>
EOT

# Send reports
sendmail -t < "$HTML_REPORT"
if [[ $DOWN_COUNT -gt 0 ]]; then
  sendmail -t < "$DOWN_REPORT"
fi