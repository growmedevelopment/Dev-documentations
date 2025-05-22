#!/bin/bash
API_KEY="-------------API_KEY--------------------"

page=1

while :; do
  response=$(curl -s --location --request GET "https://manage.runcloud.io/api/v3/servers?page=$page" \
    --header "Authorization: Bearer $API_KEY" \
    --header "Accept: application/json" \
    --header "Content-Type: application/json")

  # Check if JSON is valid
  if ! echo "$response" | jq empty 2>/dev/null; then
    echo "❌ Response is not valid JSON (page $page)"
    echo "$response"
    exit 1
  fi

  # Print each server (name and IP)
  echo "$response" | jq -r '.data[] | "\(.id)\t\(.name)\t\(.ipAddress)"'

  # Inject SSH key into each server
  # Change label and publicKey for your

  echo "$response" | jq -c '.data[]' | while read -r row; do
    server_id=$(echo "$row" | jq -r '.id')
    ssh_response=$(curl -s --location -g --request POST "https://manage.runcloud.io/api/v3/servers/$server_id/ssh/credentials" \
      --header "Authorization: Bearer $API_KEY" \
      --header "Content-Type: application/json" \
      --data-raw '{
          "label": "----growMe---------",
          "username": "root",
          "publicKey": "------------publicKey----------",
          "temporary": false
      }'
    )
    echo "Injected SSH key for server ID: $server_id - Response: $ssh_response"
  done

  # Check for next page
  next_url=$(echo "$response" | jq -r '.meta.pagination.links.next')
  if [[ "$next_url" == "null" || -z "$next_url" ]]; then
    break
  fi

  ((page++))
done