#!/opt/homebrew/bin/bash
set -euo pipefail

SERVER_ID="$1"
SERVER_IP="$2"
SERVER_NAME="$3"

echo "🔍 Checking SSH access to server: $SERVER_NAME | ID: $SERVER_ID | IP: $SERVER_IP"

echo "📡 Sending SSH key injection request..."

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

# Optional: Extract message or success flag from JSON
status=$(echo "$ssh_response" | jq -r '.status // empty')
message=$(echo "$ssh_response" | jq -r '.message // empty')

echo "🔑 SSH injection status: ${status:-Unknown}"
echo "📝 Message: ${message:-No message returned}"

# Detect error condition (adjust depending on actual RunCloud response structure)
if echo "$ssh_response" | grep -q '"error"'; then
  echo "❌ Failed to inject SSH key into server $SERVER_NAME ($SERVER_ID)"
  exit 1
else
  echo "✅ SSH key injected successfully into $SERVER_NAME"
fi