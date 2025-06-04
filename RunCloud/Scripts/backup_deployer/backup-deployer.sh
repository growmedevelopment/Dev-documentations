#!/bin/bash

# === Load environment variables ===
ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "❌ .env file not found at $ENV_FILE"
  exit 1
fi

# === SSH Key Check ===
# Check if the variable starts with 'ssh-rsa' (meaning it's a raw key)
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
      if command -v mail >/dev/null; then
        echo "$name ($ip) appears to be offline." | mail -s "🚨 Server Offline: $name" "$NOTIFY_EMAIL"
      fi
      continue
    fi

    echo "✅ $name is online. Running backup script..."
   (
     echo "🚀 Starting backup on $name ($ip)..."
     ssh -o StrictHostKeyChecking=no root@"$ip" "bash /root/full_vultr_backup.sh daily"
     echo "✅ Backup finished for $name"
   ) &

  done < <(echo "$response" | jq -c '.data[]')
  echo "⌛ Waiting for all backups to finish..."
  wait
  echo "🎉 All backups completed."
  next=$(echo "$response" | jq -r '.meta?.pagination?.links?.next // empty')
  if [[ -z "$next" ]]; then
    break
  fi

  ((page++))
done