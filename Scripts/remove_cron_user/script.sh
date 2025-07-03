#!/opt/homebrew/bin/bash
set -euo pipefail

SERVER_IP="${1:-UNKNOWN}"
SCRIPT_PATH="./Scripts/remove_cron_user/deploy_payload.sh"

if timeout 5s ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no root@"$SERVER_IP" "echo ok" &>/dev/null; then
  echo "✅ SSH OK for $SERVER_IP"
  echo "🚀 Running backup deployment script remotely on $SERVER_IP..."

  ssh -o StrictHostKeyChecking=no root@"$SERVER_IP" \
    "SERVER_IP='${SERVER_IP}' bash -s" < "$SCRIPT_PATH"

  echo "✅ Deployment script executed successfully on $SERVER_IP"
else
  echo "❌ SSH connection failed for $SERVER_IP"
  exit 1
fi