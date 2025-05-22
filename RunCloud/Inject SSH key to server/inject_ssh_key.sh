#!/bin/bash
#//todo remove key
API_KEY="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ3b3Jrc3BhY2VfaWQiOjk4NDg0LCJleHAiOjE3NTA0NDU4MTYsInVzZXJfaWQiOjk4NDg5LCJ1bmlxdWVfaWRlbnRpZmllciI6IjA4ZjZiY2Y1LTZmZmItNDA4My1hNDBjLWM1M2NiZmQ3ZTkwZiJ9.nOq07e2cM4lIX41DAK7ykxQdTKuyEmNIy8MfARt2F14"

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
          "label": "dmytro-growMe",
          "username": "root",
          "publicKey": "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDESt9IxqVMNMpDL5vzG/16HWpx4rru+IKQ4ORkhYZy+CngGikolEBaxlZPRO73lq/naqRb1bM5yDfHOvKD6tGkG5A19bQSYKco9PLALQBLNtj8hELmLpqzU7DscgPiTUzveFfYrF3N/2uA203AQJCkNkC4QtNiINrFHw5zNrT7vy5qdLAZmo29gP5tqetDnvEnVmb0T30vN4xy2KLnsTa1iij0cYbMzQ1jKxIJB2kuCniZs6/O4HXN4RSyuLWdEdkfErNQE+nyNL1Qqn9ppFVQcXvM0GQUKK+SBgZLUhy7BfnO79eqw7VxI08ExkP0PJY31PGoUgb9Fpunukn3ZjFMZa4vG36Snagzy1GVDrOBo180iJ8QLoaQIW149gQdl930oMaLZlCzkCBxDEMJChMcieFGgCdBeEHus4AiZUG7B2gl3uYINTSKzci0hRHFBpQbx134TjQt+YwxiNSgH8uHeGceFAv/pzREvNzrvBvys748DijYnTI97nuUmPiThPM= dmytro@DESKTOP-RMU280C",
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