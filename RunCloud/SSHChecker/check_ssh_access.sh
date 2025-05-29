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

# Print header
printf "%-30s %-16s %-12s %-20s %-10s\n" "SERVER NAME" "IP ADDRESS" "REGION" "TAGS" "SSH"

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
    name=$(echo "$server" | jq -r '.name')
    ip=$(echo "$server" | jq -r '.ipAddress')
    region=$(echo "$server" | jq -r '.region // "N/A"')
    tags=$(echo "$server" | jq -r '.tags | map(.name) | join(", ") // "None"')

    # Try SSH with timeout (no commands)
    timeout 5s ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no "root@$ip" exit 0 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      ssh_status="✅"
    else
      ssh_status="❌"
    fi

    printf "%-30s %-16s %-12s %-20s %-10s\n" "$name" "$ip" "$region" "$tags" "$ssh_status"
  done

  next=$(echo "$response" | jq -r '.meta.pagination.links.next')
  if [[ "$next" == "null" || -z "$next" ]]; then
    break
  fi
  ((page++))
done