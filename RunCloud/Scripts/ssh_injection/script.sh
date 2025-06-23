#!/opt/homebrew/bin/bash
set -euo pipefail

SERVER_ID="$1"

echo "🔍 Checking SSH access to server id-  $SERVER_ID..."






#ssh_response=$(curl -s --location --request POST \
#  "https://manage.runcloud.io/api/v3/servers/$server_id/ssh/credentials" \
#  --header "Authorization: Bearer $API_KEY" \
#  --header "Content-Type: application/json" \
#  --data-raw "{
#    \"label\": \"$SSH_KEY_NAME\",
#    \"username\": \"root\",
#    \"publicKey\": \"$SSH_PUBLIC_KEY\",
#    \"temporary\": false
#  }")
#
#echo "🔑 SSH key injected on server [$server_name] - Response: $ssh_response"
