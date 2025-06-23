#!/bin/bash

# Get project root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

### 🔐 Load .env
load_env() {
  ENV_FILE="$ROOT_DIR/.env"
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
  else
    echo "❌ .env file not found at $ENV_FILE"
    exit 1
  fi

  if [[ -z "${VULTURE_API_TOKEN:-}" || -z "${NOTIFY_EMAIL:-}" ]]; then
    echo "❌ Required vars (VULTURE_API_TOKEN, NOTIFY_EMAIL) not set"
    exit 1
  fi
}

### ⏱️ Detect Timeout Command
detect_timeout_cmd() {
  if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout"
  elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout"
  else
    echo "❌ timeout/gtimeout not found"
    exit 1
  fi
}

fetch_vultr_servers() {
  echo "📡 Fetching from Vultr API..."
  local JSON_FILE="$ROOT_DIR/servers.json"
  local page=1
  > "$JSON_FILE"
  echo "[" > "$JSON_FILE"
  local first=true

  while true; do
    response=$(curl -s -H "Authorization: Bearer $VULTR_API_TOKEN" \
      "https://api.vultr.com/v2/instances?page=$page&per_page=500")

    if echo "$response" | jq -e '.instances | type == "array"' >/dev/null; then
      local count
      count=$(echo "$response" | jq '.instances | length')
      echo "📦 Page $page: $count instances"

      entries=$(echo "$response" | jq -c '.instances[] | {id, name: .label, ipAddress: .main_ip}')
      while read -r entry; do
        if [[ "$first" == true ]]; then
          echo "$entry" >> "$JSON_FILE"
          first=false
        else
          echo ",$entry" >> "$JSON_FILE"
        fi
      done <<< "$entries"
    else
      echo "❌ API error on page $page"
      echo "$response"
      echo "]" >> "$JSON_FILE"
      return 1
    fi

    next=$(echo "$response" | jq -r '.meta.links.next // empty')
    [[ -z "$next" || "$next" == "null" ]] && break
    ((page++))
    sleep 0.05
  done

  echo "]" >> "$JSON_FILE"
  echo "📄 Server data saved to $JSON_FILE"
}

### 📡 Fetch from RunCloude
fetch_runcloud_servers() {
  echo "📡 Fetching full server data from RunCloud..."
  local JSONFILE="$ROOT_DIR/servers.json"
  > "$JSONFILE"

  local page=1
  local first=true
  echo "[" > "$JSONFILE"

  while true; do
    echo "🌐 Fetching page $page (perPage=40)..."
    response=$(curl -s -X GET \
      "https://manage.runcloud.io/api/v3/servers?page=$page&perPage=40" \
      -H "Authorization: Bearer $RUNCLOUD_API_TOKEN" \
      -H "Accept: application/json")

    if echo "$response" | jq -e '.data | type == "array"' >/dev/null; then
      local count
      count=$(echo "$response" | jq '.data | length')
      echo "📦 Retrieved $count servers from page $page"

      json_data=$(echo "$response" | jq -c '.data[]')
      while read -r entry; do
        if [[ "$first" == true ]]; then
          echo "$entry" >> "$JSONFILE"
          first=false
        else
          echo ",$entry" >> "$JSONFILE"
        fi
      done <<< "$json_data"
    else
      echo "❌ RunCloud API error on page $page"
      echo "$response"
      echo "]" >> "$JSONFILE"
      return 1
    fi

    next_url=$(echo "$response" | jq -r '.meta.pagination.links.next // empty')
    if [[ -z "$next_url" ]]; then
      echo "✅ No more pages. All server data retrieved."
      break
    fi

    ((page++))
    sleep 0.1
  done

  echo "]" >> "$JSONFILE"
  echo "📄 All server data saved to $JSONFILE"
}

### 🧠 Load Static IPs
get_all_servers_from_file() {
  local JSON_FILE="$ROOT_DIR/servers.json"
  SERVER_LIST=()

  if [[ ! -f "$JSON_FILE" ]]; then
    echo "❌ Server JSON file not found: $JSON_FILE"
    return 1
  fi

  echo "📄 Loading server IPs from $JSON_FILE..."
  mapfile -t SERVER_LIST < <(jq -r '.[].ipAddress' "$JSON_FILE")
}

### 🧩 Run Any Script
run_script() {
  local SCRIPT_NAME="$1"
  local SERVER="$2"
  local SCRIPT_PATH="$ROOT_DIR/Scripts/$SCRIPT_NAME/script.sh"

  if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "❌ Script '$SCRIPT_NAME' not found at $SCRIPT_PATH"
    return 1
  fi

  "$SCRIPT_PATH" "$SERVER"
}