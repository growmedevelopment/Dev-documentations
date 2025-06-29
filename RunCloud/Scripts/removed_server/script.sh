#!/bin/bash

# ------------------- CONFIG -------------------
load_env
EMAIL_FROM="noreply@yourdomain.com"
ROOT_DIR="/tmp"  # or any path you want to store servers.json



# ------------------- COMPARISON -------------------
compare_servers() {
  local runcloud_json="$1"
  local vultr_json="$2"

  local missing_json="[]"

  # Iterate over Vultr servers and find those not in RunCloud by IP
  echo "$vultr_json" | jq -c '.[]' | while read -r vultr; do
    vultr_ip=$(echo "$vultr" | jq -r '.ipAddress')
    # Search for matching IP in RunCloud JSON
    found=$(echo "$runcloud_json" | jq --arg ip "$vultr_ip" '[.[] | select(.ipAddress == $ip)] | length')
    if [[ "$found" -eq 0 ]]; then
      missing_json=$(echo "$missing_json" | jq --argjson item "$vultr" '. += [$item]')
    fi
  done

  echo "$missing_json"
}

process_missing_servers() {
  local missing_json="$1"

  local found=$(echo "$missing_json" | jq 'length')
  if [[ "$found" -eq 0 ]]; then
    echo "✅ No missing servers found. No email sent."
    return
  fi

  echo -e "\n---- Servers in Vultr but not in RunCloud ----"
  local html_table="<table border='1' cellpadding='5' cellspacing='0' style='border-collapse:collapse;'>
  <tr style='background-color:#f2f2f2;'><th>IP Address</th><th>Server Name</th><th>Vultr ID</th></tr>"

  echo "$missing_json" | jq -c '.[]' | while read -r server; do
    ip=$(echo "$server" | jq -r '.ipAddress')
    name=$(echo "$server" | jq -r '.name')
    id=$(echo "$server" | jq -r '.id')
    echo "IP: $ip, Name: $name, ID: $id"
    html_table="${html_table}<tr><td>${ip}</td><td>${name}</td><td>${id}</td></tr>"
  done

  html_table="${html_table}</table>"
  send_summary_email "$html_table"
}

send_summary_email() {
  local html_table="$1"
  local body="<!DOCTYPE html><html><body>"
  body="${body}<p>Dear Team,</p>"
  body="${body}<p>The following servers are still active in Vultr but missing in RunCloud:</p>"
  body="${body}${html_table}"
  body="${body}<p>Please review and take necessary action.</p>"
  body="${body}</body></html>"

  echo -e "Subject:🚨 Vultr Servers Missing in RunCloud\nFrom:${EMAIL_FROM}\nMIME-Version: 1.0\nContent-Type: text/html\n\n${body}" | /usr/sbin/sendmail -t "${NOTIFY_EMAIL}"
  echo "📧 Summary email sent to ${NOTIFY_EMAIL}."
}



# ------------------- MAIN -------------------
vultr_json=$(fetch_vultr_servers)
runcloud_json=$(fetch_all_runcloud_servers2)

echo "🔍 Comparing Vultr and RunCloud servers..."
missing_json=$(compare_servers "$runcloud_json" "$vultr_json")
process_missing_servers "$missing_json"

