#!/opt/homebrew/bin/bash
set -euo pipefail

SERVER_IP="$1"
echo "🌐 Connecting to $SERVER_IP to update timezone..."

# Try to get server hostname (skip if unreachable or password prompt appears)
name=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$SERVER_IP" 'hostname' 2>/dev/null || echo "$SERVER_IP")

# Check if we actually got a hostname
if [[ "$name" == "$SERVER_IP" ]]; then
  echo "⚠️ Skipping $SERVER_IP — SSH key-based login failed (possibly password required)"
  exit 0
fi

# ✅ Ensure timezone is set to America/Edmonton
echo "🕒 Ensuring timezone is set to America/Edmonton on $name..."
ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$SERVER_IP" '
  current_tz=$(timedatectl show --value --property=Timezone)
  if [[ "$current_tz" != "America/Edmonton" ]]; then
    echo "🌎 Updating timezone from $current_tz to America/Edmonton..."
    timedatectl set-timezone America/Edmonton
    timedatectl set-ntp true
  else
    echo "✅ Timezone already set to America/Edmonton"
  fi
'

echo "✅ Timezone update complete for $name ($SERVER_IP)"