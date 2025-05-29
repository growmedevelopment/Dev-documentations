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

# Print header
echo -e "SERVER NAME\t\t\tIP ADDRESS\t\tREGION\t\tTAGS"

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
    echo -e "$name\t$ip\t$region\t$tags"
  done

  next=$(echo "$response" | jq -r '.meta.pagination.links.next')
  if [[ "$next" == "null" || -z "$next" ]]; then
    break
  fi
  ((page++))
done