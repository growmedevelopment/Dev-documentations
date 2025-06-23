#!/opt/homebrew/bin/bash
set -euo pipefail

SERVER_ID="$1"

echo "🔍 Checking SSH access to server id: $SERVER_ID..."

# Inject SSH key via RunCloud API
ssh_response=$(curl -s --location --request POST \
  "https://manage.runcloud.io/api/v3/servers/$SERVER_ID/ssh/credentials" \
  --header "Authorization: Bearer $RUNCLOUD_API_TOKEN" \
  --header "Content-Type: application/json" \
  --data-raw "{
    \"label\": \"$SSH_KEY_NAME\",
    \"username\": \"root\",
    \"publicKey\": \"$SSH_PUBLIC_KEY\",
    \"temporary\": false
  }")

echo "🔑 SSH key injection response for server [$SERVER_ID]:"
echo "$ssh_response"