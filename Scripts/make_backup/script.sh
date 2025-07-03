#!/opt/homebrew/bin/bash
set -euo pipefail

SERVER_IP="$1"
echo "🚀 Starting backup on $SERVER_IP..."

# Try to get server hostname (skip if unreachable or password prompt appears)
name=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$SERVER_IP" 'hostname' 2>/dev/null || echo "$SERVER_IP")

# Check if we actually got a hostname
if [[ "$name" == "$SERVER_IP" ]]; then
  echo "⚠️ Skipping $SERVER_IP — SSH key-based login failed (possibly password required)"
  exit 0
fi

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  echo "💤 [DRY RUN] Would back up $name ($SERVER_IP)"
  exit 0
fi

# Run backup (fail fast if password would be required)
if timeout "${SSH_TIMEOUT:-300}"s ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$SERVER_IP" "bash /root/full_vultr_backup.sh daily"; then
  echo "✅ Backup finished for $name"
  exit 0
else
  echo "❌ Backup failed or timed out for $name ($SERVER_IP)"
  if command -v mail >/dev/null && [[ -n "${NOTIFY_EMAIL:-}" ]]; then
    echo "$name ($SERVER_IP) backup failed or timed out." | mail -s "🚨 Backup Failure: $name" "$NOTIFY_EMAIL"
  fi
  exit 1
fi