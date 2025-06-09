#!/bin/bash
set -euo pipefail

### ───────────────────────────────────────────────
### 🔐 Load .env Environment Variables
### ───────────────────────────────────────────────
load_env() {
  ENV_FILE="$(dirname "$0")/../../.env"
  if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
  else
    echo "❌ .env file not found at $ENV_FILE"
    exit 1
  fi

  if [[ -z "${API_KEY:-}" || -z "${SSH_KEY_NAME:-}" || -z "${SSH_PUBLIC_KEY:-}" ]]; then
    echo "❌ Missing required variables: API_KEY, SSH_KEY_NAME, or SSH_PUBLIC_KEY"
    exit 1
  fi
}

### ───────────────────────────────────────────────
### 🔁 Fetch and Process All Servers (Paged)
### ───────────────────────────────────────────────
process_all_servers() {
  local page=1
  local per_page=40

  while :; do
    echo "📦 Fetching page $page..."
    local response
    response=$(curl -s --location --request GET \
      "https://manage.runcloud.io/api/v3/servers?page=$page&perPage=$per_page" \
      --header "Authorization: Bearer $API_KEY" \
      --header "Accept: application/json" \
      --header "Content-Type: application/json")

    if ! echo "$response" | jq empty 2>/dev/null; then
      echo "❌ Response is not valid JSON (page $page)"
      echo "$response"
      exit 1
    fi

    local count
    count=$(echo "$response" | jq '.data | length')

    if (( count == 0 )); then
      echo "✅ No more servers found on page $page. Done."
      break
    fi

    print_servers "$response"
    inject_ssh_keys "$response"

    ((page++))
  done
}

### ───────────────────────────────────────────────
### 🖨️ Print Server List
### ───────────────────────────────────────────────
print_servers() {
  local response="$1"
  echo "$response" | jq -r '.data[] | "\(.id)\t\(.name)\t\(.ipAddress)"'
}

### ───────────────────────────────────────────────
### 🔐 Inject SSH Key into Each Server (If Not Exists)
### ───────────────────────────────────────────────
inject_ssh_keys() {
  local response="$1"

  echo "$response" | jq -c '.data[]' | while read -r row; do
    local server_id
    server_id=$(echo "$row" | jq -r '.id')
    local server_name
    server_name=$(echo "$row" | jq -r '.name')

    echo "➕ Injecting SSH key into server [$server_name]..."

    local ssh_response
    ssh_response=$(curl -s --location --request POST \
      "https://manage.runcloud.io/api/v3/servers/$server_id/ssh/credentials" \
      --header "Authorization: Bearer $API_KEY" \
      --header "Content-Type: application/json" \
      --data-raw "{
        \"label\": \"$SSH_KEY_NAME\",
        \"username\": \"root\",
        \"publicKey\": \"$SSH_PUBLIC_KEY\",
        \"temporary\": false
      }")

    echo "🔑 SSH key injected on server [$server_name] - Response: $ssh_response"
  done
}

### 🚀 Main Entry Point
main() {
  load_env
  process_all_servers
}

main