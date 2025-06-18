#!/opt/homebrew/bin/bash
set -euo pipefail

SERVER_IP="${1:-UNKNOWN}"

echo "🚀 Running backup deployment on $SERVER_IP ($(hostname))"
# Check SSH access
echo "🔍 Checking SSH access to $SERVER_IP..."
if timeout 5s ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no root@"$SERVER_IP" "echo ok" &>/dev/null; then
  echo "✅ SSH OK for $SERVER_IP"
  echo "🚀 Running backup deployment script remotely on $SERVER_IP..."

  SCRIPT_PATH="./Scripts/set_making_backup/deploy_payload.sh"

  ssh -o StrictHostKeyChecking=no root@"$SERVER_IP" \
    "AWS_ACCESS_KEY_ID='${AWS_ACCESS_KEY_ID}' \
     AWS_SECRET_ACCESS_KEY='${AWS_SECRET_ACCESS_KEY}' \
     SMTP_RELAY_USER='${SMTP_RELAY_USER}' \
     SMTP_RELAY_PASS='${SMTP_RELAY_PASS}' \
     BACKUP_ADMIN_EMAIL='${NOTIFY_EMAIL}' \
     bash -s" < "$SCRIPT_PATH"

  echo "✅ Deployment script executed successfully on $SERVER_IP"
else
  echo "❌ SSH connection failed for $SERVER_IP"
  exit 1
fi