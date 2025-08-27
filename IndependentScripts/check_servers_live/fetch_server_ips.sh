#!/bin/bash
set -euo pipefail

VULTR_API_TOKEN="-----------"
IP_LIST_FILE="/root/server_ips.txt"
LABEL_IP_FILE="/root/server_labels.csv"
TODAY=$(date +%Y-%m-%d)

echo "📡 Fetching Vultr server list..."
page=1
echo "[]" > /tmp/instances.json

while true; do
  response=$(curl -s -H "Authorization: Bearer $VULTR_API_TOKEN" \
    "https://api.vultr.com/v2/instances?page=$page&per_page=500")

  if echo "$response" | jq -e '.instances | type=="array"' >/dev/null; then
    instances=$(echo "$response" | jq '.instances')
    jq -s '.[0] + .[1]' /tmp/instances.json <(echo "$instances") > /tmp/tmp.json
    mv /tmp/tmp.json /tmp/instances.json
  else
    echo "❌ API error"
    echo "$response"
    exit 1
  fi

  next=$(echo "$response" | jq -r '.meta.links.next // empty')
  [[ -z "$next" || "$next" == "null" ]] && break
  ((page++))
done

# Save only IPs
jq -r '.[] | .main_ip' /tmp/instances.json > "$IP_LIST_FILE"

# Save IP + label (handy for other scripts)
jq -r '.[] | [.main_ip, .label] | @csv' /tmp/instances.json > "$LABEL_IP_FILE"

echo "✅ Saved $(wc -l < "$IP_LIST_FILE") IPs to $IP_LIST_FILE"
echo "✅ Saved IPs + labels to $LABEL_IP_FILE"
echo "$TODAY" > /tmp/last_ip_fetch.txt