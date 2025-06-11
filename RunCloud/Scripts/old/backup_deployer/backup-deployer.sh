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
if [[ "$SSH_PUBLIC_KEY" == ssh-rsa* ]]; then
  echo "✅ Using raw SSH public key string"
  RAW_KEY="$SSH_PUBLIC_KEY"
else
  if [ ! -f "$SSH_PUBLIC_KEY" ]; then
    echo "❌ SSH key not found at $SSH_PUBLIC_KEY"
    exit 1
  fi
  RAW_KEY=$(cat "$SSH_PUBLIC_KEY")
  echo "✅ Loaded SSH key from file"
fi

# === Setup ===
MAX_JOBS=5
SSH_TIMEOUT=300
trap 'echo "⚠️ Script interrupted. Exiting..."; exit 1' INT TERM

run_limited() {
  while (( $(jobs -r | wc -l) >= MAX_JOBS )); do
    sleep 1
  done
  "$@" &
}

backup_server() {
  local name="$1"
  local ip="$2"

  echo "🚀 Starting backup on $name ($ip)..."


  if [ "$DRY_RUN" == "true" ]; then
    echo "💤 [DRY RUN] Would back up $name ($ip)"
  else
      if timeout "$SSH_TIMEOUT"s ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$ip" "bash /root/full_vultr_backup.sh daily"; then
        echo "✅ Backup finished for $name"
      else
        echo "❌ Backup failed or timed out for $name ($ip)"
        if command -v mail >/dev/null && [ -n "$NOTIFY_EMAIL" ]; then
          echo "$name ($ip) backup failed or timed out." | mail -s "🚨 Backup Failure: $name" "$NOTIFY_EMAIL"
        fi
      fi
  fi

}

# === Start deployment ===
page=1
current_server=0
total_servers=0

while :; do
  response=$(curl -s --location --request GET "https://manage.runcloud.io/api/v3/servers?page=$page" \
    --header "Authorization: Bearer $API_KEY" \
    --header "Accept: application/json" \
    --header "Content-Type: application/json")

  count=$(echo "$response" | jq '.data | length')
  ((total_servers += count))

  if ! echo "$response" | jq -e '.data' > /dev/null 2>&1; then
    echo "⚠️ Warning: Could not parse server list on page $page. Skipping..."
    ((page++))
    continue
  fi

  while IFS= read -r server; do
    ((current_server++))
    ip=$(echo "$server" | jq -r '.ipAddress')
    name=$(echo "$server" | jq -r '.name')

    echo "🔍 [$current_server/$total_servers] Checking availability of $name ($ip)..."
    if ! ping -c 2 -W 2 "$ip" > /dev/null; then
      echo "❌ $name ($ip) is offline."
      if command -v mail >/dev/null && [ -n "$NOTIFY_EMAIL" ]; then
        echo "$name ($ip) appears to be offline." | mail -s "🚨 Server Offline: $name" "$NOTIFY_EMAIL"
      fi
      continue
    fi

    echo "✅ $name is online. Running backup script..."
    run_limited backup_server "$name" "$ip"

  done < <(echo "$response" | jq -c '.data[]')



  next=$(echo "$response" | jq -r '.meta?.pagination?.links?.next // empty')
  if [[ -z "$next" ]]; then
    break
  fi
  ((page++))
done

wait
echo "🎉 All backups completed for page $page."