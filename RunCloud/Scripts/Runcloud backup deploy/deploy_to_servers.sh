#!/bin/bash

# === Load environment variables ===
ENV_FILE="$(dirname "$0")/../../.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "❌ .env file not found at $ENV_FILE"
  exit 1
fi

# === SSH Key Check ===

if [ ! -f "$SSH_PUBLIC_KEY" ]; then
  echo "❌ SSH key not found at $SSH_PUBLIC_KEY"
  exit 1
fi

# === Check deploy_payload.sh exists ===
DEPLOY_SCRIPT="$(dirname "$0")/deploy_payload.sh"
if [ ! -f "$DEPLOY_SCRIPT" ]; then
  echo "❌ deploy_payload.sh not found at $DEPLOY_SCRIPT"
  exit 1
fi

# === Load Server IPs from servers.list ===
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_FILE="$SCRIPT_DIR/servers.list"
if [ ! -f "$SERVER_FILE" ]; then
  echo "❌ Server list file not found at $SERVER_FILE"
  exit 1
fi

SERVER_LIST=()
while IFS= read -r line; do
  [[ "$line" =~ ^\s*# ]] && continue
  [[ -z "$line" ]] && continue
  SERVER_LIST+=("$line")
done < "$SERVER_FILE"

# ✅ DEBUG: print loaded IPs
echo "Loaded ${#SERVER_LIST[@]} server(s):"
for ip in "${SERVER_LIST[@]}"; do
  echo " - $ip"
done

# === Loop through servers ===
for ip in "${SERVER_LIST[@]}"; do
  echo "🔍 Checking availability of $ip..."
  if ! ping -c 2 -W 2 "$ip" > /dev/null; then
    echo "❌ $ip is offline."
    if command -v mail >/dev/null; then
      echo "$ip appears to be offline." | mail -s "🚨 Server Offline: $ip" "$NOTIFY_EMAIL"
    fi
    continue
  fi

  echo "✅ $ip is online. Deploying..."

  ssh -o StrictHostKeyChecking=no root@"$ip" \
    "AWS_ACCESS_KEY_ID='$AWS_ACCESS_KEY_ID' \
     AWS_SECRET_ACCESS_KEY='$AWS_SECRET_ACCESS_KEY' \
     SMTP_RELAY_USER='$RELAY_USER' \
     SMTP_RELAY_PASS='$RELAY_PASS' \
     BACKUP_ADMIN_EMAIL='$NOTIFY_EMAIL' \
     HEALTHCHECK_ALERT_EMAIL='$NOTIFY_EMAIL' \
     bash -s" < "$DEPLOY_SCRIPT"
done