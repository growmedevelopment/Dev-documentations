#!/bin/bash

# Load API Key from environment
ENV_FILE="$(dirname "$0")/../../.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "❌ .env file not found at $ENV_FILE"
  exit 1
fi

TMPFILE=$(mktemp)
page=1
echo "📡 Fetching servers..."

# Fetch all servers and store them in TMPFILE
while true; do
  response=$(curl -s -H "Authorization: Bearer $API_KEY" \
                  "https://manage.runcloud.io/api/v3/servers?page=$page")

  echo "$response" | jq -e '.data | type == "array"' >/dev/null || break
  echo "$response" | jq -c '.data[]' >> "$TMPFILE"

  next=$(echo "$response" | jq -r '.meta.pagination.links.next // empty')
  [[ -z "$next" || "$next" == "null" ]] && break
  ((page++))
done

echo "🚀 Connecting to servers..."

# Print header
printf "%-30s %-16s %-12s %-20s %-10s\n" "SERVER NAME" "IP ADDRESS" "REGION" "TAGS" "SSH"

# Read servers into an array and check each via SSH
mapfile -t SERVERS < "$TMPFILE"
count=0
for server in "${SERVERS[@]}"; do
  name=$(echo "$server" | jq -r '.name')
  ip=$(echo "$server" | jq -r '.ipAddress')
  region=$(echo "$server" | jq -r '.region // "N/A"')
  tags=$(echo "$server" | jq -r '.tags | map(.name) | join(", ") // "None"')

  timeout 5s ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no "root@$ip" exit 0 >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    ssh_status="✅"
  else
    ssh_status="❌"
  fi

  printf "%-30s %-16s %-12s %-20s %-10s\n" "$name" "$ip" "$region" "$tags" "$ssh_status"
done

rm "$TMPFILE"