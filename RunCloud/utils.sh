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

### 📡 Fetch from Vultr
fetch_all_servers() {
  echo "📡 Fetching from Vultr API..."
  local TMPFILE="$ROOT_DIR/servers.list"
  local page=1
  > "$TMPFILE"

  while true; do
    response=$(curl -s -H "Authorization: Bearer $VULTURE_API_TOKEN" \
      "https://api.vultr.com/v2/instances?page=$page&per_page=500")

    if echo "$response" | jq -e '.instances | type == "array"' >/dev/null; then
      echo "$response" | jq -r '.instances[].main_ip' >> "$TMPFILE"
    else
      echo "❌ API error on page $page"
      echo "$response"
      exit 1
    fi

    next=$(echo "$response" | jq -r '.meta.links.next // empty')
    [[ -z "$next" || "$next" == "null" ]] && break
    ((page++))
    sleep 0.05
  done

  echo "📊 Saved $(wc -l < "$TMPFILE") servers to $TMPFILE"
}

### 🧠 Load Static IPs
get_all_servers_from_file() {
  local SERVER_FILE="$ROOT_DIR/servers.list"
  SERVER_LIST=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^\s*# ]] && continue
    [[ -z "$line" ]] && continue
    SERVER_LIST+=("$line")
  done < "$SERVER_FILE"
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