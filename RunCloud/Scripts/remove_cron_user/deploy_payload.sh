#!/bin/bash
set -euo pipefail

echo "🧹 Removing root's user crontab on $SERVER_IP..."

# Try to remove the crontab, suppress error if it's already empty
if crontab -l &>/dev/null; then
  crontab -r
  echo "✅ Root crontab removed on $SERVER_IP"
else
  echo "ℹ️ No crontab to remove for root on $SERVER_IP"
fi