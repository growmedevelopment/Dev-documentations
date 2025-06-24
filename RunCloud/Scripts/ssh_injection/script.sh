#!/opt/homebrew/bin/bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "❗ Usage: $0 <SERVER_IP> <SERVER_ID> <SERVER_NAME>"
  exit 1
fi

SERVER_IP="$1"
SERVER_ID="$2"
SERVER_NAME="$3"

# Ensure required env vars are set
: "${RUNCLOUD_API_TOKEN:?RUNCLOUD_API_TOKEN is not set}"
: "${SSH_PUBLIC_KEY:?SSH_PUBLIC_KEY is not set}"
: "${SSH_KEY_NAME:?SSH_KEY_NAME is not set}"

label="${SSH_KEY_NAME}"

echo "🔍 Checking SSH access to server: $SERVER_NAME | ID: $SERVER_ID | IP: $SERVER_IP"
echo "📡 Sending SSH key injection request..."

ssh_response=$(curl -s --location --request POST \
  "https://manage.runcloud.io/api/v3/servers/$SERVER_ID/ssh/credentials" \
  --header "Authorization: Bearer $RUNCLOUD_API_TOKEN" \
  --header "Content-Type: application/json" \
  --data-raw "{
    \"label\": \"$label\",
    \"username\": \"root\",
    \"publicKey\": \"$SSH_PUBLIC_KEY\",
    \"temporary\": false
  }")

# Check if response has an ID field (success case)
injected_id=$(echo "$ssh_response" | jq -r '.id // empty')

if [[ -n "$injected_id" ]]; then
  echo "✅ SSH key injected successfully into $SERVER_NAME (ID: $injected_id)"
else
  echo "❌ Unexpected response format. Full response:"
  echo "$ssh_response"

  # Extract error message if available
  message=$(echo "$ssh_response" | jq -r '.message // "No message returned"')
  echo "📝 Message: $message"

  if [[ "$message" == "Resources not found." ]]; then
    echo "💡 Tip: The server ID may be invalid or no longer exists in your RunCloud account."
  elif [[ "$message" == "The label has already been taken." ]]; then
    echo "💡 Tip: SSH key label must be unique — this script appends timestamp + server ID to ensure uniqueness."
  fi

  exit 1
fi